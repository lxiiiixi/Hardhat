// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBorrowForSwap.sol";
import "../swap/Curve.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IFuture.sol";
import "../future/FutureMath.sol";


interface ISwap {
    function osd() external view returns (address);

    function getPoolInfo(address token) external view returns (
        address liquidity, 
        uint256 createdAt, 
        bool rebalancible, 
        bool usePriceFeed
    );
    function getPoolReserve(address token) external view returns (
        uint256 reserveToken, 
        uint256 reserveOsd, 
        uint256 availableToken, 
        uint256 availableOsd
    );
    function getFeeRates(address token) external view returns (uint16[3] memory);
    function getPoolFeePolicy(address token) external view
        returns (
            uint8 feeType,
            uint16 feeRate0,
            uint16 feeRate1,
            uint16 feeRate2,
            uint8 revenueRate,
            uint256 revenueOsd
        );
    function getPriceRatio(address token)
        external
        view
        returns (uint256 tokenRatio, uint256 osdRatio);
}

interface ITradeStake {
    function updateScore(address _account, uint256 _score) external;
}

contract TradeStakeUpdater is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    ISwap public swap;
    IFuture public future;
    address public osd; 
    address public priceFeed;
    address public tradeStake;
    uint256 public constant OSD_PRICE = 1e8;
    mapping(address => bool) private caller;

    constructor(address _swap, address _priceFeed, address _future, address _tradeStake) {
        swap = ISwap(_swap);
        osd = swap.osd();
        priceFeed = _priceFeed;
        future = IFuture(_future);
        tradeStake = _tradeStake;
    }

    modifier expires(uint256 deadline) {
        // solhint-disable-next-line not-rely-on-time
        require(deadline == 0 || deadline >= block.timestamp, "EXPIRED");
        _;
    }

    modifier onlyCaller() {
        require(caller[_msgSender()], "onlyCaller");
        _;
    }

    function _getDebt(
        uint256 poolOsd,
        bool rebalancible,
        uint256 valueOut
    ) internal pure returns (uint256 debt) {
        if (poolOsd < valueOut) {
            require(rebalancible, "INSUFF_OSD");
            debt = valueOut - poolOsd;
        } else {
            debt = 0;
        }
    }

    function _getTokenPrice(address token, bool usePriceFeed) internal view returns (uint256 price) {
        if (token == address(osd)) {
            return OSD_PRICE;
        }
        if (!usePriceFeed) {
            return 0;
        }
        price = IOracle(priceFeed).getPrice(token);
        require(price > 0, "PRICE_ZERO");
    }

    function _getValueOut(
        address token,
        uint8 feeType,
        uint256 amountIn
    )
        internal
        view
        returns (
            uint256 valueOut,
            uint256 fee
        )
    {
        (uint256 reserve, uint256 reserveOsd, , ) = swap.getPoolReserve(token);
        ( , , , bool usePriceFeed) = swap.getPoolInfo(token);
        uint256 valueOut0 = Curve.getValueOut(
            reserve,
            reserveOsd,
            usePriceFeed,
            _getTokenPrice(token, usePriceFeed),
            amountIn
        );
        uint16[3] memory feeRates = swap.getFeeRates(token);
        uint256 feeRate = feeRates[feeType];
        fee = (valueOut0 * feeRate) / 100000;
        valueOut = valueOut0 - fee;
    }

    function _getValueIn(
        address token,
        uint8 feeType,
        uint256 amountOut
    )
        internal
        view
        returns (
            uint256 valueIn,
            uint256 fee
        )
    {
        (uint256 reserve, uint256 reserveValue, , ) = swap.getPoolReserve(token);
        ( , , , bool usePriceFeed) = swap.getPoolInfo(token);
        uint256 valueIn0 = Curve.getValueIn(
            reserve,
            reserveValue,
            usePriceFeed,
            _getTokenPrice(token, usePriceFeed),
            amountOut
        );
        uint16[3] memory feeRates = swap.getFeeRates(token);
        uint256 feeRate = feeRates[feeType];
        fee = (valueIn0 * feeRate) / (100000 - feeRate);
        valueIn = valueIn0 + fee;
    }

    function _getAmountOut(
        address token,
        uint8 feeType,
        uint256 valueIn
    )
        internal
        view
        returns (
            uint256 fee
        )
    {
        uint16[3] memory feeRates = swap.getFeeRates(token);
        uint256 feeRate = feeRates[feeType];
        fee = (valueIn * feeRate) / 100000;
    }

    function _getAmountIn(
        address token,
        uint8 feeType,
        uint256 valueOut
    )
        internal
        view
        returns (
            uint256 fee
        )
    {
        uint16[3] memory feeRates = swap.getFeeRates(token);
        uint256 feeRate = feeRates[feeType];
        fee = (valueOut * feeRate) / (100000 - feeRate);
    }

    function swapInPart1(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256, uint256) {
        uint256 amountOsd;
        uint256 amountFee;
        if (tokenIn == address(osd)) {
            amountOsd = amountIn;
            amountFee = 0;
        } else {
            ( uint8 feeType, , , , uint8 revenueRate, ) = swap.getPoolFeePolicy(tokenOut);
            (
                uint256 valueOut,
                uint256 fee
            ) = _getValueOut(tokenIn, feeType, amountIn);
            amountOsd = valueOut;
            uint256 revenue = (fee * revenueRate) / 100;
            amountFee = fee - revenue;
        }
        return (amountOsd, amountFee);
    }

    function swapInPart2(
        address tokenIn,
        address tokenOut,
        uint256 amountOsd
    ) internal view returns (uint256) {
        uint256 amountFee;
        if (tokenOut == address(osd)) {
            amountFee = 0;
        } else {
            ( uint8 feeType, , , , uint8 revenueRate, ) = swap.getPoolFeePolicy(tokenIn);
            (uint256 fee) = _getAmountOut(
                tokenOut,
                feeType,
                amountOsd
            );
            uint256 revenue = (fee * revenueRate) / 100;
            amountFee = fee - revenue;
        }
        return amountFee;
    }

    function swapOutPart1(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal view returns (uint256, uint256) {
        uint256 amountOsd;
        uint256 amountFee;
        if (tokenOut == address(osd)) {
            amountOsd = amountOut;
            amountFee = 0;
        } else {
            ( uint8 feeType, , , , uint8 revenueRate, ) = swap.getPoolFeePolicy(tokenIn);
            (uint256 _amountOsd, uint256 fee) = _getValueIn(
                tokenOut,
                feeType,
                amountOut
            );
            amountOsd = _amountOsd;
            uint256 revenue = (fee * revenueRate) / 100;
            amountFee = fee - revenue;
        }
        return (amountOsd, amountFee);
    }

    function swapOutPart2(
        address tokenIn,
        address tokenOut,
        uint256 amountOsd
    ) internal view returns (uint256) {
        uint256 amountIn;
        uint256 amountFee;
        if (tokenIn == address(osd)) {
            amountIn = amountOsd;
            amountFee = 0;
        } else {
            ( uint8 feeType, , , , uint8 revenueRate, ) = swap.getPoolFeePolicy(tokenOut);
            uint256 fee = _getAmountIn(tokenIn, feeType, amountOsd);
            uint256 revenue = (fee * revenueRate) / 100;
            amountFee = fee - revenue;
        }
        return amountFee;
    }

    function swapIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256,
        address to,
        uint256 deadline
    ) external expires(deadline) onlyCaller {
        (uint256 amountOsd, uint256 amountFee) = swapInPart1(tokenIn, tokenOut, amountIn);
        uint256 amountFee2 = swapInPart2(tokenIn, tokenOut, amountOsd);
        ITradeStake(tradeStake).updateScore(to, amountFee + amountFee2);
    }

    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external expires(deadline) onlyCaller {
        (uint256 amountOsd, uint256 amountFee) = swapOutPart1(tokenIn, tokenOut, amountOut);
        uint256 amountFee2 = swapOutPart2(tokenIn, tokenOut, amountOsd);
        ITradeStake(tradeStake).updateScore(to, amountFee + amountFee2);
    }

    function increasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool,
        uint256 _notionalDelta
    ) external onlyCaller {
        bytes32 pairKey = future.getPairKey(_collateralToken, _indexToken);
        uint256 tradingFee = (future.tradingFeeRates(pairKey) * _notionalDelta) /
            FutureMath.TRADING_FEE_RATE_PRECISION;
        (uint256 tokenRatio, uint256 osdRatio) = swap.getPriceRatio(_collateralToken);
        uint256 amountOsd;
        if (tokenRatio > 0) {
            amountOsd = tradingFee * osdRatio / tokenRatio;
        } else {
            amountOsd = tradingFee;
        }
        ITradeStake(tradeStake).updateScore(_account, amountOsd);
    }

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool,
        uint256,
        uint256 _notionalDelta,
        address
    ) external onlyCaller {
        bytes32 pairKey = future.getPairKey(_collateralToken, _indexToken);
        uint256 tradingFee = (future.tradingFeeRates(pairKey) * _notionalDelta) /
            FutureMath.TRADING_FEE_RATE_PRECISION;
        (uint256 tokenRatio, uint256 osdRatio) = swap.getPriceRatio(_collateralToken);
        uint256 amountOsd;
        if (tokenRatio > 0){
            amountOsd = tradingFee * osdRatio / tokenRatio;
        } else {
            amountOsd = tradingFee;
        }
        ITradeStake(tradeStake).updateScore(_account, amountOsd);
    }

    function liquidatePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external onlyCaller {
        bytes32 pairKey = future.getPairKey(_collateralToken, _indexToken);
        (   
            ,
            uint256 _notionalDelta,
            ,
        ) = future.getPosition(_collateralToken, _indexToken, _account, _isLong);
        uint256 tradingFee = (future.tradingFeeRates(pairKey) * _notionalDelta) /
            FutureMath.TRADING_FEE_RATE_PRECISION;
        (uint256 tokenRatio, uint256 osdRatio) = swap.getPriceRatio(_collateralToken);
        uint256 amountOsd;
        if (tokenRatio > 0) {
            amountOsd = tradingFee * osdRatio / tokenRatio;
        } else {
            amountOsd = tradingFee;
        }
        ITradeStake(tradeStake).updateScore(_account, amountOsd);
    }

    function setCaller(address _caller, bool _approve) external onlyOwner {
        caller[_caller] = _approve;
    }
}
