//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./CraftingState.sol";

abstract contract CraftingContracts is Initializable, CraftingState {

    function __CraftingContracts_init() internal initializer {
        CraftingState.__CraftingState_init();
    }

    function setContracts(
        address _zugAddress,
        address _dungeonCrawlingItemAddress,
        address _etherOrcsItemsAddress,
        address _boneShardsAddress,
        address _randomizerAddress,
        address _orcsAddress,
        address _alliesAddress,
        address _vendorAddress)
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
            && vendorAddress != address(0);
    }
}