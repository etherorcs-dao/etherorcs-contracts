//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ActiveFarmingContracts.sol";

contract ActiveFarming is Initializable, ActiveFarmingContracts {

    function initialize() external initializer {
        ActiveFarmingContracts.__ActiveFarmingContracts_init();
    }

    function startFarmingBatch(
        address _owner,
        uint64 _randomRequestKey,
        FarmingParams[] calldata _params)
    external
    whenNotPaused
    contractsAreSet
    onlyWorld
    {
        // Track items to burn in batch.
        // Because most entities use the same item for boosting, burning in batch saves gas over burning
        // each item individually.
        uint256[] memory _itemBoostIds = new uint256[](_params.length);
        uint256[] memory _itemBoostAmounts = new uint256[](_params.length);
        uint256 _nextIndex = 0;

        for(uint256 i = 0; i < _params.length; i++) {
            uint16 _itemBoostId = _params[i].itemBoostId;
            _startFarming(_params[i].tokenId, _itemBoostId, _owner, _randomRequestKey);
            if(_itemBoostId > 0) {
                bool _wasFoundInArray = false;
                for(uint j = 0; j < _nextIndex; j++) {
                    if(_itemBoostIds[j] == _itemBoostId) {
                        _wasFoundInArray = true;
                        _itemBoostAmounts[j] += itemIdToBoostInfo[_itemBoostId].amountNeeded;
                        break;
                    }
                }

                if(!_wasFoundInArray) {
                    _itemBoostIds[_nextIndex] = _itemBoostId;
                    _itemBoostAmounts[_nextIndex] = itemIdToBoostInfo[_itemBoostId].amountNeeded;
                    _nextIndex++;
                }
            }
        }

        if(_nextIndex > 0) {
            dungeonCrawlingItem.burnBatch(_owner, _itemBoostIds, _itemBoostAmounts);
        }
    }

    function endFarmingBatch(
        address _owner,
        uint16[] calldata _tokenIds)
    external
    whenNotPaused
    contractsAreSet
    onlyWorld
    {
        // EntityType -> the amount farmed for that entity
        uint256[4] memory _entityAmountToFarmed;
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            if(_tokenIds[i] == 0) {
                continue;
            }

            (uint256 _farmedAmount, EntityType _entityType) = _claimFarming(_tokenIds[i], _owner);

            delete tokenIdToInfo[_tokenIds[i]].startTime;
            delete tokenIdToInfo[_tokenIds[i]].hasClaimedItems;

            _entityAmountToFarmed[uint8(_entityType)] += _farmedAmount;
        }

        _mintFarmedAmounts(_owner, _entityAmountToFarmed);
    }

    function _mintFarmedAmounts(address _owner, uint256[4] memory _entityAmountToFarmed) private {
        for(uint256 i = 0; i < _entityAmountToFarmed.length; i++) {
            uint256 _amount = _entityAmountToFarmed[i];
            if(_amount == 0) {
                continue;
            }

            EntityType _entityType = EntityType(i);

            if(typeToClassInfo[_entityType].etherOrcItemId > 0) {
                etherOrcsItems.mint(_owner, typeToClassInfo[_entityType].etherOrcItemId, _amount);
            } else {
                zug.mint(_owner, _amount);
            }
        }
    }

    function _startFarming(
        uint16 _tokenId,
        uint16 _itemBoostId,
        address _owner,
        uint64 _randomRequestKey)
    private
    {
        uint32 _boost = _validateItemForBoost(_itemBoostId);

        tokenIdToInfo[_tokenId].startTime = uint128(block.timestamp);
        tokenIdToInfo[_tokenId].boost = _boost;
        tokenIdToInfo[_tokenId].randomRequestKey = _randomRequestKey;

        emit EntityFarmingStarted(
            _owner,
            _tokenId,
            _randomRequestKey,
            tokenIdToInfo[_tokenId].startTime,
            _boost
        );
    }

    function _validateItemForBoost(
        uint16 _itemId)
    private
    view
    returns(uint32 _boost)
    {
        if(_itemId == 0) {
            return 0;
        }
        ItemBoostInfo storage _itemBoostInfo = itemIdToBoostInfo[_itemId];
        require(_itemBoostInfo.boost > 0 && _itemBoostInfo.amountNeeded > 0, "Bad boost item");

        _boost = _itemBoostInfo.boost;
    }

    function claimFarming(
        uint16[] calldata _tokenIds)
    external
    whenNotPaused
    onlyEOA
    contractsAreSet
    {
        // EntityType -> the amount farmed for that entity
        uint256[4] memory _entityAmountToFarmed;
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint16 _tokenId = _tokenIds[i];
            require(msg.sender == world.ownerForStakedEntity(_tokenId), "Not owner");

            (uint256 _farmedAmount, EntityType _entityType) = _claimFarming(_tokenIds[i], msg.sender);

            tokenIdToInfo[_tokenId].claimedTime = uint128(block.timestamp);

            _entityAmountToFarmed[uint8(_entityType)] += _farmedAmount;
        }

        _mintFarmedAmounts(msg.sender, _entityAmountToFarmed);
    }

    function _claimFarming(
        uint16 _tokenId,
        address _owner)
    private
    returns(uint256 _farmedAmount, EntityType _entityType)
    {
        require(tokenIdToInfo[_tokenId].startTime > 0, "Not farming");

        uint16 _classBoost;
        (_entityType, _classBoost) = _getEntityTypeAndBoost(_tokenId);

        ClassFarmingInfo storage _classInfo = typeToClassInfo[_entityType];

        _farmedAmount = _getFarmedAmount(_tokenId, _classBoost, _entityType, _classInfo);

        OutputOutcome[] memory _outcomes = _pickAndMintRewards(_tokenId, _owner, _classInfo);

        emit EntityFarmingClaimed(_owner, _tokenId, _farmedAmount, _outcomes);
    }

    function _pickAndMintRewards(
        uint16 _tokenId,
        address _owner,
        ClassFarmingInfo storage _classInfo)
    private
    returns(OutputOutcome[] memory _outcomes)
    {
        if(_classInfo.outputs.length == 0) {
            return _outcomes;
        }
        uint128 _startTime = tokenIdToInfo[_tokenId].startTime;
        if(_startTime + minimumTimeForItems <= block.timestamp) {
            if(!tokenIdToInfo[_tokenId].hasClaimedItems) {
                uint256 _randomNumber = uint256(keccak256(abi.encodePacked(randomizer.getRandom(tokenIdToInfo[_tokenId].randomRequestKey), _tokenId)));

                _outcomes = new OutputOutcome[](_classInfo.outputs.length);

                for(uint256 i = 0; i < _classInfo.outputs.length; i++) {
                    _outcomes[i] = _determineAndMintOutputs(_classInfo.outputs[i], _randomNumber, _owner);
                }

                tokenIdToInfo[_tokenId].hasClaimedItems = true;
            }
        }
    }

    function _determineAndMintOutputs(
        Output storage _output,
        uint256 _randomNumber,
        address _owner)
    private
    returns(OutputOutcome memory _outcome)
    {
        uint8 _outputAmount = _determineOutputAmount(
            _output,
            _randomNumber);

        _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));

        _outcome.items = new Item[](_outputAmount);

        for(uint256 i = 0; i < _outputAmount; i++) {
            if(i != 0) {
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
            }

            OutputOption storage _selectedOption = _determineOutputOption(
                _output,
                _randomNumber);

            _outcome.items[i].itemId = _selectedOption.itemId;
            _outcome.items[i].itemAmount = _selectedOption.itemAmount;

            if(_selectedOption.itemAmount > 0 && _selectedOption.itemId > 0) {
                dungeonCrawlingItem.mint(_owner, _selectedOption.itemId, _selectedOption.itemAmount);
            }
        }
    }

    function _determineOutputOption(
        Output storage _output,
        uint256 _randomNumber)
    private
    view
    returns(OutputOption storage)
    {
        if(_output.outputOptions.length == 1) {
            return _output.outputOptions[0];
        } else {
            uint256 _outputOptionResult = _randomNumber % 100000;
            uint32 _topRange = 0;
            for(uint256 j = 0; j < _output.outputOptions.length; j++) {
                OutputOption storage _outputOption = _output.outputOptions[j];
                _topRange += _outputOption.optionOdds;
                if(_outputOptionResult < _topRange) {
                    return _outputOption;
                }
            }
        }

        revert("Bad output option odds");
    }

    // Determines how many "rolls" the user has for the passed in output.
    function _determineOutputAmount(
        Output storage _output,
        uint256 _randomNumber
    ) private view returns(uint8) {
        uint8 _outputAmount;
        if(_output.outputAmount.length == 1) {
            _outputAmount = _output.outputAmount[0];
        } else {
            uint256 _outputResult = _randomNumber % 100000;
            uint32 _topRange = 0;

            for(uint256 i = 0; i < _output.outputAmount.length; i++) {
                _topRange += _output.outputAmount[i];
                if(_outputResult < _topRange) {
                    _outputAmount = _output.outputAmount[i];
                    break;
                }
            }
        }
        return _outputAmount;
    }

    function _getFarmedAmount(
        uint16 _tokenId,
        uint16 _classBoost,
        EntityType _entityType,
        ClassFarmingInfo storage _classInfo)
    private
    view
    returns(uint256)
    {
        uint128 _startTime = tokenIdToInfo[_tokenId].startTime;
        if(_startTime + minimumTimeForFarming > block.timestamp) {
            return 0;
        }

        uint128 _lastClaimTime = _startTime;
        if(tokenIdToInfo[_tokenId].claimedTime > _startTime) {
            _lastClaimTime = tokenIdToInfo[_tokenId].claimedTime;
        }

        uint256 _timeForCalculation = block.timestamp;
        uint256 _upperLimit = _startTime + maximumTimeFarmingCap;
        if(_upperLimit < _timeForCalculation) {
            _timeForCalculation = _upperLimit;
        }

        // If the user claims after the full farming time,
        // the last claim time will be set to that time.
        // The time for calculation when unstaking will be capped
        // at the max farming time. In this case, they already got all
        // that they deserved.
        //
        if(_lastClaimTime > _timeForCalculation) {
            return 0;
        }

        uint256 _adjustedClassBoost = _entityType == EntityType.ORC
            ? uint256(_classBoost) * 1 ether
            : uint256(_classBoost) * 0.05 ether;

        uint256 _itemBoost = tokenIdToInfo[_tokenId].boost;

        // Class boost are additive to the base rate while item boosts are multiplicative
        if(_itemBoost == 0) {
            return (_timeForCalculation - _lastClaimTime) * noBoostItemPercent * (uint256(_classInfo.baseRatePerDay) + _adjustedClassBoost) / 1 days / 100000;
        } else {
            return (_timeForCalculation - _lastClaimTime) * (1 ether + (_itemBoost * 1 ether) / 100000) * (uint256(_classInfo.baseRatePerDay) + _adjustedClassBoost) / 1 ether / 1 days;
        }
    }

    function _getEntityTypeAndBoost(
        uint16 _tokenId)
    private
    view
    returns(EntityType _entityType, uint16 _classBoost)
    {
        if(_isOrc(_tokenId)) {
            _entityType = EntityType.ORC;

            (,,,,,_classBoost,) = orcs.orcs(_tokenId);
        } else {
            uint8 _class;
            (_class,,,_classBoost,,) = allies.allies(_tokenId);

            _entityType = EntityType(_class);
        }
    }

    function _isOrc(uint256 _tokenId) private pure returns(bool) {
        return _tokenId < 5051;
    }

    modifier onlyWorld() {
        require(msg.sender == address(world), "Only callable by world");

        _;
    }
}