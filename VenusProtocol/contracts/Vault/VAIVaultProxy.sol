pragma solidity ^0.5.16;

import "./VAIVaultStorage.sol";
import "./VAIVaultErrorReporter.sol";

// 用于管理 VARVault 的升级和管理员权限的代理合约，允许管理员设置新的实现合约地址和新的管理员地址，然后相应的实现和管理员可以接受这些变更。

contract VAIVaultProxy is VAIVaultAdminStorage, VAIVaultErrorReporter {
    /**
     * @notice Emitted when pendingVAIVaultImplementation is changed
     */
    event NewPendingImplementation(
        address oldPendingImplementation,
        address newPendingImplementation
    );

    /**
     * @notice Emitted when pendingVAIVaultImplementation is accepted, which means VAI Vault implementation is updated
     */
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );

    /**
     * @notice Emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    constructor() public {
        // Set admin to caller
        admin = msg.sender;
    }

    /*** Admin Functions ***/
    // 设置新的实现合约地址
    function _setPendingImplementation(
        address newPendingImplementation
    ) public returns (uint) {
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PENDING_IMPLEMENTATION_OWNER_CHECK
                );
        }

        address oldPendingImplementation = pendingVAIVaultImplementation;

        pendingVAIVaultImplementation = newPendingImplementation;

        emit NewPendingImplementation(
            oldPendingImplementation,
            pendingVAIVaultImplementation
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Accepts new implementation of VAI Vault. msg.sender must be pendingImplementation
     * @dev Admin function for new implementation to accept it's role as implementation
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     *
     * pendingVAIVaultImplementation 接受新的作为实现合约的角色
     * 1. 检查调用者是 pendingImplementation
     * 2. 保存当前值，用于日志
     */
    function _acceptImplementation() public returns (uint) {
        // Check caller is pendingImplementation
        if (msg.sender != pendingVAIVaultImplementation) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.ACCEPT_PENDING_IMPLEMENTATION_ADDRESS_CHECK
                );
        }

        // Save current values for inclusion in log
        address oldImplementation = vaiVaultImplementation;
        address oldPendingImplementation = pendingVAIVaultImplementation;

        vaiVaultImplementation = pendingVAIVaultImplementation;

        pendingVAIVaultImplementation = address(0);

        emit NewImplementation(oldImplementation, vaiVaultImplementation);
        emit NewPendingImplementation(
            oldPendingImplementation,
            pendingVAIVaultImplementation
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPendingAdmin(address newPendingAdmin) public returns (uint) {
        // Check caller = admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PENDING_ADMIN_OWNER_CHECK
                );
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _acceptAdmin() public returns (uint) {
        // Check caller is pendingAdmin
        if (msg.sender != pendingAdmin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.ACCEPT_ADMIN_PENDING_ADMIN_CHECK
                );
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     * 代理执行一个实现合约，无论实现合约返回或者revert，它都会返回外部调用者。
     *
     * 作用：将所有其他函数的执行委托给当前的实现合约，当合约需要升级时，只需要将实现合约的地址改为新的实现合约地址即可。
     */
    function() external payable {
        // delegate all other functions to current implementation
        (bool success, ) = vaiVaultImplementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize)

            switch success
            case 0 {
                revert(free_mem_ptr, returndatasize)
            }
            default {
                return(free_mem_ptr, returndatasize)
            }
        }
    }
}

/**
 * VRTVault.sol 存在问题：
 * 1、 用户质押和利息均为 vrt,需要使用一个变量记录所有用户所有的质押总和，
 * 当提取利息时，剩下余额必须大于质押总和，否则利息计算或者设置错误时，用户的本金可被他人以利息的方式提走，
 * 遭受损失。
 * 2、 如果按照上面改动缺少紧急提币功能，当利息不足时，用户无法提取本金。建议增加一个紧急提币功能，
 *
 * withdrawBep20 函数提取多余代码币，未排除vrt代币本身，这样就可以提取所有用户的质押本金
 */
