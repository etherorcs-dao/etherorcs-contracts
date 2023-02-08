//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./WorldContracts.sol";

contract World is Initializable, WorldContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        WorldContracts.__WorldContracts_init();
    }

    function transferEntitiesToActiveFarming(
        FarmingParams[] calldata _farmingParams)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(_farmingParams.length > 0);

        uint256[] memory _tokenIds = new uint256[](_farmingParams.length);

        for(uint256 i = 0; i < _farmingParams.length; i++) {
            _tokenIds[i] = _farmingParams[i].tokenId;
        }

        _validateAndTransferFromLocation(msg.sender, _tokenIds);

        for(uint256 i = 0; i < _farmingParams.length; i++) {
            // To
            // Done in batch

            // Finalize
            tokenIdToInfo[_tokenIds[i]].location = Location.ACTIVE_FARMING;
        }

        uint64 _randomRequestKey = randomizer.request();

        activeFarming.startFarmingBatch(msg.sender, _randomRequestKey, _farmingParams);

        emit EntityLocationChanged(_tokenIds, msg.sender, Location.ACTIVE_FARMING);
    }

    // Called by the ERC721 contracts to rip entities out of the world contract. Could revert if entity is dungeon crawling
    //
    function adminTransferEntityOutOfWorld(
        address _originalOwner,
        uint16 _tokenId)
    external
    whenNotPaused
    contractsAreSet
    requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = _tokenId;

        _validateAndTransferFromLocation(_originalOwner, _tokenIds);

        // To
        // Unstake the entity.
        delete tokenIdToInfo[_tokenId];

        if(_isOrc(_tokenId)) {
            orcs.transfer(_originalOwner, _tokenId);
        } else {
            allies.transfer(_originalOwner, _tokenId);
        }

        // Finalize
        tokenIdToInfo[_tokenId].location = Location.NOT_STAKED;

        emit EntityLocationChanged(_tokenIds, _originalOwner, Location.NOT_STAKED);
    }


    // Only called by DungeonCrawling/Crafting when an entity is unstaked, but handled by the world location.
    //
    function adminSetLocationToWorld(
        address _originalOwner,
        uint16 _tokenId)
    external
    whenNotPaused
    {
        require(msg.sender == address(dungeonCrawling)
            || msg.sender == address(crafting), "Dungeon crawling or crafting only");

        tokenIdToInfo[_tokenId].location = Location.WORLD;

        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = _tokenId;

        emit EntityLocationChanged(_tokenIds, _originalOwner, Location.WORLD);
    }

    function transferEntitiesToCrafting(
        StartCraftingParams[] calldata _startCraftingParams)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        uint256[] memory _tokenIds = new uint256[](_startCraftingParams.length);

        for(uint256 i = 0; i < _startCraftingParams.length; i++) {
            _tokenIds[i] = _startCraftingParams[i].tokenId;
        }

        _validateAndTransferFromLocation(msg.sender, _tokenIds);

        for(uint256 i = 0; i < _startCraftingParams.length; i++) {
            StartCraftingParams calldata _params = _startCraftingParams[i];
            uint16 _tokenId = uint16(_params.tokenId);

            // Set to the CRAFTING location before starting the craft.
            // The Crafting contract checks this location to determine if an entity
            // is being tracked by the world contract.
            tokenIdToInfo[_tokenId].location = Location.CRAFTING;

            // To
            // Only emit this token as crafting if the recipe does not finish instantly.
            // If it does finish instantly, this entity will already be marked as at the WORLD
            // location via event.
            if(crafting.startCraftingWorld(msg.sender, _params)) {
                _tokenIds[i] = 0;
            }
        }

        emit EntityLocationChanged(_tokenIds, msg.sender, Location.CRAFTING);
    }

    function transferEntitiesToDungeonCrawling(
        string calldata _dungeonName,
        DungeonCrawlingEntity[] calldata _entities,
        uint64[][] calldata _entityInputQuantities,
        uint64[] calldata _inputQuantities)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        uint256[] memory _tokenIds = new uint256[](_entities.length);

        for(uint256 i = 0; i < _entities.length; i++) {
            _tokenIds[i] = _entities[i].tokenId;
        }

        _validateAndTransferFromLocation(msg.sender, _tokenIds);

        for(uint256 i = 0; i < _entities.length; i++) {
            DungeonCrawlingEntity calldata _entity = _entities[i];

            // To
            // Done in batch after the for loop, as all entities going to dungeon crawling are going to the same location.

            // Finalize
            tokenIdToInfo[_entity.tokenId].location = Location.DUNGEON_CRAWLING;
        }

        // Start dungeon crawling for all entities.
        dungeonCrawling.startDungeonCrawlWorld(msg.sender, _dungeonName, _entities, _entityInputQuantities, _inputQuantities);

        emit EntityLocationChanged(_tokenIds, msg.sender, Location.DUNGEON_CRAWLING);
    }

    function transferEntitiesOutOfWorld(
        uint256[] calldata _tokenIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(_tokenIds.length > 0);

        _validateAndTransferFromLocation(msg.sender, _tokenIds);

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint16 _tokenId = uint16(_tokenIds[i]);

            // To
            // Unstake the entity.
            delete tokenIdToInfo[_tokenId];

            if(_isOrc(_tokenId)) {
                orcs.transfer(msg.sender, _tokenId);
            } else {
                allies.transfer(msg.sender, _tokenId);
            }

            // Finalize
            tokenIdToInfo[_tokenId].location = Location.NOT_STAKED;
        }

        emit EntityLocationChanged(_tokenIds, msg.sender, Location.NOT_STAKED);
    }

    function _validateAndTransferFromLocation(address _owner, uint256[] memory _tokenIds) private {
        uint16[] memory _oldActiveFarmingTokenIds = new uint16[](_tokenIds.length);
        bool _hasEntityActiveFarming = false;

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint16 _tokenId = uint16(_tokenIds[i]);
            _requireValidEntityAndLocation(_owner, _tokenId);

            Location _oldLocation = _transferFromLocation(_owner, _tokenId);
            if(_oldLocation == Location.ACTIVE_FARMING) {
                _oldActiveFarmingTokenIds[i] = _tokenId;
                _hasEntityActiveFarming = true;
            }
        }

        if(_hasEntityActiveFarming) {
            activeFarming.endFarmingBatch(_owner, _oldActiveFarmingTokenIds);
        }
    }

    function _transferFromLocation(address _owner, uint16 _tokenId) private returns(Location _oldLocation) {
        _oldLocation = tokenIdToInfo[_tokenId].location;

        if(_oldLocation == Location.ACTIVE_FARMING) {

            // Active farming is ended in batch to save on gas.
        } else if(_oldLocation == Location.NOT_STAKED) {

            tokenIdToInfo[_tokenId].owner = _owner;

            // Will revert if user doesn't own token.
            uint256[] memory _pullArray = new uint256[](1);
            _pullArray[0] = _tokenId;

            if(_isOrc(_tokenId)) {
                orcs.pull(_owner, _pullArray);
            } else {
                allies.pull(_owner, _pullArray);
            }
        } else if(_oldLocation == Location.WORLD) {
            // If they are sitting in the World, there is nothing to be done here.
            //
        } else if(_oldLocation == Location.DUNGEON_CRAWLING) {
            // If they are actively dungeon crawling, this txn will revert as only the end method can
            // remove them from dungeon crawling.
            //
            // If they are in a dungeon crawling cooldown, we will try to remove them. Otherwise,
            // this will revert.
            //
            // If multiple entities are staked, we will only need to call adminUnstakeItemsAndEntities once. The next
            // entitiy we look at will have their location set to the WORLD, so we won't make it to this code.
            //
            dungeonCrawling.adminUnstakeItemsAndEntities(_owner);

            require(locationForStakedEntity(_tokenId) == Location.WORLD, "Entity is still locked or dungeon crawling");
        } else if(_oldLocation == Location.CRAFTING) {
            // End existing crafting session if possible
            //
            crafting.endCraftingForEntity(_owner, _tokenId);
        } else {
            revert("World: Unknown from location");
        }
    }

    function _requireValidEntityAndLocation(address _owner, uint16 _tokenId) private view {
        Location _oldLocation = tokenIdToInfo[_tokenId].location;

        // If the location is NOT_STAKED, the entity is not in the world yet, so checking the owner wouldn't make sense.
        //
        if(_oldLocation != Location.NOT_STAKED) {
            require(tokenIdToInfo[_tokenId].owner == _owner, "World: User does not own entity");
        }
    }

    function ownerForStakedEntity(uint256 _tokenId) public view returns(address) {
        address _owner = tokenIdToInfo[_tokenId].owner;
        require(_owner != address(0), "World: Entity is not staked");
        return _owner;
    }

    function locationForStakedEntity(uint256 _tokenId) public view returns(Location) {
        return tokenIdToInfo[_tokenId].location;
    }

    function isEntityStaked(uint256 _tokenId) public view returns(bool) {
        return tokenIdToInfo[_tokenId].owner != address(0);
    }

    function infoForEntity(uint256 _tokenId) external view returns(TokenInfo memory) {
        require(isEntityStaked(_tokenId), "World: Entity is not staked");
        return tokenIdToInfo[_tokenId];
    }

    function _isOrc(uint256 _tokenId) private pure returns(bool) {
        return _tokenId < 5051;
    }

    // Nothing to do here. Needed for the ability to pull orcs/allies and stake them here.
    function pullCallback(address, uint256[] calldata) external {

    }
}