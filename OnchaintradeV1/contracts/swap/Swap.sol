// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";

import "./Liquidity.sol";
import "./Osd.sol";
import "./Curve.sol";

import "../interfaces/ISwapForBorrow.sol";
import "../interfaces/IBorrowForSwap.sol";
import "../interfaces/IOracle.sol";

interface DecimalERC20 {
    function decimals() external view returns (uint8);
}

contract Swap is Ownable, ISwapForBorrow {
    using SafeERC20 for IERC20;

    struct Pool {
        IERC20 token;
        Liquidity liquidity;
        uint256 reserve;
        uint256 lastRatioToken;
        uint256 lastRatioOsd;
        uint256 osd;
        // status? paused?
        uint256 createdAt;
        bool rebalancible;
        bool usePriceFeed;
        // type => rate
        // 0: default: used for token <=> osd
        // 1: used for token
        // 2: stable
        uint8 feeType;
        uint16[3] feeRates; // 150/1000000 = 0.15%
        uint8 revenueRate; // 70/100 = 70%
        uint256 revenueOsd;
        uint8 tokenDecimal;
    }

    enum OrderType {
        SELL,
        BUY
    }

    event Swapped(
        address indexed sender,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed to
    );
    event SwappedSingle(
        address indexed sender,
        address token,
        uint256 amountIn,
        uint256 amountOut,
        OrderType orderType
    );
    event PoolAmountUpdated(
        address indexed token,
        uint256 reserve,
        uint256 osd,
        uint256 ratioToken,
        uint256 ratioOsd
    );
    event AddLiquidity(
        address indexed token,
        uint256 tokenAmount,
        uint256 lpTokenAmount,
        address indexed to
    );
    event RemoveLiquidity(
        address indexed token,
        uint256 tokenAmount,
        uint256 osdAmount,
        address indexed to
    );
    event WitdhrawRevenueOsd(
        address indexed token,
        uint256 amount,
        address indexed to
    );
    event CaptureSwapFee(
        address indexed token,
        uint256 protocolFee,
        uint256 liquidityFee
    );
    event TokenListed(address indexed token, address liquidity);
    event Rebalance(address indexed token, uint256 osdAmount, uint256 lpAmount);

    mapping(address => Pool) public pools; // 地址 - Pool
    address[] public poolTokenList; // 池子token列表
    Osd public osd; // osd 代币
    IBorrowForSwap public $borrow; //
    address public priceFeed; // 价格源

    uint256 public constant OSD_PRICE = 1e8;

    constructor(address _osd) {
        osd = Osd(_osd);
    }

    modifier expires(uint256 deadline) {
        // solhint-disable-next-line not-rely-on-time
        require(deadline == 0 || deadline >= block.timestamp, "EXPIRED");
        _;
    }

    function listToken(
        address token,
        uint256 amount,
        uint256 amountOsd,
        address to
    ) external returns (uint256) {
        require(amount > 0, "ZERO_AMOUNT");
        require(amountOsd > 0, "ZERO_AMOUNT_OSD");

        Pool storage pool = pools[token];
        require(address(pool.token) == address(0), "POOL_EXISTS");
        require(token != address(osd), "CANNOT_LIST_OSD");

        poolTokenList.push(token);
        pool.token = IERC20(token);
        pool.liquidity = new Liquidity(token); // 基于 token 创建一个新的 Liquidity 合约实例
        // solhint-disable-next-line not-rely-on-time
        pool.createdAt = block.timestamp;

        pool.reserve = amount;
        pool.lastRatioToken = amount;
        pool.lastRatioOsd = amountOsd;
        pool.revenueRate = 70;
        pool.feeRates = [300, 150, 300];
        pool.tokenDecimal = DecimalERC20(token).decimals();
        // pool.osd = 0;
        // pool.revenueOsd = 0;

        pool.token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 liquidity = amount;
        {
            uint256 MIN_LIQUIDITY = 300;
            require(liquidity > MIN_LIQUIDITY, "AMOUNT_TOO_SMALL");
            pool.liquidity.mint(to, liquidity - MIN_LIQUIDITY);
            pool.liquidity.mint(address(this), MIN_LIQUIDITY); // avoid remove all liquidity;
            liquidity = liquidity - MIN_LIQUIDITY;
        }

        emit TokenListed(token, address(pool.liquidity));
        emit PoolAmountUpdated(
            address(pool.token),
            pool.reserve,
            pool.osd,
            pool.lastRatioToken,
            pool.lastRatioOsd
        );
        emit AddLiquidity(token, amount, liquidity, to);
        return liquidity;
    }

    function addLiquidity(
        address token,
        uint256 amount,
        address to,
        uint256 deadline
    ) external expires(deadline) returns (uint256) {
        Pool storage pool = pools[token];
        require(address(pool.token) != address(0), "POOL_NOT_EXISTS");

        uint256 liquidity = _liquidityOut(pool, amount);
        // 本方法的重点在于这里的计算：传入的资产数量计算出数据更新之前池子对应的流动性份额数量

        uint256 newReserve = pool.reserve += amount;
        $borrow.updateInterest(token, newReserve); // 更新记录的利息信息

        emit PoolAmountUpdated(
            address(pool.token),
            pool.reserve,
            pool.osd,
            pool.lastRatioToken,
            pool.lastRatioOsd
        );

        emit AddLiquidity(token, amount, liquidity, to);

        pool.token.safeTransferFrom(msg.sender, address(this), amount);
        pool.liquidity.mint(to, liquidity);
        return liquidity;
    }

    function removeLiquidity(
        address token,
        uint256 liquidity,
        address to,
        uint256 deadline
    ) external expires(deadline) returns (uint256, uint256) {
        Pool storage pool = pools[token];
        require(address(pool.token) != address(0), "POOL_NOT_EXISTS");

        (uint256 amount, uint256 amountOsd) = _liquidityIn(pool, liquidity);
        // 根据池子信息和希望移除的流动性数量计算出对应的token数量和osd数量

        require(pool.reserve > amount, "INSUFF_RESERVE");
        uint256 newReserve = pool.reserve -= amount;
        $borrow.updateInterest(token, newReserve);
        pool.osd -= amountOsd;

        pool.liquidity.burn(msg.sender, liquidity);
        pool.token.safeTransfer(to, amount);
        osd.mint(to, amountOsd);

        emit PoolAmountUpdated(
            address(pool.token),
            pool.reserve,
            pool.osd,
            pool.lastRatioToken,
            pool.lastRatioOsd
        );
        emit RemoveLiquidity(token, amount, amountOsd, to);

        return (amount, amountOsd);
    }

    function withdrawRevenueOsd(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.revenueOsd >= amount, "INSUFF_REVENUE");
        pool.revenueOsd -= amount;
        osd.mint(to, amount);
        emit WitdhrawRevenueOsd(token, amount, to);
    }

    function getRevenueOsd(address token) external view returns (uint256) {
        Pool storage pool = pools[token];
        return pool.revenueOsd;
    }

    function _getTokenPrice(
        address token
    ) internal view returns (uint256 price) {
        if (token == address(osd)) {
            return OSD_PRICE;
        }
        Pool storage pool = pools[token];
        if (!pool.usePriceFeed) {
            return 0;
        }
        price = IOracle(priceFeed).getPrice(token);
        console.log("_getTokenPrice by oracle:", price);
        require(price > 0, "PRICE_ZERO");
    }

    // 计算从流动性池pool中取出指定amount数量的资产所对应的流动性份额数量
    function _liquidityOut(
        Pool storage pool,
        uint256 amount
    ) internal view returns (uint256 liquidity) {
        uint256 netValue;
        uint256 valueIn = amount;
        if (pool.usePriceFeed) {
            (uint256 reserve, ) = _getReserve(pool);
            uint256 tokenPrice = _getTokenPrice(address(pool.token));
            netValue = reserve + (pool.osd * OSD_PRICE) / tokenPrice;
            // 如果使用预言机，代币净值为： 池中代币的储备量 + 以池子代币价格为度量单位的该池子osd总价值
        } else {
            (uint256 reserve, uint256 reserveOsd) = _getReserve(pool);
            netValue = reserve + (reserve * pool.osd) / reserveOsd;
            // 如果不使用预言机，代币净值为： 池中代币的储备量 + osd储备量按照储备比例转换为相同代币后相加得到
        }

        // 对于这里净值的理解：其实就是整个池子中token和osd的总价值，将osd转换为以当前代币相同的单位价值来衡量的价值量

        liquidity = ((pool.liquidity.totalSupply() * valueIn) / netValue);
        // liquidity = 总流动性 * 用户要取出的流动性数量 / 流动池中的所有资产总量
        console.log("_liquidityOut liquidity:", liquidity);
    }

    function _rebalanceLiquidityOut(
        Pool storage pool,
        uint256 amount, // 要交换的代币数量
        uint256 amountOsd, // 交换获得的osd代币数量
        uint256 debt
    ) internal view returns (uint256 liquidity) {
        uint256 netValue;
        uint256 valueIn = debt;

        (uint256 reserve, ) = _getReserve(pool);
        netValue = (reserve * amountOsd) / amount + pool.osd;
        // 交易前的osd代币的净值 = 前池中的储备量 * amountOsd的比例 + 交易前池中记录的osd余额

        // 计算需要发行的新流动性代币数量
        liquidity =
            (pool.liquidity.totalSupply() * valueIn) /
            (netValue - valueIn);
    }

    function _liquidityIn(
        Pool storage pool,
        uint256 liquidity
    ) internal view returns (uint256 amount, uint256 amountOsd) {
        (uint256 reserve, ) = _getReserve(pool);
        amount = (reserve * liquidity) / pool.liquidity.totalSupply(); // 整个池子的资产储备量reserve * 即将注入的流动性在整个池子流动性的占比
        amountOsd = (pool.osd * liquidity) / pool.liquidity.totalSupply(); // 使用同样的比例计算出的，注入liquidity数量的流动性对应的osd数量
        console.log("_liquidityIn:", amount, amountOsd);
    }

    function _getReserve(
        Pool storage pool
    ) internal view returns (uint256, uint256) {
        (uint256 newDebt, uint256 totalProtocolRevenue, ) = $borrow.getDebt(
            address(pool.token)
        );
        uint256 reserve = pool.reserve + newDebt - totalProtocolRevenue;
        uint256 value = (reserve * pool.lastRatioOsd) / pool.lastRatioToken; // 小问题：没有除零检查
        console.log("_getReserve", reserve, value);
        // 这里返回的分别都是对于这个池子来说代币和osd的储备量，其中osd是根据池子代币储备量和上一次osd和池子代币的比例计算出来的，也就是说这个比例是保持不变的
        return (reserve, value);
    }

    // todo test
    function getPoolReserve(
        address token
    )
        public
        view
        returns (
            uint256 reserveToken,
            uint256 reserveOsd,
            uint256 availableToken,
            uint256 availableOsd
        )
    {
        Pool storage pool = pools[token];
        require(address(pool.token) != address(0), "POOL_NOT_EXISTS");
        availableToken = pool.reserve;
        availableOsd = pool.osd;
        (reserveToken, reserveOsd) = _getReserve(pool);
    }

    // algorithms/curves
    function _getValueOut(
        Pool storage pool,
        uint8 feeType,
        uint256 amountIn
    )
        internal
        view
        returns (
            uint256 valueOut, // amountIn 数量的代币对应可以得到的osd输出数量
            uint256 newReserve, // 池子中的新储备（reserve + amountIn）
            uint256 newValue, // 池子中osd的新储备量（如果不是osd则返回0）
            uint256 fee, // 这次交易的过程中会产生的费用
            uint256 debt //
        )
    {
        // 1. 计算池子当前的token和osd储备
        (uint256 reserve, uint256 reserveOsd) = _getReserve(pool);
        address token = address(pool.token);
        // 2. 计算得到在当前池子中两个代币储备量和代币价格基础上，amountIn数量的代币对应的输出代币数量
        uint256 valueOut0 = Curve.getValueOut(
            reserve,
            reserveOsd,
            pool.usePriceFeed,
            _getTokenPrice(token), // 池子中 token 价格
            amountIn
        );
        // valueOut0： 输入代币对应的输出代币数量 （到底是代币数量还是价值，这里是以什么标准来定价值的）
        // 如果使用预言机价格： valueOut0 = _getTokenPrice(token) * 1e8 / amountIn （目前测试都是会使用预言机的情况）
        // 如果不使用预言机（也就是token和osd的计算）： valueOut0 = reserveOsd - (reserve * reserveOsd) / (reserve + debt)(减去的这个部分如果计算得到的值等于0则赋值为1)

        console.log("_getValueOut valueOut0 by curve:", valueOut0); // 100

        // 3. 根据输出量计算出这次交易的费率，计算可以输出
        uint256 feeRate = pool.feeRates[feeType];
        fee = (valueOut0 * feeRate) / 100000; // valueOut0 * 300 / 100000 才能大于1然后产生费用
        valueOut = valueOut0 - fee;

        console.log("_getValueOut get fee:", fee, feeRate);

        newReserve = reserve + amountIn;
        if (!pool.usePriceFeed) {
            newValue = reserveOsd - valueOut0;
        }

        // newValue就是新的osd储备的值，如果不使用预言机，说明这针对的输出代币是osd，新的osd储备就要减去对应输入即将输出的osd代币（储备需要减少），否则这个值直接返回0
        // newValue = 池子中osd储备 - amountIn数量的token输入需要osd输出的量
        console.log("_getValueOut newValue valueOut:", newValue, valueOut);
        console.log(
            "_getValueOut will get debt:",
            newReserve,
            newValue,
            valueOut0
        );

        // todo overflow revert
        debt = _getDebt(pool, newReserve, newValue, valueOut0);
    }

    function _getAmountOut(
        Pool storage pool,
        uint8 feeType,
        uint256 valueIn
    )
        internal
        view
        returns (
            uint256 amountOut,
            uint256 newReserve,
            uint256 newValue,
            uint256 fee
        )
    {
        uint256 feeRate = pool.feeRates[feeType];
        fee = (valueIn * feeRate) / 100000;
        uint256 valueIn1 = valueIn - fee;

        (uint256 reserve, uint256 reserveValue) = _getReserve(pool);
        address token = address(pool.token);
        console.log(reserve, reserveValue, valueIn1, "0000000");
        amountOut = Curve.getAmountOut(
            reserve,
            reserveValue,
            pool.usePriceFeed,
            _getTokenPrice(token),
            valueIn1
        );
        // 计算token需要输出的数量
        // 如果使用预言机： 首先需要保证token价格大于0， amountOut = valueIn1 * 1e8 / _getTokenPrice(token)
        // 如果不使用预言机： out = (reserveValue * reserve) / (reserveValue + valueIn1)
        //                 amountOut =  reserve - out (如果out等于0，则赋值为0)
        console.log("_getAmountOut: amountOut by Curve", amountOut);
        require(reserve > amountOut, "INSUFF_TOKEN");
        newReserve = reserve - amountOut;
        newValue = reserveValue + valueIn;
    }

    function _getValueIn(
        Pool storage pool,
        uint8 feeType,
        uint256 amountOut
    )
        internal
        view
        returns (
            uint256 valueIn,
            uint256 newReserve,
            uint256 newValue,
            uint256 fee
        )
    {
        (uint256 reserve, uint256 reserveValue) = _getReserve(pool);
        uint256 valueIn0 = Curve.getValueIn(
            reserve,
            reserveValue,
            pool.usePriceFeed,
            _getTokenPrice(address(pool.token)),
            amountOut
        );
        newReserve = reserve - amountOut;
        require(reserve > amountOut, "INSUFF_TOKEN");
        newValue = reserveValue + valueIn0;

        uint256 feeRate = pool.feeRates[feeType];
        fee = (valueIn0 * feeRate) / (100000 - feeRate);
        valueIn = valueIn0 + fee;
    }

    function _getAmountIn(
        Pool storage pool,
        uint8 feeType,
        uint256 valueOut
    )
        internal
        view
        returns (
            uint256 amountIn,
            uint256 newReserve,
            uint256 newValue,
            uint256 fee,
            uint256 debt
        )
    {
        uint256 feeRate = pool.feeRates[feeType];
        fee = (valueOut * feeRate) / (100000 - feeRate);

        uint256 valueOut1 = valueOut + fee;

        (uint256 reserve, uint256 reserveValue) = _getReserve(pool);
        address token = address(pool.token);
        (amountIn) = Curve.getAmountIn(
            reserve,
            reserveValue,
            pool.usePriceFeed,
            _getTokenPrice(token),
            valueOut1
        );
        newReserve = reserve + amountIn;
        newValue = reserveValue - valueOut;
        debt = _getDebt(pool, newReserve, newValue, valueOut1);
    }

    function _getDebt(
        Pool storage pool,
        uint256 /*reserve*/,
        uint256 /*value*/,
        uint256 valueOut
    ) internal view returns (uint256 debt) {
        if (pool.osd < valueOut) {
            require(pool.rebalancible, "INSUFF_OSD");
            debt = valueOut - pool.osd;
        } else {
            debt = 0;
        }
    }

    // core swap
    function _swapOsd(
        Pool storage pool, // 池子
        uint256 amount, // swap token的输入数量
        uint256 newReserve, // token的新增储备
        uint256 newValue, // 新的osd值
        uint256 amountOsd, // 要swap的osd数量
        uint256 fee, // swap过程中产生的费用（osd）
        uint256 debt // awap过程中产生的债务
    ) internal {
        pool.reserve += amount;
        $borrow.updateInterest(address(pool.token), pool.reserve);

        uint256 revenue = (fee * pool.revenueRate) / 100;
        pool.revenueOsd += revenue;

        emit CaptureSwapFee(address(pool.token), revenue, fee - revenue);

        if (!pool.usePriceFeed) {
            pool.lastRatioToken = newReserve;
            pool.lastRatioOsd = newValue - revenue;
        }

        if (debt == 0) {
            pool.osd = pool.osd - (amountOsd + revenue);
        } else {
            pool.osd = fee - revenue;
            uint256 liquidity = _rebalanceLiquidityOut(
                pool,
                amount,
                amountOsd,
                debt
            );
            pool.liquidity.mint(owner(), liquidity);
        }
        emit PoolAmountUpdated(
            address(pool.token),
            pool.reserve,
            pool.osd,
            pool.lastRatioToken,
            pool.lastRatioOsd
        );
        emit SwappedSingle(
            msg.sender,
            address(pool.token),
            amount,
            amountOsd,
            OrderType.SELL
        );
        console.log("_swapOsd transfer token", amount);

        pool.token.safeTransferFrom(msg.sender, address(this), amount);
    }

    function _swapToken(
        Pool storage pool,
        uint256 amount,
        uint256 newReserve,
        uint256 newValue,
        uint256 amountOsd,
        uint256 fee,
        address to
    ) internal {
        uint256 newReserve1 = pool.reserve -= amount;
        $borrow.updateInterest(address(pool.token), newReserve1);

        uint256 revenue = (fee * pool.revenueRate) / 100;
        pool.revenueOsd += revenue;
        pool.osd += (amountOsd - revenue);
        emit CaptureSwapFee(address(pool.token), revenue, fee - revenue);

        if (!pool.usePriceFeed) {
            pool.lastRatioToken = newReserve;
            pool.lastRatioOsd = newValue - revenue;
        }
        emit SwappedSingle(
            msg.sender,
            address(pool.token),
            amount,
            amountOsd,
            OrderType.BUY
        );

        emit PoolAmountUpdated(
            address(pool.token),
            pool.reserve,
            pool.osd,
            pool.lastRatioToken,
            pool.lastRatioOsd
        );
        pool.token.safeTransfer(to, amount);
    }

    function swapInPart1(
        Pool storage poolIn,
        Pool storage poolOut,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256) {
        uint256 amountOsd;
        if (tokenIn == address(osd)) {
            amountOsd = amountIn;
            osd.burn(msg.sender, amountIn);
        } else {
            (
                uint256 valueOut,
                uint256 newReserve,
                uint256 newValue,
                uint256 fee,
                uint256 debt
            ) = _getValueOut(poolIn, poolOut.feeType, amountIn);
            // 疑问：为什么这里是根据 poolOut.feeType 来计算费率
            amountOsd = valueOut; // 计算得到的输出代币价值对应的osd数量

            console.log(
                "swapInPart1:(not osd)",
                amountOsd,
                newReserve,
                newValue
            );

            _swapOsd(
                poolIn,
                amountIn,
                newReserve,
                newValue,
                amountOsd,
                fee,
                debt
            );
        }
        return amountOsd;
    }

    function swapInPart2(
        Pool storage poolIn,
        Pool storage poolOut,
        address tokenOut,
        address to,
        uint256 amountOsd
    ) internal returns (uint256) {
        uint256 amountOut;
        if (tokenOut == address(osd)) {
            amountOut = amountOsd;
            osd.mint(to, amountOut);
        } else {
            (
                uint256 _amountOut,
                uint256 newReserve,
                uint256 newValue,
                uint256 fee
            ) = _getAmountOut(poolOut, poolIn.feeType, amountOsd);

            amountOut = _amountOut;

            console.log("swapInPart2:(not osd) amountOut:", amountOut);

            address _to = to; // avoid stack too deep
            _swapToken(
                poolOut,
                amountOut,
                newReserve,
                newValue,
                amountOsd,
                fee,
                _to
            );
        }
        return amountOut;
    }

    function swapIn(
        address tokenIn, // 用户的输入代币
        address tokenOut, // 用户想要换出的输出代币
        uint256 amountIn, // 输入数量
        uint256 amountOutMin, // 最小输出数量
        address to, // 将输出代币发送的目标地址
        uint256 deadline
    ) external expires(deadline) returns (uint256) {
        require(tokenIn != tokenOut, "SAME_TOKEN");
        Pool storage poolIn = pools[tokenIn];
        Pool storage poolOut = pools[tokenOut];

        uint256 amountOsd = swapInPart1(poolIn, poolOut, tokenIn, amountIn);

        uint256 amountOut = swapInPart2(
            poolIn,
            poolOut,
            tokenOut,
            to,
            amountOsd
        );
        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, to);
        console.log(
            "swapIn: amountOut amountOutMin",
            amountOsd,
            amountOut,
            amountOutMin
        );
        require(amountOut >= amountOutMin, "INSUFF_OUTPUT");
        return amountOut;
    }

    function swapOutPart1(
        Pool storage poolIn,
        Pool storage poolOut,
        address tokenOut,
        address to,
        uint256 amountOut
    ) internal returns (uint256) {
        uint256 amountOsd;
        if (tokenOut == address(osd)) {
            amountOsd = amountOut;
            osd.mint(msg.sender, amountOut);
        } else {
            (
                uint256 _amountOsd,
                uint256 newReserve,
                uint256 newValue,
                uint256 fee
            ) = _getValueIn(poolOut, poolIn.feeType, amountOut);
            amountOsd = _amountOsd;

            console.log("swapOutPart1 - amountOsd", amountOsd);

            _swapToken(
                poolOut,
                amountOut,
                newReserve,
                newValue,
                amountOsd,
                fee,
                to
            );
        }
        return amountOsd;
    }

    function swapOutPart2(
        Pool storage poolIn,
        Pool storage poolOut,
        address tokenIn,
        address to,
        uint256 amountOsd
    ) internal returns (uint256) {
        uint256 amountIn;
        if (tokenIn == address(osd)) {
            amountIn = amountOsd;
            osd.burn(to, amountIn);
        } else {
            (
                uint256 _amountIn,
                uint256 newReserve,
                uint256 newValue,
                uint256 fee,
                uint256 debt
            ) = _getAmountIn(poolIn, poolOut.feeType, amountOsd);
            amountIn = _amountIn;

            console.log("swapOutPart2 - amountIn", amountIn);

            _swapOsd(
                poolIn,
                amountIn,
                newReserve,
                newValue,
                amountOsd,
                fee,
                debt
            );
        }
        return amountIn;
    }

    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external expires(deadline) returns (uint256) {
        require(tokenIn != tokenOut, "SAME_TOKEN");
        Pool storage poolIn = pools[tokenIn];
        Pool storage poolOut = pools[tokenOut];

        uint256 amountOsd = swapOutPart1(
            poolIn,
            poolOut,
            tokenOut,
            to,
            amountOut
        );

        uint256 amountIn = swapOutPart2(
            poolIn,
            poolOut,
            tokenIn,
            to,
            amountOsd
        );
        console.log("swapOut - amountIn", amountIn);
        require(amountIn <= amountInMax, "EXCESSIVE_INPUT");

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, to);
        return amountIn;
    }

    // viewers
    function getLiquidityOut(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        Pool storage pool = pools[token];
        uint256 liquidity = _liquidityOut(pool, amount);
        return liquidity;
    }

    function getLiquidityIn(
        address token,
        uint256 liquidity
    ) external view returns (uint256, uint256) {
        Pool storage pool = pools[token];
        (uint256 amount, uint256 amountOsd) = _liquidityIn(pool, liquidity);
        return (amount, amountOsd);
    }

    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "SAME_TOKEN");
        Pool storage poolIn = pools[tokenIn];
        Pool storage poolOut = pools[tokenOut];

        uint256 amountOsd;
        if (tokenIn == address(osd)) {
            amountOsd = amountIn;
        } else {
            (amountOsd, , , , ) = _getValueOut(
                poolIn,
                poolOut.feeType,
                amountIn
            );
        }

        if (tokenOut == address(osd)) {
            amountOut = amountOsd;
        } else {
            (amountOut, , , ) = _getAmountOut(
                poolOut,
                poolIn.feeType,
                amountOsd
            );
            require(amountOut < poolOut.reserve, "INSUFF_TOKEN");
        }
    }

    function getAmountIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256 amountIn) {
        require(tokenIn != tokenOut, "SAME_TOKEN");
        Pool storage poolIn = pools[tokenIn];
        Pool storage poolOut = pools[tokenOut];

        uint256 amountOsd;
        if (tokenOut == address(osd)) {
            amountOsd = amountOut;
        } else {
            (amountOsd, , , ) = _getValueIn(poolOut, poolIn.feeType, amountOut);
        }

        if (tokenIn == address(osd)) {
            amountIn = amountOsd;
        } else {
            (amountIn, , , , ) = _getAmountIn(
                poolIn,
                poolOut.feeType,
                amountOsd
            );
            require(amountIn < poolIn.reserve, "INSUFF_TOKEN");
        }
    }

    // admin
    function updatePool(
        address token,
        uint256 lastRatioToken,
        uint256 lastRatioOsd,
        bool rebalancible,
        bool usePriceFeed,
        uint8 feeType,
        uint8 revenueRate,
        uint16[3] calldata feeRates
    ) external onlyOwner {
        Pool storage pool = pools[token];
        require(address(pool.token) != address(0), "POOL_NOT_EXISTS");

        if (lastRatioToken > 0 && lastRatioOsd > 0) {
            pool.lastRatioToken = lastRatioToken;
            pool.lastRatioOsd = lastRatioOsd;
        }
        pool.rebalancible = rebalancible;
        pool.usePriceFeed = usePriceFeed;
        pool.feeType = feeType;
        pool.revenueRate = revenueRate;
        pool.feeRates = feeRates;
    }

    function getFeeRates(
        address token
    ) external view returns (uint16[3] memory) {
        return pools[token].feeRates;
    }

    // borrow
    // todo restrict borrow
    function borrow(
        address token,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        require(msg.sender == address($borrow), "INVALID_CALLER");

        Pool storage pool = pools[token];
        require(address(pool.token) != address(0), "POOL_NOT_EXISTS");
        uint256 newReserve = pool.reserve -= amount;
        pool.token.safeTransfer(to, amount);
        return newReserve;
    }

    function protocolRevenueExtract(
        address token,
        uint256 amount,
        address to
    ) external returns (bool) {
        require(msg.sender == address($borrow), "INVALID_CALLER");
        Pool storage pool = pools[token];
        require(address(pool.token) != address(0), "POOL_NOT_EXISTS");
        (, , uint256 protocolRevenueAmount) = $borrow.getDebt(
            address(pool.token)
        );
        require(amount <= protocolRevenueAmount, "INSUFF_REVENUE");
        pool.token.safeTransfer(to, amount);
        return true;
    }

    function repay(
        address token,
        uint256 amount,
        address from
    ) external override returns (uint256) {
        require(msg.sender == address($borrow), "INVALID_CALLER");

        Pool storage pool = pools[token];
        require(address(pool.token) != address(0), "POOL_NOT_EXISTS");
        uint256 newReserve = pool.reserve += amount;
        pool.token.safeTransferFrom(from, address(this), amount);
        return newReserve;
    }

    function getAvailability(
        address token
    ) external view override returns (uint256) {
        return pools[token].reserve;
    }

    function getPoolState(
        address token
    )
        external
        view
        returns (
            uint256 reserve,
            uint256 lastRatioToken,
            uint256 lastRatioOsd,
            uint256 osd_
        )
    {
        reserve = pools[token].reserve;
        lastRatioToken = pools[token].lastRatioToken;
        lastRatioOsd = pools[token].lastRatioOsd;
        osd_ = pools[token].osd;
    }

    function getPoolInfo(
        address token
    )
        external
        view
        returns (
            address liquidity,
            uint256 createdAt,
            bool rebalancible,
            bool usePriceFeed
        )
    {
        liquidity = address(pools[token].liquidity);
        createdAt = pools[token].createdAt;
        rebalancible = pools[token].rebalancible;
        usePriceFeed = pools[token].usePriceFeed;
    }

    function getPoolTokenList() external view returns (address[] memory) {
        uint256 poolTokenListLen = poolTokenList.length;
        address[] memory _poolTokenList = new address[](poolTokenListLen);
        for (uint i = 0; i < poolTokenListLen; i++) {
            _poolTokenList[i] = poolTokenList[i];
        }
        return _poolTokenList;
    }

    function getPoolFeePolicy(
        address token
    )
        external
        view
        returns (
            uint8 feeType,
            uint16 feeRate0,
            uint16 feeRate1,
            uint16 feeRate2,
            uint8 revenueRate,
            uint256 revenueOsd
        )
    {
        feeType = pools[token].feeType;
        feeRate0 = pools[token].feeRates[0];
        feeRate1 = pools[token].feeRates[1];
        feeRate2 = pools[token].feeRates[2];
        revenueRate = pools[token].revenueRate;
        revenueOsd = pools[token].revenueOsd;
    }

    function getPriceRatio(
        address token
    ) external view returns (uint256 tokenRatio, uint256 osdRatio) {
        Pool storage pool = pools[token];
        if (address(pool.token) == address(0)) {
            return (0, 0);
        }

        if (pool.usePriceFeed) {
            return (OSD_PRICE, _getTokenPrice(address(pool.token)));
        }
        return (pool.lastRatioToken, pool.lastRatioOsd);
    }

    function setBorrow(address _borrow) external onlyOwner {
        $borrow = IBorrowForSwap(_borrow);
    }

    function setPriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = _priceFeed;
    }
}
