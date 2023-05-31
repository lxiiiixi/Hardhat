// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IFastPriceEvent {
    function emitPriceEvent(address _token, uint256 _price, uint256 emitPriceEvent) external;
}
