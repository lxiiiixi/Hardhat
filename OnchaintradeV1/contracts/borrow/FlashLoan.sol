// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

abstract contract FlashLoan is IERC3156FlashLender {
    bytes32 private constant _RETURN_VALUE = keccak256("ERC3156FlashBorrower.onFlashLoan");

    function flashFee(address, uint256 amount) public view virtual override returns (uint256);

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) public override returns (bool) {
        require(amount <= maxFlashLoan(token), "AMOUNT_EXCCED");
        uint256 fee = flashFee(token, amount);
        flashLoanBorrow(token, amount, address(receiver));
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == _RETURN_VALUE,
            "INVALID_RETURN"
        );
        flashLoanRepay(token, amount, fee, address(receiver));
        return true;
    }

    function maxFlashLoan(address token) public view virtual override returns (uint256);

    function flashLoanBorrow(
        address token,
        uint256 amount,
        address to
    ) internal virtual;

    function flashLoanRepay(
        address token,
        uint256 amount,
        uint256 amountFee,
        address from
    ) internal virtual;
}
