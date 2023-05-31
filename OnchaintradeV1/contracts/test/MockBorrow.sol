// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/IBorrowForSwap.sol";

contract MockBorrow is IBorrowForSwap {
    mapping(address => uint256) public debts;
    mapping(address => uint256) public availabilities;

    function updateInterest(address asset, uint256 availability) external override returns (bool) {
        availabilities[asset] = availability;
        return true;
    }

    function getDebt(address token) external view override returns (uint256, uint256, uint256) {
        return (debts[token], 0, 0);
    }

    function setDebt(address token, uint256 value) external {
        debts[token] = value;
    }
}
