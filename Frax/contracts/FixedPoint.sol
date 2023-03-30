// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./Babylonian.sol";

/**
 * a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))
 * 一个用于处理二进制定点数的库（定点数是一种通过为小数部分保留固定数量的位来在二进制中表示十进制数的方法。）
 * 在以太坊智能合约中，所有数字都是整数，但有时需要在智能合约中处理小数。FixedPoint 提供了一种用于处理小数的方法，它使用固定小数位数表示定点数，可以在智能合约中进行高精度计算，并且不需要使用浮点运算器。
 *
 * 该库实现了分辨率为 1/2^112 的定点数
 * 该库包括多个用于编码、解码、乘法、除法、取倒数和平方根的定点数的函数。
 */

library FixedPoint {
    // range: [0, 2**112 - 1]
    // resolution: 1 / 2**112
    struct uq112x112 {
        uint224 _x;
    }

    // range: [0, 2**144 - 1]
    // resolution: 1 / 2**112
    struct uq144x112 {
        uint _x;
    }

    // uq112x112 和 uq144x112 结构用于表示具有 112 和 144 位定点数。这些结构存储一个单一的无符号整数值，小数部分的位数由 RESOLUTION 常量确定。
    uint8 private constant RESOLUTION = 112; // 意味着定点数的小数部分由整数值的低 112 位表示
    uint private constant Q112 = uint(1) << RESOLUTION;
    uint private constant Q224 = Q112 << RESOLUTION;

    // encode a uint112 as a UQ112x112
    // 将无符号整数转换为 uq112x112 类型
    function encode(uint112 x) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(x) << RESOLUTION);
    }

    // encodes a uint144 as a UQ144x112
    // 将无符号整数转换为 uq144x112 类型
    function encode144(uint144 x) internal pure returns (uq144x112 memory) {
        return uq144x112(uint256(x) << RESOLUTION);
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    // 将 uq112x112 除以无符号整数，返回另一个 uq112x112 值
    function div(
        uq112x112 memory self,
        uint112 x
    ) internal pure returns (uq112x112 memory) {
        require(x != 0, "FixedPoint: DIV_BY_ZERO");
        return uq112x112(self._x / uint224(x));
    }

    // multiply a UQ112x112 by a uint, returning a UQ144x112
    // reverts on overflow
    // 将 uq112x112 乘以无符号整数，返回一个 uq144x112 值
    function mul(
        uq112x112 memory self,
        uint y
    ) internal pure returns (uq144x112 memory) {
        uint z;
        require(
            y == 0 || (z = uint(self._x) * y) / y == uint(self._x),
            "FixedPoint: MULTIPLICATION_OVERFLOW"
        );
        return uq144x112(z);
    }

    // returns a UQ112x112 which represents the ratio of the numerator to the denominator
    // equivalent to encode(numerator).div(denominator)
    // 计算两个无符号整数的比率，并返回代表结果的 uq112x112 值。它还检查除以零的情况。
    function fraction(
        uint112 numerator,
        uint112 denominator
    ) internal pure returns (uq112x112 memory) {
        require(denominator > 0, "FixedPoint: DIV_BY_ZERO");
        return uq112x112((uint224(numerator) << RESOLUTION) / denominator);
    }

    // decode a UQ112x112 into a uint112 by truncating after the radix point
    // 通过在基数点后截断来将 uq112x112 值转换回无符号整数
    function decode(uq112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    // decode a UQ144x112 into a uint144 by truncating after the radix point
    // 通过在基数点后截断来将 uq144x112 值转换回无符号整数
    function decode144(uq144x112 memory self) internal pure returns (uint144) {
        return uint144(self._x >> RESOLUTION);
    }

    // take the reciprocal of a UQ112x112
    // 计算 uq112x112 值的倒数并返回另一个 uq112x112 值，它检查除以零的情况
    function reciprocal(
        uq112x112 memory self
    ) internal pure returns (uq112x112 memory) {
        require(self._x != 0, "FixedPoint: ZERO_RECIPROCAL");
        return uq112x112(uint224(Q224 / self._x));
    }

    // square root of a UQ112x112
    // 计算 uq112x112 值的平方根并返回另一个 uq112x112 值。它使用巴比伦方法来计算平方根。
    function sqrt(
        uq112x112 memory self
    ) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(Babylonian.sqrt(uint256(self._x)) << 56));
    }
}
