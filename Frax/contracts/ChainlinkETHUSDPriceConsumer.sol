// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./AggregatorV3Interface.sol";

// 使用 Chainlink 的 AggregatorV3Interface 接口获取 ETH/USD 价格
// 负责以美元为单位获取ETH的价格，要从这个合同中得到以美元为单位的ETH的价格，调用getLatestPrice()并除以getDecimals()返回的值
contract ChainlinkETHUSDPriceConsumer {
    AggregatorV3Interface internal priceFeed; // 示例化 AggregatorV3Interface 接口，并将其存储在 priceFeed 变量中

    constructor() public {
        // 传入的参数是 Chainlink 的 ETH/USD 价格数据源的地址
        priceFeed = AggregatorV3Interface(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        );
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price; // 返回最新的 ETH/USD 价格
    }

    function getDecimals() public view returns (uint8) {
        return priceFeed.decimals(); // 获取并返回价格数据的小数位数
    }
}
