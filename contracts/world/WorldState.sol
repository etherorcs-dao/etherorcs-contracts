//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "./IWorld.sol";
import "../external/IOrcs.sol";
import "../external/IAllies.sol";
import "../activefarming/IActiveFarming.sol";
import "../../shared/UtilitiesUpgradeable.sol";
import "../external/IRandomizer.sol";
import "../dungeoncrawling/IDungeonCrawling.sol";
import "../crafting/ICrafting.sol";

abstract contract WorldState is IWorld, ERC721HolderUpgradeable, UtilitiesUpgradeable {

    event EntityLocationChanged(uint256[] _tokenIds, address _owner, Location _newLocation);

    IOrcs internal orcs;
    IAllies internal allies;
    IActiveFarming internal activeFarming;

    mapping(uint256 => TokenInfo) internal tokenIdToInfo;

    // Deprecated. Too expensive and don't need that info on chain.
    mapping(address => EnumerableSetUpgradeable.UintSet) internal ownerToStakedTokens;

    IRandomizer internal randomizer;
    IDungeonCrawling internal dungeonCrawling;
    ICrafting internal crafting;

    function __WorldState_init() internal initializer {
        UtilitiesUpgradeable.__Utilities_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
    }
}

// Be careful of changing as this is stored in storage.
struct TokenInfo {
    // Slot 1 (168/256)
    address owner;
    Location location;
    uint88 emptySpace1;
}