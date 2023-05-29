// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";

contract Lock {
    uint256 public unlockTime;
    address payable public owner; // owner 地址（可以接受eth）

    event Withdrawal(uint256 amount, uint256 when); // 撤回事件

    constructor(uint256 _unlockTime) payable {
        require(
            block.timestamp < _unlockTime,
            "Unlock time should be in the future"
        );

        unlockTime = _unlockTime;
        owner = payable(msg.sender); // 将当前交易的发送方（msg.sender）作为可支付（payable）地址的所有者（owner）
        // 确保该地址可以接收以太币或代币，并且只有该发送方可以访问和管理该地址。
    }

    function withdraw() public {
        console.log(
            "Unlock time is %o and block timestamp is %o",
            unlockTime,
            block.timestamp
        );

        // 保证撤回需要是owner操作 且达到了资金撤回的时间
        require(block.timestamp >= unlockTime, "You can't withdraw yet");
        require(msg.sender == owner, "You aren't the owner");

        // address(this)代表当前智能合约的地址
        emit Withdrawal(address(this).balance, block.timestamp);
        // 合约向owner的地址转帐合约所有的balance
        owner.transfer(address(this).balance);
    }

    function testConsole() public view returns (bool) {
        console.log("Caller is '%s'", msg.sender);
        console.log("Caller is '%d'", msg.sender);
        console.log("Caller is ", msg.sender);
        console.log("Number is '%s'", 0xff);
        console.log("Number is '%d'", 0xff);
        console.logBytes1(bytes1(0xff));
        console.logBytes(abi.encode(msg.sender));
        console.log("Reslut is ", true);
        return true;
    }
}
