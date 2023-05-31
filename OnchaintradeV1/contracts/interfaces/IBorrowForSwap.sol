// contracts/interfaces/IBorrowForSwap.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IBorrowForSwap {
    function updateInterest(address asset, uint256 availability) external returns (bool);

    function getDebt(address asset)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}
