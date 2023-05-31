// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract MockFlashBorrower is IERC3156FlashBorrower {
    bytes32 private constant _RETURN_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public borrowAddress;
    address public repayAddress;

    constructor(address _borrow, address _repay) {
        borrowAddress = _borrow;
        repayAddress = _repay;
    }

    function onFlashLoan(
        address, /* initiator */
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata /* data */
    ) external override returns (bytes32) {
        IERC20(token).transfer(borrowAddress, amount);
        IERC20(token).approve(repayAddress, amount + fee);
        return _RETURN_VALUE;
    }
}
