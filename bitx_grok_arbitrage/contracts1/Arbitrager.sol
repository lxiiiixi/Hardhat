// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "hardhat/console.sol";

struct SwapCalculateParams {
    address baseToken;
    address pair0; // tokenA/base
    address pair1; // tokenA/tokenB
    address pair2; // tokenB/base
    uint taxRate0; // tokenA tax rate
    uint taxRate1; // tokenB tax rate
    uint baseAmount;
}

struct SwapParams {
    address baseToken;
    address pair0; // tokenA/base
    address pair1; // tokenA/tokenB
    address pair2; // tokenB/base
    uint baseAmount;
    uint baseTokenShouldPay;
    uint tokenAShouldPay;
    uint tokenBShouldPay;
}

contract Arbitrager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
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

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountIn) {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint numerator = reserveIn * amountOut * 10000;
        uint denominator = (reserveOut - amountOut) * 9975;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountInFromPair(
        address pair,
        uint amountOut,
        address amountOutToken,
        uint taxRate
    ) internal view returns (uint amountIn, address amountIntoken) {
        address token0 = IPancakePair(pair).token0();
        address token1 = IPancakePair(pair).token1();
        (uint reserve0, uint reserve1, ) = IPancakePair(pair).getReserves();
        bool amountOutTokenIsToken0 = token0 == amountOutToken;
        if (amountOutTokenIsToken0) {
            amountIntoken = token1;
        }
        amountIntoken = token0;
        uint reserveIn = amountOutTokenIsToken0 ? reserve1 : reserve0;
        uint reserveOut = amountOutTokenIsToken0 ? reserve0 : reserve1;
        amountIn = getAmountIn(amountOut, reserveIn, reserveOut);
        if (taxRate > 0) {
            amountIn = (amountIn * 100) / (100 - taxRate) + 1;
        }
        return (amountIn, amountIntoken);
    }

    function calculateRewardAndAmountIn(
        SwapCalculateParams calldata params
    )
        public
        view
        returns (
            uint reward,
            uint baseTokenShouldPay,
            uint tokenAShouldPay,
            uint tokenBShouldPay
        )
    {
        // 1. calculate tokenA amountIn -> get baseAmount baseToken
        address tokenA;
        (tokenAShouldPay, tokenA) = getAmountInFromPair(
            params.pair0,
            params.baseAmount,
            params.baseToken,
            params.taxRate0
        );

        // 2. calculate tokenB amountIn -> get tokenAShouldPay tokenA
        address tokenB;
        (tokenBShouldPay, tokenB) = getAmountInFromPair(
            params.pair1,
            tokenAShouldPay,
            tokenA,
            params.taxRate1
        );

        // 3. calculate baseToken amountIn -> get tokenBShouldPay tokenB
        (baseTokenShouldPay, ) = getAmountInFromPair(
            params.pair2,
            tokenBShouldPay,
            tokenB,
            0
        );

        if (params.baseAmount <= baseTokenShouldPay) {
            reward = 0;
        } else {
            reward = params.baseAmount - baseTokenShouldPay;
        }
    }

    function swap(SwapParams calldata params) external {
        address pair = params.pair0;
        address token0 = IPancakePair(pair).token0();
        uint amountOut0 = token0 == params.baseToken ? params.baseAmount : 0;
        uint amountOut1 = token0 == params.baseToken ? 0 : params.baseAmount;
        bytes memory data = abi.encode(params);
        // tokenA in / baseToken out
        IPancakePair(pair).swap(amountOut0, amountOut1, address(this), data);
        uint baseTokenReward = params.baseAmount - params.baseTokenShouldPay;
        IBEP20(params.baseToken).transfer(msg.sender, baseTokenReward);
    }

    function pancakeCall(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) public {
        SwapParams memory swapParam = abi.decode(data, (SwapParams));
        address baseToken = swapParam.baseToken;

        // 1. transfer baseToken to pair2
        IBEP20(baseToken).transfer(
            swapParam.pair2,
            swapParam.baseTokenShouldPay
        );

        // 2. swap: baseToken in -> tokenB out
        address token0 = IPancakePair(swapParam.pair2).token0();
        address token1 = IPancakePair(swapParam.pair2).token1();
        address tokenB = token0 == swapParam.baseToken ? token1 : token0;
        uint amount0Out = token0 == swapParam.baseToken
            ? 0
            : swapParam.tokenBShouldPay;
        uint amount1Out = token0 == swapParam.baseToken
            ? swapParam.tokenBShouldPay
            : 0;
        IPancakePair(swapParam.pair2).swap(
            amount0Out,
            amount1Out,
            swapParam.pair1,
            new bytes(0)
        );

        // 3. awap: tokenB => tokenA
        token0 = IPancakePair(swapParam.pair1).token0();
        amount0Out = token0 == tokenB ? 0 : swapParam.tokenAShouldPay;
        amount1Out = token0 == tokenB ? swapParam.tokenAShouldPay : 0;
        IPancakePair(swapParam.pair1).swap(
            amount0Out,
            amount1Out,
            swapParam.pair0,
            new bytes(0)
        );
    }
}

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

interface IBEP20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}
