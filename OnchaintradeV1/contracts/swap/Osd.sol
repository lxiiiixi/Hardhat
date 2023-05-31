// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Osd is ERC20("OSD", "OSD"), Ownable {
    mapping(address => bool) public minters;

    function mint(address to, uint256 amount) external {
        require(minters[msg.sender], "UNAUTHORIZED_MINTER");
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external {
        require(minters[msg.sender], "UNAUTHORIZED_MINTER");
        _burn(account, amount);
    }

    function setMinter(address account, bool approved) external onlyOwner {
        minters[account] = approved;
    }
}
