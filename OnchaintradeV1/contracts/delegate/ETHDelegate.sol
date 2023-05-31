// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ISwap} from "../interfaces/ISwap.sol";
import "hardhat/console.sol";


contract ETHDelegate {
    using SafeERC20 for IERC20;

    IWETH internal immutable WETH;
    ISwap internal immutable swap;
    IERC20 internal immutable osd;

    constructor(address _weth, address _swap, address _osd) {
        WETH = IWETH(_weth);
        swap = ISwap(_swap);
        osd = IERC20(_osd);
    }

    function swapOut(        
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external payable {
        require(address(tokenIn) == address(WETH) || address(tokenOut) == address(WETH), "TokenIn or TokenOut must weth");
        if (address(tokenIn) == address(WETH)){
            // ethIn: otherOut
            WETH.deposit{value: msg.value}();
            WETH.approve(address(swap), msg.value);
            swap.swapOut(tokenIn, tokenOut, amountInMax, amountOut, to, deadline);
        } else if (address(tokenOut) == address(WETH)) {
            // otherIn: ethOut
            // token to delegate
            IERC20(address(tokenIn)).safeTransferFrom(to, address(this), amountInMax);
            IERC20(address(tokenIn)).approve(address(swap), amountInMax);
            // call swap
            uint256 _amountOut = swap.swapOut(tokenIn, tokenOut, amountInMax, amountOut, address(this), deadline);
            // unwrapped weth
            WETH.withdraw(_amountOut);
            // transfer eth to account
            payable(to).transfer(_amountOut);
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
        require(address(tokenIn) == address(WETH) || address(tokenOut) == address(WETH), "TokenIn or TokenOut must weth");
        if (address(tokenIn) == address(WETH)){
            // ethIn: otherOut
            WETH.deposit{value: msg.value}();
            WETH.approve(address(swap), msg.value);
            swap.swapIn(tokenIn, tokenOut, amountIn, amountOutMin, to, deadline);
        } else if (address(tokenOut) == address(WETH)) {
            // otherIn: ethOut
            // token to delegate
            IERC20(address(tokenIn)).safeTransferFrom(to, address(this), amountIn);
            IERC20(address(tokenIn)).approve(address(swap), amountIn);
            // call swap
            uint256 _amountOut = swap.swapIn(tokenIn, tokenOut, amountIn, amountOutMin, address(this), deadline);
            // unwrapped weth
            WETH.withdraw(_amountOut);
            // transfer eth to account
            payable(to).transfer(_amountOut);
        }
    }

    function addLiquidity(
        address token,
        uint256 amount,
        address to,
        uint256 deadline
    ) external payable returns (uint256) {
        require(address(token) == address(WETH), "Token must weth");
        require(amount == msg.value, "Eth value must equal amount");
        WETH.deposit{value: msg.value}();
        WETH.approve(address(swap), msg.value);
        uint256 liquidity = swap.addLiquidity(token, amount, to, deadline);
        return liquidity;
    }

    function removeLiquidity(
        address token,
        uint256 liquidity,
        address to,
        uint256 deadline
    ) external payable returns (uint256, uint256) {
        require(address(token) == address(WETH), "Token must weth");
        (address liquidityAddress, , ,) = swap.getPoolInfo(token);
        IERC20(liquidityAddress).safeTransferFrom(to, address(this), liquidity);
        IERC20(liquidityAddress).approve(address(swap), liquidity);
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