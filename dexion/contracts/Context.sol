// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data; // 返回当前调用的完整数据
        // 在以太坊中，当你想要调用一个合约中的函数时，你需要提供函数的名称和参数。这些信息会被编码为字节码，并作为 msg.data 发送到合约中。
        // 为了在调试或测试时查看传递给函数的完整参数列表
    }
}

// 在 Solidity 0.5.0 版本及以后，当使用 view 或 pure 修饰符时，函数不能修改合约的状态，否则编译器会发出一个警告。然而，在这个函数中我们并没有使用任何语句来修改合约的状态，这是因为该函数的唯一目的是为了获取函数调用的完整数据。因此，编译器无法确定该函数是否会修改合约的状态，因此会发出警告。
// 为了避免这个警告，我们使用了 this; 语句。这个语句实际上是执行一个空操作，不会修改任何状态，但是它会使编译器认为函数有一个有效的状态更改，从而消除了警告。
