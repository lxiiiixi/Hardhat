// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFuture {
    // 交易对状态
    enum PairStatus {
        unlist, // 下架中
        list, // 上架中
        stop_open, // 无法加仓，开仓，只能减仓
        stop // 只能清算
    }


    function tokenDecimals(address token) external view returns (uint8);

    function tradingFeeRates(bytes32 key) external view returns (uint256);

    function maxMaintanenceMarginRatios(bytes32 key) external view returns (uint256);

    function minMaintanenceMarginRatios(bytes32 key) external view returns (uint256);

    function maxPositionUsdWithMaxLeverages(bytes32 key) external view returns (uint256);

    function maxLeverages(bytes32 key) external view returns (uint256);

    function maxTotalLongSizes(bytes32 key) external view returns (uint256);

    function maxTotalShortSizes(bytes32 key) external view returns (uint256);

    function cumulativeLongFundingRates(bytes32 key) external view returns (int256);

    function cumulativeShortFundingRates(bytes32 key) external view returns (int256);

    function longFundingRates(bytes32 key) external view returns (int256);

    function shortFundingRates(bytes32 key) external view returns (int256);

    function lastFundingTimestamps(bytes32 key) external view returns (uint256);

    function collateralInsuranceFunds(address addr) external view returns (uint256);

    function protocolUnrealizedFees(bytes32 key) external view returns (uint256);

    function totalShortSizes(bytes32 key) external view returns (uint256);

    function totalLongSizes(bytes32 key) external view returns (uint256);

    function totalLongOpenNotionals(bytes32 key) external view returns (uint256);

    function totalShortOpenNotionals(bytes32 key) external view returns (uint256);

    function getPairKey(address _collateralToken, address _indexToken)
        external
        pure
        returns (bytes32);

    function getPairStatus(address _collateralToken, address _indexToken)
        external
        view
        returns (PairStatus);

    function getUtilisationRatio(
        address _collateralToken,
        address _indexToken,
        int256 _longSizeDelta,
        int256 _shortSizeDelta
    ) external view returns (uint256);

    function getPosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    )
        external
        view
        returns (
            uint256 margin,
            uint256 openNotional,
            uint256 size,
            int256 entryFundingRate
        );

    function getMaintanenceMarginRatio(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external view returns (uint256);

    function getPositionEntryPrice(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external view returns (uint256 collateralPrice, uint256 indexPrice);

    function getPrice(address _token) external view returns (uint256);

    function increaseMargin(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external;

    function decreaseMargin(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _marginDelta,
        address _receiver
    ) external;

    function increasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta
    ) external;

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        address _receiver
    ) external returns (uint256);

    function decreasePositionByRatio(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        address _receiver
    ) external returns(uint256);

    function increaseInsuranceFund(address _collateralToken) external;

    function liquidatePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external;

    function validateLiquidate(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        bool _raise
    ) external view returns (bool shouldLiquidate);

    function token1ToToken2(
        address token1,
        int256 token1Amount,
        address token2
    ) external view returns (int256);
}
