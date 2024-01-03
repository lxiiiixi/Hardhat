// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLenderPool is ReentrancyGuard, IERC3156FlashLender {
    address public owner;
    mapping(address => uint256) public balances;
    uint256 private constant FIXED_FEE = 1000;
    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    error CallbackFailed();

    constructor(address _owner) {
        owner = _owner;
    }

    function deposit(address token, uint256 amount) external {
        require(msg.sender == owner, "Only owner can deposit");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        balances[token] += amount;
    }

    function maxFlashLoan(address token) external view returns (uint256) {
        return balances[token];
    }

    function flashFee(
        address token,
        uint256 amount
    ) external pure returns (uint256) {
        return FIXED_FEE;
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        uint256 balanceBefore = balances[token];
        require(balanceBefore >= amount, "Not enough tokens in pool");

        IERC20(token).transfer(address(receiver), amount);
        balances[token] -= amount;
        if (
            IERC3156FlashBorrower(receiver).onFlashLoan(
                msg.sender,
                token,
                amount,
                FIXED_FEE,
                data
            ) != CALLBACK_SUCCESS
        ) {
            revert CallbackFailed();
        }

        uint256 balanceAfter = balances[token];
        require(
            balanceAfter >= balanceBefore,
            "Flash loan hasn't been paid back"
        );
        return true;
    }

    receive() external payable {}
}
