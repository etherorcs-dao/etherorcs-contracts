//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./MarketplaceState.sol";

abstract contract MarketplaceContracts is Initializable, MarketplaceState {

    function __MarketplaceContracts_init() internal initializer {
        MarketplaceState.__MarketplaceState_init();
    }

    function setContracts(
        address _zugAddress,
        address _etherOrcItemsAddress,
        address _dungeonCrawlingItemAddress,
        address _wethAddress,
        address _wethFeeRecipient)
    external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE)
    {
        zug = IZug(_zugAddress);
        etherOrcsItems = IEtherOrcsItems(_etherOrcItemsAddress);
        dungeonCrawlingItem = IDungeonCrawlingItem(_dungeonCrawlingItemAddress);
        weth = IWeth(_wethAddress);
        wethFeeRecipient = _wethFeeRecipient;
    }

    modifier contractsAreSet() {
        require(areContractsSet(), "Marketplace: Contracts aren't set");
        _;
    }

    function areContractsSet() public view returns(bool) {
        return address(zug) != address(0)
            && address(etherOrcsItems) != address(0)
            && address(dungeonCrawlingItem) != address(0)
            && address(weth) != address(0)
            && wethFeeRecipient != address(0);
    }
}