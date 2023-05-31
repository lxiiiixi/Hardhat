// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ISwap} from "../interfaces/ISwap.sol";
import {ITradeStakeUpdater} from "../interfaces/ITradeStakeUpdater.sol";
import "hardhat/console.sol";


contract SwapRouter {
    using SafeERC20 for IERC20;

    IWETH internal immutable WETH;
    ISwap internal immutable swap;
    IERC20 internal immutable osd;
    ITradeStakeUpdater internal immutable tradeStakeUpdater;

    constructor(address _weth, address _swap, address _osd, address _tradeStakeUpdater) {
        WETH = IWETH(_weth);
        swap = ISwap(_swap);
        osd = IERC20(_osd);
        tradeStakeUpdater = ITradeStakeUpdater(_tradeStakeUpdater);
    }

    function swapOut(        
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external payable {
        tradeStakeUpdater.swapOut(tokenIn, tokenOut, amountInMax, amountOut, to, deadline);
        if (address(tokenIn) == address(WETH)){
            // eth -> weth
            require(amountInMax == msg.value, "AMOUNTIN_MAX_EUQAL_ETH");
            WETH.deposit{value: msg.value}();
            WETH.approve(address(swap), msg.value);
            uint256 amountIn = swap.swapOut(tokenIn, tokenOut, amountInMax, amountOut, to, deadline);
            // change token in
            uint256 amountInChange = amountInMax - amountIn;
            if (amountInChange > 0) {
                WETH.withdraw(amountInChange);
                payable(to).transfer(amountInChange);
            }
        } else if (address(tokenOut) == address(WETH)) {
            // token -> router
            IERC20(address(tokenIn)).safeTransferFrom(to, address(this), amountInMax);
            IERC20(address(tokenIn)).approve(address(swap), amountInMax);
            // call swapOut
            uint256 amountIn = swap.swapOut(tokenIn, tokenOut, amountInMax, amountOut, address(this), deadline);
            // weth -> to
            WETH.withdraw(amountOut);
            payable(to).transfer(amountOut);
            // amountInChange -> to
            uint256 amountInChange = amountInMax - amountIn;
            if (amountInChange > 0) {
                IERC20(address(tokenIn)).transfer(to, amountInChange);
            }
        } else {
            // token -> router
            IERC20(address(tokenIn)).safeTransferFrom(to, address(this), amountInMax);
            IERC20(address(tokenIn)).approve(address(swap), amountInMax);
            // call swapOutn
            uint256 amountIn = swap.swapOut(tokenIn, tokenOut, amountInMax, amountOut, to, deadline);
            // amountInChange -> to
            uint256 amountInChange = amountInMax - amountIn;
            if (amountInChange > 0) {
                IERC20(address(tokenIn)).transfer(to, amountInChange);
            }
        }
    }

    function swapIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external payable {
        tradeStakeUpdater.swapIn(tokenIn, tokenOut, amountIn, amountOutMin, to, deadline);
        if (address(tokenIn) == address(WETH)){
            // eth -> weth
            require(amountIn == msg.value, "AMOUNTIN_EUQAL_ETH");
            WETH.deposit{value: msg.value}();
            WETH.approve(address(swap), msg.value);
            // swapIn
            swap.swapIn(tokenIn, tokenOut, amountIn, amountOutMin, to, deadline);
        } else if (address(tokenOut) == address(WETH)) {
            // token -> router
            IERC20(address(tokenIn)).safeTransferFrom(to, address(this), amountIn);
            IERC20(address(tokenIn)).approve(address(swap), amountIn);
            // swapIn
            uint256 amountOut = swap.swapIn(tokenIn, tokenOut, amountIn, amountOutMin, address(this), deadline);
            // weth -> to
            WETH.withdraw(amountOut);
            payable(to).transfer(amountOut);
        } else {
            // token -> router
            IERC20(address(tokenIn)).safeTransferFrom(to, address(this), amountIn);
            IERC20(address(tokenIn)).approve(address(swap), amountIn);
            // swapIn
            swap.swapIn(tokenIn, tokenOut, amountIn, amountOutMin, to, deadline);
        }
    }

    function addLiquidity(
        address token,
        uint256 amount,
        address to,
        uint256 deadline
    ) external payable returns (uint256) {
        require(to == msg.sender, "To need eq msg.sender");
        if (address(token) == address(WETH)) {
            require(amount == msg.value, "Eth value must equal amount");
            WETH.deposit{value: msg.value}();
            WETH.approve(address(swap), msg.value);
        } else {
            IERC20(address(token)).safeTransferFrom(to, address(this), amount);
            IERC20(address(token)).approve(address(swap), amount);
        }
        uint256 liquidity = swap.addLiquidity(token, amount, to, deadline);
        return liquidity;
    }

    function removeLiquidity(
        address token,
        uint256 liquidity,
        address to,
        uint256 deadline
    ) external payable returns (uint256, uint256) {
        require(to == msg.sender, "To need eq msg.sender");
        (address liquidityAddress, , ,) = swap.getPoolInfo(token);
        IERC20(liquidityAddress).safeTransferFrom(to, address(this), liquidity);
        IERC20(liquidityAddress).approve(address(swap), liquidity);
        if (address(token) == address(WETH)){
            // call swap
            (uint256 amount, uint256 amountOsd) = swap.removeLiquidity(token, liquidity, address(this), deadline);
            // unwrapped weth
            WETH.withdraw(amount);
            // transfer eth to account
            payable(to).transfer(amount);
            // 
            if (amountOsd > 0) {
                osd.safeTransfer(to, amountOsd);
            }
            return (amount, amountOsd);
        } else {
            (uint256 amount, uint256 amountOsd) = swap.removeLiquidity(token, liquidity, to, deadline);
            return (amount, amountOsd);
        }
    }


    function getWETHAddress() external view returns (address) {
        return address(WETH);
    }

    /**
     * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
     */
    receive() external payable {
        require(msg.sender == address(WETH), "Receive not allowed");
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }
    

}