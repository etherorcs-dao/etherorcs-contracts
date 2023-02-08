//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";

import "./ICrafting.sol";
import "../dungeoncrawlingitem/IDungeonCrawlingItem.sol";
import "../external/IZug.sol";
import "../external/IEtherOrcsItems.sol";
import "../external/IBoneShards.sol";
import "../external/IRandomizer.sol";
import "../external/IOrcs.sol";
import "../external/IAllies.sol";
import "../../shared/UtilitiesUpgradeable.sol";
import "../world/IWorld.sol";

abstract contract CraftingDiamondState is ERC721HolderUpgradeable, ERC1155HolderUpgradeable, UtilitiesUpgradeable {

    event RecipeAdded(uint64 indexed _recipeId, CraftingRecipe _craftingRecipe);
    event RecipeDeleted(uint64 indexed _recipeId);

    event CraftingStarted(
        address indexed _user,
        uint256 indexed _craftingId,
        uint128 _timeOfCompletion,
        uint64 _recipeId,
        uint64 _randomRequestKey,
        uint64 _tokenId,
        ItemInfo[] suppliedInputs);
    event CraftingEnded(
        uint256 _craftingId,
        uint256 _zugRewarded,
        uint256 _boneShardRewarded,
        CraftingItemOutcome[] _itemOutcomes
    );

    IZug zug;
    IBoneShards boneShards;
    IDungeonCrawlingItem dungeonCrawlingItem;
    IEtherOrcsItems etherOrcsItems;
    IRandomizer randomizer;
    IOrcs orcs;
    IAllies allies;
    address vendorAddress;

    uint64 public recipeIdCur;

    mapping(string => uint64) public recipeNameToRecipeId;

    mapping(uint64 => CraftingRecipe) public recipeIdToRecipe;
    mapping(uint64 => CraftingRecipeInfo) public recipeIdToInfo;
    // Ugly type signature.
    // This allows an O(1) lookup if a given combination is an option for an input and the exact amount and index of that option.
    mapping(uint64 => mapping(uint256 => mapping(address => mapping(uint256 => uint256)))) internal recipeIdToInputIndexToCollectionToItemIdToOptionIndex;

    // Deprecated! Can be cheaper
    mapping(address => EnumerableSetUpgradeable.UintSet) internal userToCraftsInProgress;

    uint256 public craftingIdCur;
    mapping(uint256 => UserCraftingInfo) internal craftingIdToUserCraftingInfo;

    // The percent of zug that goes to the vendor.
    uint256 public percentToVendor;

    IWorld world;

    // Tracks the crafting id of the given entity.
    // NOTE: To save on gas, this is NOT cleared when the crafting instance is completed.
    // Txns that use this would revert if they tried to use the old crafting id as isCraftInProgress would be false.
    mapping(uint64 => uint256) public tokenIdToCraftingId;

    function __CraftingDiamondState_init() internal initializer {
        UtilitiesUpgradeable.__Utilities_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        craftingIdCur = 1;
        recipeIdCur = 1;

        percentToVendor = 20000;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155ReceiverUpgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _isValidRecipeId(uint64 _recipeId) internal view returns(bool) {
        return recipeIdToRecipe[_recipeId].recipeStartTime > 0;
    }
}

struct UserCraftingInfo {
    uint128 timeOfCompletion;
    uint64 recipeId;
    uint64 randomRequestKey;
    uint64 tokenId;
    address user;
    bool isCraftInProgress;
    ItemInfo[] nonBurnedInputs;
    mapping(address => mapping(uint256 => UserCraftingInput)) inputCollectionToItemIdToInput;
}

struct UserCraftingInput {
    uint64 itemAmount;
    bool wasBurned;
}

struct CraftingRecipe {
    string recipeName;
    // The time at which this recipe becomes available. Must be greater than 0.
    //
    uint256 recipeStartTime;
    // The time at which this recipe ends. If 0, there is no end.
    //
    uint256 recipeStopTime;
    // The cost of zug, if any, to craft this recipe.
    //
    uint256 zugCost;
    // The cost of bone shard, if any, to craft this recipe.
    //
    uint256 boneShardCost;
    // The number of times this recipe can be crafted globally.
    //
    uint64 maxCraftsGlobally;
    // The amount of time this recipe takes to complete. May be 0, in which case the recipe could be instant (if it does not require a random).
    //
    uint64 timeToComplete;
    // If _requires721, this is the minimum level required to be able to perform this
    //
    uint16 minimumLevelRequired;
    // If this requires an orc or ally.
    //
    bool requires721;
    // The inputs for this recipe.
    //
    RecipeInput[] inputs;
    // The outputs for this recipe.
    //
    RecipeOutput[] outputs;
}

// The info stored in the following struct is either:
// - Calculated at the time of recipe creation
// - Modified as the recipe is crafted over time
//
struct CraftingRecipeInfo {
    // The number of times this recipe has been crafted.
    //
    uint64 currentCraftsGlobally;
    // Indicates if the crafting recipe requires a random number. If it does, it will
    // be split into two transactions. The recipe may still be split into two txns if the crafting recipe takes time.
    //
    bool isRandomRequired;
}

// This struct represents a single input requirement for a recipe.
// This may have multiple inputs that can satisfy the "input".
//
struct RecipeInput {
    RecipeInputOption[] inputOptions;
    // Indicates the number of this input that must be provided.
    // i.e. 11 options to choose from. Any 3 need to be provided.
    // If isRequired is false, the user can ignore all 3 provided options.
    uint8 amount;
    // Indicates if this input MUST be satisifed.
    //
    bool isRequired;
}

// This struct represents a single option for a given input requirement for a recipe.
//
struct RecipeInputOption {
    // Either EtherOrcItems or DungeonCrawlingItems.
    //
    ItemInfo itemInfo;
    // Indicates if this input is burned or not.
    //
    bool isBurned;
    // The amount of time using this input will reduce the recipe time by.
    //
    uint64 timeReduction;
    // The amount of zug using this input will reduce the cost by.
    //
    uint256 zugReduction;
    // The amount of bone shard using this input will reduce the cost by.
    //
    uint256 boneShardReduction;
}

// Represents an output of a recipe. This output may have multiple options within it.
// It also may have a chance associated with it.
//
struct RecipeOutput {
    RecipeOutputOption[] outputOptions;
    // This array will indicate how many times the outputOptions are rolled.
    // This may have 0, indicating that this RecipeOutput may not be received.
    //
    uint8[] outputAmount;
    // This array will indicate the odds for each individual outputAmount.
    //
    OutputOdds[] outputOdds;
}

// An individual option within a given output.
//
struct RecipeOutputOption {
    // Dungeon Crawling Item ONLY. May be 0.
    //
    uint64 itemId;
    // The min and max for item amount, if different, is a linear odd with no boosting.
    //
    uint64 itemAmountMin;
    uint64 itemAmountMax;
    uint128 zugAmount;
    uint128 boneShardAmount;
    // The odds this option is picked out of the RecipeOutput group.
    //
    OutputOdds optionOdds;
}

// This is a generic struct to represent the odds for any output. This could be the odds of how many outputs would be rolled,
// or the odds for a given option.
//
struct OutputOdds {
    uint32 baseOdds;
    address boostItemCollection;
    // The itemId to boost these odds. If this shows up ANYWHERE in the inputs, it will be boosted.
    //
    uint64 boostItemId;
    // The odds if the boost collection/item is supplied as an input.
    //
    uint32 boostOdds;
}

// For event
struct CraftingItemOutcome {
    uint64[] itemIds;
    uint64[] itemAmounts;
}