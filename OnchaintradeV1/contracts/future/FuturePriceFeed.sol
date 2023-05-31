// SPDX-License-Identifier: MIT

import "../interfaces/IFuturePriceFeed.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IFastPriceFeed.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.0;

contract FuturePriceFeed is IFuturePriceFeed, Ownable {
    uint256 public constant PRICE_PRECISION = 10**30;
    uint256 public constant ONE_USD = PRICE_PRECISION;

    address public fastPriceFeed;

    // set priceFeed address
    function setFastPriceFeed(address _fastPriceFeed) external onlyOwner {
        fastPriceFeed = _fastPriceFeed;
    }

    // price = token_usd * 1e30
    // eg: eth_usd = $1200, then eth price = 1200 * 1e30
    // eg: dai_usd,usdc_usd = $1, then dai/usdc price = 1 * 1e30
    function getPrice(address _token) external view override returns (uint256) {
        if (_token == address(0)) {
            return ONE_USD;
        }
        uint256 price = IFastPriceFeed(fastPriceFeed).getPlainPrice(_token);
        require(price > 0, "price_zero");
        return price;
    }
}
