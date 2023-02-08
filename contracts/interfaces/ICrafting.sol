// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ICrafting {
    function startCraftingWorld(address _owner, StartCraftingParams calldata _startCraftingParam) external returns(bool);

    function endCraftingForEntity(address _owner, uint64 _tokenId) external;
}

struct StartCraftingParams {
    uint64 tokenId;
    uint64 recipeId;
    ItemInfo[] inputs;
}

struct ItemInfo {
    address collection;
    uint64 itemId;
    uint64 amount;
}