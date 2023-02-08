//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./DungeonCrawlingContracts.sol";

abstract contract DungeonCrawlingSettings is Initializable, DungeonCrawlingContracts {

    function __DungeonCrawlingSettings_init() internal onlyInitializing {
        DungeonCrawlingContracts.__DungeonCrawlingContracts_init();
    }

    function addDungeon(
        string calldata _dungeonName,
        DungeonInfo calldata _info)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        require(!isKnownDungeon(_dungeonName)
            && _info.startTime > 0
            && !compareStrings(_dungeonName, ""), "Bad Dungeon Info");

        dungeonNameToInfo[_dungeonName] = _info;

        for(uint256 i = 0; i < _info.inputs.length; i++) {
            require(_info.inputs[i].itemId > 0);
            require(_info.inputs[i].maxQuantity == 0 || _info.inputs[i].maxQuantity >= _info.inputs[i].minQuantity, "Max < min");
            require(_info.inputs[i].collection == address(etherOrcsItems) || _info.inputs[i].collection == address(dungeonCrawlingItem), "Unknown input collection");
        }

        emit DungeonAdded(_dungeonName, _info);
    }

    function modifyUnlockAndCooldownTime(
        string calldata _dungeonName,
        uint64 _dungeonUnlockPeriod,
        uint64 _dungeonCooldownPeriod)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        require(isKnownDungeon(_dungeonName));

        dungeonNameToInfo[_dungeonName].dungeonCooldownPeriod = _dungeonCooldownPeriod;
        dungeonNameToInfo[_dungeonName].dungeonUnlockPeriod = _dungeonUnlockPeriod;

        emit DungeonTimesModified(_dungeonName, _dungeonUnlockPeriod, _dungeonCooldownPeriod);
    }

    function removeDungeon(
        string calldata _dungeonName)
    external
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        require(isKnownDungeon(_dungeonName));

        dungeonNameToInfo[_dungeonName].endTime = dungeonNameToInfo[_dungeonName].startTime;

        emit DungeonRemoved(_dungeonName);
    }

    function setPercentToVendor(uint256 _percentToVendor) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        percentToVendor = _percentToVendor;
    }

    function isKnownDungeon(string memory _dungeonName) public view returns(bool) {
        return dungeonNameToInfo[_dungeonName].startTime > 0;
    }
}