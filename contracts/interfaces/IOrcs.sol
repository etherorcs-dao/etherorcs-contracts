// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IOrcs {
    // Pulls the given orcs to the calling address.
    function pull(address _owner, uint256[] calldata _ids) external;

    function transfer(address _to, uint256 _tokenId) external;

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external;

    function orcs(uint256 id)
        external
        view
        returns (
            uint8 body,
            uint8 helm,
            uint8 mainhand,
            uint8 offhand,
            uint16 level,
            uint16 zugModifier,
            uint32 lvlProgress
        );
}