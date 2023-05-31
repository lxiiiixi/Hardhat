// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IFastPriceFeed {
    function lastUpdatedAt() external view returns (uint256);

    function lastUpdatedBlock() external view returns (uint256);

    function getPlainPrice(address token) external view returns (uint256);

    function getPrice(address _token, uint256 _referencePrice) external view returns (uint256);
}
