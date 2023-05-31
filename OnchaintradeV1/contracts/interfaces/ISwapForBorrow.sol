// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface ISwapForBorrow {
    function borrow(
        address token,
        uint256 amount,
        address to
    ) external returns (uint256);

    function repay(
        address token,
        uint256 amount,
        address from
    ) external returns (uint256);

    function getAvailability(address token) external view returns (uint256);

    function protocolRevenueExtract(address token, uint256 amount, address to) external returns(bool);
}
