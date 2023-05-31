// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FutureTradeFeeCapture {
    // in swap: IERC20(reserveToken).safeTransferFrom(from, swapPool, amount)
    using SafeERC20 for IERC20;
    address public feeTo;

    constructor(address _feeTo) {
        feeTo = _feeTo;
    }

    function settleFutureProfit(
        address reserveToken,
        uint256 amount,
        address from
    ) external {
        IERC20(reserveToken).safeTransferFrom(from, feeTo, amount);
    }
}
