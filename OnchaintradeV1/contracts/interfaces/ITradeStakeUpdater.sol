// contracts/interfaces/ITradeStakeUpdater.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ITradeStakeUpdater {
    
    function swapIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256,
        address to,
        uint256 deadline
    ) external;
    
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external;

    function increasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool,
        uint256 _notionalDelta
    ) external;

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool,
        uint256,
        uint256 _notionalDelta,
        address
    ) external;

    function liquidatePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external;

}
