// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "hardhat/console.sol";

interface IPancakePair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
}

/**
 * 本合约适用于 tokenA/tokenB 组交易对之后的套利
 * 三个交易对在UniswapV2上，分别为tokenA/base, tokenB/base, tokenA/tokenB
 * 套利流程为
 * 1. 在tokenA/base上借出base
 * 2. 在tokenB/base上出售部分借出的base,得到tokenB
 * 3. 在tokenA/tokenB上出售得到的tokenB,得到tokenA
 * 4. 向tokenA/base上归还tokenA
 * 5. 盈利为剩下的base
 */
contract PanCakeSwap is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // 代币转移
    function _safeTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TRANSFER_FAILED"
        );
    }

    // 由输出计算输入，固定pancakeV2的手续费率千分之2.5
    function getAmountInByPair(
        address pair,
        bool outIsToken0,
        uint amountOut
    ) internal view returns (uint amountIn) {
        (uint reserve00, uint reserve01, ) = IPancakePair(pair).getReserves();
        uint reserveIn = outIsToken0 ? reserve01 : reserve00;
        uint reserveOut = outIsToken0 ? reserve00 : reserve01;
        require(
            amountOut > 0 && amountOut < reserveOut,
            "PancakeLibrary: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        uint numerator = reserveIn * amountOut * 10000;
        uint denominator = (reserveOut - amountOut) * (10000 - 25);
        amountIn = (numerator / denominator) + 1;
    }

    // 用于计算奖励时的参数
    struct SwapParamsWithoutPay {
        address base_token; // 稳定币或者WBNB
        address pair0; // 包含tokenA的交易对
        uint tax_rate0; // tokenA的税率
        address middle_pair; // 包含tokenA和tokenB的交易对
        address pair1; // 包含tokenB的交易对
        uint tax_rate1; // tokenB的税率
        uint base_load; // pair0中借出的baseToken数量
    }

    /**
     * 用于计算盈利,注意，并未考虑到土狗币在购买过程中进行额外的兑换功能,如果确实发生了，会造成计算的误差
     */
    function cal_three_pair_reward(
        SwapParamsWithoutPay memory p
    )
        public
        view
        returns (uint reward, uint base_pay, uint tokenA_pay, uint tokenB_pay)
    {
        // 返回奖励和支付的baseToken数量
        address token0 = IPancakePair(p.pair0).token0();
        address token1 = IPancakePair(p.pair0).token1();
        // tokenA in => base out
        address tokenA = token0 == p.base_token ? token1 : token0;
        tokenA_pay = getAmountInByPair(
            p.pair0,
            p.base_token == token0,
            p.base_load
        );
        // 考虑 burn_rate ,需要还更多的 tokenA
        if (p.tax_rate0 > 0) {
            tokenA_pay = (tokenA_pay * 100) / (100 - p.tax_rate0) + 1;
        }

        // 计算需要的tokenB的数量
        token0 = IPancakePair(p.middle_pair).token0();
        // tokenB in => tokenA out
        tokenB_pay = getAmountInByPair(
            p.middle_pair,
            tokenA == token0,
            tokenA_pay
        );
        // 考虑 burn_rate ,需要还更多的 tokenB
        if (p.tax_rate1 > 0) {
            tokenB_pay = (tokenB_pay * 100) / (100 - p.tax_rate1) + 1;
        }

        // 计算需要的base数量
        token1 = IPancakePair(p.pair1).token1();
        // base in => tokenB out
        base_pay = getAmountInByPair(
            p.pair1,
            p.base_token == token1,
            tokenB_pay
        );
        reward = p.base_load > base_pay ? p.base_load - base_pay : 0;
        if (reward == 0) {
            base_pay = 0;
            tokenA_pay = 0;
            tokenB_pay = 0;
        }
    }

    // 用于实际交换时的参数
    struct SwapParams {
        address base_token; // 稳定币或者WBNB
        address pair0; // 包含tokenA的交易对
        address middle_pair; // 包含tokenA和tokenB的交易对
        address pair1; // 包含tokenB的交易对
        uint base_load; // pair0中借出的baseToken数量
        uint base_pay; // 支付的数量，通过 cal_three_pair_reward 计算得到
        uint tokenA_pay; // 支付的数量，通过 cal_three_pair_reward 计算得到
        uint tokenB_pay; // 支付的数量，通过 cal_three_pair_reward 计算得到
    }

    /// 真实兑换，操作和计算盈利是相反的，从 pair0中借出baseToken,在pair1中兑换成tokenB,在pair_middle中兑换成tokenA
    /// 注意，并未考虑到土狗币在购买过程中进行额外的兑换功能,如果确实发生了，会造成交易失败
    /// 注意，并未考虑计算盈利和实际交易时的环境差别,如果考虑，使用swap_with_cal
    function swap(SwapParams calldata p) external onlyOwner {
        address token0 = IPancakePair(p.pair0).token0();
        uint amountOut0 = token0 == p.base_token ? p.base_load : 0;
        uint amountOut1 = token0 == p.base_token ? 0 : p.base_load;
        bytes memory data = abi.encode(p);
        IPancakePair(p.pair0).swap(amountOut0, amountOut1, address(this), data);
        // get reward
        console.log("get reward");
        _safeTransfer(p.base_token, msg.sender, p.base_load - p.base_pay);
    }

    fallback() external virtual {
        (, , , bytes memory data) = abi.decode(
            msg.data[4:],
            (address, uint, uint, bytes)
        );
        SwapParams memory p = abi.decode(data, (SwapParams));
        //先行转移base代币
        _safeTransfer(p.base_token, p.pair1, p.base_pay);

        //计算 tokenB 及 amountOut
        address token0 = IPancakePair(p.pair1).token0();
        address token1 = IPancakePair(p.pair1).token1();
        address tokenB = token0 == p.base_token ? token1 : token0;
        uint amount0Out = token0 == p.base_token ? 0 : p.tokenB_pay;
        uint amount1Out = token0 == p.base_token ? p.tokenB_pay : 0;

        // base => tokenB
        IPancakePair(p.pair1).swap(
            amount0Out,
            amount1Out,
            p.middle_pair,
            new bytes(0)
        );

        // tokenB => tokenA 并归还借贷
        token0 = IPancakePair(p.middle_pair).token0();
        amount0Out = token0 == tokenB ? 0 : p.tokenA_pay;
        amount1Out = token0 == tokenB ? p.tokenA_pay : 0;
        IPancakePair(p.middle_pair).swap(
            amount0Out,
            amount1Out,
            p.pair0,
            new bytes(0)
        );
    }

    // todo 合约上计算base_load
}
