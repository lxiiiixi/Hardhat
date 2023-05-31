// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library FutureMath {
    // decimal for trading fee rate
    uint256 internal constant TRADING_FEE_RATE_PRECISION = 1e9;
    // decimal for funding fee rate
    uint256 internal constant FUNDING_RATE_PRECISION = 1e10;
    // leverage decimal
    uint256 internal constant LEVERAGE_PRECISION = 1e9;
    // margin ratio decimal
    uint256 internal constant MARGIN_RATIO_PRECISION = 1e9;
    // utilisation decimal
    uint256 internal constant UTILISATION_RATIO_PRECISION = 1e9;
    // price decimal
    uint256 internal constant PRICE_PRECISION = 1e30;
    // 1 usd decimal
    uint256 internal constant ONE_USD = PRICE_PRECISION;
    // max value of u256
    uint256 internal constant MAX_UINT256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    // max maintenance margin ratio
    uint256 internal constant MAX_MR = 1e9 * 1e9;

    // amount of token1 expressed in token2 with their respective price //token1 => token2
    function token1ToToken2(
        uint256 token1Amount,
        uint256 token1Price,
        uint8 token1Decimal,
        uint256 token2Price,
        uint8 token2Decimal
    ) internal pure returns (uint256) {
        // token1Usd = (token1Amount / (10**token1Decimal)) * token1Price
        // token2Amount = (token1Usd / token2Price) * (10**token2Decimal)
        // token2Amount = token1Amount * token1Price * (10 ** token2Decimal) / (token2Price * (10 ** token1Decimal))

        if (token1Decimal > token2Decimal) {
            return
                (token1Amount * token1Price) /
                (token2Price * (10**(token1Decimal - token2Decimal)));
        } else {
            // todo potential overflow???
            // usdc => dai
            // token1Amount = 300,000,000 * 1e18 = 3e8 * 1e18
            // token1Price = 1e30
            // 10 ** (18 - 6) = 1e12
            return
                (token1Amount * token1Price * (10**(token2Decimal - token1Decimal))) / token2Price;
        }
    }
}
