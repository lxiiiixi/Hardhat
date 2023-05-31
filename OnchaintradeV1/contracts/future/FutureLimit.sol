// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IFuture.sol";
import "../interfaces/IFutureLimit.sol";
import "hardhat/console.sol";

contract FutureLimit is Ownable, ReentrancyGuard, IFutureLimit {
    using SafeERC20 for IERC20;
    using Address for address payable;

    struct IncreaseOrder {
        address collateralToken;
        address indexToken;
        address account;
        bool isLong;
        uint256 marginDelta;
        uint256 notionalDelta;
        uint256 sizeDelta;
        uint256 execFee;
    }

    struct DecreaseOrder {
        address collateralToken;
        address indexToken;
        address account;
        bool isLong;
        uint256 notionalDelta;
        // for side:long, minSizeDelta for take profit, maxSizeDelta for stop loss
        // for side:short, minSizeDelta for stop loss, maxSizeDelta for take profit
        uint256 minSizeDelta;
        uint256 maxSizeDelta;
        uint256 execFee;
    }

    enum ExecStatus {
        success, // exec success
        decreaseExceed, // failed before operating, pos.openNotional < notionalDelta when decrease
        pairUnlist, // failed before operating, pair unlist
        pendingExec, // waiting for exec
        cancel // user cancel
    }

    enum Operation {
        create,
        update,
        cancel,
        exec
    }

    enum DecreaseExecType {
        takeProfit,
        stopLoss
    }

    mapping(address => mapping(uint256 => IncreaseOrder)) public increaseOrders;
    mapping(address => mapping(uint256 => DecreaseOrder)) public decreaseOrders;
    mapping(address => uint256) public increaseOrderIndexes;
    mapping(address => uint256) public decreaseOrderIndexes;
    mapping(address => bool) public systemRouters;
    mapping(address => uint256) public tokenBalances;
    address public future;
    uint256 public minExecFee;

    event CreateIncreaseOrder(address account, uint256 orderIndex);
    event CancelIncreaseOrder(address account, uint256 orderIndex);
    event ExecIncreaseOrder(address account, uint256 orderIndex);
    event EditIncreaseOrder(address account, uint256 orderIndex);
    event UpdateIncreaseOrder(
        address collateralToken,
        address indexToken,
        address indexed account,
        bool isLong,
        uint256 marginDelta,
        uint256 notionalDelta,
        uint256 sizeDelta,
        uint256 execFee,
        uint256 orderIndex,
        Operation operation,
        ExecStatus execStatus
    );

    event CreateDecreaseOrder(address account, uint256 orderIndex);
    event CancelDecreaseOrder(address account, uint256 orderIndex);
    event ExecDecreaseOrder(address account, uint256 orderIndex);
    event EditDecreaseOrder(address account, uint256 orderIndex);
    event UpdateDecreaseOrder(
        address collateralToken,
        address indexToken,
        address indexed account,
        bool isLong,
        uint256 notionalDelta,
        uint256 minSizeDelta,
        uint256 maxSizeDelta,
        uint256 execFee,
        uint256 orderIndex,
        Operation operation,
        ExecStatus execStatus,
        DecreaseExecType execType
    );

    event SetSystemRouter(address router, bool enable);
    event SetMinExecFee(uint256 _minExecFee);

    constructor(address _future, uint256 _minExecFee) {
        future = _future;
        minExecFee = _minExecFee;

        emit SetMinExecFee(minExecFee);
    }

    function setMinExecFee(uint256 _minExecFee) public onlyOwner {
        minExecFee = _minExecFee;
        emit SetMinExecFee(_minExecFee);
    }

    function setSystemRouter(address router, bool enable) public onlyOwner {
        systemRouters[router] = enable;
        emit SetSystemRouter(router, enable);
    }

    function createIncreaseOrder(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _sizeDelta,
        uint256 _execFee // in eth
    ) external payable override nonReentrant returns (uint256) {
        _validateRouter(_account);
        _validPairList(_collateralToken, _indexToken, true);
        _assertExecFeeValid(_execFee);
        uint256 _marginDelta = _transferIn(_collateralToken);
        _assertIncreaseOrderSizeDeltaValid(
            _collateralToken,
            _indexToken,
            _isLong,
            _notionalDelta,
            _sizeDelta
        );

        uint256 _orderIndex = increaseOrderIndexes[_account];
        IncreaseOrder memory order = IncreaseOrder(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            _marginDelta,
            _notionalDelta,
            _sizeDelta,
            _execFee
        );
        increaseOrderIndexes[_account] = _orderIndex + 1;
        increaseOrders[_account][_orderIndex] = order;

        emit CreateIncreaseOrder(_account, _orderIndex);
        emit UpdateIncreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.marginDelta,
            order.notionalDelta,
            order.sizeDelta,
            order.execFee,
            _orderIndex,
            Operation.create,
            ExecStatus.pendingExec
        );

        return _orderIndex;
    }

    function updateIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        uint256 _notionalDelta,
        uint256 _sizeDelta
    ) external override nonReentrant {
        _validateRouter(_account);

        IncreaseOrder storage order = increaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);

        order.notionalDelta = _notionalDelta;
        order.sizeDelta = _sizeDelta;

        _assertIncreaseOrderSizeDeltaValid(
            order.collateralToken,
            order.indexToken,
            order.isLong,
            _notionalDelta,
            _sizeDelta
        );

        emit EditIncreaseOrder(_account, _orderIndex);
        emit UpdateIncreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.marginDelta,
            order.notionalDelta,
            order.sizeDelta,
            order.execFee,
            _orderIndex,
            Operation.update,
            ExecStatus.pendingExec
        );
    }

    function cancelIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address _to,
        address payable _execFeeTo
    ) external override nonReentrant {
        _validateRouter(_account);
        IncreaseOrder memory order = increaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);

        delete increaseOrders[_account][_orderIndex];

        _transferOut(order.collateralToken, order.marginDelta, _to);
        _transferOutEth(order.execFee, _execFeeTo);

        emit CancelIncreaseOrder(_account, _orderIndex);
        emit UpdateIncreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.marginDelta,
            order.notionalDelta,
            order.sizeDelta,
            order.execFee,
            _orderIndex,
            Operation.cancel,
            ExecStatus.cancel
        );
    }

    function execIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _execFeeTo
    ) external override nonReentrant {
        IncreaseOrder memory order = increaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);
        validateIncreaseOrderPrice(_account, _orderIndex, true);
        delete increaseOrders[_account][_orderIndex];

        _transferOut(order.collateralToken, order.marginDelta, future);
        IFuture(future).increasePosition(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta
        );
        _transferOutEth(order.execFee, _execFeeTo);

        emit ExecIncreaseOrder(_account, _orderIndex);
        emit UpdateIncreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.marginDelta,
            order.notionalDelta,
            order.sizeDelta,
            order.execFee,
            _orderIndex,
            Operation.exec,
            ExecStatus.success
        );
    }

    function createDecreaseOrder(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _minSizeDelta,
        uint256 _maxSizeDelta,
        uint256 _execFee
    ) external payable override nonReentrant returns (uint256) {
        _validateRouter(_account);
        _validPairList(_collateralToken, _indexToken, true);
        _assertExecFeeValid(_execFee);
        _assertDecreaseOrderSizeDeltaValid(
            _collateralToken,
            _indexToken,
            _notionalDelta,
            _minSizeDelta,
            _maxSizeDelta
        );

        uint256 _orderIndex = decreaseOrderIndexes[_account];
        DecreaseOrder memory order = DecreaseOrder(
            _collateralToken,
            _indexToken,
            _account,
            _isLong,
            _notionalDelta,
            _minSizeDelta,
            _maxSizeDelta,
            _execFee
        );
        decreaseOrderIndexes[_account] = _orderIndex + 1;
        decreaseOrders[_account][_orderIndex] = order;

        emit CreateDecreaseOrder(_account, _orderIndex);
        emit UpdateDecreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta,
            order.minSizeDelta,
            order.maxSizeDelta,
            order.execFee,
            _orderIndex,
            Operation.create,
            ExecStatus.pendingExec,
            DecreaseExecType.takeProfit
        );

        return _orderIndex;
    }

    function updateDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        uint256 _notionalDelta,
        uint256 _minSizeDelta,
        uint256 _maxSizeDelta
    ) external override nonReentrant {
        _validateRouter(_account);

        DecreaseOrder storage order = decreaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);
        _assertDecreaseOrderSizeDeltaValid(
            order.collateralToken,
            order.indexToken,
            _notionalDelta,
            _minSizeDelta,
            _maxSizeDelta
        );

        order.notionalDelta = _notionalDelta;
        order.minSizeDelta = _minSizeDelta;
        order.maxSizeDelta = _maxSizeDelta;

        emit EditDecreaseOrder(_account, _orderIndex);
        emit UpdateDecreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta,
            order.minSizeDelta,
            order.maxSizeDelta,
            order.execFee,
            _orderIndex,
            Operation.update,
            ExecStatus.pendingExec,
            DecreaseExecType.takeProfit
        );
    }

    function cancelDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _execFeeTo
    ) external override nonReentrant {
        _validateRouter(_account);
        DecreaseOrder memory order = decreaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);
        delete decreaseOrders[_account][_orderIndex];
        _transferOutEth(order.execFee, _execFeeTo);
        emit CancelDecreaseOrder(_account, _orderIndex);
        emit UpdateDecreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta,
            order.minSizeDelta,
            order.maxSizeDelta,
            order.execFee,
            _orderIndex,
            Operation.cancel,
            ExecStatus.cancel,
            DecreaseExecType.takeProfit
        );
    }

    function execDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address _marginTo,
        address payable _execFeeTo
    ) external override nonReentrant returns (uint256) {
        _validateRouter(_account); // decrease order will send margin to _marginTo address, so restrict the msg.sender to accepted router or account self
        // for weth => eth transform, do not transfer collateral token to _account directly here
        DecreaseOrder memory order = decreaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);
        validDecreaseOrderNotional(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta,
            true
        );

        _transferOutEth(order.execFee, _execFeeTo);

        DecreaseExecType execType = DecreaseExecType.takeProfit;
        {
            (, bool isStopLossValid) = validateDecreaseOrderPrice(_account, _orderIndex, true);

            if (isStopLossValid) {
                execType = DecreaseExecType.stopLoss;
            }
        }
        delete decreaseOrders[_account][_orderIndex];

        emit ExecDecreaseOrder(_account, _orderIndex);
        emit UpdateDecreaseOrder(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta,
            order.minSizeDelta,
            order.maxSizeDelta,
            order.execFee,
            _orderIndex,
            Operation.exec,
            ExecStatus.success,
            execType
        );
        uint256 marginDelta = IFuture(future).decreasePositionByRatio(
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta,
            _marginTo
        );
        return marginDelta;
    }

    function getIncreaseOrder(address _account, uint256 _orderIndex)
        external
        view
        override
        returns (
            address collateralToken,
            address indexToken,
            address account,
            bool isLong,
            uint256 marginDelta,
            uint256 notionalDelta,
            uint256 sizeDelta,
            uint256 execFee
        )
    {
        IncreaseOrder storage order = increaseOrders[_account][_orderIndex];
        return (
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.marginDelta,
            order.notionalDelta,
            order.sizeDelta,
            order.execFee
        );
    }

    function getIncreaseOrderCollateralToken(address _account, uint256 _orderIndex)
        external
        view
        override
        returns (address collateralToken)
    {
        IncreaseOrder storage order = increaseOrders[_account][_orderIndex];
        return order.collateralToken;
    }

    function getDecreaseOrder(address _account, uint256 _orderIndex)
        external
        view
        override
        returns (
            address collateralToken,
            address indexToken,
            address account,
            bool isLong,
            uint256 notionalDelta,
            uint256 minSizeDelta,
            uint256 maxSizeDelta,
            uint256 execFee
        )
    {
        DecreaseOrder storage order = decreaseOrders[_account][_orderIndex];
        return (
            order.collateralToken,
            order.indexToken,
            order.account,
            order.isLong,
            order.notionalDelta,
            order.minSizeDelta,
            order.maxSizeDelta,
            order.execFee
        );
    }

    function getDecreaseOrderCollateralToken(address _account, uint256 _orderIndex)
        external
        view
        override
        returns (address collateralToken)
    {
        DecreaseOrder storage order = decreaseOrders[_account][_orderIndex];
        return order.collateralToken;
    }

    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
        return nextBalance - prevBalance;
    }

    function _transferOut(
        address _token,
        uint256 _amount,
        address _receiver
    ) private {
        IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
    }

    function _transferOutEth(uint256 _amount, address payable _receiver) private {
        _receiver.sendValue(_amount);
    }

    function _assertOrderExist(address orderAccount) private pure {
        require(_validOrderExist(orderAccount), "non_exist_order");
    }
    function _validOrderExist(address orderAccount) private pure returns(bool) {
        return orderAccount != address(0);
    }

    function _assertExecFeeValid(uint256 _execFee) private view {
        require(msg.value == _execFee, "incorrect_exec_fee");
        require(_execFee >= minExecFee, "low_exec_fee");
    }

    function _assertDecreaseOrderSizeDeltaValid(
        address _collateralToken,
        address _indexToken,
        uint256 _notionalDelta,
        uint256 _minSizeDelta,
        uint256 _maxSizeDelta
    ) private view {
        require(_notionalDelta > 0, "invalid_notional_delta");
        uint256 curSizeDelta = uint256(
            IFuture(future).token1ToToken2(_collateralToken, int256(_notionalDelta), _indexToken)
        );

        require(_minSizeDelta > 0 || _maxSizeDelta > 0, "invalid_size_delta");
        if (_minSizeDelta > 0 && _maxSizeDelta > 0) {
            require(_minSizeDelta < _maxSizeDelta, "invalid_size_delta");
        }
        require(_minSizeDelta < curSizeDelta, "invalid_open_price");
        require(_maxSizeDelta > curSizeDelta, "invalid_open_price");
    }

    function _assertIncreaseOrderSizeDeltaValid(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _sizeDelta
    ) private view {
        require(_notionalDelta > 0, "invalid_notional_delta");
        require(_sizeDelta > 0, "invalid_size_delta");
        uint256 curSizeDelta = uint256(
            IFuture(future).token1ToToken2(_collateralToken, int256(_notionalDelta), _indexToken)
        );
        if (_isLong) {
            require(_sizeDelta > curSizeDelta, "invalid_open_price");
        } else {
            require(_sizeDelta < curSizeDelta, "invalid_open_price");
        }
    }

    function _validateRouter(address _account) private view {
        if (msg.sender == _account) {
            return;
        }
        if (systemRouters[msg.sender]) {
            return;
        }
        revert("invalid_router");
    }

    function _validPairList(
        address _collateralToken,
        address _indexToken,
        bool _raise
    ) private view returns (bool) {
        IFuture.PairStatus status = IFuture(future).getPairStatus(_collateralToken, _indexToken);
        bool isList = status == IFuture.PairStatus.list;
        if (_raise) {
            require(isList, "pair_unlist");
        }
        return isList;
    }

    function increaseOrderExists(address account, uint256 orderIndex) public view returns (bool) {
        IncreaseOrder storage order = increaseOrders[account][orderIndex];
        return _validOrderExist(order.account);
    }

    function decreaseOrderExists(address account, uint256 orderIndex) public view returns (bool) {
        DecreaseOrder storage order = decreaseOrders[account][orderIndex];
        return _validOrderExist(order.account);
    }

    function increaseOrderExecable(address account, uint256 orderIndex) public view returns(bool) {
        bool exist = increaseOrderExists(account, orderIndex);
        if (!exist) {
            return false;
        }
        bool priceValid = validateIncreaseOrderPrice(account, orderIndex, false);
        return priceValid;
    }

    function decreaseOrderExecable(address account, uint256 orderIndex) public view returns(bool) {
        bool exist = decreaseOrderExists(account, orderIndex);
        if (!exist) {
            return false;
        }
        DecreaseOrder storage order = decreaseOrders[account][orderIndex];
        bool notionalValid = validDecreaseOrderNotional(order.collateralToken, order.indexToken, order.account, order.isLong, order.notionalDelta, false);
        if (!notionalValid) {
            return false;
        }
        (bool isTakeProfitValid, bool isStopLossValid) = validateDecreaseOrderPrice(account, orderIndex, false);
        bool priceValid = isTakeProfitValid || isStopLossValid;
        return priceValid;
    }

    function validDecreaseOrderNotional(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong,
        uint256 _notionalDelta,
        bool _raise
    ) public view override returns (bool) {
        (, uint256 posOpenNotional, , ) = IFuture(future).getPosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong
        );
        bool valid = posOpenNotional >= _notionalDelta;
        if (_raise) {
            require(valid, "notional_delta_exceed");
        }
        return valid;
    }

    function validateIncreaseOrderPrice(
        address _account,
        uint256 _orderIndex,
        bool _raise
    ) public view override returns (bool) {
        IncreaseOrder storage order = increaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);

        uint256 curSizeDelta = uint256(
            IFuture(future).token1ToToken2(
                order.collateralToken,
                int256(order.notionalDelta),
                order.indexToken
            )
        );
        bool valid = false;
        if (order.isLong) {
            valid = curSizeDelta >= order.sizeDelta;
        } else {
            valid = curSizeDelta <= order.sizeDelta;
        }
        if (_raise) {
            require(valid, "price_not_triggered");
        }
        return valid;
    }

    function validateDecreaseOrderPrice(
        address _account,
        uint256 _orderIndex,
        bool _raise
    ) public view override returns (bool takeProfitValid, bool stopLossValid) {
        DecreaseOrder storage order = decreaseOrders[_account][_orderIndex];
        _assertOrderExist(order.account);

        uint256 curSizeDelta = uint256(
            IFuture(future).token1ToToken2(
                order.collateralToken,
                int256(order.notionalDelta),
                order.indexToken
            )
        );

        if (order.isLong) {
            // take profit
            if (order.minSizeDelta > 0) {
                takeProfitValid = curSizeDelta <= order.minSizeDelta;
            }
            // stop loss
            if (order.maxSizeDelta > 0) {
                stopLossValid = curSizeDelta >= order.maxSizeDelta;
            }
        } else {
            // stop loss
            if (order.minSizeDelta > 0) {
                stopLossValid = curSizeDelta <= order.minSizeDelta;
            }
            // take profit
            if (order.maxSizeDelta > 0) {
                takeProfitValid = curSizeDelta >= order.maxSizeDelta;
            }
        }
        if (_raise && !takeProfitValid && !stopLossValid) {
            revert("price_not_triggered");
        }
    }
}
