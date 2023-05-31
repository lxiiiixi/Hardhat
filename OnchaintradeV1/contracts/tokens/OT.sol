// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract OT is ERC20, Ownable {

    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        // initial balance
        _mint(msg.sender, 1e26);
    }

}