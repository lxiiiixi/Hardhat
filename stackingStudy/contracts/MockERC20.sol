// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "hardhat/console.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) public ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

// contract MockERC777 is ERC777 {
//     constructor(
//         string memory name,
//         string memory symbol,
//         uint256 initialSupply,
//         address[] memory defaultOperators_
//     ) public ERC777(name, symbol, defaultOperators_) {
//         _mint(msg.sender, initialSupply, new bytes(0), new bytes(0));
//     }
// }
