// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MdxTokenOld is ERC20Votes, Ownable {
    uint256 public constant maxSupply = 1000000000 * 1e18; // the total supply

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _miners;

    constructor() ERC20("MDX Token", "MDX") ERC20Permit("MDX Token") {}

    modifier onlyMiner() {
        require(isMiner(msg.sender), "caller is not the miner");
        _;
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyMiner returns (bool) {
        if (totalSupply() + amount > maxSupply) {
            return false;
        }
        _mint(to, amount);
        return true;
    }

    function addMiner(address miner) external onlyOwner returns (bool) {
        require(miner != address(0), "MdxToken: miner is the zero address");
        return EnumerableSet.add(_miners, miner);
    }

    function delMiner(address miner) external onlyOwner returns (bool) {
        require(miner != address(0), "MdxToken: miner is the zero address");
        return EnumerableSet.remove(_miners, miner);
    }

    function getMinerLength() public view returns (uint256) {
        return EnumerableSet.length(_miners);
    }

    function isMiner(address account) public view returns (bool) {
        return EnumerableSet.contains(_miners, account);
    }

    function getMiner(
        uint256 _index
    ) external view onlyOwner returns (address) {
        require(
            _index <= getMinerLength() - 1,
            "MdxToken: index out of bounds"
        );
        return EnumerableSet.at(_miners, _index);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(
        address account,
        uint256 amount
    ) internal override(ERC20Votes) {
        super._burn(account, amount);
    }
}
