// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/IFastPriceFeed.sol";
import "../interfaces/IFastPriceEvent.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

// 价格源
contract FastPriceFeed is IFastPriceFeed, Ownable {
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    //  (256 - 32) 0s followed by 32 1s
    uint256 public constant PRICE_BITMASK = 0xffffffff;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    uint256 public constant MAX_PRICE_DURATION = 30 minutes;

    address public fastPriceEvent;

    uint256 public override lastUpdatedAt;
    uint256 public override lastUpdatedBlock;

    uint256 public priceDuration;
    uint256 public minBlockInterval;
    uint256 public maxTimeDeviation;

    // max deviation from primary price
    uint256 public maxDeviationBasisPoints;

    mapping(address => bool) public isUpdater;

    mapping(address => uint256) public prices;

    address[] public tokens;
    // 10 ** tokenDecimal
    uint256[] public tokenPrecisions;

    modifier onlyUpdater() {
        require(isUpdater[msg.sender], "fast_price_feed_forbideen");
        _;
    }

    constructor(
        uint256 _priceDuration,
        uint256 _minBlockInterval,
        uint256 _maxDeviationBasisPoints,
        address _fastPriceEvent
    ) {
        require(_priceDuration <= MAX_PRICE_DURATION, "invalid_price_duration");
        priceDuration = _priceDuration;
        minBlockInterval = _minBlockInterval;
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
        fastPriceEvent = _fastPriceEvent;
    }

    function setUpdater(address _account, bool _isActive) external onlyOwner {
        isUpdater[_account] = _isActive;
    }

    function setFastPriceEvents(address _fastPriceEvent) external onlyOwner {
        fastPriceEvent = _fastPriceEvent;
    }

    function setPriceDuration(uint256 _priceDuration) external onlyOwner {
        require(_priceDuration <= MAX_PRICE_DURATION, "invalid_price_duration");
        priceDuration = _priceDuration;
    }

    function setMinBlockInterval(uint256 _minBlockInterval) external onlyOwner {
        minBlockInterval = _minBlockInterval;
    }

    function setMaxTimeDeviation(uint256 _maxTimeDeviation) external onlyOwner {
        maxTimeDeviation = _maxTimeDeviation;
    }

    function setLastUpdatedAt(uint256 _lastUpdatedAt) external onlyOwner {
        lastUpdatedAt = _lastUpdatedAt;
    }

    function setMaxDeviationBasisPoints(
        uint256 _maxDeviationBasisPoints
    ) external onlyOwner {
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
    }

    function setTokens(
        address[] memory _tokens,
        uint256[] memory _tokenPrecisions
    ) external onlyOwner {
        require(_tokens.length == _tokenPrecisions.length, "invalid_length");
        tokens = _tokens;
        tokenPrecisions = _tokenPrecisions;
    }

    function setPrice(
        address _token,
        uint256 _price,
        uint256 _timestamp
    ) external onlyOwner {
        prices[_token] = _price;
        address _fastPriceEvent = fastPriceEvent;
        _emitPriceEvent(_fastPriceEvent, _token, _price, _timestamp);
    }

    function setPrices(
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _timestamp
    ) external onlyUpdater {
        _setLastUpdatedValues();
        _timestamp = block.timestamp;
        address _fastPriceEvent = fastPriceEvent;

        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            prices[token] = _prices[i];
            _emitPriceEvent(_fastPriceEvent, token, _prices[i], _timestamp);
        }
    }

    function setCompactedPrices(
        uint256[] memory _priceBitArray
    ) external onlyUpdater {
        uint256 _timestamp = block.timestamp;
        _setLastUpdatedValues();

        address _fastPriceEvent = fastPriceEvent;

        for (uint256 i = 0; i < _priceBitArray.length; i++) {
            uint256 priceBits = _priceBitArray[i];

            for (uint256 j = 0; j < 8; j++) {
                uint256 index = i * 8 + j;
                if (index >= tokens.length) {
                    return;
                }

                uint256 startBit = 32 * j;
                uint256 price = (priceBits >> startBit) & PRICE_BITMASK;

                address token = tokens[i * 8 + j];
                uint256 tokenPrecision = tokenPrecisions[i * 8 + j];
                uint256 adjustedPrice = (price * PRICE_PRECISION) /
                    tokenPrecision;
                prices[token] = adjustedPrice;

                _emitPriceEvent(
                    _fastPriceEvent,
                    token,
                    adjustedPrice,
                    _timestamp
                );
            }
        }
    }

    function setPricesWithBits(uint256 _priceBits) external onlyUpdater {
        _setPricesWithBits(_priceBits);
    }

    function getPrice(
        address _token,
        uint256 _refPrice
    ) external view override returns (uint256) {
        if (block.timestamp > lastUpdatedAt + priceDuration) {
            return _refPrice;
        }

        uint256 fastPrice = prices[_token];
        if (fastPrice == 0) {
            return _refPrice;
        }

        if (_refPrice == 0) {
            return fastPrice;
        }

        uint256 maxPrice = (_refPrice *
            (BASIS_POINTS_DIVISOR + maxDeviationBasisPoints)) /
            BASIS_POINTS_DIVISOR;
        uint256 minPrice = (_refPrice *
            (BASIS_POINTS_DIVISOR - maxDeviationBasisPoints)) /
            BASIS_POINTS_DIVISOR;

        if (fastPrice >= minPrice && fastPrice <= maxPrice) {
            return fastPrice;
        }
        return _refPrice;
    }

    function getPlainPrice(
        address _token
    ) external view override returns (uint256) {
        if (block.timestamp > lastUpdatedAt + priceDuration) {
            revert("price_expired");
        }
        return prices[_token];
    }

    function _setPricesWithBits(uint256 _priceBits) private {
        _setLastUpdatedValues();
        address _fastPriceEvent = fastPriceEvent;
        uint256 _timestamp = block.timestamp;
        for (uint256 j = 0; j < 8; j++) {
            uint256 index = j;
            if (index >= tokens.length) {
                return;
            }

            uint256 startBit = 32 * j;
            uint256 price = (_priceBits >> startBit) & PRICE_BITMASK;

            address token = tokens[j];
            uint256 tokenPrecision = tokenPrecisions[j];
            uint256 adjustedPrice = (price * PRICE_PRECISION) / tokenPrecision;
            prices[token] = adjustedPrice;

            _emitPriceEvent(_fastPriceEvent, token, adjustedPrice, _timestamp);
        }
    }

    function _emitPriceEvent(
        address _fastPriceEvent,
        address _token,
        uint256 _price,
        uint256 _timestamp
    ) private {
        if (_fastPriceEvent == address(0)) {
            return;
        }

        IFastPriceEvent(_fastPriceEvent).emitPriceEvent(
            _token,
            _price,
            _timestamp
        );
    }

    function _setLastUpdatedValues() private {
        lastUpdatedAt = block.timestamp;
        lastUpdatedBlock = block.number;
    }
}
