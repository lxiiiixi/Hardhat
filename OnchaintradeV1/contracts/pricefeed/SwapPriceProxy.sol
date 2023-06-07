// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/IFastPriceFeed.sol";
import "../interfaces/IOracle.sol";

interface DecimalERC20 {
    function decimals() external view returns (uint8);
}

contract SwapPriceProxy is IOracle {
    address public feed;

    constructor(address _feed) {
        feed = _feed;
    }

    // function getPrice(address token) external view returns (uint256) {
    function getPrice(address token) external view override returns (uint256) {
        uint256 price = IFastPriceFeed(feed).getPlainPrice(token); // usd * 10**30
        uint8 decimal = DecimalERC20(token).decimals();

        // require(price > 0, "price_zero");

        // (price / (10**30)) * (10 ** (26 - decimal))

        // for btc: decimal = 8, returns = $/sat * 1e18 = $/btc * 10 **(26 - 8)
        // for eth: decimal = 18, returns = $/wei * 1e18 = $/eth * 10** (26 - 18)
        // for usdc: decimal = 6, returns =$/usdc * 10**(26 - 6)
        return price / (10 ** (decimal + 4));
    }
}
