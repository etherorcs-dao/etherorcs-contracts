//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./CraftingDiamondState.sol";

contract CraftingDiamondVariables is Initializable, CraftingDiamondState {

    function __CraftingDiamondVariables_init() internal initializer {
        CraftingDiamondState.__CraftingDiamondState_init();
    }

    function setContracts(
        address _zugAddress,
        address _dungeonCrawlingItemAddress,
        address _etherOrcsItemsAddress,
        address _boneShardsAddress,
        address _randomizerAddress,
        address _orcsAddress,
        address _alliesAddress,
        address _vendorAddress,
        address _worldAddress)
    external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        zug = IZug(_zugAddress);
        dungeonCrawlingItem = IDungeonCrawlingItem(_dungeonCrawlingItemAddress);
        etherOrcsItems = IEtherOrcsItems(_etherOrcsItemsAddress);
        boneShards = IBoneShards(_boneShardsAddress);
        randomizer = IRandomizer(_randomizerAddress);
        orcs = IOrcs(_orcsAddress);
        allies = IAllies(_alliesAddress);
        vendorAddress = _vendorAddress;
        world = IWorld(_worldAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(zug) != address(0)
            && address(dungeonCrawlingItem) != address(0)
            && address(etherOrcsItems) != address(0)
            && address(boneShards) != address(0)
            && address(randomizer) != address(0)
            && address(orcs) != address(0)
            && address(allies) != address(0)
            && vendorAddress != address(0)
            && address(world) != address(0);
    }

    function addCraftingRecipe(
        CraftingRecipe calldata _craftingRecipe)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        require(_craftingRecipe.recipeStartTime > 0 &&
            (_craftingRecipe.recipeStopTime == 0  || _craftingRecipe.recipeStopTime > _craftingRecipe.recipeStartTime)
            && recipeNameToRecipeId[_craftingRecipe.recipeName] == 0,
            "Bad crafting recipe");

        uint64 _recipeId = recipeIdCur;
        recipeIdCur++;

        recipeNameToRecipeId[_craftingRecipe.recipeName] = _recipeId;

        // Input validation.
        for(uint256 i = 0; i < _craftingRecipe.inputs.length; i++) {
            RecipeInput calldata _input = _craftingRecipe.inputs[i];

            require(_input.inputOptions.length > 0, "Input must have options");

            for(uint256 j = 0; j < _input.inputOptions.length; j++) {
                RecipeInputOption calldata _inputOption = _input.inputOptions[j];

                require((_inputOption.itemInfo.collection == address(etherOrcsItems)
                    || _inputOption.itemInfo.collection == address(dungeonCrawlingItem))
                    && _inputOption.itemInfo.amount > 0,
                    "Bad collection or amount");

                recipeIdToInputIndexToCollectionToItemIdToOptionIndex[_recipeId][i][_inputOption.itemInfo.collection][_inputOption.itemInfo.itemId] = j;
            }
        }

        // Output validation.
        require(_craftingRecipe.outputs.length > 0, "Recipe requires outputs");

        bool _isRandomRequiredForRecipe;
        for(uint256 i = 0; i < _craftingRecipe.outputs.length; i++) {
            RecipeOutput calldata _output = _craftingRecipe.outputs[i];

            require(_output.outputAmount.length > 0
                && _output.outputAmount.length == _output.outputOdds.length
                && _output.outputOptions.length > 0,
                "Bad output info");

            // If there is a variable amount for this RecipeOutput or multiple options,
            // a random is required.
            _isRandomRequiredForRecipe = _isRandomRequiredForRecipe
                || _output.outputAmount.length > 1
                || _output.outputOptions.length > 1;

            for(uint256 j = 0; j < _output.outputOptions.length; j++) {
                RecipeOutputOption calldata _outputOption = _output.outputOptions[j];

                // If there is an amount range, a random is required.
                _isRandomRequiredForRecipe = _isRandomRequiredForRecipe
                    || _outputOption.itemAmountMin != _outputOption.itemAmountMax;
            }
        }

        recipeIdToRecipe[_recipeId] = _craftingRecipe;
        recipeIdToInfo[_recipeId].isRandomRequired = _isRandomRequiredForRecipe;

        emit RecipeAdded(_recipeId, _craftingRecipe);
    }

    function deleteRecipe(
        uint64 _recipeId)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        require(_isValidRecipeId(_recipeId), "Unknown recipe Id");
        recipeIdToRecipe[_recipeId].recipeStopTime = recipeIdToRecipe[_recipeId].recipeStartTime;

        emit RecipeDeleted(_recipeId);
    }

    function setPercentToVendor(uint256 _percentToVendor) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        percentToVendor = _percentToVendor;
    }

    function recipeIdForName(string calldata _recipeName) external view returns(uint64) {
        return recipeNameToRecipeId[_recipeName];
    }

    function randomIdForCraftingId(uint256 _craftingId) external view returns(uint64) {
        return craftingIdToUserCraftingInfo[_craftingId].randomRequestKey;
    }
}