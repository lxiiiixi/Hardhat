// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v3-core/contracts/libraries/TransferHelper.sol";

struct PairData {
    address pair;
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
}

struct PairParam {
    address pair;
    bool isZeroForOne;
    uint256 tokenInFeeRate;
    uint256 tokenOutFeeRate;
}

struct SwapParam {
    uint256 amount;
    PairParam[] pairParams;
}

struct FlashLoanCallbackData {
    address tokenIn;
    SwapParam swapParam;
    uint256[] amountOuts;
}

contract Arbitrage {
    address internal immutable owner;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    uint feeDenominator = 100;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyArbitrage() {
        require(tx.origin == owner, "Not Arbitrage!");
        _;
    }

    function balance(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function pancakeCall(
        address /*sender*/,
        uint /*amount0*/,
        uint /*amount1*/,
        bytes calldata data
    ) public onlyArbitrage {
        FlashLoanCallbackData memory callbackData = abi.decode(
            data,
            (FlashLoanCallbackData)
        );

        TransferHelper.safeTransfer(
            callbackData.tokenIn,
            callbackData.swapParam.pairParams[0].pair,
            callbackData.swapParam.amount
        );

        for (
            uint i = 0;
            i < callbackData.swapParam.pairParams.length - 1;
            ++i
        ) {
            PairParam memory pairParam = callbackData.swapParam.pairParams[i];
            IUniswapV2Pair(pairParam.pair).swap(
                pairParam.isZeroForOne ? 0 : callbackData.amountOuts[i],
                pairParam.isZeroForOne ? callbackData.amountOuts[i] : 0,
                callbackData.swapParam.pairParams[i + 1].pair,
                ""
            );
        }
    }

    function swap(
        address tokenIn,
        SwapParam memory swapParam,
        uint256[] memory amountOuts
    ) public onlyArbitrage {
        FlashLoanCallbackData memory data = FlashLoanCallbackData(
            tokenIn,
            swapParam,
            amountOuts
        );
        PairParam memory pairParam = swapParam.pairParams[
            swapParam.pairParams.length - 1
        ];
        IUniswapV2Pair(pairParam.pair).swap(
            pairParam.isZeroForOne
                ? 0
                : amountOuts[swapParam.pairParams.length - 1],
            pairParam.isZeroForOne
                ? amountOuts[swapParam.pairParams.length - 1]
                : 0,
            address(this),
            abi.encode(data)
        );
    }

    function checkProfit(
        SwapParam memory swapParam
    ) public view returns (int256 profit) {
        (, uint256[] memory amountOutsReal) = getSwapAmountOuts(swapParam);
        uint256 amountOut = amountOutsReal[amountOutsReal.length - 1];
        profit = int256(amountOut) - int256(swapParam.amount);
    }

    function getSwapAmountOuts(
        SwapParam memory swapParam
    ) public view returns (uint256[] memory, uint256[] memory) {
        uint256 amountIn = swapParam.amount;
        uint256 amountOut;
        uint256[] memory amountOuts = new uint256[](
            swapParam.pairParams.length
        );
        uint256[] memory amountOutsReal = new uint256[](
            swapParam.pairParams.length
        );
        for (uint i = 0; i < swapParam.pairParams.length; ++i) {
            PairParam memory pairParam = swapParam.pairParams[i];
            PairData memory pairData = getPairData(pairParam.pair);
            uint256 realAmountIn = (amountIn *
                (feeDenominator - pairParam.tokenInFeeRate)) / feeDenominator;
            if (pairParam.isZeroForOne) {
                amountOut = getAmountOut(
                    realAmountIn,
                    pairData.reserve0,
                    pairData.reserve1
                );
            } else {
                amountOut = getAmountOut(
                    realAmountIn,
                    pairData.reserve1,
                    pairData.reserve0
                );
            }

            amountOuts[i] = amountOut;
            amountOutsReal[i] =
                (amountOut * (feeDenominator - pairParam.tokenOutFeeRate)) /
                feeDenominator;
            amountIn = amountOutsReal[i];
        }

        return (amountOuts, amountOutsReal);
    }

    function getPairData(address pair) internal view returns (PairData memory) {
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        return PairData(pair, token0, token1, reserve0, reserve1);
    }

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountIn) {
        unchecked {
            uint numerator = reserveIn * amountOut * 10000;
            uint denominator = (reserveOut - amountOut) * 9975;
            amountIn = (numerator / denominator) + 1;
        }
    }

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountOut) {
        unchecked {
            uint amountInWithFee = amountIn * 9975;
            uint numerator = amountInWithFee * reserveOut;
            uint denominator = (reserveIn * 10000) + amountInWithFee;
            amountOut = numerator / denominator;
        }
    }

    // 可以离线实现
    function optimize(
        SwapParam memory swapParam
    ) public view returns (uint256 amountInOp) {
        uint256 i;
        uint256 j;
        uint256 amountLeft = swapParam.amount;
        int256 profitInit = checkProfit(swapParam);

        if (profitInit < 0) {
            return 0;
        }

        uint256 amountRight;

        for (i = 0; i < 10; ++i) {
            amountRight = amountLeft * 10;
            swapParam.amount = amountRight;

            int256 profit = checkProfit(swapParam);
            if (profit > profitInit) {
                amountLeft = amountRight;
            } else {
                break;
            }
        }

        uint256 amountMid = (amountLeft + amountRight) / 2;
        swapParam.amount = amountMid;
        int256 profitMid = checkProfit(swapParam);

        for (i = 0; i < 25; ++i) {
            if ((amountRight - amountLeft) < 1e5) {
                break;
            }
            uint256 diff;
            int256 profitTemp;

            // 计算最优点是在 amountMid 左侧还是右侧
            swapParam.amount = amountMid - amountMid / 1e5;
            int256 profitLeft = checkProfit(swapParam);

            swapParam.amount = amountMid + amountMid / 1e5;
            int256 profitRight = checkProfit(swapParam);

            if (profitLeft > profitRight) {
                diff = amountMid - amountLeft;
                // 按照 diff指数除 不断接近 amountMid，直到profit超过。
                for (j = 1; j < 20; ++j) {
                    swapParam.amount = amountMid - (diff / 2 ** j);
                    profitTemp = checkProfit(swapParam);
                    if (profitTemp > profitMid) {
                        profitMid = profitTemp;
                        amountLeft = amountMid - (diff / 2 ** (j - 1));
                        amountRight = amountMid;
                        amountMid = swapParam.amount;
                        break;
                    }
                }
            } else {
                diff = amountRight - amountMid;
                for (j = 1; j < 20; ++j) {
                    swapParam.amount = amountMid + (diff / 2 ** j);
                    profitTemp = checkProfit(swapParam);
                    if (profitTemp > profitMid) {
                        profitMid = profitTemp;
                        amountLeft = amountMid;
                        amountRight = amountMid + (diff / 2 ** (j - 1));
                        amountMid = swapParam.amount;
                        break;
                    }
                }
            }
        }

        return amountMid;
    }
}
