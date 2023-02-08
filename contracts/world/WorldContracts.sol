//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./WorldState.sol";

abstract contract WorldContracts is Initializable, WorldState {

    function __WorldContracts_init() internal initializer {
        WorldState.__WorldState_init();
    }

    function setContracts(
        address _orcsAddress,
        address _alliesAddress,
        address _activeFarmingAddress,
        address _randomizerAddress,
        address _dungeonCrawlingAddress,
        address _craftingAddress)
    external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        orcs = IOrcs(_orcsAddress);
        allies = IAllies(_alliesAddress);
        activeFarming = IActiveFarming(_activeFarmingAddress);
        randomizer = IRandomizer(_randomizerAddress);
        dungeonCrawling = IDungeonCrawling(_dungeonCrawlingAddress);
        crafting = ICrafting(_craftingAddress);
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "World: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(orcs) != address(0)
            && address(allies) != address(0)
            && address(activeFarming) != address(0)
            && address(randomizer) != address(0)
            && address(dungeonCrawling) != address(0)
            && address(crafting) != address(0);
    }
}