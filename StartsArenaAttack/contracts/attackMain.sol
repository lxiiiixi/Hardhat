// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "./attack.sol";

contract AttackerMain {
    Attacker public attackContract;

    constructor(address _target, address payable _recipient) payable {
        attackContract = new Attacker(_target, _recipient);
        attackContract.attack{value: msg.value}();
    }
}
