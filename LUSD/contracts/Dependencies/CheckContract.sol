// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

/** 检查 address 是已经部署且没有被销毁的合约 */
contract CheckContract {
    /**
     * Check that the account is an already deployed non-destroyed contract.
     * See: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol#L12
     */
    function checkContract(address _account) internal view {
        require(_account != address(0), "Account cannot be zero address");

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(_account)
        } // 使用内敛汇编获取合约代码大小（普通用户没有EVM代码）
        require(size > 0, "Account code size cannot be zero");
    }
}
