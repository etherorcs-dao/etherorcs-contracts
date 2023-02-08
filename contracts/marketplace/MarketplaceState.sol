//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IMarketplace.sol";
import "../../shared/UtilitiesUpgradeable.sol";
import "../external/IZug.sol";
import "../external/IEtherOrcsItems.sol";
import "../external/IWeth.sol";
import "../dungeoncrawlingitem/IDungeonCrawlingItem.sol";

abstract contract MarketplaceState is IMarketplace, UtilitiesUpgradeable {

    struct Listing {
        uint64 quantity;
        uint128 pricePerItem;
        uint64 expirationTime;
    }

    event ItemListedOrUpdated(
        address seller,
        TradeableCollection collection,
        uint256 tokenId,
        uint64 quantity,
        uint128 pricePerItem,
        uint64 expirationTime
    );

    event ItemCanceled(address indexed seller, TradeableCollection indexed collection, uint256 indexed tokenId);

    event ItemSold(
        address seller,
        address buyer,
        TradeableCollection collection,
        uint256 tokenId,
        uint64 quantity,
        uint128 pricePerItem
    );

    event BurnFeeUpdated(uint256 newBurnFee);
    event WethFeeStepsUpdated(WethFeeStep[] wethFeeSteps);
    event MaticFeeStepsUpdated(MaticFeeStep[] maticFeeSteps);

    IZug public zug;
    IEtherOrcsItems public etherOrcsItems;

    // The minimum price for which any item can be sold
    uint256 public constant MIN_PRICE = 1e9;

    // The % of the zug that will be burnt. Out of 100,000.
    uint256 public burnFee;

    /// @notice mapping for listings, maps: nftAddress => tokenId => offeror
    mapping(TradeableCollection => mapping(uint256 => mapping(address => Listing))) public listings;

    IDungeonCrawlingItem public dungeonCrawlingItem;
    IWeth public weth;
    address public wethFeeRecipient;

    WethFeeStep[] public wethFeeSteps;
    MaticFeeStep[] public maticFeeSteps;

    function __MarketplaceState_init() internal initializer {
        UtilitiesUpgradeable.__Utilities_init();
    }
}

enum TradeableCollection {
    ETHER_ORCS_ITEMS,
    DUNGEON_CRAWLING_ITEM
}

struct WethFeeStep {
    // The maximum zug amount to use this fee step as the weth fee rate, including maxZugAmount
    //
    uint256 maxZugAmount;

    // The weth amount per 1 $ZUG for this step. If this final price ends up in this step, this is the rate they will pay per zug.
    //
    uint256 wethFeePerZug;
}

struct MaticFeeStep {
    // The maximum zug amount to use this fee step as the matic fee rate, including maxZugAmount
    //
    uint256 maxZugAmount;

    // The matic amount per 1 $ZUG for this step. If this final price ends up in this step, this is the rate they will pay per zug.
    //
    uint256 maticFeePerZug;
}