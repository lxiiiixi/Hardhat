// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockMigrator {
    address public owner;
    address public chef;
    IERC20 public token;
    IERC20 public newToken;

    constructor(address _chef, IERC20 _token, IERC20 _newToken) public {
        owner = msg.sender;
        chef = _chef;
        token = _token;
        newToken = _newToken;
    }

    function migrate(IERC20 _token) external returns (IERC20) {
        require(msg.sender == chef, "not from master chef");
        require(_token == token, "not from target token");
        uint bal = token.balanceOf(address(chef));
        token.transferFrom(chef, owner, bal);
        return newToken;
    }
}
