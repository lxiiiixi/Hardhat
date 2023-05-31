// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFutureUtil {
    function validateIncreasePosition() external view;

    function validateDecreasePosition() external view;

    function getUtilisationRatio(
        address _collateralToken,
        address _indexToken,
        int256 _longSizeDelta,
        int256 _shortSizeDelta
    ) external view returns (uint256);

    // return shouldUpdate, longFundingRates, shortFundingRates, timestamp
    function updateFundingRate(
        address _collateralToken,
        address _indexToken,
        int256 _longNotionalDelta,
        int256 _shortNotionalDelta,
        int256 _longSizeDelta,
        int256 _shortSizeDelta
    )
        external
        view
        returns (
            bool,
            int256,
            int256,
            int256,
            int256,
            uint256
        );

    function getTradingFee(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta
    ) external view returns (uint256);

    function getMaintanenceMarginRatio(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external view returns (uint256 marginRatio);
}
