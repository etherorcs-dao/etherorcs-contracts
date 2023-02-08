//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./MarketplaceContracts.sol";

contract Marketplace is Initializable, MarketplaceContracts {

    using SafeERC20Upgradeable for IWeth;

    function initialize() external initializer {
        MarketplaceContracts.__MarketplaceContracts_init();
    }

    function setBurnFee(uint256 _burnFee) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        require(_burnFee < 100000, "Marketplace: Bad burn fee");
        burnFee = _burnFee;

        emit BurnFeeUpdated(burnFee);
    }

    function setWethFeeSteps(WethFeeStep[] calldata _wethFeeSteps) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        delete wethFeeSteps;

        for(uint256 i = 0; i < _wethFeeSteps.length; i++) {
            WethFeeStep calldata _step = _wethFeeSteps[i];
            if(i == _wethFeeSteps.length - 1) {
                require(_step.maxZugAmount == type(uint256).max, "Marketplace: Bad max zug amount");
            }
            wethFeeSteps.push(_step);
        }

        emit WethFeeStepsUpdated(_wethFeeSteps);
    }

    function setMaticFeeSteps(MaticFeeStep[] calldata _maticFeeSteps) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        delete maticFeeSteps;

        for(uint256 i = 0; i < _maticFeeSteps.length; i++) {
            MaticFeeStep calldata _step = _maticFeeSteps[i];
            if(i == _maticFeeSteps.length - 1) {
                require(_step.maxZugAmount == type(uint256).max, "Marketplace: Bad max zug amount");
            }
            maticFeeSteps.push(_step);
        }

        emit MaticFeeStepsUpdated(_maticFeeSteps);
    }

    function createListing(
        TradeableCollection _collection,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(_expirationTime > block.timestamp, "Marketplace: Invalid expiration time");
        require(_pricePerItem >= MIN_PRICE, "Marketplace: Below min price");
        require(_quantity > 0, "Marketplace: Nothing to list");

        uint256 _quantityOwnedByUser;

        if(_collection == TradeableCollection.ETHER_ORCS_ITEMS) {
            _quantityOwnedByUser = etherOrcsItems.balanceOf(msg.sender, _tokenId);
        } else if(_collection == TradeableCollection.DUNGEON_CRAWLING_ITEM) {
            _quantityOwnedByUser = dungeonCrawlingItem.balanceOf(msg.sender, _tokenId);

            require(!dungeonCrawlingItem.isTokenSoulbound(_tokenId), "Cannot list a soulbound token");
        } else {
            revert("Marketplace: Unknown collection");
        }

        require(_quantityOwnedByUser >= _quantity, "Marketplace: Must hold enough items");

        listings[_collection][_tokenId][msg.sender] = Listing(
            _quantity,
            _pricePerItem,
            _expirationTime
        );

        emit ItemListedOrUpdated(
            msg.sender,
            _collection,
            _tokenId,
            _quantity,
            _pricePerItem,
            _expirationTime
        );
    }

    function cancelListings(
        CancelListingParams[] calldata _cancelListingParams)
    external
    onlyEOA
    {
        require(_cancelListingParams.length > 0);

        for(uint256 i = 0; i < _cancelListingParams.length; i++) {
            CancelListingParams calldata _params = _cancelListingParams[i];
            delete (listings[_params.collection][_params.tokenId][msg.sender]);
            emit ItemCanceled(msg.sender, _params.collection, _params.tokenId);
        }
    }

    function buyItems(
        BuyItemParams[] calldata _buyItemParams)
    external
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(_buyItemParams.length > 0, "Marketplace: Bad buy items array length");
        uint256 _totalZugSales;
        for(uint256 i = 0; i < _buyItemParams.length; i++) {
            _totalZugSales += _buyItem(_buyItemParams[i]);
        }

        _payWethFee(_totalZugSales);
    }

    function buyItemsMatic(
        BuyItemParams[] calldata _buyItemParams)
    external
    payable
    onlyEOA
    whenNotPaused
    contractsAreSet
    {
        require(_buyItemParams.length > 0, "Marketplace: Bad buy items array length");
        uint256 _totalZugSales;
        for(uint256 i = 0; i < _buyItemParams.length; i++) {
            _totalZugSales += _buyItem(_buyItemParams[i]);
        }

        _payMaticFee(_totalZugSales);
    }

    // Returns the total price of this item
    function _buyItem(BuyItemParams calldata _buyItemParams) private returns(uint256 zugSaleAmount) {
        // Validate buy order
        require(msg.sender != _buyItemParams.owner, "Marketplace: Cannot buy your own item");
        require(_buyItemParams.quantity > 0, "Marketplace: Nothing to buy");

        // Validate listing
        Listing memory listedItem = listings[_buyItemParams.collection][_buyItemParams.tokenId][_buyItemParams.owner];
        require(listedItem.quantity > 0, "Marketplace: not listed item");
        require(listedItem.expirationTime >= block.timestamp, "Marketplace: listing expired");
        require(listedItem.pricePerItem > 0, "Marketplace: listing price invalid");
        require(listedItem.quantity >= _buyItemParams.quantity, "Marketplace: not enough quantity");
        require(listedItem.pricePerItem <= _buyItemParams.maxPricePerItem, "Marketplace: price increased");

        if(_buyItemParams.collection == TradeableCollection.ETHER_ORCS_ITEMS) {
            uint256 _decimalAmount = uint256(_buyItemParams.quantity) * 1 ether;
            // No approval needed if burn/mint
            etherOrcsItems.burn(_buyItemParams.owner, _buyItemParams.tokenId, _decimalAmount);
            etherOrcsItems.mint(msg.sender, _buyItemParams.tokenId, _decimalAmount);
        } else if(_buyItemParams.collection == TradeableCollection.DUNGEON_CRAWLING_ITEM) {
            dungeonCrawlingItem.noApprovalSafeTransferFrom(_buyItemParams.owner, msg.sender, _buyItemParams.tokenId, _buyItemParams.quantity);
        } else {
            revert("Marketplace: Unknown collection");
        }

        zugSaleAmount = _payFees(listedItem, _buyItemParams.quantity, msg.sender, _buyItemParams.owner);

        // Announce sale
        emit ItemSold(
            _buyItemParams.owner,
            msg.sender,
            _buyItemParams.collection,
            _buyItemParams.tokenId,
            _buyItemParams.quantity,
            listedItem.pricePerItem
        );

        // Deplete or cancel listing
        if(listedItem.quantity == _buyItemParams.quantity) {
            delete listings[_buyItemParams.collection][_buyItemParams.tokenId][_buyItemParams.owner];
        } else {
            listings[_buyItemParams.collection][_buyItemParams.tokenId][_buyItemParams.owner].quantity -= _buyItemParams.quantity;
        }
    }

    // Pays the seller and zug fees. Returns the price for this item.
    function _payFees(Listing memory _listOrBid, uint256 _quantity, address _from, address _to) private returns(uint256) {
        // Handle purchase price payment
        uint256 _totalPrice = uint256(_listOrBid.pricePerItem) * _quantity;

        uint256 _burnFeeAmount = _totalPrice * burnFee / 100000;

        // Easier to burn and re-mint than try and approve and transfer.
        zug.burn(_from, _totalPrice);
        zug.mint(_to, _totalPrice - _burnFeeAmount);

        return _totalPrice;
    }

    function _payWethFee(uint256 _totalZugSales) private {
        uint256 _wethFeePerZug;
        for(uint256 i = 0; i < wethFeeSteps.length; i++) {
            WethFeeStep storage _step = wethFeeSteps[i];
            if(_totalZugSales > _step.maxZugAmount) {
                continue;
            }
            _wethFeePerZug = _step.wethFeePerZug;
            break;
        }

        if(_wethFeePerZug == 0) {
            return;
        }

        uint256 _wethFeeAmount = (_wethFeePerZug * _totalZugSales) / 1 ether;

        weth.safeTransferFrom(msg.sender, wethFeeRecipient, _wethFeeAmount);
    }

    function _payMaticFee(uint256 _totalZugSales) private {
        uint256 _maticFeePerZug;
        for(uint256 i = 0; i < maticFeeSteps.length; i++) {
            MaticFeeStep storage _step = maticFeeSteps[i];
            if(_totalZugSales > _step.maxZugAmount) {
                continue;
            }
            _maticFeePerZug = _step.maticFeePerZug;
            break;
        }

        uint256 _maticFeeAmount = (_maticFeePerZug * _totalZugSales) / 1 ether;

        require(msg.value == _maticFeeAmount, "Incorrect value for matic fee");

        (bool _success,) = wethFeeRecipient.call { value: msg.value }("");
        require(_success, "Matic failed to transfer");
    }
}

struct BuyItemParams {
    TradeableCollection collection;
    /// The identifier for the token to be bought
    uint256 tokenId;
    /// Current owner of the item(s) to be bought
    address owner;
    /// How many of this token identifier to be bought (or 1 for a ERC-721 token)
    uint64 quantity;
    /// The maximum price (in units of the paymentToken) for each token offered
    uint128 maxPricePerItem;
}

struct CancelListingParams {
    TradeableCollection collection;
    uint256 tokenId;
}