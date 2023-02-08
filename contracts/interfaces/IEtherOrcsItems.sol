// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IEtherOrcsItems {
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes calldata _data) external;
    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;
    function balanceOf(address _owner, uint256 _id) external view returns (uint256);
    function mint(address _to, uint256 _id, uint256 _amount) external;
    function burn(address _from, uint256 _id, uint256 _amount) external;
}