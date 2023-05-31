// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISwapForBorrow.sol";
import "../interfaces/IBorrowForSwap.sol";

import "hardhat/console.sol";

contract MockSwap is Ownable, ISwapForBorrow {
    using SafeERC20 for IERC20;
    IBorrowForSwap public $borrow;

    mapping(address => uint256) private mapper;
    
    function increasePosition(
        address _collateralToken,
        address _indexToken,
        address _account,
        bool,
        uint256 _notionalDelta
    ) external {
        
    }

    function getAvailability(address asset) external view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function borrow(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        IERC20(asset).transfer(to, amount);
        return IERC20(asset).balanceOf(address(this));
    }

    function repay(
        address asset,
        uint256 repayAmount,
        address from
    ) external override returns (uint256) {
        IERC20(asset).transferFrom(from, address(this), repayAmount);
        return IERC20(asset).balanceOf(address(this));
    }

    function getPriceRatio(address token) external pure returns (uint256, uint256){
        return (1, 1);
    }

    function setBorrow(address _borrow) external {
        $borrow = IBorrowForSwap(_borrow);
    }

    function addReserve(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        $borrow.updateInterest(asset, IERC20(asset).balanceOf(address(this)));
    }

    function removeReserve(address asset, uint256 amount) external {
        IERC20(asset).transfer(msg.sender, amount);
        $borrow.updateInterest(asset, IERC20(asset).balanceOf(address(this)));
    }

    function protocolRevenueExtract(address token, uint256 amount, address to) external returns(bool) {
        mapper[token] = amount;
        mapper[to] = amount;
        return true;
    }

    function settleFutureProfit(address token, uint256 amount, address from) external {
        IERC20(token).safeTransferFrom(from, address(this), amount);
    }
    
}
