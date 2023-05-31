// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IFutureUtil.sol";
import "../interfaces/IFuture.sol";
import "./FutureMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract FutureUtil is IFutureUtil, Ownable {
    address public future;  // future contract

    mapping(bytes32 => uint256) public fundingRateMultiplier; // pairKey -> multiplier, precision: FutureMath.FUNDING_RATE_PRECISION

    constructor(address _future) {
        // fundingRateMultiplier = 250000; // 0.0025%   
        future = _future;
    }

    // validate if allowed to open position, currently not used
    function validateIncreasePosition() external view override {}

    // validate if allowed to close/decrease position, currently not used
    function validateDecreasePosition() external view override {}

    // set fundingRateMultiplier method
    function setFundingRateMultiplier(address _collateralToken, address _indexToken, uint256 _multiplier) external onlyOwner{
        bytes32 _pairKey = getPairKey(_collateralToken, _indexToken);
        fundingRateMultiplier[_pairKey] = _multiplier;
    }

    // calculate hourly funding rate
    function calculateFundingRate(
        bytes32 key,
        int256 _longSizeDelta,
        int256 _shortSizeDelta,
        uint256 utilisationRatio
    ) private view returns (int256, int256) {
        uint256 longSize = uint256(int256(IFuture(future).totalLongSizes(key)) + _longSizeDelta);
        uint256 shortSize = uint256(int256(IFuture(future).totalShortSizes(key)) + _shortSizeDelta);

        if (longSize == 0 || shortSize == 0) {
            longSize = 1;
            shortSize = 1;
        }
        
        uint256 k = 1 * fundingRateMultiplier[key] * utilisationRatio;

        uint256 longFundingRate = (k * (longSize)) /
            (shortSize * FutureMath.UTILISATION_RATIO_PRECISION);
        uint256 shortFundingRate = (k * (shortSize)) /
            (longSize * FutureMath.UTILISATION_RATIO_PRECISION);

        // longOI > shortOI, long traders pay fees to short traders and insurance fund
        if (longFundingRate > shortFundingRate) {
            return (int256(longFundingRate), -int256(shortFundingRate));
        }
        // shortOI > longOI, short traders pay fees to long traders and insurance fund
        if (longFundingRate < shortFundingRate) {
            return (-int256(longFundingRate), int256(shortFundingRate));
        }
        // longOI == shortOI, no funding fees
        return (0, 0);
    }

    // calculate funding fee rate need to be added from last calculation
    function updateFundingRate(
        address _collateralToken,
        address _indexToken,
        int256, /*_longNotionalDelta*/
        int256, /*_shortNotionalDelta*/
        int256 _longSizeDelta,
        int256 _shortSizeDelta
    )
        external
        view
        override
        returns (
            bool,
            int256,
            int256,
            int256,
            int256,
            uint256
        )
    {
        bytes32 key = getPairKey(_collateralToken, _indexToken);
        uint256 utilisationRatio = IFuture(future).getUtilisationRatio(
            _collateralToken,
            _indexToken,
            _longSizeDelta,
            _shortSizeDelta
        );
        uint256 lastTimestamp = IFuture(future).lastFundingTimestamps(key);
        uint256 timeLapse = block.timestamp - lastTimestamp;
        if (lastTimestamp == 0) {
            timeLapse = 1 hours;
        }

        (int256 hourLongFundingRate, int256 hourShortFundingRate) = calculateFundingRate(
            key,
            _longSizeDelta,
            _shortSizeDelta,
            utilisationRatio
        );

        int256 durationLongFundingRate = (hourLongFundingRate * int256(timeLapse)) / int256(1 hours);
        int256 durationShortFundingRate = (hourShortFundingRate * int256(timeLapse)) /
            int256(1 hours);

        return (
            true,
            hourLongFundingRate,
            hourShortFundingRate,
            durationLongFundingRate,
            durationShortFundingRate,
            block.timestamp
        );
    }

    // calculate token1 => token2 using their $price
    function token1ToToken2(
        address token1,
        int256 token1Amount,
        address token2
    ) private view returns (int256) {
        if (token1Amount == 0) {
            return 0;
        }
        uint256 token1Price = IFuture(future).getPrice(token1);
        uint256 token2Price = IFuture(future).getPrice(token2);
        uint8 token1Decimal = IFuture(future).tokenDecimals(token1);
        uint8 token2Decimal = IFuture(future).tokenDecimals(token2);
        if (token1Amount > 0) {
            return
                int256(
                    FutureMath.token1ToToken2(
                        uint256(token1Amount),
                        token1Price,
                        token1Decimal,
                        token2Price,
                        token2Decimal
                    )
                );
        } else {
            return
                -int256(
                    FutureMath.token1ToToken2(
                        uint256(-token1Amount),
                        token1Price,
                        token1Decimal,
                        token2Price,
                        token2Decimal
                    )
                );
        }
    }

    // calculate trading fee, not currently used by front end
    function getTradingFee(
        address _collateralToken,
        address _indexToken,
        address, /*_account*/
        bool, /*_isLong*/
        uint256 _notionalDelta
    ) external view override returns (uint256) {
        bytes32 key = getPairKey(_collateralToken, _indexToken);
        uint256 feeRate = IFuture(future).tradingFeeRates(key);
        require(feeRate > 0, "invalid_fee_rate");
        return (_notionalDelta * feeRate) / FutureMath.TRADING_FEE_RATE_PRECISION;
    }

    // calculate position funding fee
    function getPositionFundingFee(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external view returns (int256) {
        bytes32 key = getPairKey(_collateralToken, _indexToken);

        int256 cumulativeFundingRate = 0;
        if (_isLong) {
            cumulativeFundingRate = IFuture(future).cumulativeLongFundingRates(key);
        } else {
            cumulativeFundingRate = IFuture(future).cumulativeShortFundingRates(key);
        }
        (, uint256 openNotional, , int256 entryFundingRate) = IFuture(future).getPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong
        );
        return
            (int256(openNotional) * (cumulativeFundingRate - entryFundingRate)) /
            int256(FutureMath.FUNDING_RATE_PRECISION);
    }

    // calculate hourly funding fee of increased position size
    function getIncreaseFundingFee(
        address _collateralToken,
        address _indexToken,
        address, /*_account*/
        bool _isLong,
        uint256 _notionalDelta
    ) external view returns (int256) {
        bytes32 key = getPairKey(_collateralToken, _indexToken);

        int256 fundingRate = 0;
        if (_isLong) {
            fundingRate = IFuture(future).longFundingRates(key);
        } else {
            fundingRate = IFuture(future).shortFundingRates(key);
        }
        return (int256(_notionalDelta) * fundingRate) / int256(FutureMath.FUNDING_RATE_PRECISION);
    }

    // get pair key
    function getPairKey(address _collateralToken, address _indexToken)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken));
    }

    // get account key
    function getAccountKey(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken, _account, _isLong));
    }

    // get Utilisation Ratio
    function getUtilisationRatio(
        address _collateralToken,
        address _indexToken,
        int256 _longSizeDelta,
        int256 _shortSizeDelta
    ) public view override returns (uint256) {
        uint256 insuranceFund = IFuture(future).collateralInsuranceFunds(_collateralToken);
        if (insuranceFund == 0) {
            // 100%
            return FutureMath.UTILISATION_RATIO_PRECISION;
        }
        bytes32 key = getPairKey(_collateralToken, _indexToken);

        int256 longSize = int256(IFuture(future).totalLongSizes(key)) + _longSizeDelta;
        int256 shortSize = int256(IFuture(future).totalShortSizes(key)) + _shortSizeDelta;

        int256 diffNotional = IFuture(future).token1ToToken2(
            _indexToken,
            longSize - shortSize,
            _collateralToken
        );
        uint256 diff = diffNotional >= 0 ? uint256(diffNotional) : uint256(-diffNotional);

        return (FutureMath.UTILISATION_RATIO_PRECISION * diff) / insuranceFund;
    }

    // get MMR
    function getMaintanenceMarginRatio(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external view override returns (uint256 marginRatio) {
        bytes32 key = getPairKey(_collateralToken, _indexToken);
        (uint256 margin, uint256 openNotional, , ) = IFuture(future).getPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong
        );

        if (openNotional == 0) {
            return 0;
        }

        uint256 minMaintanenceMarginRatio = IFuture(future).minMaintanenceMarginRatios(key);
        uint256 maxMaintanenceMarginRatio = IFuture(future).maxMaintanenceMarginRatios(key);

        // maintanenceMarginRatio = max(minMaintanenceMarginRatio, min(maxMaintanenceMarginRatio, initMarginRatio))

        marginRatio = (margin * FutureMath.MARGIN_RATIO_PRECISION) / openNotional / 2;

        if (marginRatio > maxMaintanenceMarginRatio) {
            marginRatio = maxMaintanenceMarginRatio;
        }
        if (marginRatio < minMaintanenceMarginRatio) {
            marginRatio = minMaintanenceMarginRatio;
        }
    }
}
