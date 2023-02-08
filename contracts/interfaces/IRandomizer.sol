// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IRandomizer {
    function request() external returns (uint64 _randomKey);
    function getRandom(uint64 _randomKey) external view returns(uint256 _randomNumber);
}