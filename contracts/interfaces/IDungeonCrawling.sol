// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDungeonCrawling {
    function startDungeonCrawlWorld(
        address _owner,
        string calldata _dungeonName,
        DungeonCrawlingEntity[] calldata _entities,
        uint64[][] calldata _entityInputQuantities,
        uint64[] calldata _inputQuantities)
    external;

    function adminUnstakeItemsAndEntities(
        address _owner)
    external;
}

struct DungeonCrawlingEntity {
    // tokenId indicates if the entity is an orc or ally, based on the number (orc < 5051)
    uint64 tokenId;
    uint64 mainHandItemId;
    uint64 offHandItemId;
    uint64 armorItemId;
}