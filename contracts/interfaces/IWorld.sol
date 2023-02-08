// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IWorld {
    function locationForStakedEntity(uint256 _tokenId) external view returns(Location);

    function ownerForStakedEntity(uint256 _tokenId) external view returns(address);

    function adminSetLocationToWorld(address _originalOwner, uint16 _tokenId) external;
}

// NOT_STAKED - Entity is not in the world contract
// ACTIVE_FARMING - Entity is farming
// DUNGEON_CRAWLING - Entity is in the middle of a dungeon
// WORLD - Entity is staked in the world contract, but not doing anything
// CRAFTING - Entity is in a crafting recipe that requires an entity, such as raids
//
enum Location {
    NOT_STAKED,
    ACTIVE_FARMING,
    DUNGEON_CRAWLING,
    WORLD,
    CRAFTING
}