// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IAllies {
    // Pulls the given allies to the calling address.
    function pull(address owner, uint256[] calldata ids) external;

    function transfer(address _to, uint256 _tokenId) external;

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external;

    function allies(uint256 id)
        external
        view
        returns (
            uint8 class,
            uint16 level,
            uint32 lvlProgress,
            uint16 modF,
            uint8 skillCredits,
            bytes22 details
        );
}