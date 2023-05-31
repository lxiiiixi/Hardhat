// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapForFuture {
    // in swap: IERC20(reserveToken).safeTransferFrom(from, swapPool, amount)
    function settleFutureProfit(
        address reserveToken,
        uint256 amount,
        address from
    ) external;

    function swapIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256);
}
