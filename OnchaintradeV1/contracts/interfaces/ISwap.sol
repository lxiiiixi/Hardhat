// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface ISwap {
    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external returns (uint256);

    function swapIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256);

    function addLiquidity(
        address token,
        uint256 amount,
        address to,
        uint256 deadline
    ) external returns (uint256);

    function removeLiquidity(
        address token,
        uint256 liquidity,
        address to,
        uint256 deadline
    ) external returns (uint256, uint256);

    function getPoolInfo(address token)
        external
        view
        returns (
            address,
            uint256,
            bool,
            bool
        );
}
