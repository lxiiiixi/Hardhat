// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IFuture.sol";
import "../interfaces/ISwapForFuture.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IFutureLimit.sol";
import "../interfaces/ITradeStakeUpdater.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "hardhat/console.sol";

// future router contract
contract FutureRouter {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // weth contract
    address public weth;
    // future contract
    address public future;
    address public futureLimit;
    // swap contract
    address public swapPool;
    // stake updater contract
    address public tradeStakeUpdater;

    constructor(
        address _future,
        address _weth,
        address _swapPool,
        address _tradeStakeUpdater,
        address _futureLimit
    ) {
        future = _future;
        weth = _weth;
        swapPool = _swapPool;
        tradeStakeUpdater = _tradeStakeUpdater;
        futureLimit = _futureLimit;
    }

    receive() external payable {
        require(msg.sender == weth, "invalid_eth_sender");
    }

    // get execution fee for limit orders
    function getLimitMinExecFee() external view returns (uint256) {
        return IFutureLimit(futureLimit).minExecFee();
    }

    // user open/increase position
    function increasePosition(
        address _tokenIn,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _notionalDelta,
        uint256 _collateralPrice,
        uint256 _indexPrice
    ) external {
        if (_tokenIn != _collateralToken && _amountIn > 0) {
            IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
            IERC20(_tokenIn).approve(swapPool, _amountIn);
            _amountIn = ISwapForFuture(swapPool).swapIn(
                _tokenIn,
                _collateralToken,
                _amountIn,
                _minOut,
                future,
                0
            );
        }
        if (_tokenIn == _collateralToken && _amountIn > 0) {
            IERC20(_tokenIn).safeTransferFrom(msg.sender, address(future), _amountIn);
        }
        _increasePosition(
            _collateralToken,
            _indexToken,
            _isLong,
            _notionalDelta,
            _collateralPrice,
            _indexPrice
        );
    }

    // limit open position
    function limitIncreasePosition(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        uint256 _sizeDelta,
        uint256 _execFee
    ) external payable {
        require(msg.value == _execFee && msg.value > 0, "incorrect_msg_value");
        if (_marginDelta > 0) {
            IERC20(_collateralToken).safeTransferFrom(
                msg.sender,
                address(futureLimit),
                _marginDelta
            );
        }

        IFutureLimit(futureLimit).createIncreaseOrder{value: _execFee}(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _notionalDelta,
            _sizeDelta,
            _execFee
        );
    }

    // open eth margined position
    function limitIncreasePositionETH(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        uint256 _sizeDelta,
        uint256 _execFee
    ) external payable {
        require(msg.value == _marginDelta + _execFee, "incorrect_msg_value");
        require(_execFee > 0, "exec_fee_zero");
        require(weth == _collateralToken, "invalid_collateral_weth");
        if (_marginDelta > 0) {
            IWETH(weth).deposit{value: _marginDelta}();
            IERC20(weth).safeTransfer(futureLimit, _marginDelta);
        }
        IFutureLimit(futureLimit).createIncreaseOrder{value: _execFee}(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _notionalDelta,
            _sizeDelta,
            _execFee
        );
    }

    // limit decrease position
    function limitDecrasePosition(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _minSizeDelta,
        uint256 _maxSizeDelta,
        uint256 _execFee
    ) external payable {
        require(msg.value == _execFee && _execFee > 0, "incorrect_msg_value");
        IFutureLimit(futureLimit).createDecreaseOrder{value: _execFee}(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _notionalDelta,
            _minSizeDelta,
            _maxSizeDelta,
            _execFee
        );
    }

    // limit open and stop loss/take profit
    function limitIncreaseAndDecreasePosition(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _increaseMarginDelta,
        uint256 _increaseNotionalDelta,
        uint256 _increaseSizeDelta,
        uint256 _increaseExecFee,
        uint256 _decreaseNotionalDelta,
        uint256 _decreaseMinSizeDelta,
        uint256 _decreaseMaxSizeDelta,
        uint256 _decreaseExecFee
    ) external payable {
        require(msg.value == _increaseExecFee + _decreaseExecFee, "incorrect_msg_value");
        require(_increaseExecFee > 0, "exec_fee_zero");
        require(_decreaseExecFee > 0, "exec_fee_zero");
        if (_increaseMarginDelta > 0) {
            IERC20(_collateralToken).safeTransferFrom(
                msg.sender,
                address(futureLimit),
                _increaseMarginDelta
            );
        }
        IFutureLimit(futureLimit).createIncreaseOrder{value: _increaseExecFee}(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _increaseNotionalDelta,
            _increaseSizeDelta,
            _increaseExecFee
        );
        IFutureLimit(futureLimit).createDecreaseOrder{value: _decreaseExecFee}(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _decreaseNotionalDelta,
            _decreaseMinSizeDelta,
            _decreaseMaxSizeDelta,
            _decreaseExecFee
        );
    }

    // eth margined limit increase and stop loss/take profit or limit close
    function limitIncreaseAndDecreasePositionETH(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _increaseMarginDelta,
        uint256 _increaseNotionalDelta,
        uint256 _increaseSizeDelta,
        uint256 _increaseExecFee,
        uint256 _decreaseNotionalDelta,
        uint256 _decreaseMinSizeDelta,
        uint256 _decreaseMaxSizeDelta,
        uint256 _decreaseExecFee
    ) external payable {
        require(
            msg.value == _increaseMarginDelta + _increaseExecFee + _decreaseExecFee,
            "incorrect_msg_value"
        );
        require(_increaseExecFee > 0, "exec_fee_zero");
        require(_decreaseExecFee > 0, "exec_fee_zero");
        require(weth == _collateralToken, "invalid_collateral_weth");
        if (_increaseMarginDelta > 0) {
            IWETH(weth).deposit{value: _increaseMarginDelta}();
            IERC20(_collateralToken).safeTransfer(address(futureLimit), _increaseMarginDelta);
        }
        IFutureLimit(futureLimit).createIncreaseOrder{value: _increaseExecFee}(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _increaseNotionalDelta,
            _increaseSizeDelta,
            _increaseExecFee
        );
        IFutureLimit(futureLimit).createDecreaseOrder{value: _decreaseExecFee}(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _decreaseNotionalDelta,
            _decreaseMinSizeDelta,
            _decreaseMaxSizeDelta,
            _decreaseExecFee
        );
    }

    // execute increase orders
    function execIncreaseOrder(address _account, uint256 _orderIndex) external {
        IFutureLimit(futureLimit).execIncreaseOrder(_account, _orderIndex, payable(msg.sender));
    }

    // execute decrease orders
    function execDecreaseOrder(address _account, uint256 _orderIndex) external returns (uint256) {
        address collateralToken = IFutureLimit(futureLimit).getDecreaseOrderCollateralToken(
            _account,
            _orderIndex
        );
        if (collateralToken == weth) {
            uint256 marginDelta = IFutureLimit(futureLimit).execDecreaseOrder(
                _account,
                _orderIndex,
                address(this),
                payable(msg.sender)
            );
            IWETH(weth).withdraw(marginDelta);
            _transferOutETH(marginDelta, payable(_account));
            return marginDelta;
        } else {
            return
                IFutureLimit(futureLimit).execDecreaseOrder(
                    _account,
                    _orderIndex,
                    _account,
                    payable(msg.sender)
                );
        }
    }

    // cancel increase orders
    function cancelIncreaseOrder(uint256 _orderIndex) public {
        (address collateralToken, , , , uint256 _marginDelta, , , ) = IFutureLimit(futureLimit)
            .getIncreaseOrder(msg.sender, _orderIndex);
        if (collateralToken == weth && _marginDelta > 0) {
            IFutureLimit(futureLimit).cancelIncreaseOrder(
                msg.sender,
                _orderIndex,
                address(this),
                payable(msg.sender)
            );
            IWETH(futureLimit).withdraw(_marginDelta);
            _transferOutETH(_marginDelta, payable(msg.sender));
        } else {
            IFutureLimit(futureLimit).cancelIncreaseOrder(
                msg.sender,
                _orderIndex,
                msg.sender,
                payable(msg.sender)
            );
        }
    }

    // cancel decrease orders
    function cancelDecreaseOrder(uint256 _orderIndex) public {
        IFutureLimit(futureLimit).cancelDecreaseOrder(msg.sender, _orderIndex, payable(msg.sender));
    }

    // bulk cancel orders
    function bulkCancelOrder(
        uint256[] memory increaseOrderIndexes,
        uint256[] memory decreaseOrderIndexes
    ) external {
        for (uint256 i = 0; i < increaseOrderIndexes.length; i++) {
            address collateralToken = IFutureLimit(futureLimit).getIncreaseOrderCollateralToken(
                msg.sender,
                increaseOrderIndexes[i]
            );
            if (collateralToken == address(0)) {
                // order not exist
                continue;
            }
            cancelIncreaseOrder(increaseOrderIndexes[i]);
        }
        for (uint256 i = 0; i < decreaseOrderIndexes.length; i++) {
            address collateralToken = IFutureLimit(futureLimit).getDecreaseOrderCollateralToken(
                msg.sender,
                decreaseOrderIndexes[i]
            );
            if (collateralToken == address(0)) {
                // order not exist
                continue;
            }
            cancelDecreaseOrder(decreaseOrderIndexes[i]);
        }
    }

    function bulkLimitOrderExecable(
        address[] memory increaseOrderAccounts,
        uint256[] memory increaseOrderIndexes,
        address[] memory decreaseOrderAccounts,
        uint256[] memory decreaseOrderIndexes
    )
        public
        view
        returns (bool[] memory increaseOrderExecables, bool[] memory decreaseOrderExecables)
    {
        uint256 increaseOrderLen = increaseOrderAccounts.length;
        uint256 decreaseOrderLen = decreaseOrderAccounts.length;
        require(increaseOrderLen == increaseOrderIndexes.length, "invalid_length");
        require(decreaseOrderLen == decreaseOrderIndexes.length, "invalid_length");

        increaseOrderExecables = new bool[](increaseOrderLen);
        decreaseOrderExecables = new bool[](decreaseOrderLen);

        for (uint256 i = 0; i < increaseOrderLen; i++) {
            increaseOrderExecables[i] = IFutureLimit(futureLimit).increaseOrderExecable(
                increaseOrderAccounts[i],
                increaseOrderIndexes[i]
            );
        }
        for (uint256 i = 0; i < decreaseOrderLen; i++) {
            decreaseOrderExecables[i] = IFutureLimit(futureLimit).decreaseOrderExecable(
                decreaseOrderAccounts[i],
                decreaseOrderIndexes[i]
            );
        }
    }

    // increase ETH margined positions
    function increasePositionETH(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _minOut,
        uint256 _notionalDelta,
        uint256 _collateralPrice,
        uint256 _indexPrice
    ) external payable {
        uint256 _amountIn = msg.value;
        if (_amountIn > 0) {
            IWETH(weth).deposit{value: _amountIn}();
        }
        if (weth != _collateralToken && _amountIn > 0) {
            require(IERC20(weth).approve(swapPool, _amountIn), "approve_fail");
            _amountIn = ISwapForFuture(swapPool).swapIn(
                weth,
                _collateralToken,
                _amountIn,
                _minOut,
                future,
                0
            );
        }
        if (weth == _collateralToken && _amountIn > 0) {
            IERC20(weth).transfer(future, _amountIn);
        }
        _increasePosition(
            _collateralToken,
            _indexToken,
            _isLong,
            _notionalDelta,
            _collateralPrice,
            _indexPrice
        );
    }

    // increase position
    function _increasePosition(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _notionalDelta,
        uint256 _collateralPrice,
        uint256 _indexPrice
    ) private {
        if (_collateralPrice > 0) {
            require(IFuture(future).getPrice(_collateralToken) >= _collateralPrice, "price_limit");
        }
        if (_indexPrice > 0) {
            require(IFuture(future).getPrice(_indexToken) <= _indexPrice, "price_limit");
        }
        ITradeStakeUpdater(tradeStakeUpdater).increasePosition(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _notionalDelta
        );
        IFuture(future).increasePosition(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _notionalDelta
        );
    }

    // user decrease/close position
    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        uint256 _collateralPrice,
        uint256 _indexPrice,
        address _receiver,
        address _tokenOut
    ) external {
        _decreasePosition(
            _collateralToken,
            _indexToken,
            _isLong,
            _marginDelta,
            _notionalDelta,
            _collateralPrice,
            _indexPrice,
            _receiver,
            _tokenOut
        );
    }

    // user decrease ETH margined positions
    function decreasePositionETH(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        uint256 _collateralPrice,
        uint256 _indexPrice,
        address payable _receiver
    ) external {
        require(_collateralToken == weth, "invalid_collateral");
        uint256 amountOut = _decreasePosition(
            _collateralToken,
            _indexToken,
            _isLong,
            _marginDelta,
            _notionalDelta,
            _collateralPrice,
            _indexPrice,
            address(this),
            address(this)
        );
        IWETH(weth).withdraw(amountOut);
        _receiver.sendValue(amountOut);
    }

    // liquidate position method
    function liquidatePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external {
        ITradeStakeUpdater(tradeStakeUpdater).liquidatePosition(
            _collateralToken,
            _indexToken,
            _account,
            _isLong
        );
        IFuture(future).liquidatePosition(_collateralToken, _indexToken, _account, _isLong);
    }

    // bulk liquidate position method
    function bulkLiquidatePosition(
        address[] memory _collTokens,
        address[] memory _indexTokens,
        address[] memory _accounts,
        bool[] memory _isLongs
    ) external {
        require(_collTokens.length == _indexTokens.length, "invalid_length");
        require(_collTokens.length == _accounts.length, "invalid_length");
        require(_collTokens.length == _isLongs.length, "invalid_length");
        for (uint256 i = 0; i < _collTokens.length; i++) {
            IFuture(future).liquidatePosition(
                _collTokens[i],
                _indexTokens[i],
                _accounts[i],
                _isLongs[i]
            );
        }
    }

    // user increase margin
    function increaseMargin(
        address _tokenIn,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountIn,
        uint256 _minOut
    ) external {
        require(_amountIn > 0, "invalid_amount");
        if (_tokenIn != _collateralToken) {
            IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
            IERC20(_tokenIn).approve(swapPool, _amountIn);
            _amountIn = ISwapForFuture(swapPool).swapIn(
                _tokenIn,
                _collateralToken,
                _amountIn,
                _minOut,
                future,
                0
            );
        }
        if (_tokenIn == _collateralToken) {
            IERC20(_tokenIn).safeTransferFrom(msg.sender, future, _amountIn);
        }
        IFuture(future).increaseMargin(_collateralToken, _indexToken, msg.sender, _isLong);
    }

    // increase eth margined position
    function increaseMarginETH(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _minOut
    ) external payable {
        uint256 _amountIn = msg.value;
        require(_amountIn > 0, "invalid_msg_value");
        IWETH(weth).deposit{value: _amountIn}();
        if (weth != _collateralToken) {
            require(IERC20(weth).approve(swapPool, _amountIn), "approve_fail");
            _amountIn = ISwapForFuture(swapPool).swapIn(
                weth,
                _collateralToken,
                _amountIn,
                _minOut,
                future,
                0
            );
        }
        if (weth == _collateralToken) {
            IERC20(weth).transfer(future, _amountIn);
        }
        IFuture(future).increaseMargin(_collateralToken, _indexToken, msg.sender, _isLong);
    }

    // decrease margin
    function decreaseMargin(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountOut,
        address _receiver
    ) external {
        IFuture(future).decreaseMargin(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _amountOut,
            _receiver
        );
    }

    // increase insurance fund
    function increaseInsuranceFund(address _collateralToken, uint256 _amount) external {
        IERC20(_collateralToken).safeTransferFrom(msg.sender, future, _amount);
        IFuture(future).increaseInsuranceFund(_collateralToken);
    }

    // decrease ETH margin
    function decreaseMarginETH(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _amountOut,
        address payable _receiver
    ) external {
        require(_collateralToken == weth, "invalid_collateral_token");
        IFuture(future).decreaseMargin(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _amountOut,
            address(this)
        );
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    // decrease/close position
    function _decreasePosition(
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _marginDelta,
        uint256 _notionalDelta,
        uint256 _collateralPrice,
        uint256 _indexPrice,
        address _receiver,
        address _tokenOut
    ) private returns (uint256) {
        require(msg.sender == _receiver, "Invalid caller");
        if (_collateralPrice > 0) {
            require(IFuture(future).getPrice(_collateralToken) >= _collateralPrice, "price_limit");
        }
        if (_indexPrice > 0) {
            require(IFuture(future).getPrice(_indexToken) <= _indexPrice, "price_limit");
        }
        ITradeStakeUpdater(tradeStakeUpdater).decreasePosition(
            _collateralToken,
            _indexToken,
            msg.sender,
            _isLong,
            _marginDelta,
            _notionalDelta,
            _receiver
        );

        if (_tokenOut != _collateralToken) {
            uint256 _amountOut = IFuture(future).decreasePositionByRatio(
                _collateralToken,
                _indexToken,
                msg.sender,
                _isLong,
                _notionalDelta,
                address(this)
            );
            IERC20(_collateralToken).approve(swapPool, _amountOut);
            return
                ISwapForFuture(swapPool).swapIn(
                    _collateralToken,
                    _tokenOut,
                    _amountOut,
                    0,
                    _receiver,
                    0
                );
        }

        return
            IFuture(future).decreasePositionByRatio(
                _collateralToken,
                _indexToken,
                msg.sender,
                _isLong,
                _notionalDelta,
                _receiver
            );
    }

    // transfer ETH to future contract
    function _transferETHToFuture() private {
        IWETH(weth).deposit();
        IERC20(weth).safeTransfer(future, msg.value);
    }

    // transfer ETH out from future contract
    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }
}
