// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

library Curve {
    function constantPrice(
        uint256 priceX,
        uint256 priceY,
        uint256 amountX
    ) internal pure returns (uint256 amountY) {
        return (amountX * priceX) / priceY;
    }

    function constantProductOut(
        uint256 x0,
        uint256 y0,
        uint256 x0Add
    ) internal pure returns (uint256 y0Remove) {
        uint256 x1 = x0 + x0Add;
        uint256 y1 = (x0 * y0) / x1;

        // x0 * y0 = (x0 + x0Add) * (y0 - y0Remove)
        // if (x0 + x0Add) > x0 * y0, set (y0 - y0Remove) = 1
        if (y1 == 0) {
            y1 = 1;
        }
        y0Remove = y0 - y1;
    }

    function constantProductIn(
        uint256 x0,
        uint256 y0,
        uint256 x0Remove
    ) internal pure returns (uint256 y0Add) {
        uint256 x1 = x0 - x0Remove;
        uint256 y1 = (x0 * y0) / x1;
        y0Add = y1 - y0;
    }

    function getValueOut(
        uint256 reserve,
        uint256 value,
        bool usePriceFeed,
        uint256 reservePrice,
        uint256 amountIn
    ) internal pure returns (uint256 valueOut) {
        if (usePriceFeed) {
            require(reservePrice > 0, "price_zero");
            valueOut = constantPrice(reservePrice, 1e8, amountIn);
        } else {
            // x * y = k
            valueOut = constantProductOut(reserve, value, amountIn);
        }
    }

    function getValueIn(
        uint256 reserve,
        uint256 value,
        bool usePriceFeed,
        uint256 reservePrice,
        uint256 amountOut
    ) internal pure returns (uint256 valueIn) {
        if (usePriceFeed) {
            require(reservePrice > 0, "price_zero");
            valueIn = constantPrice(reservePrice, 1e8, amountOut);
        } else {
            valueIn = constantProductIn(reserve, value, amountOut);
        }
    }

    function getAmountOut(
        uint256 reserve,
        uint256 value,
        bool usePriceFeed,
        uint256 reservePrice,
        uint256 valueIn
    ) internal pure returns (uint256 amountOut) {
        if (usePriceFeed) {
            require(reservePrice > 0, "price_zero");
            amountOut = constantPrice(1e8, reservePrice, valueIn);
        } else {
            amountOut = constantProductOut(value, reserve, valueIn);
        }
    }

    function getAmountIn(
        uint256 reserve,
        uint256 value,
        bool usePriceFeed,
        uint256 reservePrice,
        uint256 valueOut
    ) internal pure returns (uint256 amountIn) {
        if (usePriceFeed) {
            require(reservePrice > 0, "price_zero");
            amountIn = constantPrice(1e8, reservePrice, valueOut);
        } else {
            amountIn = constantProductIn(value, reserve, valueOut);
        }
    }
}
