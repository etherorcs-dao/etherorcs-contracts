// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IBoneShards is IERC20Upgradeable {
    function burn(address _from, uint256 _amount) external;
    function mint(address _from, uint256 _amount) external;
}