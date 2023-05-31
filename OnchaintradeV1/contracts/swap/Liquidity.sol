// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface PropertyERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);
}

contract Liquidity is ERC20, Ownable {
    address public token;
    uint8 private _decimals;

    constructor(address _token)
        ERC20(lpName(PropertyERC20(_token).symbol()), lpSymbol(PropertyERC20(_token).symbol()))
    {
        token = _token;
        _decimals = PropertyERC20(token).decimals();
    }

    function lpName(string memory symbol) internal pure returns (string memory) {
        return string.concat("OT ", symbol, " LP");
    }

    function lpSymbol(string memory symbol) internal pure returns (string memory) {
        return string.concat(symbol, " LP");
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public onlyOwner {
        _burn(to, amount);
    }
}
