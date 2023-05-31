// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFuturePriceFeed {
    function getPrice(address _token) external view returns (uint256);
}
