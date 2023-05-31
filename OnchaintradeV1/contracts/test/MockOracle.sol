// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/IOracle.sol";

contract MockOracle is IOracle {
    mapping(address => uint256) public prices;
    mapping(address => uint256) public decimals;

    function getPrice(address token) external view override returns (uint256) {
        uint256 price = prices[token];
        uint256 dec = decimals[token];

        // for btc: decimal = 8, returns = $/sat * 1e18 = $/btc * 10 **(26 - 8)
        // for eth: decimal = 18, returns = $/wei * 1e18 = $/eth * 10** (26 - 18)
        // for usdc: decimal = 6, returns =$/usdc * 10**(26 - 6)
        return price * (10**(18 - dec));
    }

    function setPrice(
        address token,
        uint256 value,
        uint256 dec
    ) external {
        // value decimals: 8
        // total decimals: 8+18
        prices[token] = value; // $xxx * 10**8
        decimals[token] = dec; // token decimal
    }
}
