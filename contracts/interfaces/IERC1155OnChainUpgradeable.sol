// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

interface IERC1155OnChainUpgradeable is IERC1155Upgradeable {
    function propertyValueForToken(uint256 _tokenId, string calldata _propertyName) external view returns(string memory);
    function isTokenSoulbound(uint256 _tokenId) external view returns(bool);
    function hasReachedMaxMintedAllowed(uint256 _tokenId) external view returns(bool);
}