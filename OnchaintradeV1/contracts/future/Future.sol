// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./FutureMath.sol";
import "../interfaces/IFuturePriceFeed.sol";
import "../interfaces/IFuture.sol";
import "../interfaces/IFutureUtil.sol";
import "hardhat/console.sol";

// interface for erc20 token decimals
interface DecimalERC20 {
    function decimals() external view returns (uint8);
}

// perps main contract
contract Future is IFuture, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // position struct
    struct Position {
        uint256 margin;
        uint256 openNotional;
        uint256 size;
        int256 entryFundingRate;
        uint256 entryCollateralPrice;
        uint256 entryIndexPrice;
    }

    // pair struct
    struct Pair {
        address collateralToken;    // collaToken
        address indexToken; // longed/shorted token
        PairStatus status;  // pair status
        uint256 unlistCollateralPrice;
        uint256 unlistIndexPrice;
    }

    // config
    address public protocolFeeTo;   // protocolFeeAddress
    address public futurePriceFeed; // Price Feed contract
    address public futureUtil;  // util contract

    mapping(bytes32 => Pair) public pairs;  // pair
    mapping(bytes32 => uint256) public override tradingFeeRates;    // pair -> tradingFeeRate
    mapping(bytes32 => uint256) public override maxMaintanenceMarginRatios; // pair -> maxMMR
    mapping(bytes32 => uint256) public override minMaintanenceMarginRatios; // pair -> minMMR
    mapping(bytes32 => uint256) public override maxPositionUsdWithMaxLeverages; // pair -> max position size with max leverage
    mapping(bytes32 => uint256) public override maxLeverages;   // pair -> max leverage
    mapping(bytes32 => uint256) public override maxTotalLongSizes;  // pair -> maxTotalLongOI
    mapping(bytes32 => uint256) public override maxTotalShortSizes; // pair -> maxTotalShortOI

    mapping(address => uint8) public override tokenDecimals;    // token -> decimal
    mapping(address => uint256) public tokenBalances;   // token ->balance
    mapping(bytes32 => int256) public override cumulativeLongFundingRates;  // pair -> cLFR
    mapping(bytes32 => int256) public override cumulativeShortFundingRates; // pair -> cSFR
    mapping(bytes32 => int256) public override longFundingRates;    // pair -> most recent hourly lFR
    mapping(bytes32 => int256) public override shortFundingRates;   // pair -> most recent hourly sFR
    mapping(bytes32 => uint256) public override lastFundingTimestamps;  // pair -> last funding settlement time
    mapping(address => uint256) public override collateralInsuranceFunds;   // collToken -> balance
    mapping(bytes32 => uint256) public override protocolUnrealizedFees; // pair -> revenue balance
    mapping(bytes32 => uint256) public override totalLongSizes; // pair -> total Long OI(token)
    mapping(bytes32 => uint256) public override totalShortSizes; // pair -> total short OI(token)
    mapping(bytes32 => uint256) public override totalLongOpenNotionals; //pair -> totalLongOI($)
    mapping(bytes32 => uint256) public override totalShortOpenNotionals;    //pair -> totalShortOI($)
    mapping(bytes32 => Position) public positions;  // posKey -> position
    mapping(address => mapping(address => bool)) public userRouters; // user defined router
    mapping(address => bool) public systemRouters;  // system router address

    event UpdateMaxTotalSize(
        bytes32 indexed pairKey,
        address collateralToken,
        address indexToken,
        uint256 maxLongSize,
        uint256 maxShortSize
    );

    event UpdateFundingRate(
        bytes32 indexed pairKey,
        address collateralToken,
        address indexToken,
        int256 longFundingFeeRate,
        int256 shortFundingFeeRate,
        int256 cumulativeLongFundingRate,
        int256 cumulativeShortFundingRate,
        uint256 timestamp
    );

    event UpdateTradingFeeRate(
        bytes32 indexed pairKey,
        address _collateralToken,
        address _indexToken,
        uint256 tradingFeeRate
    );

    event UpdateMaxLeverage(
        bytes32 indexed pairKey,
        address _collateralToken,
        address _indexToken,
        uint256 maxPositionUsdWithMaxLeverage,
        uint256 maxLeverage
    );

    event UpdateMarginRatio(
        bytes32 indexed pairKey,
        address _collateralToken,
        address _indexToken,
        uint256 minMaintanenceMarginRatio,
        uint256 maxMaintanenceMarginRatio
    );

    event RealizeProtocolFee(
        bytes32 indexed pairKey,
        address _collateralToken,
        address _indexToken,
        address feeTo,
        uint256 amount
    );

    event UpdateInsuranceFund(
        address indexed _collateralToken,
        uint256 prevValue,
        uint256 currentValue
    );

    event ListPair(
        bytes32 indexed key,
        address indexed collateralToken,
        address indexed indexToken
    );

    event UpdatePosition(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 margin,
        uint256 openNotional,
        uint256 size,
        int256 entryFundingRate
    );

    event IncreaseMargin(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 amount
    );
    event DecreaseMarginLegacy(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 amount
    );

    event DecreaseMargin(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        int256 pnl,
        int256 fundingFee,
        uint256 amount
    );

    event IncreasePosition(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 openNotionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        uint256 collateralPrice,
        uint256 indexPrice
    );

    event DecreasePosition(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 openNotionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        int256 pnl,
        uint256 collateralPrice,
        uint256 indexPrice
    );

    event ClosePosition(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 notionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        int256 pnl,
        uint256 collateralPrice,
        uint256 indexPrice
    );

    event LiquidatePosition(
        bytes32 indexed positionKey,
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 notionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        int256 pnl,
        uint256 collateralPrice,
        uint256 indexPrice
    );

    event SetSystemRouter(address router, bool allowed);

    constructor() {
        tokenDecimals[address(0)] = 18;
        protocolFeeTo = msg.sender;
    }

    // 上架交易对
    function listPair(address _collateralToken, address _indexToken) external onlyOwner {
        require(_collateralToken != address(0), "invalid_collateral");
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);

        Pair storage pair = pairs[pairKey];

        require(pair.status == PairStatus.unlist, "pair_listed");

        tokenDecimals[_collateralToken] = DecimalERC20(_collateralToken).decimals();

        // to support virtual tokens: doge/usdc, sol/usdc, create a ERC20 indexToken and support it's price feed
        if (_indexToken != address(0)) {
            tokenDecimals[_indexToken] = DecimalERC20(_indexToken).decimals();
        }
        getPrice(_collateralToken);
        getPrice(_indexToken);

        pair.collateralToken = _collateralToken;
        pair.indexToken = _indexToken;
        pair.status = PairStatus.list;

        emit ListPair(pairKey, _collateralToken, _indexToken);
    }


    // 设置交易对最大总仓位大小
    function setMaxTotalSize(
        address _collateralToken,
        address _indexToken,
        uint256 _maxLongSize,
        uint256 _maxShortSize
    ) external onlyOwner {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);

        maxTotalLongSizes[pairKey] = _maxLongSize;
        maxTotalShortSizes[pairKey] = _maxShortSize;
        emit UpdateMaxTotalSize(
            pairKey,
            _collateralToken,
            _indexToken,
            _maxLongSize,
            _maxShortSize
        );
    }

    // set pair status
    function setPairStatus(
        address _collateralToken,
        address _indexToken,
        PairStatus _status
    ) external onlyOwner {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        PairStatus oldStatus = pairs[pairKey].status;

        require(oldStatus != PairStatus.unlist, "wrong_old_status");

        if (_status == PairStatus.stop_open) {
            require(
                oldStatus == PairStatus.list || oldStatus == PairStatus.stop,
                "wrong_old_status"
            );
        } else if (_status == PairStatus.stop) {
            require(oldStatus == PairStatus.stop_open, "wrong_old_status");
        } else if (_status == PairStatus.list) {} else {
            revert("wrong_status");
        }
        pairs[pairKey].status = _status;
    }

    // user add margin to existing position
    function increaseMargin(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external override nonReentrant {
        _validateRouter(_account);
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);

        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);

        require(pos.openNotional > 0, "position_not_exist");

        uint256 _marginDelta = _transferIn(_collateralToken);
        pos.margin = pos.margin + _marginDelta;

        emit IncreaseMargin(posKey, _collateralToken, _indexToken, _account, _isLong, _marginDelta);
        emit UpdatePosition(
            posKey,
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            pos.margin,
            pos.openNotional,
            pos.size,
            pos.entryFundingRate
        );
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);
    }

    // user remove margin from position, not currently used by front end
    function decreaseMarginLegacy(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _marginDelta,
        address _receiver
    ) external nonReentrant {
        _validateRouter(_account);
        require(_account == _receiver, "Invalid caller");
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);

        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);

        _validatePositionExist(pos);
        require(pos.margin > _marginDelta, "margin_delta_exceed");

        pos.margin = pos.margin - _marginDelta;
        _transferOut(_collateralToken, _marginDelta, _receiver);
        emit DecreaseMarginLegacy(
            posKey,
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            _marginDelta
        );
        emit UpdatePosition(
            posKey,
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            pos.margin,
            pos.openNotional,
            pos.size,
            pos.entryFundingRate
        );

        // todo replace by validatePosition, validate max usd per position
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);
    }

    // user decrease margin from position
    function decreaseMargin(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _marginDelta,
        address _receiver
    ) external override nonReentrant {
        _validateRouter(_account);
        require(_account == _receiver, "Invalid caller");
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);

        _updateFundingFeeRate(_collateralToken, _indexToken, _isLong, 0, 0);

        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);

        _validatePositionExist(pos);
        (int256 fundingFee, , int256 pnl, , ) = _calcNewPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            0,
            0,
            false
        );

        uint256 leftMargin = uint256(int256(pos.margin) - fundingFee + pnl);
        require(leftMargin > _marginDelta, "margin_delta_exceed");

        pos.margin = leftMargin - _marginDelta;
        pos.openNotional = uint256(token1ToToken2(_indexToken, int256(pos.size), _collateralToken));
        pos.entryFundingRate = getCumulativeFundingRate(_collateralToken, _indexToken, _isLong);
        pos.entryCollateralPrice = getPrice(_collateralToken);
        pos.entryIndexPrice = getPrice(_indexToken);

        positionSettlement(
            _collateralToken,
            _indexToken,
            fundingFee,
            0,
            pnl,
            0,
            _marginDelta,
            _receiver
        );

        emit DecreaseMargin(
            posKey,
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            pnl,
            fundingFee,
            _marginDelta
        );
        emit UpdatePosition(
            posKey,
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            pos.margin,
            pos.openNotional,
            pos.size,
            pos.entryFundingRate
        );

        // todo replace by validatePosition, validate max usd per position
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);
    }

    // open new or increase an already existing position
    function increasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta
    ) public override nonReentrant {
        _validateRouter(_account);
        require(getPairStatus(_collateralToken, _indexToken) == PairStatus.list, "pair_unlist");
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);

        _updateFundingFeeRate(
            _collateralToken,
            _indexToken,
            _isLong,
            int256(_notionalDelta),
            token1ToToken2(_collateralToken, int256(_notionalDelta), _indexToken)
        );

        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);
        uint256 marginDelta = _transferIn(_collateralToken);
        uint256 sizeDelta = uint256(
            token1ToToken2(_collateralToken, int256(_notionalDelta), _indexToken)
        );

        (int256 fundingFee, uint256 tradingFee, , , ) = _calcNewPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            _notionalDelta,
            sizeDelta,
            true
        );

        {
            _increaseTotalSize(_collateralToken, _indexToken, _isLong, sizeDelta);
            _increaseTotalOpenNotional(_collateralToken, _indexToken, _isLong, _notionalDelta);

            int256 remainMargin = int256(pos.margin) +
                int256(marginDelta) -
                fundingFee -
                int256(tradingFee);
            require(remainMargin > 0, "insuff_margin");

            pos.margin = uint256(remainMargin);
            pos.openNotional = pos.openNotional + _notionalDelta;
            pos.size = pos.size + sizeDelta;
            pos.entryFundingRate = getCumulativeFundingRate(_collateralToken, _indexToken, _isLong);
            pos.entryCollateralPrice = getPrice(_collateralToken);
            pos.entryIndexPrice = getPrice(_indexToken);
        }

        emitIncreasePositionEvent(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            marginDelta,
            _notionalDelta,
            sizeDelta,
            tradingFee,
            fundingFee
        );

        positionSettlement(
            _collateralToken,
            _indexToken,
            fundingFee,
            tradingFee,
            0,
            0,
            0,
            address(0)
        );
        validatePosition(_collateralToken, _indexToken, _account, _isLong, true);
        _validateMaxTotalSize(_collateralToken, _indexToken, _isLong);
    }

    // emit close position event
    function emitClosePositionEvent(
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 notionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        int256 pnl
    ) private {
        bytes32 posKey = getPositionKey(collateralToken, indexToken, account, isLong);
        uint256 indexPrice = getPrice(indexToken);
        uint256 collateralPrice = getPrice(collateralToken);
        emit ClosePosition(
            posKey,
            collateralToken,
            indexToken,
            account,
            isLong,
            marginDelta,
            notionalDelta,
            sizeDelta,
            tradingFee,
            fundingFee,
            pnl,
            collateralPrice,
            indexPrice
        );
        emit UpdatePosition(posKey, collateralToken, indexToken, account, isLong, 0, 0, 0, 0);
    }

    // emit increase position event
    function emitIncreasePositionEvent(
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 notionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee
    ) private {
        bytes32 posKey = getPositionKey(collateralToken, indexToken, account, isLong);
        uint256 indexPrice = getPrice(indexToken);
        uint256 collateralPrice = getPrice(collateralToken);
        {
            emit IncreasePosition(
                posKey,
                collateralToken,
                indexToken,
                account,
                isLong,
                marginDelta,
                notionalDelta,
                sizeDelta,
                tradingFee,
                fundingFee,
                collateralPrice,
                indexPrice
            );
        }
        Position storage pos = positions[posKey];
        emit UpdatePosition(
            posKey,
            collateralToken,
            indexToken,
            account,
            isLong,
            pos.margin,
            pos.openNotional,
            pos.size,
            pos.entryFundingRate
        );
    }

    // emit decrease position event
    function emitDecreasePositionEvent(
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 notionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        int256 pnl
    ) private {
        bytes32 posKey = getPositionKey(collateralToken, indexToken, account, isLong);
        uint256 indexPrice = getPrice(indexToken);
        uint256 collateralPrice = getPrice(collateralToken);

        emit DecreasePosition(
            posKey,
            collateralToken,
            indexToken,
            account,
            isLong,
            marginDelta,
            notionalDelta,
            sizeDelta,
            tradingFee,
            fundingFee,
            pnl,
            collateralPrice,
            indexPrice
        );
        Position storage pos = positions[posKey];
        emit UpdatePosition(
            posKey,
            collateralToken,
            indexToken,
            account,
            isLong,
            pos.margin,
            pos.openNotional,
            pos.size,
            pos.entryFundingRate
        );
    }

    // user decrease or close position
    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        address _receiver
    ) public override nonReentrant returns (uint256) {
        _validateRouter(_account);
        require(_account == _receiver, "Invalid caller");
        require(getPairStatus(_collateralToken, _indexToken) == PairStatus.list, "pair_unlist");
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);

        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);

        require(pos.openNotional > 0, "position_not_exist");

        _updateFundingFeeRate(
            _collateralToken,
            _indexToken,
            _isLong,
            -int256(_notionalDelta),
            -int256((_notionalDelta * pos.size) / pos.openNotional)
        );

        require(pos.openNotional >= _notionalDelta, "decrease_size_exceed");
        if (pos.openNotional == _notionalDelta) {
            return _closePosition(_collateralToken, _indexToken, _account, _isLong, _receiver);
        } else {
            return
                _decreasePosition(
                    _collateralToken,
                    _indexToken,
                    _account,
                    _isLong,
                    _marginDelta,
                    _notionalDelta,
                    _receiver
                );
        }
    }

    // decrease and remove margin by ratio
    function decreasePositionByRatio(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        address _receiver
    ) public override nonReentrant returns (uint256) {
        _validateRouter(_account);
        // require(_account == _receiver, "Invalid caller");
        require(getPairStatus(_collateralToken, _indexToken) == PairStatus.list, "pair_unlist");
        validateLiquidate(_collateralToken, _indexToken, _account, _isLong, true);
        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);

        require(pos.openNotional > 0, "position_not_exist");
        _updateFundingFeeRate(
            _collateralToken,
            _indexToken,
            _isLong,
            -int256(_notionalDelta),
            -int256((_notionalDelta * pos.size) / pos.openNotional)
        );
        require(pos.openNotional >= _notionalDelta, "decrease_size_exceed");

        if (pos.openNotional == _notionalDelta) {
            return _closePosition(_collateralToken, _indexToken, _account, _isLong, _receiver);
        } else {
            (int256 fundingFee, uint256 tradingFee, int256 pnl, , ) = _calcNewPosition(
                _collateralToken,
                _indexToken,
                _account,
                _isLong,
                _notionalDelta,
                _notionalDelta * pos.size / pos.openNotional,
                false
            );
            pnl = ((pnl * int256(_notionalDelta)) / int256(pos.openNotional));
            int256 leftMargin = int256(pos.margin) + pnl - fundingFee - int256(tradingFee);
            uint256 _marginDelta = (uint256(leftMargin) * _notionalDelta) / pos.openNotional;
            return
                _decreasePosition(
                    _collateralToken,
                    _indexToken,
                    _account,
                    _isLong,
                    _marginDelta,
                    _notionalDelta,
                    _receiver
                );
        }
    }

    // close position
    function _closePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        address _receiver
    ) private returns (uint256) {
        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);
        (
            int256 fundingFee,
            uint256 tradingFee,
            int256 pnl,
            int256 remainMargin,

        ) = _calcNewPosition(
                _collateralToken,
                _indexToken,
                _account,
                _isLong,
                pos.openNotional,
                pos.size,
                false
            );
        _decreaseTotalSize(_collateralToken, _indexToken, _isLong, pos.size);
        _decreaseTotalOpenNotional(_collateralToken, _indexToken, _isLong, pos.openNotional);
        require(remainMargin > 0, "should_liquidate");
        emitClosePositionEvent(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            pos.margin,
            pos.openNotional,
            pos.size,
            tradingFee,
            fundingFee,
            pnl
        );
        {
            bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
            delete positions[posKey];
        }

        uint256 toUserAmount = positionSettlement(
            _collateralToken,
            _indexToken,
            fundingFee,
            tradingFee,
            pnl,
            0,
            uint256(remainMargin),
            _receiver
        );
        return toUserAmount;
    }

    // position settlement when opened/closed/decreased
    function positionSettlement(
        address _collateralToken,
        address _indexToken,
        int256 _fundingFee,
        uint256 _tradingFee,
        int256 _pnl,
        int256 _liquidateRemainMargin,
        uint256 _toUserAmount,
        address _receiver
    ) private returns (uint256) {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);

        int256 toInsuranceAmount = _fundingFee - _pnl + _liquidateRemainMargin;

        protocolUnrealizedFees[pairKey] += _tradingFee;
        insuranceFundSettlement(_collateralToken, toInsuranceAmount);

        if (_toUserAmount > 0) {
            _transferOut(_collateralToken, _toUserAmount, _receiver);
        }
        return _toUserAmount;
    }

    // 内部减仓函数
    function _decreasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        address _receiver
    ) private returns (uint256) {
        // require(_account == _receiver, "Invalid caller");
        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);

        (int256 fundingFee, uint256 tradingFee, int256 pnl, , ) = _calcNewPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            _notionalDelta,
            pos.size * _notionalDelta / pos.openNotional,
            false
        );

        pnl = (pnl * int256(_notionalDelta)) / int256(pos.openNotional);

        uint256 toUserAmount = positionSettlement(
            _collateralToken,
            _indexToken,
            fundingFee,
            tradingFee,
            pnl,
            0,
            _marginDelta,
            _receiver
        );

        int256 remainMargin = int256(pos.margin) -
            fundingFee -
            int256(tradingFee) -
            int256(_marginDelta) +
            pnl;
        require(remainMargin > 0, "insuff_margin");
        uint256 sizeDelta = ((_notionalDelta) * pos.size) / pos.openNotional;

        _decreaseTotalOpenNotional(_collateralToken, _indexToken, _isLong, _notionalDelta);
        _decreaseTotalSize(_collateralToken, _indexToken, _isLong, sizeDelta);
        pos.margin = uint256(remainMargin);
        pos.size = pos.size - sizeDelta;
        pos.openNotional = pos.openNotional - _notionalDelta;
        pos.entryFundingRate = getCumulativeFundingRate(_collateralToken, _indexToken, _isLong);

        emitDecreasePositionEvent(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            _marginDelta,
            _notionalDelta,
            sizeDelta,
            tradingFee,
            fundingFee,
            pnl
        );

        return toUserAmount;
    }

    // liquidate position method
    function liquidatePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) public override nonReentrant {
        Position storage pos = _getPosition(_collateralToken, _indexToken, _account, _isLong);

        require(pos.openNotional > 0, "position_not_exist");

        _updateFundingFeeRate(
            _collateralToken,
            _indexToken,
            _isLong,
            -int256(pos.openNotional),
            -int256(pos.size)
        );

        {
            bool shouldLiquidate = validateLiquidate(
                _collateralToken,
                _indexToken,
                _account,
                _isLong,
                false
            );
            require(shouldLiquidate, "position_cannot_liquidate");
        }

        (
            int256 fundingFee,
            uint256 tradingFee,
            int256 pnl,
            int256 remainMargin,

        ) = _calcNewPosition(
                _collateralToken,
                _indexToken,
                _account,
                _isLong,
                pos.openNotional,
                pos.size,
                false
            );
        emitLiquidatePositionEvent(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            pos.margin,
            pos.openNotional,
            pos.size,
            tradingFee,
            fundingFee,
            pnl
        );
        positionSettlement(
            _collateralToken,
            _indexToken,
            fundingFee,
            tradingFee,
            pnl,
            remainMargin,
            0,
            address(0)
        );
        _decreaseTotalSize(_collateralToken, _indexToken, _isLong, pos.size);
        _decreaseTotalOpenNotional(_collateralToken, _indexToken, _isLong, pos.openNotional);
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        delete positions[posKey];
    }

    // emit liquidate position event
    function emitLiquidatePositionEvent(
        address collateralToken,
        address indexToken,
        address account,
        bool isLong,
        uint256 marginDelta,
        uint256 notionalDelta,
        uint256 sizeDelta,
        uint256 tradingFee,
        int256 fundingFee,
        int256 pnl
    ) private {
        bytes32 posKey = getPositionKey(collateralToken, indexToken, account, isLong);
        uint256 indexPrice = getPrice(indexToken);
        uint256 collateralPrice = getPrice(collateralToken);
        emit LiquidatePosition(
            posKey,
            collateralToken,
            indexToken,
            account,
            isLong,
            marginDelta,
            notionalDelta,
            sizeDelta,
            tradingFee,
            fundingFee,
            pnl,
            collateralPrice,
            indexPrice
        );
        emit UpdatePosition(posKey, collateralToken, indexToken, account, isLong, 0, 0, 0, 0);
    }

    function validatePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        bool _raise
    ) public view returns (bool isRevert) {
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];

        if (pos.size == 0) {
            return (false);
        }

        (, , , int256 remainMargin, ) = _calcNewPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            0,
            0,
            false
        );
        if (remainMargin < 0) {
            isRevert = true;
            if (_raise) {
                revert("insuff_margin");
            }
        }
        uint256 maxLeverage = maxLeverages[getPairKey(_collateralToken, _indexToken)];
        uint256 currentLeverage = maxLeverage;
        if (remainMargin > 0) {
            currentLeverage = (uint256(
                token1ToToken2(_indexToken, int256(pos.size), _collateralToken)
            ) * FutureMath.LEVERAGE_PRECISION) / uint256(remainMargin);
        }
        if (maxLeverage < currentLeverage) {
            isRevert = true;
            if (_raise) {
                revert("exceed_leverage");
            }
        }
    }

    // validate if a position should be liquidated
    function validateLiquidate(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        bool _raise
    ) public view override returns (bool shouldLiquidate) {
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];

        if (pos.size == 0) {
            return false;
        }

        (, , , int256 remainMargin, int256 marginRatio) = _calcNewPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            pos.openNotional,
            pos.size,
            false
        );

        if (remainMargin < 0) {
            shouldLiquidate = true;
            if (_raise) {
                revert("should_liquidate");
            }
        } else {
            uint256 mantainanceMarginRatio = IFutureUtil(futureUtil).getMaintanenceMarginRatio(
                _collateralToken,
                _indexToken,
                _account,
                _isLong
            );
            if (marginRatio < int256(mantainanceMarginRatio)) {
                shouldLiquidate = true;
                if (_raise) {
                    revert("should_liquidate");
                }
            }
        }
    }

    // get maintanence margin ratio of a position
    function getMaintanenceMarginRatio(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external view override returns (uint256) {
        return
            IFutureUtil(futureUtil).getMaintanenceMarginRatio(
                _collateralToken,
                _indexToken,
                _account,
                _isLong
            );
    }

    // get fundingFeeRate, trading fee and PnL of a position
    function calcNewPosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _sizeDelta,
        bool _isIncreasePosition
    )
        public
        view
        returns (
            int256 fundingFee,
            uint256 tradingFee,
            int256 pnl,
            int256 remainMargin,
            int256 marginRatio,
            uint256 openNotional
        )
    {
        (fundingFee, tradingFee, pnl, remainMargin, marginRatio) = _calcNewPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            _notionalDelta,
            _sizeDelta,
            _isIncreasePosition
        );

        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];

        if (_isIncreasePosition) {
            openNotional = pos.openNotional + _notionalDelta;
        } else {
            require(pos.openNotional >= _notionalDelta, "insuff_open_notional");
            openNotional = pos.openNotional - _notionalDelta;
        }
    }

    // calculate funding fee rate, trading fee rate, PnL of a position
    function _calcNewPosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta, // for trading fees
        uint256 _sizeDelta,
        bool _isIncreasePosition // if is increasing, calc funding fee for _notionalDelta
    )
        private
        view
        returns (
            int256 fundingFee,
            uint256 tradingFee,
            int256 pnl,
            int256 remainMargin,
            int256 marginRatio
        )
    {
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];

        tradingFee = calculateTradingFee(_collateralToken, _indexToken, _isLong, _notionalDelta, _sizeDelta, _isIncreasePosition);

        fundingFee = calculateFundingFee(
            _collateralToken,
            _indexToken,
            pos,
            _isLong,
            _notionalDelta,
            _isIncreasePosition
        );

        uint256 notional = 0;
        (pnl, notional) = calculatePnl(_collateralToken, _indexToken, _account, _isLong);

        remainMargin = int256(pos.margin) - int256(tradingFee) - fundingFee + pnl;

        if (pos.openNotional == 0) {
            marginRatio = int256(FutureMath.MAX_MR);
        } else {
            if (notional > 0) {
                marginRatio =
                (int256(FutureMath.MARGIN_RATIO_PRECISION) * remainMargin) /
                int256(notional);
            } else {
                marginRatio = int256(FutureMath.MAX_MR);
            }
        }
    }

    // calculate trading fee when open/close/liquidate a position
    function calculateTradingFee(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 sizeDelta,
        bool _isIncreasePosition
    ) private view returns(uint256) {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        uint256 feeRate = tradingFeeRates[pairKey];

        uint256 totalLongSize = totalLongSizes[pairKey];
        uint256 totalShortSize = totalShortSizes[pairKey];
        if (_isIncreasePosition) {
            if (_isLong) {
                totalLongSize += sizeDelta;
            } else {
                totalShortSize += sizeDelta;
            }
            if (_isLong && totalLongSize > totalShortSize && totalShortSize != 0) {
                feeRate = totalLongSize * feeRate / totalShortSize;
            }
            if (!_isLong && totalLongSize < totalShortSize && totalLongSize != 0) {
                feeRate = totalShortSize * feeRate / totalLongSize;
            }
        } 
        // else {
        //     if (_isLong) {
        //         totalLongSize -= sizeDelta;
        //     } else {
        //         totalShortSize -= sizeDelta;
        //     }
        //     if (!_isLong && totalLongSize > totalShortSize && totalShortSize != 0) {
        //         feeRate = totalLongSize * feeRate / totalShortSize;
        //     }
        //     if (_isLong && totalLongSize < totalShortSize && totalLongSize != 0) {
        //         feeRate = totalShortSize * feeRate / totalLongSize;
        //     }
        // }
        return feeRate * _notionalDelta / FutureMath.TRADING_FEE_RATE_PRECISION;
    }

    // calculate funding fee
    function calculateFundingFee(
        address _collateralToken,
        address _indexToken,
        Position storage pos,
        bool _isLong,
        uint256 _notionalDelta,
        bool _isIncreasePosition
    ) private view returns (int256 fundingFee) {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        uint256 _increaseNotionalDelta = 0;
        if (_isIncreasePosition) {
            _increaseNotionalDelta = _notionalDelta;
        }

        if (_isLong) {
            fundingFee =
                (int256(pos.openNotional) *
                    (cumulativeLongFundingRates[pairKey] - pos.entryFundingRate)) /
                int256(FutureMath.FUNDING_RATE_PRECISION);
            fundingFee +=
                (int256(_increaseNotionalDelta) * longFundingRates[pairKey]) /
                int256(FutureMath.FUNDING_RATE_PRECISION);
        } else {
            fundingFee =
                (int256(pos.openNotional) *
                    (cumulativeShortFundingRates[pairKey] - pos.entryFundingRate)) /
                int256(FutureMath.FUNDING_RATE_PRECISION);
            fundingFee +=
                (int256(_increaseNotionalDelta) * shortFundingRates[pairKey]) /
                int256(FutureMath.FUNDING_RATE_PRECISION);
        }
    }

    //position PnL&funding fee is settled with insurance pool when opened/closed/liquidated
    function insuranceFundSettlement(address _collateralToken, int256 settleAmount) private {
        // if add amount to insurance, just add it
        if (settleAmount > 0) {
            emit UpdateInsuranceFund(
                _collateralToken,
                collateralInsuranceFunds[_collateralToken],
                collateralInsuranceFunds[_collateralToken] + uint256(settleAmount)
            );
            collateralInsuranceFunds[_collateralToken] =
                collateralInsuranceFunds[_collateralToken] +
                uint256(settleAmount);
            return;
        }
        // else: remove amount from insurance fund
        uint256 uSettleAmount = uint256(-settleAmount);
        if (uSettleAmount <= collateralInsuranceFunds[_collateralToken]) {
            emit UpdateInsuranceFund(
                _collateralToken,
                collateralInsuranceFunds[_collateralToken],
                collateralInsuranceFunds[_collateralToken] - uint256(uSettleAmount)
            );
            collateralInsuranceFunds[_collateralToken] =
                collateralInsuranceFunds[_collateralToken] -
                uSettleAmount;
            return;
        }
        revert("insuff_insurance_fund");
    }

    // calculate position PnL
    function calculatePnl(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) private view returns (int256, uint256) {
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];

        uint256 collateralPrice = getPrice(_collateralToken);
        uint256 indexPrice = getPrice(_indexToken);
        uint8 indexDecimal = tokenDecimals[_indexToken];
        uint8 collateralDecimal = tokenDecimals[_collateralToken];
        uint256 notional = FutureMath.token1ToToken2(
            pos.size,
            indexPrice,
            indexDecimal,
            collateralPrice,
            collateralDecimal
        );

        int256 pnl = 0;
        if (_isLong) {
            pnl = int256(notional) - int256(pos.openNotional);
        } else {
            pnl = int256(pos.openNotional) - int256(notional);
        }
        return (pnl, notional);
    }

    // get insurance utilization by pair
    function getUtilisationRatio(
        address _collateralToken,
        address _indexToken,
        int256 _longSizeDelta,
        int256 _shortSizeDelta
    ) external view override returns (uint256) {
        return
            IFutureUtil(futureUtil).getUtilisationRatio(
                _collateralToken,
                _indexToken,
                _longSizeDelta,
                _shortSizeDelta
            );
    }

    // set tradingFeeRate for a specific pair
    function setTradingFeeRate(
        address _collateralToken,
        address _indexToken,
        uint256 tradingFeeRate
    ) external onlyOwner {
        bytes32 key = getPairKey(_collateralToken, _indexToken);

        require(tradingFeeRate < FutureMath.TRADING_FEE_RATE_PRECISION, "invalid_rate");
        tradingFeeRates[key] = tradingFeeRate;

        emit UpdateTradingFeeRate(
            key,
            _collateralToken,
            _indexToken,
            tradingFeeRate
            );
    }

    // funding fee rate update
    function _updateFundingFeeRate(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        int256 _notionalDelta,
        int256 _sizeDelta
    ) private {
        if (_isLong) {
            updateFundingFeeRate(_collateralToken, _indexToken, _notionalDelta, 0, _sizeDelta, 0);
        } else {
            updateFundingFeeRate(_collateralToken, _indexToken, 0, _notionalDelta, 0, _sizeDelta);
        }
    }

    // update funding fee rate
    function updateFundingFeeRate(
        address _collateralToken,
        address _indexToken,
        int256 _longNotionalDelta,
        int256 _shortNotionalDelta,
        int256 _longSizeDelta,
        int256 _shortSizeDelta
    ) private {
        (
            bool shouldUpdate,
            int256 hourLongFundingRate,
            int256 hourShortFundingRate,
            int256 durationLongFundingRate,
            int256 durationShortFundingRate,
            uint256 timestamp
        ) = IFutureUtil(futureUtil).updateFundingRate(
                _collateralToken,
                _indexToken,
                _longNotionalDelta,
                _shortNotionalDelta,
                _longSizeDelta,
                _shortSizeDelta
            );

        if (shouldUpdate) {
            bytes32 key = getPairKey(_collateralToken, _indexToken);

            longFundingRates[key] = hourLongFundingRate;
            shortFundingRates[key] = hourShortFundingRate;
            cumulativeLongFundingRates[key] =
                cumulativeLongFundingRates[key] +
                durationLongFundingRate;
            cumulativeShortFundingRates[key] =
                cumulativeShortFundingRates[key] +
                durationShortFundingRate;
            lastFundingTimestamps[key] = timestamp;

            emit UpdateFundingRate(
                key,
                _collateralToken,
                _indexToken,
                longFundingRates[key],
                shortFundingRates[key],
                cumulativeLongFundingRates[key],
                cumulativeShortFundingRates[key],
                timestamp
            );
        }
    }

    // set max leverage
    function setMaxLeverage(
        address _collateralToken,
        address _indexToken,
        uint256 maxPositionUsdWithMaxLeverage,
        uint256 maxLeverage
    ) external onlyOwner {
        bytes32 key = getPairKey(_collateralToken, _indexToken);

        require(maxLeverage >= FutureMath.LEVERAGE_PRECISION, "invalid_leverage");
        require(maxPositionUsdWithMaxLeverage > 0, "invalid_usd_value");
        maxPositionUsdWithMaxLeverages[key] = maxPositionUsdWithMaxLeverage;
        maxLeverages[key] = maxLeverage;

        emit UpdateMaxLeverage(
            key,
            _collateralToken,
            _indexToken,
            maxPositionUsdWithMaxLeverage,
            maxLeverage
        );
    }

    // set max/min maintanence margin ratio
    function setMarginRatio(
        address _collateralToken,
        address _indexToken,
        uint256 _minMaintanenceMarginRatio,
        uint256 _maxMaintanenceMarginRatio
    ) external onlyOwner {
        bytes32 key = getPairKey(_collateralToken, _indexToken);
        require(_minMaintanenceMarginRatio <= _maxMaintanenceMarginRatio, "invalid_min_max");
        require(_minMaintanenceMarginRatio > 0, "invalid_margin_ratio");

        minMaintanenceMarginRatios[key] = _minMaintanenceMarginRatio;
        maxMaintanenceMarginRatios[key] = _maxMaintanenceMarginRatio;

        emit UpdateMarginRatio(
            key,
            _collateralToken,
            _indexToken,
            _minMaintanenceMarginRatio,
            _maxMaintanenceMarginRatio
        );
    }

    // set system router for eth <=> weth swap，can also be used for erc20 approval before transferring to this contract
    function setSystemRouter(address _router, bool allowed) external onlyOwner {
        systemRouters[_router] = allowed;
        emit SetSystemRouter(_router, allowed);
    }

    // set user router
    function setUserRouter(address _router, bool allowed) external {
        userRouters[msg.sender][_router] = allowed;
    }

    // set price feed address
    function setPriceFeed(address _priceFeed) external onlyOwner {
        futurePriceFeed = _priceFeed;
    }

    // set util contract address
    function setFutureUtil(address _futureUtil) external onlyOwner {
        futureUtil = _futureUtil;
    }

    // set address to receive protocol revenue
    function setProtocolFeeTo(address _feeto) external onlyOwner {
        protocolFeeTo = _feeto;
    }

    // withdraw fee revenue
    function realizeProtocolFee(address[] memory collateralTokens, address[] memory indexTokens)
        external
    {
        require(msg.sender == protocolFeeTo || msg.sender == owner(), "invalid_access");
        require(collateralTokens.length == indexTokens.length, "invalid_args_length");
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            realizePairProtocoFee(collateralTokens[i], indexTokens[i]);
        }
    }

    // withdraw fee one pair a time
    function realizePairProtocoFee(address collateralToken, address indexToken) public {
        require(msg.sender == protocolFeeTo || msg.sender == owner(), "invalid_access");
        bytes32 pairKey = getPairKey(collateralToken, indexToken);
        uint256 amount = protocolUnrealizedFees[pairKey];
        if (amount > 0) {
            _transferOut(collateralToken, amount, protocolFeeTo);
            emit RealizeProtocolFee(pairKey, collateralToken, indexToken, protocolFeeTo, amount);
        }
        protocolUnrealizedFees[pairKey] = 0;
    }

    // get token price from oracle
    function getPrice(address _token) public view override returns (uint256) {
        return IFuturePriceFeed(futurePriceFeed).getPrice(_token);
    }

    // get pair key
    function getPairKey(address _collateralToken, address _indexToken)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken));
    }

    // get position info
    function getPosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    )
        external
        view
        override
        returns (
            uint256 margin,
            uint256 openNotional,
            uint256 size,
            int256 entryFundingRate
        )
    {
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];
        return (pos.margin, pos.openNotional, pos.size, pos.entryFundingRate);
    }

    // get position entry price, this method is faulty
    function getPositionEntryPrice(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external view override returns (uint256 collateralPrice, uint256 indexPrice) {
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];

        collateralPrice = pos.entryCollateralPrice;
        indexPrice = pos.entryIndexPrice;
    }

    // get cummulative funding rates of a pair
    function getCumulativeFundingRate(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (int256) {
        bytes32 key = getPairKey(_collateralToken, _indexToken);
        if (_isLong) {
            return cumulativeLongFundingRates[key];
        } else {
            return cumulativeShortFundingRates[key];
        }
    }

    // get position key
    function getPositionKey(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collateralToken, _indexToken, _account, _isLong));
    }

    // get pair status(listed/unlisted...)
    function getPairStatus(address _collateralToken, address _indexToken)
        public
        view
        returns (PairStatus)
    {
        bytes32 key = getPairKey(_collateralToken, _indexToken);
        return pairs[key].status;
    }

    // add funds to insurance pool
    function increaseInsuranceFund(address _collateralToken) public nonReentrant {
        uint256 _amount = _transferIn(_collateralToken);
        emit UpdateInsuranceFund(
            _collateralToken,
            collateralInsuranceFunds[_collateralToken],
            collateralInsuranceFunds[_collateralToken] + _amount
        );
        collateralInsuranceFunds[_collateralToken] =
            collateralInsuranceFunds[_collateralToken] +
            _amount;
    }

    // withdraw funds from insurance pool
    function decreaseInsuranceFund(
        address _collateralToken,
        uint256 _amount,
        address _receiver
    ) public onlyOwner nonReentrant {
        require(collateralInsuranceFunds[_collateralToken] > _amount, "insuff_insurance_fund");
        emit UpdateInsuranceFund(
            _collateralToken,
            collateralInsuranceFunds[_collateralToken],
            collateralInsuranceFunds[_collateralToken] - _amount
        );
        collateralInsuranceFunds[_collateralToken] =
            collateralInsuranceFunds[_collateralToken] -
            _amount;
        _transferOut(_collateralToken, _amount, _receiver);
    }

    // update totoal $OI of a pair when positions increased
    function _increaseTotalOpenNotional(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 amount
    ) private {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        if (_isLong) {
            totalLongOpenNotionals[pairKey] = totalLongOpenNotionals[pairKey] + amount;
        } else {
            totalShortOpenNotionals[pairKey] = totalShortOpenNotionals[pairKey] + amount;
        }
    }

    // update totoal $OI of a pair when positions decreased
    function _decreaseTotalOpenNotional(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 amount
    ) private {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        if (_isLong) {
            totalLongOpenNotionals[pairKey] = totalLongOpenNotionals[pairKey] - amount;
        } else {
            totalShortOpenNotionals[pairKey] = totalShortOpenNotionals[pairKey] - amount;
        }
    }

    // update totoal OI(token) of a pair when positions increased
    function _increaseTotalSize(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 amount
    ) private {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        if (_isLong) {
            totalLongSizes[pairKey] = totalLongSizes[pairKey] + amount;
        } else {
            totalShortSizes[pairKey] = totalShortSizes[pairKey] + amount;
        }
    }

    // update totoal OI(token) of a pair when positions decreased
    function _decreaseTotalSize(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 amount
    ) private {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        if (_isLong) {
            totalLongSizes[pairKey] = totalLongSizes[pairKey] - amount;
        } else {
            totalShortSizes[pairKey] = totalShortSizes[pairKey] - amount;
        }
    }

    // get position info
    function _getPosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) private view returns (Position storage) {
        bytes32 posKey = getPositionKey(_collateralToken, _indexToken, _account, _isLong);
        Position storage pos = positions[posKey];
        return pos;
    }

    // calculate amount of token1 expressed in token2 with their respective $price
    function token1ToToken2(
        address token1,
        int256 token1Amount,
        address token2
    ) public view override returns (int256) {
        if (token1Amount == 0) {
            return 0;
        }
        uint256 token1Price = getPrice(token1);
        uint256 token2Price = getPrice(token2);
        uint8 token1Decimal = tokenDecimals[token1];
        uint8 token2Decimal = tokenDecimals[token2];
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


    // transfer funds out of this contract
    function _transferOut(
        address _token,
        uint256 _amount,
        address _receiver
    ) private {
        IERC20(_token).safeTransfer(_receiver, _amount);

        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
    }

    // transfer funds to this contract and returns difference
    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
        return nextBalance - prevBalance;
    }

    // transfer funds out of this contract and returns difference
    function _trasnferFromOut(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
        return prevBalance - nextBalance;
    }

    // valicate existence of a position
    function _validatePositionExist(Position storage pos) private view {
        require(pos.margin > 0, "position_not_exist");
        require(pos.size > 0, "position_not_exist");
        require(pos.openNotional > 0, "position_not_exist");
    }

    // valicate msg.sender is position holder or system router
    function _validateRouter(address _account) private view {
        if (msg.sender == _account) {
            return;
        }
        if (systemRouters[msg.sender]) {
            return;
        }
        require(userRouters[_account][msg.sender], "invalid_router");
    }

    // position opened must not be bigger than max allowed size
    function _validateMaxTotalSize(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private view {
        bytes32 pairKey = getPairKey(_collateralToken, _indexToken);
        if (_isLong) {
            if (
                totalLongSizes[pairKey] > maxTotalLongSizes[pairKey] &&
                maxTotalLongSizes[pairKey] > 0
            ) {
                revert("total_size_exceed");
            }
        } else {
            if (
                totalShortSizes[pairKey] > maxTotalShortSizes[pairKey] &&
                maxTotalShortSizes[pairKey] > 0
            ) {
                revert("total_size_exceed");
            }
        }
    }

    // validate msg.sender is router address or position holder(real user)
    function validateRouter(address _account) public view {
        _validateRouter(_account);
    }
}
