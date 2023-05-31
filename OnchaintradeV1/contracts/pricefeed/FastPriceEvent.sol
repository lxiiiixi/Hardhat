// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/IFastPriceEvent.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FastPriceEvent is IFastPriceEvent, Ownable {
    mapping(address => bool) public isPriceFeed;
    event PriceUpdate(address token, uint256 price, uint256 _timestamp, address priceFeed);

    function setIsPriceFeed(address _priceFeed, bool _isPriceFeed) external onlyOwner {
        isPriceFeed[_priceFeed] = _isPriceFeed;
    }

    function emitPriceEvent(address _token, uint256 _price, uint256 _timestamp) external override {
        require(isPriceFeed[msg.sender], "invalid_sender");
        emit PriceUpdate(_token, _price, _timestamp, msg.sender);
    }
}
