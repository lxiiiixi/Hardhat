// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

/**
持有 LUSD 清算准备金总额。 
LUSD 在打开 Trove 时移入 GasPool，并在清算或关闭 Trove 时移出。
 */

/**
 * The purpose of this contract is to hold LUSD tokens for gas compensation:
 * https://github.com/liquity/dev#gas-compensation
 * When a borrower opens a trove, an additional 50 LUSD debt is issued,
 * and 50 LUSD is minted and sent to this contract.
 * When a borrower closes their active trove, this gas compensation is refunded:
 * 50 LUSD is burned from the this contract's balance, and the corresponding
 * 50 LUSD debt on the trove is cancelled.
 * See this issue for more context: https://github.com/liquity/dev/issues/186
 *
 * 这个合约的目的是持有LUSD代币以进行gas补偿：
 * 当借款人打开Trove时（需要支付一定的 gas 费用），为了减轻借款人的负担，Liquity 协议会向 GasPool 智能合约中存入一定数量的 LUSD 代币，作为 gas 补偿。
 * 当借款人关闭其活跃的Trove时，将退还此燃气补偿：50 LUSD从该合约的余额中销毁，并取消 Trove上相应的50 LUSD债务。
 */
contract GasPool {
    // do nothing, as the core contracts have permission to send to and burn from this address
}
