// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

// chainlink 的接口 用于获取基于链上的价格
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    // 根据轮次 ID 获取指定轮次的价格数据
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId, // 轮次 ID
            int256 answer, // 价格
            uint256 startedAt, // 数据开始时间
            uint256 updatedAt, // 数据更新时间
            uint80 answeredInRound // 答案所在轮次id
        );

    // 获取最新的价格数据
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
