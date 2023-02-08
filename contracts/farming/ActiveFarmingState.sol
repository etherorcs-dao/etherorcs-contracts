//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";

import "./IActiveFarming.sol";
import "../dungeoncrawlingitem/IDungeonCrawlingItem.sol";
import "../world/IWorld.sol";
import "../external/IZug.sol";
import "../external/IOrcs.sol";
import "../external/IAllies.sol";
import "../external/IEtherOrcsItems.sol";
import "../external/IRandomizer.sol";
import "../../shared/UtilitiesUpgradeable.sol";

abstract contract ActiveFarmingState is IActiveFarming, UtilitiesUpgradeable {

    event EntityFarmingStarted(address _owner, uint16 _tokenId, uint64 _randomRequestKey, uint128 _startTime, uint32 _boost);
    event EntityFarmingClaimed(address _owner, uint16 _tokenId, uint256 _claimAmount, OutputOutcome[] _outcomes);

    event MinimumTimeForFarmingChanged(uint32 _minimumTimeForFarming);
    event MaximumTimeFarmingCapChanged(uint32 _maximumTimeFarmingCap);
    event MinimumTimeForItemsChanged(uint32 _minimumTimeForItems);

    event EntityBaseRatePerDayChanged(EntityType _entityType, uint128 _ratePerDay);
    event EntityOutputsChanged(EntityType _entityType, Output[] _outputs);

    event ItemBoostChanged(uint16 itemId, uint32 boost, uint8 amountNeeded);

    event NoBoostItemPercentChanged(uint256 noBoostItemPercent);

    struct OutputOutcome {
        Item[] items;
    }

    struct Item {
        uint128 itemId;
        uint128 itemAmount;
    }

    IZug internal zug;
    IOrcs internal orcs;
    IAllies internal allies;
    IDungeonCrawlingItem internal dungeonCrawlingItem;
    IEtherOrcsItems internal etherOrcsItems;
    IRandomizer internal randomizer;
    IWorld internal world;

    // The minimum amount of time for an entity to get any of the basic farming rewards when claiming.
    uint32 public minimumTimeForFarming;
    // This is the max time entities can be left and the basic farming rewards continue to grow.
    uint32 public maximumTimeFarmingCap;
    // The minimum amount of time for an entity to get any special items when claiming.
    uint32 public minimumTimeForItems;

    mapping(EntityType => ClassFarmingInfo) public typeToClassInfo;
    mapping(uint16 => FarmingInfo) public tokenIdToInfo;

    mapping(uint16 => ItemBoostInfo) public itemIdToBoostInfo;

    // A number where 100000 = 100%, is the percent of the farming rate that is used when no boost items are used.
    uint256 public noBoostItemPercent;

    function __ActiveFarmingState_init() internal initializer {
        UtilitiesUpgradeable.__Utilities_init();

        minimumTimeForFarming = 1 days;
        emit MinimumTimeForFarmingChanged(minimumTimeForFarming);
        minimumTimeForItems = 3 days;
        emit MinimumTimeForItemsChanged(minimumTimeForItems);
        maximumTimeFarmingCap = 7 days;
        emit MaximumTimeFarmingCapChanged(maximumTimeFarmingCap);

        noBoostItemPercent = 100000;
        emit NoBoostItemPercentChanged(noBoostItemPercent);
    }
}

struct ItemBoostInfo {
    // Slot 1 (40/256)
    uint32 boost;
    uint8 amountNeeded;
    uint216 emptySpace1;
}

struct ClassFarmingInfo {
    // Slot 1 (144/256)
    // The base rate of items farmed per day. Stored in Ether.
    uint128 baseRatePerDay;
    // The item this entity farms. If 0, assumed that this entity farms $ZUG.
    uint16 etherOrcItemId;
    uint112 emptySpace1;

    // Slot 2
    // The items this entity can find while farming
    Output[] outputs;
}

struct FarmingInfo {
    // Slot 1 (232/256)
    // The time this entity started (or continued) to craft.
    uint128 startTime;
    // A boost where 100,000 = 100%. A 5% boost would set this to 5,000. 200% = 200,000.
    uint32 boost;
    // The random number request key for this farming session.
    uint64 randomRequestKey;
    // Indicates if the items have already been claimed for this farming session.
    bool hasClaimedItems;
    uint24 emptySpace1;

    // Slot 2 (128/256)
    // The time the user last claimed. If set, this means they have claimed mid-farming.
    // If 0, or less than startTime, this means to use the startTime.
    uint128 claimedTime;
    uint128 emptySpace2;
}

// Not upgrade safe since stored in an array.
// Only use the emptySpace available
struct Output {
    OutputOption[] outputOptions;
    // This array will indicate how many times the outputOptions are rolled.
    // This may have 0, indicating that this Output may not be received.
    //
    uint8[] outputAmount;
    // This array will indicate the odds for each individual outputAmount.
    //
    uint32[] outputOdds;
}

// Not upgrade safe since stored in an array.
struct OutputOption {
    // Dungeon Crawling Item ONLY.
    //
    uint64 itemId;
    uint64 itemAmount;
    // The odds this option is picked out of the RecipeOutput group.
    //
    uint32 optionOdds;
}