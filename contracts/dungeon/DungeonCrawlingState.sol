//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";

import "../dungeoncrawlingitem/IDungeonCrawlingItem.sol";
import "../external/IZug.sol";
import "../external/IOrcs.sol";
import "../external/IAllies.sol";
import "../external/IEtherOrcsItems.sol";
import "../external/IBoneShards.sol";
import "../../shared/UtilitiesUpgradeable.sol";

abstract contract DungeonCrawlingState is ERC721HolderUpgradeable, ERC1155HolderUpgradeable, UtilitiesUpgradeable {

    event DungeonAdded(
        string _dungeonName,
        DungeonInfo _info);

    event DungeonStarted(
        address indexed _user,
        string _dungeonName,
        uint64 _dungeonInputsIndex,
        DungeonCrawlingEntity[] _entities,
        InputsForEntity[] _entityInputs,
        DungeonSuppliedInput[] _inputs);

    event DungeonEnded(
        address indexed _user,
        uint64 _dungeonInputsIndex,
        uint256 _cooldownTimeComplete,
        uint256 _unlockTimeReady,
        DungeonCrawlingOutcome _outcome);

    event DungeonTimesModified(
        string _dungeonName,
        uint64 _dungeonUnlockPeriod,
        uint64 _dungeonCooldownPeriod
    );

    event DungeonRemoved(
        string _dungeonName
    );

    event InputsUnstaked(
        uint64 _dungeonInputsIndex
    );

    bytes32 constant DUNGEON_MASTER_ROLE = keccak256("DUNGEON_MASTER");
    string constant EQUIPMENT_SLOT_PROPERTY_NAME = "Equipment Slot";
    string constant EQUIPMENT_MAIN_HAND = "Main Hand";
    string constant EQUIPMENT_OFF_HAND = "Off Hand";
    string constant EQUIPMENT_ARMOR = "Armor";
    string constant ORC_EQUIPPABLE = "Equippable by Orc?";
    string constant OGRE_EQUIPPABLE = "Equippable by Ogre?";
    string constant ROGUE_EQUIPPABLE = "Equippable by Rogue?";
    string constant SHAMAN_EQUIPPABLE = "Equippable by Shaman?";
    string constant YES = "Yes";

    IZug public zug;
    IBoneShards public boneShards;
    IOrcs public orcs;
    IAllies public allies;
    IDungeonCrawlingItem public dungeonCrawlingItem;
    IEtherOrcsItems public etherOrcsItems;

    mapping(string => DungeonInfo) public dungeonNameToInfo;

    mapping(address => UserInfo) public userToInfo;

    // Tracks the number of crawls a given entity has done for a given dungeon.
    mapping(string => mapping(uint256 => uint16)) public dungeonNameToTokenIdToNumberOfCrawls;

    mapping(uint256 => uint256) public tokenIdToCooldownTime;
    mapping(uint256 => address) public tokenIdToOwner;

    // Globally unique that tracks the inputs to dungeon crawling. Starts from 1.
    uint64 public dungeonInputsIndexCur;
    // A mapping used to store inputs for all users. The user's have possession of these inputs by having
    // the key of the inputs in this mapping. These inputs are never be removed once they are added to this array, as there
    // is no point, and it would cost more gas to remove.
    // This setup was chosen as copying arrays back in forth in storage/memory is a pain.
    mapping(uint64 => DungeonCrawlingInputs) internal dungeonCrawlingInputs;

    address public vendorAddress;

    // The percent of zug that goes to the vendor.
    uint256 public percentToVendor;

    function __DungeonCrawlingState_init() internal onlyInitializing {
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();
        UtilitiesUpgradeable.__Utilities_init();

        dungeonInputsIndexCur = 1;
        percentToVendor = 20000;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155ReceiverUpgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

struct DungeonInfo {
    // The global start time of this dungeon.
    uint256 startTime;
    // The global end time of this dungeon. May be 0 if no end time.
    uint256 endTime;
    // The amount of zug that must be burned to enter this dungeon.
    uint256 zugCost;
    // The time it takes after a given entity finishes this dungeon for it able to start crawling again.
    uint64 dungeonCooldownPeriod;
    // The time it takes after a given entity finishes this dungeon for the items/NFTs to be unstaked.
    uint64 dungeonUnlockPeriod;
    // The max limit of how many different "crawls" can occur with this dungeon. If 0, unlimited.
    uint64 maxNumberOfCrawlsGlobal;
    uint64 currentNumberOfCrawls;
    // The max limit of how many different "crawls" can occur with this dungeon per individual entity. If 0, unlimited.
    uint16 maxNumberOfCrawlsPerEntity;
    // The minimum number of entities that can be taken into the dungeon.
    uint8 minEntitiesPerCrawl;
    // The max number of entities that can be taken into the dungeon.
    uint8 maxEntitiesPerCrawl;
    // The minimum level required by all entities that will enter this dungeon.
    uint16 minimumLevel;
    DungeonInputRequirement[] entityInputs;
    DungeonInputRequirement[] inputs;
}

struct DungeonInputRequirement {
    // The item ID of the input.
    uint64 itemId;
    // The minimum quantity that is required for this input. If 0, this input is optional.
    uint32 minQuantity;
    // The maximum quantity that can be staked for this input. If 0, no maximum.
    uint32 maxQuantity;
    // The address of the 1155 collection
    address collection;
    // If this is true, the inputs will be burned when crawling starts. If false, they will be staked until the cooldown is over.
    bool willBurn;
}

struct UserInfo {
    // The start time of the user's dungeon. Acts as a flag to indicate if the user is dungeon crawling currently.
    uint256 dungeonStartTime;
    // The dungeon this user is in.
    string activeDungeonName;
    // The index of the inputs that are active. This will not be cleared after a user
    // has finished dungeon crawling. Use dungeonStartTime to indicate if a user is dungeon crawling.
    uint64 activeInputIndex;
    // The inputs from previous dungeon crawling runs that are still locked for this user.
    LockedEntityInfo[] lockedInputIndexes;
}

struct LockedEntityInfo {
    uint192 unlockTime;
    uint64 inputIndex;
}

struct DungeonCrawlingInputs {
    DungeonCrawlingEntity[] entities;
    mapping(uint256 => DungeonSuppliedInput[]) tokenIdToEntityInputs;
    DungeonSuppliedInput[] inputs;
}

struct DungeonCrawlingEntity {
    // tokenId indicates if the entity is an orc or ally, based on the number (orc < 5051)
    uint64 tokenId;
    uint64 mainHandItemId;
    uint64 offHandItemId;
    uint64 armorItemId;
}

// Needed as subgraph can't handle a double array [][]
struct InputsForEntity {
    DungeonSuppliedInput[] inputs;
}

struct DungeonSuppliedInput {
    address collection;
    uint64 itemId;
    uint64 quantity;
    bool burned;
}

struct DungeonCrawlingOutcome {
    uint256 zugAmount;
    uint256 boneShardsAmount;
    bool overrideCooldownsAndUnlocks;
    uint256[] dungeonCrawlingItemIds;
    uint256[] dungeonCrawlingItemAmounts;
}