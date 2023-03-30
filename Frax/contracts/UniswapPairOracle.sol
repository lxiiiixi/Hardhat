// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./FixedPoint.sol";

import "./UniswapV2OracleLibrary.sol";
import "./UniswapV2Library.sol";

// Fixed window oracle that recomputes the average price for the entire period once every period
// Note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
// 固定窗口预测器，每个周期重新计算整个期间的平均价格
contract UniswapPairOracle {
    using FixedPoint for *; // 用于处理定点数运算

    address owner_address;
    address timelock_address;

    uint public PERIOD = 3600; // 1 hour TWAP (time-weighted average price)

    IUniswapV2Pair public immutable pair; // Uniswap交易对地址
    // 交易对中的两个token地址
    address public immutable token0;
    address public immutable token1;

    // 交易对中的两个token的累计价格
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    uint32 public blockTimestampLast; // 最后一次更新价格的区块时间戳

    // 交易对中的两个token的平均价格
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == owner_address || msg.sender == timelock_address,
            "You are not an owner or the governance timelock"
        );
        _;
    }

    constructor(
        address factory,
        address tokenA,
        address tokenB,
        address _owner_address,
        address _timelock_address
    ) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(
            UniswapV2Library.pairFor(factory, tokenA, tokenB)
        );
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // Fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // Fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(
            reserve0 != 0 && reserve1 != 0,
            "UniswapPairOracle: NO_RESERVES"
        ); // Ensure that there's liquidity in the pair

        owner_address = _owner_address;
        timelock_address = _timelock_address;
    }

    // 设置合约的owner地址
    function setOwner(address _owner_address) external onlyByOwnerOrGovernance {
        owner_address = _owner_address;
    }

    // 设置治理timelock地址
    function setTimelock(
        address _timelock_address
    ) external onlyByOwnerOrGovernance {
        timelock_address = _timelock_address;
    }

    // 设置计算 TWAP 的时间周期
    function setPeriod(uint _period) external onlyByOwnerOrGovernance {
        PERIOD = _period;
    }

    // 更新交易对的价格数据并计算新的平均价格
    function update() external {
        (
            uint price0Cumulative,
            uint price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // Overflow is desired

        // Ensure that at least one full period has passed since the last update
        // 确保自上次更新以来至少过了一个完整的周期
        require(timeElapsed >= PERIOD, "UniswapPairOracle: PERIOD_NOT_ELAPSED");

        // Overflow is desired, casting never truncates
        // Cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // Note this will always return 0 before update has been called successfully for the first time.
    // 查询指定 token 在交易对中的价格
    function consult(
        address token,
        uint amountIn
    ) external view returns (uint amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, "UniswapPairOracle: INVALID_TOKEN");
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
