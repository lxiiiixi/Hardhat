// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ITradeStakeUpdater} from "../interfaces/ITradeStakeUpdater.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockTradeStakeUpdater is ITradeStakeUpdater, Ownable {
    mapping(address => bool) private caller;
    uint256 public swapAmount;

    modifier expires(uint256 deadline) {
        // solhint-disable-next-line not-rely-on-time
        require(deadline == 0 || deadline >= block.timestamp, "EXPIRED");
        _;
    }

    modifier onlyCaller() {
        require(caller[_msgSender()], "onlyCaller");
        _;
    }

    function swapIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256,
        address to,
        uint256 deadline
    ) external override expires(deadline) onlyCaller {
        swapAmount += amountIn;
    }

    function swapOut(
        address tokenIn,
        address tokenOut,
        uint256,
        uint256 amountOut,
        address to,
        uint256 deadline
    ) external expires(deadline) onlyCaller {
        swapAmount -= amountOut;
    }

    function increasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool,
        uint256 _notionalDelta
    ) external {}

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool,
        uint256,
        uint256 _notionalDelta,
        address
    ) external {}

    function liquidatePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool _isLong
    ) external {}

    function setCaller(address _caller, bool _approve) external onlyOwner {
        caller[_caller] = _approve;
    }
}
