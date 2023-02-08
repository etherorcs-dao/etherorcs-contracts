//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./DungeonCrawlingSettings.sol";

contract DungeonCrawling is Initializable, DungeonCrawlingSettings {

    function initialize() external initializer {
        DungeonCrawlingSettings.__DungeonCrawlingSettings_init();
    }

    function startDungeonCrawl(
        string calldata _dungeonName,
        DungeonCrawlingEntity[] calldata _entities,
        uint64[][] calldata _entityInputQuantities,
        uint64[] calldata _inputQuantities)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        _unstakeItemsAndEntitiesIfPossible();

        _updateDungeonForUser(_dungeonName);

        _stakeEntities(_dungeonName, _entities, _entityInputQuantities);
        _stakeInputs(
            dungeonNameToInfo[_dungeonName].inputs, // What inputs are being staked
            dungeonCrawlingInputs[userToInfo[msg.sender].activeInputIndex].inputs, // Where to store the result
            _inputQuantities); // The inputs for each input

        emit DungeonStarted(
            msg.sender,
            _dungeonName,
            dungeonInputsIndexCur - 1,
            _entities,
            _suppliedEntityInputsForUser(msg.sender),
            dungeonCrawlingInputs[dungeonInputsIndexCur - 1].inputs);
    }

    function _updateDungeonForUser(
        string calldata _dungeonName)
    private
    {
        require(!_isUserDungeonCrawling(msg.sender), "User is already dungeon crawling");

        DungeonInfo storage _dungeonInfo = dungeonNameToInfo[_dungeonName];
        require((_dungeonInfo.endTime == 0 || block.timestamp < _dungeonInfo.endTime)
            && isKnownDungeon(_dungeonName)
            && (_dungeonInfo.maxNumberOfCrawlsGlobal == 0 || _dungeonInfo.currentNumberOfCrawls < _dungeonInfo.maxNumberOfCrawlsGlobal), "Bad dungeon");

        _dungeonInfo.currentNumberOfCrawls++;

        userToInfo[msg.sender].dungeonStartTime = block.timestamp;
        userToInfo[msg.sender].activeDungeonName = _dungeonName;

        userToInfo[msg.sender].activeInputIndex = dungeonInputsIndexCur;
        dungeonInputsIndexCur++;

        if(_dungeonInfo.zugCost > 0) {
            zug.burn(msg.sender, _dungeonInfo.zugCost);
            zug.mint(vendorAddress, (_dungeonInfo.zugCost * percentToVendor) / 100000);
        }
    }

    function _stakeEntities(
        string calldata _dungeonName,
        DungeonCrawlingEntity[] calldata _entities,
        uint64[][] calldata _entityInputQuantities)
    private
    {
        require(_entities.length >= dungeonNameToInfo[_dungeonName].minEntitiesPerCrawl
            && dungeonNameToInfo[_dungeonName].maxEntitiesPerCrawl >= _entities.length
            && _entities.length == _entityInputQuantities.length, "Bad entities amount");

        uint256[] memory _pullArray = new uint256[](1);

        for(uint256 i = 0; i < _entities.length; i++) {
            uint256 _tokenId = _entities[i].tokenId;
            _pullArray[0] = _tokenId;
            uint16 _level;
            string memory _entityEquippableName;

            if(_isOrc(_tokenId)) {
                (,,,,_level,,) = orcs.orcs(_tokenId);

                _entityEquippableName = ORC_EQUIPPABLE;

                orcs.pull(msg.sender, _pullArray);
            } else {
                uint8 _class;
                (_class,_level,,,,) = allies.allies(_tokenId);

                if(_class == 1) {
                    _entityEquippableName = SHAMAN_EQUIPPABLE;
                } else if(_class == 2) {
                    _entityEquippableName = OGRE_EQUIPPABLE;
                } else if(_class == 3) {
                    _entityEquippableName = ROGUE_EQUIPPABLE;
                } else {
                    revert("Bad class id");
                }

                allies.pull(msg.sender, _pullArray);
            }

            _storeEntity(_dungeonName, _entities[i], _entityEquippableName, _level);

            dungeonCrawlingInputs[userToInfo[msg.sender].activeInputIndex].entities.push(_entities[i]);

            _stakeInputs(
                dungeonNameToInfo[_dungeonName].entityInputs,
                dungeonCrawlingInputs[userToInfo[msg.sender].activeInputIndex].tokenIdToEntityInputs[_entities[i].tokenId],
                _entityInputQuantities[i]);

            tokenIdToOwner[_tokenId] = msg.sender;
        }
    }

    function _storeEntity(
        string calldata _dungeonName,
        DungeonCrawlingEntity calldata _entity,
        string memory _entityEquippableName,
        uint16 _level)
    private
    {
        DungeonInfo storage _dungeonInfo = dungeonNameToInfo[_dungeonName];
        require(_level >= _dungeonInfo.minimumLevel, "Entity not at min level");

        require(_dungeonInfo.maxNumberOfCrawlsPerEntity == 0
            || _dungeonInfo.maxNumberOfCrawlsPerEntity > dungeonNameToTokenIdToNumberOfCrawls[_dungeonName][_entity.tokenId],
            "Entity at max crawls");

        require(block.timestamp >= tokenIdToCooldownTime[_entity.tokenId],
            "Entity cooling down");

        dungeonNameToTokenIdToNumberOfCrawls[_dungeonName][_entity.tokenId]++;

        _stakeEquipment(_entity.mainHandItemId, EQUIPMENT_MAIN_HAND, _entityEquippableName);
        _stakeEquipment(_entity.offHandItemId, EQUIPMENT_OFF_HAND, _entityEquippableName);
        _stakeEquipment(_entity.armorItemId, EQUIPMENT_ARMOR, _entityEquippableName);
    }

    function _stakeEquipment(uint64 _equipmentId, string memory _equipmentType, string memory _entityEquippableName) private {
        if(_equipmentId == 0) {
            return;
        }

        // This check ensures that the given equipment ID is of the right type. They can't
        // equip a sword as their armor.
        require(compareStrings(_equipmentType, dungeonCrawlingItem.propertyValueForToken(_equipmentId, EQUIPMENT_SLOT_PROPERTY_NAME))
            && compareStrings(YES, dungeonCrawlingItem.propertyValueForToken(_equipmentId, _entityEquippableName)),
            "Bad equipment");

        dungeonCrawlingItem.noApprovalSafeTransferFrom(msg.sender, address(this), _equipmentId, 1);
    }

    function _stakeInputs(
        DungeonInputRequirement[] storage _inputRequirements,
        DungeonSuppliedInput[] storage _suppliedInputStorage,
        uint64[] calldata _inputQuantities)
    private
    {
        require(_inputQuantities.length == _inputRequirements.length, "Bad input length");

        for(uint256 i = 0; i < _inputQuantities.length; i++) {
            uint64 _quantity = _inputQuantities[i];
            DungeonInputRequirement storage _inputRequirement = _inputRequirements[i];

            if(_quantity == 0 && _inputRequirement.minQuantity == 0) {
                continue;
            } else {
                require(_quantity >= _inputRequirement.minQuantity
                    && (_inputRequirement.maxQuantity == 0 || _quantity <= _inputRequirement.maxQuantity), "Bad quantity");

                if(_inputRequirement.collection == address(etherOrcsItems)) {
                    if(_inputRequirement.willBurn) {
                        etherOrcsItems.burn(msg.sender, _inputRequirement.itemId, _quantity * 1 ether);
                    } else {
                        etherOrcsItems.safeTransferFrom(msg.sender, address(this), _inputRequirement.itemId, _quantity, "");
                    }
                } else if(_inputRequirement.collection == address(dungeonCrawlingItem)) {
                    if(_inputRequirement.willBurn) {
                        dungeonCrawlingItem.burn(msg.sender, _inputRequirement.itemId, _quantity);
                    } else {
                        dungeonCrawlingItem.noApprovalSafeTransferFrom(msg.sender, address(this), _inputRequirement.itemId, _quantity);
                    }
                } else {
                    revert("Unknown item collection");
                }
            }

            _suppliedInputStorage.push(DungeonSuppliedInput(
                _inputRequirement.collection,
                _inputRequirement.itemId,
                _quantity,
                _inputRequirement.willBurn));
        }
    }

    function endDungeonCrawl(
        DungeonCrawlingOutcome calldata _outcome,
        bytes calldata _signature)
    external
    whenNotPaused
    contractsAreSet
    {
        require(_isUserDungeonCrawling(msg.sender), "Not dungeon crawling");

        UserInfo storage _userInfo = userToInfo[msg.sender];

        bytes32 _messageHash = keccak256(
            abi.encodePacked(
                msg.sender,
                _userInfo.dungeonStartTime,
                _outcome.zugAmount,
                _outcome.boneShardsAmount,
                _outcome.overrideCooldownsAndUnlocks,
                _outcome.dungeonCrawlingItemIds,
                _outcome.dungeonCrawlingItemAmounts
            )
        );

        require(_verifySignature(_messageHash, _signature), "Invalid signature");

        // No need to clear other fields of UserInfo.
        // Saves on gas and will not be useful while dungeonStartTime is 0.
        // Also blocks re-entrance
        delete _userInfo.dungeonStartTime;

        if(_outcome.zugAmount > 0) {
            zug.mint(msg.sender, _outcome.zugAmount);
        }

        if(_outcome.boneShardsAmount > 0) {
            boneShards.mint(msg.sender, _outcome.boneShardsAmount);
        }

        if(_outcome.dungeonCrawlingItemIds.length > 0) {
            dungeonCrawlingItem.mintBatch(msg.sender, _outcome.dungeonCrawlingItemIds, _outcome.dungeonCrawlingItemAmounts);
        }

        DungeonInfo storage _dungeonInfo = dungeonNameToInfo[_userInfo.activeDungeonName];

        DungeonCrawlingInputs storage _activeInputs = dungeonCrawlingInputs[_userInfo.activeInputIndex];

        uint256 _entityCooldown;

        // Set the cooldown for all entities involved in this dungeon crawling.
        if(!_outcome.overrideCooldownsAndUnlocks && _dungeonInfo.dungeonCooldownPeriod > 0) {
            _entityCooldown = block.timestamp + _dungeonInfo.dungeonCooldownPeriod;
            for(uint256 i = 0; i < _activeInputs.entities.length; i++) {
                DungeonCrawlingEntity storage _entity = _activeInputs.entities[i];
                tokenIdToCooldownTime[_entity.tokenId] = _entityCooldown;
            }
        }

        uint192 _unlockTimeReady;

        // If no unlock period, release everything immediately.
        if(_outcome.overrideCooldownsAndUnlocks || _dungeonInfo.dungeonUnlockPeriod == 0) {
            _unstakeEntities(_activeInputs.entities);
            _unstakeItems(_activeInputs.inputs);
            for(uint256 i = 0; i < _activeInputs.entities.length; i++) {
                _unstakeItems(_activeInputs.tokenIdToEntityInputs[_activeInputs.entities[i].tokenId]);
            }
        } else {
            _unlockTimeReady = uint192(block.timestamp + _dungeonInfo.dungeonUnlockPeriod);
            _userInfo.lockedInputIndexes.push(
                LockedEntityInfo(
                    _unlockTimeReady,
                    uint64(_userInfo.activeInputIndex)
                )
            );
        }

        emit DungeonEnded(msg.sender, _userInfo.activeInputIndex, _entityCooldown, _unlockTimeReady, _outcome);
    }

    function unstakeItemsAndEntities()
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        uint256 _groupsUnstaked = _unstakeItemsAndEntitiesIfPossible();

        // If they do not have anything to unstake, don't let the txn go through.
        // Saves the user gas.
        require(_groupsUnstaked > 0, "Nothing to unstake");
    }

    // Unstaked all possible entities. Returns the number of "groups" of entities unstaked.
    // Rather inefficient as all groups are looped through. Thought of keeping a sorted list
    // of groups based on unlock time. However, the storage cost would outweight the looping 99% of the time.
    function _unstakeItemsAndEntitiesIfPossible() private returns(uint256) {

        UserInfo storage _userInfo = userToInfo[msg.sender];

        uint256 _totalGroupsUnstaked = 0;

        // Since this is an unsigned integer, if we were to do i >= 0, it would try and make i -1 and would fail.
        // Looping backwards so we can remove things from the list in an O(1) operation and not miss checking any
        // staked groups.
        for(uint256 i = _userInfo.lockedInputIndexes.length; i > 0; i--) {
            LockedEntityInfo storage _lockedEntityInfo = _userInfo.lockedInputIndexes[i - 1];
            uint64 _inputIndex = _userInfo.lockedInputIndexes[i - 1].inputIndex;

            if(block.timestamp < _lockedEntityInfo.unlockTime) {
                continue;
            }

            DungeonCrawlingInputs storage _inputs = dungeonCrawlingInputs[_inputIndex];

            _totalGroupsUnstaked++;
            _unstakeEntities(_inputs.entities);
            _unstakeItems(_inputs.inputs);
            for(uint256 j = 0; j < _inputs.entities.length; j++) {
                _unstakeItems(_inputs.tokenIdToEntityInputs[_inputs.entities[j].tokenId]);
            }

            _userInfo.lockedInputIndexes[i - 1] = _userInfo.lockedInputIndexes[_userInfo.lockedInputIndexes.length - 1];
            delete _userInfo.lockedInputIndexes[_userInfo.lockedInputIndexes.length - 1];
            _userInfo.lockedInputIndexes.pop();

            emit InputsUnstaked(_inputIndex);
        }

        return _totalGroupsUnstaked;
    }

    function _verifySignature(
        bytes32 _messageHash,
        bytes calldata _signature)
    private
    view
    returns(bool)
    {
        address _userThatSignedMessage = ECDSAUpgradeable.recover(
            ECDSAUpgradeable.toEthSignedMessageHash(_messageHash),
            _signature
        );

        return hasRole(DUNGEON_MASTER_ROLE, _userThatSignedMessage);
    }

    function _unstakeEntities(DungeonCrawlingEntity[] memory _entities) private {
        for(uint256 i = 0; i < _entities.length; i++) {
            DungeonCrawlingEntity memory _entity = _entities[i];
            if(_isOrc(_entity.tokenId)) {
                orcs.transfer(msg.sender, _entity.tokenId);
            } else {
                allies.transfer(msg.sender, _entity.tokenId);
            }

            delete tokenIdToOwner[_entity.tokenId];

            if(_entity.mainHandItemId > 0) {
                dungeonCrawlingItem.noApprovalSafeTransferFrom(address(this), msg.sender, _entity.mainHandItemId, 1);
            }
            if(_entity.offHandItemId > 0) {
                dungeonCrawlingItem.noApprovalSafeTransferFrom(address(this), msg.sender, _entity.offHandItemId, 1);
            }
            if(_entity.armorItemId > 0) {
                dungeonCrawlingItem.noApprovalSafeTransferFrom(address(this), msg.sender, _entity.armorItemId, 1);
            }
        }
    }

    function _unstakeItems(DungeonSuppliedInput[] memory _inputs) private {
        for(uint256 i = 0; i < _inputs.length; i++) {
            DungeonSuppliedInput memory _input = _inputs[i];
            if(_input.burned || _input.quantity == 0) {
                continue;
            }

            if(_input.collection == address(etherOrcsItems)) {
                etherOrcsItems.safeTransferFrom(
                    address(this),
                    msg.sender,
                    _input.itemId,
                    _input.quantity,
                    "");
            } else {
                dungeonCrawlingItem.noApprovalSafeTransferFrom(
                    address(this),
                    msg.sender,
                    _input.itemId,
                    _input.quantity);
            }
        }
    }

    // Nothing to do here. Needed for the ability to pull orcs/allies and stake them here.
    function pullCallback(address, uint256[] calldata) external {

    }

    function _isUserDungeonCrawling(address _user) private view returns(bool) {
        return userToInfo[_user].dungeonStartTime > 0;
    }

    function _suppliedEntityInputsForUser(address _user) private view returns(InputsForEntity[] memory) {
        if(!_isUserDungeonCrawling(_user)) {
            return new InputsForEntity[](0);
        }
        DungeonCrawlingInputs storage _inputs = dungeonCrawlingInputs[userToInfo[_user].activeInputIndex];

        InputsForEntity[] memory _entityInputs = new InputsForEntity[](_inputs.entities.length);

        for(uint256 i = 0; i < _inputs.entities.length; i++) {
            uint256 _tokenId = _inputs.entities[i].tokenId;
            DungeonSuppliedInput[] storage _entityInputsStorage = _inputs.tokenIdToEntityInputs[_tokenId];
            _entityInputs[i].inputs = _entityInputsStorage;
        }

        return _entityInputs;
    }

    function _isOrc(uint256 _tokenId) private pure returns(bool) {
        return _tokenId < 5051;
    }

    function ownerOfEntity(uint256 _tokenId) public view returns(address) {
        return tokenIdToOwner[_tokenId];
    }
}