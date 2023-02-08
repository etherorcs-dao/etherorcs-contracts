//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ActiveFarmingState.sol";

abstract contract ActiveFarmingContracts is Initializable, ActiveFarmingState {

    function __ActiveFarmingContracts_init() internal initializer {
        ActiveFarmingState.__ActiveFarmingState_init();
    }

    function baseRatePerDayForEntity(EntityType _entityType) external view returns(uint128) {
        return typeToClassInfo[_entityType].baseRatePerDay;
    }

    function etherOrcItemIdForEntity(EntityType _entityType) external view returns(uint16) {
        return typeToClassInfo[_entityType].etherOrcItemId;
    }

    function setNoBoostItemPercent(
        uint256 _noBoostItemPercent)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        noBoostItemPercent = _noBoostItemPercent;
        emit NoBoostItemPercentChanged(_noBoostItemPercent);
    }

    function setMinimumTimeForFarming(
        uint32 _minimumTimeForFarming)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        minimumTimeForFarming = _minimumTimeForFarming;
        emit MinimumTimeForFarmingChanged(_minimumTimeForFarming);
    }

    function setItemBoost(
        uint16 _itemId,
        uint32 _boost,
        uint8 _amountNeeded)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        itemIdToBoostInfo[_itemId].boost = _boost;
        itemIdToBoostInfo[_itemId].amountNeeded = _amountNeeded;

        emit ItemBoostChanged(_itemId, _boost, _amountNeeded);
    }

    function setEntityInfo(
        EntityType _entityType,
        uint128 _baseRatePerDay,
        uint16 _etherOrcItemId)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        typeToClassInfo[_entityType].baseRatePerDay = _baseRatePerDay;
        typeToClassInfo[_entityType].etherOrcItemId = _etherOrcItemId;

        emit EntityBaseRatePerDayChanged(_entityType, _baseRatePerDay);
    }

    function setEntityOutputs(
        EntityType _entityType,
        Output[] calldata _outputs
    )
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        delete typeToClassInfo[_entityType].outputs;

        for(uint256 i = 0; i < _outputs.length; i++) {
            typeToClassInfo[_entityType].outputs.push(_outputs[i]);
        }

        emit EntityOutputsChanged(_entityType, _outputs);
    }

    function setContracts(
        address _zugAddress,
        address _orcsAddress,
        address _alliesAddress,
        address _dungeonCrawlingItemAddress,
        address _etherOrcsItemsAddress,
        address _randomizerAddress,
        address _worldAddress)
    external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        zug = IZug(_zugAddress);
        orcs = IOrcs(_orcsAddress);
        allies = IAllies(_alliesAddress);
        dungeonCrawlingItem = IDungeonCrawlingItem(_dungeonCrawlingItemAddress);
        etherOrcsItems = IEtherOrcsItems(_etherOrcsItemsAddress);
        randomizer = IRandomizer(_randomizerAddress);
        world = IWorld(_worldAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(zug) != address(0)
            && address(orcs) != address(0)
            && address(allies) != address(0)
            && address(dungeonCrawlingItem) != address(0)
            && address(etherOrcsItems) != address(0)
            && address(randomizer) != address(0)
            && address(world) != address(0);
    }
}