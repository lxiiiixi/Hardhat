// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface PropertyERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);
}

/**
 * 这个合约的功能主要是实现一个流动性池的代币用于在 Defi 平台中提供流动性。
 * 合约继承了 ERC20 代币标准，可以被其他合约或者用户进行交易和转移，同时也继承了 Ownable 合约，可以控制代币的发行和销毁。
 * 流动性代币的作用：
 *      当用户在 DEX 中进行交易时，他们将需要匹配卖方和买方之间的订单，这需要某种形式的流动性来实现。
 *      流动性代币的作用就是为 DEX 提供流动性，使交易能够顺利进行。
 */

contract Liquidity is ERC20, Ownable {
    address public token;
    uint8 private _decimals;

    constructor(
        address _token
    )
        ERC20(
            lpName(PropertyERC20(_token).symbol()),
            lpSymbol(PropertyERC20(_token).symbol())
        )
    {
        token = _token;
        _decimals = PropertyERC20(token).decimals();
    }

    function lpName(
        string memory symbol
    ) internal pure returns (string memory) {
        return string.concat("OT ", symbol, " LP");
    }

    function lpSymbol(
        string memory symbol
    ) internal pure returns (string memory) {
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
