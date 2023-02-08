// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IActiveFarming {
    function startFarmingBatch(
        address _owner,
        uint64 _randomRequestKey,
        FarmingParams[] calldata _params)
    external;

    function endFarmingBatch(
        address _owner,
        uint16[] calldata _tokenIds)
    external;
}

enum EntityType {
    ORC,
    SHAMAN,
    OGRE,
    ROGUE
}

struct FarmingParams {
    // Slot 1 (32/256)
    uint16 tokenId;
    uint16 itemBoostId;
}

enum FarmingAction {
    START,
    RESTART,
    END
}