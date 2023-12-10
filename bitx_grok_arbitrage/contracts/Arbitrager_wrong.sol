// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

interface IPancakePair {
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract Arbitrager2 is IERC3156FlashBorrower {
    using SafeMath for uint;

    address public lenderPool;
    address public wbnb;
    address public bitx;
    address public grok;
    IPancakePair public bitxWbnbPair;
    IPancakePair public grokBitxPair;
    IPancakePair public grokWbnbPair;

    constructor(
        address _lenderPool,
        address _wbnb,
        address _bitx,
        address _grok,
        address _bitxWbnbPair,
        address _grokBitxPair,
        address _grokWbnbPair
    ) {
        lenderPool = _lenderPool;
        wbnb = _wbnb;
        bitx = _bitx;
        grok = _grok;
        bitxWbnbPair = IPancakePair(_bitxWbnbPair);
        grokBitxPair = IPancakePair(_grokBitxPair);
        grokWbnbPair = IPancakePair(_grokWbnbPair);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(msg.sender == address(lenderPool), "Untrusted lender");
        console.log(1, IERC20(wbnb).balanceOf(address(this)));

        // 1. 使用借到的 wbnb 去购买 bitx
        // IERC20(wbnb).approve(address(bitxWbnbPair), amount);
        (uint112 bitx_reserve0, uint112 wbnb_reserve1, ) = bitxWbnbPair
            .getReserves();
        uint256 bitxMaxOut = getAmountOut(amount, wbnb_reserve1, bitx_reserve0);
        IERC20(wbnb).transferFrom(address(this), address(bitxWbnbPair), amount);
        bitxWbnbPair.swap(bitxMaxOut, 0, address(this), "");
        uint256 bitxBalance = IERC20(bitx).balanceOf(address(this));
        console.log(2, bitxBalance, bitxMaxOut);

        // // 2. 再用买到的 bitx 去换 grok
        (uint112 bitx_reserve0_0, uint112 grok_reserve1, ) = grokBitxPair
            .getReserves();
        uint256 grokMaxOut = getAmountOut(
            bitxBalance,
            bitx_reserve0_0,
            grok_reserve1
        );
        IERC20(bitx).transfer(address(grokBitxPair), bitxBalance);
        grokBitxPair.swap(0, grokMaxOut / 2, address(this), "");

        // uint256 bitxAmount = IERC20(bitx).balanceOf(address(this));
        // // IERC20(bitx).approve(address(grokBitxPair), bitxAmount);
        // grokBitxPair.swap(0, bitxAmount, address(this), "");

        // // 3. 再用 grok 去换回 wbnb
        (uint112 wbnb_reserve0, uint112 grok_reserve1_0, ) = grokWbnbPair
            .getReserves();
        console.log(wbnb_reserve0, grok_reserve1_0);
        // uint256 grokAmount = IERC20(grok).balanceOf(address(this));
        // // IERC20(grok).approve(address(grokWbnbPair), grokAmount);
        // grokWbnbPair.swap(grokAmount, 0, address(this), "");

        // console.log(IERC20(wbnb).balanceOf(address(this)));

        // // 4. 归还贷款
        // uint256 totalRepayment = amount + fee;
        // IERC20(wbnb).transfer(msg.sender, totalRepayment);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
}

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
}
