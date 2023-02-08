//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./CraftingSettings.sol";

contract Crafting is Initializable, CraftingSettings {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        CraftingSettings.__CraftingSettings_init();
    }

    function startOrEndCrafting(
        uint256[] calldata _craftingIdsToEnd,
        StartCraftingParams[] calldata _startCraftingParams)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(_craftingIdsToEnd.length > 0 || _startCraftingParams.length > 0, "No inputs provided");

        for(uint256 i = 0; i < _craftingIdsToEnd.length; i++) {
            _endCrafting(_craftingIdsToEnd[i]);
        }

        for(uint256 i = 0; i < _startCraftingParams.length; i++) {
            (uint256 _craftingId, bool _isRecipeInstant) = _startCrafting(_startCraftingParams[i]);
            if(_isRecipeInstant) {
                // No random is required if _isRecipeInstant == true.
                // Safe to pass in 0.
                _endCraftingPostValidation(_craftingId, 0);
            }
        }
    }

    // Verifies recipe info, inputs, and transfers those inputs.
    // Returns if this recipe can be completed instantly
    function _startCrafting(
        StartCraftingParams calldata _craftingParams)
    private
    returns(uint256, bool)
    {
        require(_isValidRecipeId(_craftingParams.recipeId), "Unknown recipe");

        CraftingRecipe storage _craftingRecipe = recipeIdToRecipe[_craftingParams.recipeId];
        require(block.timestamp >= _craftingRecipe.recipeStartTime &&
            (_craftingRecipe.recipeStopTime == 0
            || _craftingRecipe.recipeStopTime > block.timestamp), "Recipe has not started or stopped");
        require(!_craftingRecipe.requires721 || _craftingParams.tokenId > 0, "Recipe requires token");

        CraftingRecipeInfo storage _craftingRecipeInfo = recipeIdToInfo[_craftingParams.recipeId];
        require(_craftingRecipe.maxCraftsGlobally == 0
            || _craftingRecipe.maxCraftsGlobally > _craftingRecipeInfo.currentCraftsGlobally,
            "Recipe has reached max number of crafts");

        _craftingRecipeInfo.currentCraftsGlobally++;

        uint256 _craftingId = craftingIdCur;
        craftingIdCur++;

        uint64 _totalTimeReduction;
        uint256 _totalZugReduction;
        uint256 _totalBoneShardReduction;
        (_totalTimeReduction,
            _totalZugReduction,
            _totalBoneShardReduction) = _validateAndTransferInputs(
                _craftingRecipe,
                _craftingParams,
                _craftingId
            );

        _burnERC20s(_craftingRecipe, _totalZugReduction, _totalBoneShardReduction);

        _validateAndTransferNFT(_craftingParams.tokenId, _craftingRecipe.minimumLevelRequired);

        UserCraftingInfo storage _userCrafting = craftingIdToUserCraftingInfo[_craftingId];

        if(_craftingRecipe.timeToComplete > _totalTimeReduction) {
            _userCrafting.timeOfCompletion
                = uint128(block.timestamp + _craftingRecipe.timeToComplete - _totalTimeReduction);
        }

        if(_craftingRecipeInfo.isRandomRequired) {
            _userCrafting.randomRequestKey = randomizer.request();
        }

        _userCrafting.recipeId = _craftingParams.recipeId;
        _userCrafting.tokenId = _craftingParams.tokenId;

        // Indicates if this recipe will complete in the same txn as the startCrafting txn.
        bool _isRecipeInstant = !_craftingRecipeInfo.isRandomRequired && _userCrafting.timeOfCompletion == 0;

        if(!_isRecipeInstant) {
            userToCraftsInProgress[msg.sender].add(_craftingId);
        }

        _emitCraftingStartedEvent(_craftingId, _craftingParams);

        return (_craftingId, _isRecipeInstant);
    }

    function _emitCraftingStartedEvent(uint256 _craftingId, StartCraftingParams calldata _craftingParams) private {
        emit CraftingStarted(
            msg.sender,
            _craftingId,
            craftingIdToUserCraftingInfo[_craftingId].timeOfCompletion,
            craftingIdToUserCraftingInfo[_craftingId].recipeId,
            craftingIdToUserCraftingInfo[_craftingId].randomRequestKey,
            craftingIdToUserCraftingInfo[_craftingId].tokenId,
            _craftingParams.inputs);
    }

    function _validateAndTransferNFT(uint64 _tokenId, uint16 _minimumLevelRequired) private {
        if(_tokenId == 0) {
            return;
        }
        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = _tokenId;

        uint16 _curLevel;

        // Pull the orc/ally out first as they may have gained some levels.
        if(_tokenId < 5051) {
            orcs.pull(msg.sender, _tokenIds);
            (,,,,_curLevel,,) = orcs.orcs(_tokenId);
        } else {
            allies.pull(msg.sender, _tokenIds);
            (,_curLevel,,,,) = allies.allies(_tokenId);
        }

        require(_curLevel >= _minimumLevelRequired, "Haven't reached min level");
    }

    function _burnERC20s(
        CraftingRecipe storage _craftingRecipe,
        uint256 _totalZugReduction,
        uint256 _totalBoneShardReduction)
    private
    {
        uint256 _totalZug;
        if(_craftingRecipe.zugCost > _totalZugReduction) {
            _totalZug = _craftingRecipe.zugCost - _totalZugReduction;
        }

        uint256 _totalBoneShards;
        if(_craftingRecipe.boneShardCost > _totalBoneShardReduction) {
            _totalBoneShards = _craftingRecipe.boneShardCost - _totalBoneShardReduction;
        }

        if(_totalZug > 0) {
            zug.burn(msg.sender, _totalZug);
            zug.mint(vendorAddress, (_totalZug * percentToVendor) / 100000);
        }
        if(_totalBoneShards > 0) {
            boneShards.burn(msg.sender, _totalBoneShards);
        }
    }

    // Ensures all inputs are valid and provided if required.
    function _validateAndTransferInputs(
        CraftingRecipe storage _craftingRecipe,
        StartCraftingParams calldata _craftingParams,
        uint256 _craftingId)
    private
    returns(uint64 _totalTimeReduction, uint256 _totalZugReduction, uint256 _totalBoneShardReduction)
    {

        // Because the inputs can have a given "amount" of inputs that must be supplied,
        // the input index provided, and those in the recipe may not be identical.
        uint8 _paramInputIndex;

        for(uint256 i = 0; i < _craftingRecipe.inputs.length; i++) {
            RecipeInput storage _recipeInput = _craftingRecipe.inputs[i];

            for(uint256 j = 0; j < _recipeInput.amount; j++) {
                require(_paramInputIndex < _craftingParams.inputs.length, "Bad number of inputs");
                ItemInfo calldata _startCraftingItemInfo = _craftingParams.inputs[_paramInputIndex];
                _paramInputIndex++;
                // J must equal 0. If they are trying to skip an optional amount, it MUST be the first input supplied for the RecipeInput
                if(j == 0  && _startCraftingItemInfo.collection == address(0) && !_recipeInput.isRequired) {
                    // Break out of the amount loop. They are not providing any of the input
                    break;
                } else if(_startCraftingItemInfo.collection == address(0)) {
                    revert("Supplied no input to required input");
                } else {
                    uint256 _optionIndex = recipeIdToInputIndexToCollectionToItemIdToOptionIndex[_craftingParams.recipeId][i][_startCraftingItemInfo.collection][_startCraftingItemInfo.itemId];
                    RecipeInputOption storage _inputOption = _recipeInput.inputOptions[_optionIndex];

                    require(_inputOption.itemInfo.amount > 0
                        && _inputOption.itemInfo.amount == _startCraftingItemInfo.amount
                        && _inputOption.itemInfo.itemId == _startCraftingItemInfo.itemId
                        && _inputOption.itemInfo.collection == _startCraftingItemInfo.collection, "Bad item input given");

                    // Add to reductions
                    _totalTimeReduction += _inputOption.timeReduction;
                    _totalZugReduction += _inputOption.zugReduction;
                    _totalBoneShardReduction += _inputOption.boneShardReduction;

                    craftingIdToUserCraftingInfo[_craftingId]
                        .inputCollectionToItemIdToInput[_inputOption.itemInfo.collection][_inputOption.itemInfo.itemId].itemAmount += _inputOption.itemInfo.amount;
                    craftingIdToUserCraftingInfo[_craftingId]
                        .inputCollectionToItemIdToInput[_inputOption.itemInfo.collection][_inputOption.itemInfo.itemId].wasBurned = _inputOption.isBurned;

                    // Only need to save off non-burned inputs. Burned inputs will never be returned.
                    if(!_inputOption.isBurned) {
                        craftingIdToUserCraftingInfo[_craftingId].nonBurnedInputs.push(_inputOption.itemInfo);
                    }

                    _transferOrBurnItem(
                        _inputOption.itemInfo,
                        msg.sender,
                        address(this),
                        _inputOption.isBurned);
                }
            }
        }
    }

    function _endCrafting(uint256 _craftingId) private {
        require(userToCraftsInProgress[msg.sender].contains(_craftingId), "Invalid crafting id for user");

        // Remove crafting from users in progress crafts.
        userToCraftsInProgress[msg.sender].remove(_craftingId);

        UserCraftingInfo storage _userCraftingInfo = craftingIdToUserCraftingInfo[_craftingId];
        require(block.timestamp >= _userCraftingInfo.timeOfCompletion, "Crafting is not complete");

        uint256 _randomNumber;
        if(_userCraftingInfo.randomRequestKey > 0) {
            _randomNumber = randomizer.getRandom(_userCraftingInfo.randomRequestKey);
            require(_randomNumber > 0, "Random has not been set");
        }

        _endCraftingPostValidation(_craftingId, _randomNumber);
    }

    function _endCraftingPostValidation(uint256 _craftingId, uint256 _randomNumber) private {
        UserCraftingInfo storage _userCraftingInfo = craftingIdToUserCraftingInfo[_craftingId];
        CraftingRecipe storage _craftingRecipe = recipeIdToRecipe[_userCraftingInfo.recipeId];

        uint256 _zugRewarded;
        uint256 _boneShardRewarded;

        CraftingItemOutcome[] memory _itemOutcomes = new CraftingItemOutcome[](_craftingRecipe.outputs.length);

        for(uint256 i = 0; i < _craftingRecipe.outputs.length; i++) {
            // If needed, get a fresh random for the next output decision.
            if(i != 0 && _randomNumber != 0) {
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
            }

            (uint256 _zugForOutput, uint256 _boneShardForOutput, CraftingItemOutcome memory _outcome) = _determineAndMintOutputs(
                _craftingRecipe.outputs[i],
                _userCraftingInfo,
                _randomNumber);

            _zugRewarded += _zugForOutput;
            _boneShardRewarded += _boneShardForOutput;
            _itemOutcomes[i] = _outcome;
        }

        for(uint256 i = 0; i < _userCraftingInfo.nonBurnedInputs.length; i++) {
            ItemInfo storage _userCraftingInput = _userCraftingInfo.nonBurnedInputs[i];

            _transferOrBurnItem(
                _userCraftingInput,
                address(this),
                msg.sender,
                false);
        }

        if(_userCraftingInfo.tokenId > 0) {
            if(_userCraftingInfo.tokenId < 5051) {
                orcs.transfer(msg.sender, _userCraftingInfo.tokenId);
            } else {
                allies.transfer(msg.sender, _userCraftingInfo.tokenId);
            }
        }

        emit CraftingEnded(_craftingId, _zugRewarded, _boneShardRewarded, _itemOutcomes);
    }

    function _determineAndMintOutputs(
        RecipeOutput storage _recipeOutput,
        UserCraftingInfo storage _userCraftingInfo,
        uint256 _randomNumber)
    private
    returns(uint256 _zugForOutput, uint256 _boneShardForOutput, CraftingItemOutcome memory _outcome)
    {
        uint8 _outputAmount = _determineOutputAmount(
            _recipeOutput,
            _userCraftingInfo,
            _randomNumber);

        // Just in case the output amount needed a random. Only would need 16 bits (one random roll).
        _randomNumber >>= 16;

        uint64[] memory _itemIds = new uint64[](_outputAmount);
        uint64[] memory _itemAmounts = new uint64[](_outputAmount);

        for(uint256 i = 0; i < _outputAmount; i++) {
            if(i != 0 && _randomNumber != 0) {
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
            }

            RecipeOutputOption memory _selectedOption = _determineOutputOption(
                _recipeOutput,
                _userCraftingInfo,
                _randomNumber);
            _randomNumber >>= 16;

            uint64 _itemAmount;
            if(_selectedOption.itemAmountMin == _selectedOption.itemAmountMax) {
                _itemAmount = _selectedOption.itemAmountMax;
            } else {
                uint64 _rangeSelection = uint64(_randomNumber
                    % (_selectedOption.itemAmountMax - _selectedOption.itemAmountMin + 1));

                _itemAmount = _selectedOption.itemAmountMin + _rangeSelection;
            }

            _zugForOutput += _selectedOption.zugAmount;
            _boneShardForOutput += _selectedOption.boneShardAmount;
            _itemIds[i] = _selectedOption.itemId;
            _itemAmounts[i] = _itemAmount;

            _mintOutputOption(_selectedOption, _itemAmount);
        }

        _outcome.itemIds = _itemIds;
        _outcome.itemAmounts = _itemAmounts;
    }

    function _determineOutputOption(
        RecipeOutput storage _recipeOutput,
        UserCraftingInfo storage _userCraftingInfo,
        uint256 _randomNumber)
    private
    view
    returns(RecipeOutputOption memory)
    {
        RecipeOutputOption memory _selectedOption;
        if(_recipeOutput.outputOptions.length == 1) {
            _selectedOption = _recipeOutput.outputOptions[0];
        } else {
            uint256 _outputOptionResult = _randomNumber % 100000;
            uint32 _topRange = 0;
            for(uint256 j = 0; j < _recipeOutput.outputOptions.length; j++) {
                RecipeOutputOption storage _outputOption = _recipeOutput.outputOptions[j];
                uint32 _adjustedOdds = _adjustOutputOdds(_outputOption.optionOdds, _userCraftingInfo);
                _topRange += _adjustedOdds;
                if(_outputOptionResult < _topRange) {
                    _selectedOption = _outputOption;
                    break;
                }
            }
        }

        return _selectedOption;
    }

    // Determines how many "rolls" the user has for the passed in output.
    function _determineOutputAmount(
        RecipeOutput storage _recipeOutput,
        UserCraftingInfo storage _userCraftingInfo,
        uint256 _randomNumber
    ) private view returns(uint8) {
        uint8 _outputAmount;
        if(_recipeOutput.outputAmount.length == 1) {
            _outputAmount = _recipeOutput.outputAmount[0];
        } else {
            uint256 _outputResult = _randomNumber % 100000;
            uint32 _topRange = 0;

            for(uint256 i = 0; i < _recipeOutput.outputAmount.length; i++) {
                uint32 _adjustedOdds = _adjustOutputOdds(_recipeOutput.outputOdds[i], _userCraftingInfo);
                _topRange += _adjustedOdds;
                if(_outputResult < _topRange) {
                    _outputAmount = _recipeOutput.outputAmount[i];
                    break;
                }
            }
        }
        return _outputAmount;
    }

    function _mintOutputOption(
        RecipeOutputOption memory _selectedOption,
        uint256 _itemAmount)
    private
    {
        if(_itemAmount > 0 && _selectedOption.itemId > 0) {
            dungeonCrawlingItem.mint(
                msg.sender,
                _selectedOption.itemId,
                _itemAmount);
        }
        if(_selectedOption.zugAmount > 0) {
            zug.mint(
                msg.sender,
                _selectedOption.zugAmount);
        }
        if(_selectedOption.boneShardAmount > 0) {
            boneShards.mint(
                msg.sender,
                _selectedOption.boneShardAmount);
        }
    }

    function _adjustOutputOdds(
        OutputOdds storage _outputOdds,
        UserCraftingInfo storage _userCraftingInfo)
    private
    view
    returns(uint32)
    {
        // No boost or didn't use the boost item as an input.
        if(_outputOdds.boostItemId == 0
            || _userCraftingInfo.inputCollectionToItemIdToInput[_outputOdds.boostItemCollection][_outputOdds.boostItemId].itemAmount == 0) {
            return _outputOdds.baseOdds;
        } else {
            return _outputOdds.boostOdds;
        }
    }

    function _transferOrBurnItem(
        ItemInfo memory _itemInfo,
        address _from,
        address _to,
        bool _burn)
    private
    {
        if(_itemInfo.collection == address(etherOrcsItems)) {
            // EOIs have a decimal system. Adjust here.
            uint256 _trueAmount = _itemInfo.amount * 1 ether;
            if(_burn) {
                etherOrcsItems.burn(_from, _itemInfo.itemId, _trueAmount);
            } else {
                etherOrcsItems.safeTransferFrom(
                    _from,
                    _to,
                    _itemInfo.itemId,
                    _trueAmount,
                    "");
            }
        } else if(_itemInfo.collection == address(dungeonCrawlingItem)) {
            if(_burn) {
                dungeonCrawlingItem.burn(_from, _itemInfo.itemId, _itemInfo.amount);
            } else {
                dungeonCrawlingItem.noApprovalSafeTransferFrom(
                    _from,
                    _to,
                    _itemInfo.itemId,
                    _itemInfo.amount);
            }
        } else {
            revert("Unknown item collection");
        }
    }

    // Nothing to do here. Needed for the ability to pull orcs/allies and stake them here.
    function pullCallback(address, uint256[] calldata) external {

    }

    function randomIdForCraftingId(uint256 _craftingId) external view returns(uint64) {
        return craftingIdToUserCraftingInfo[_craftingId].randomRequestKey;
    }

}

struct StartCraftingParams {
    uint64 tokenId;
    uint64 recipeId;
    ItemInfo[] inputs;
}