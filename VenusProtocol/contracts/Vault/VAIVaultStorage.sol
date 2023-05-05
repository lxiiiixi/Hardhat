pragma solidity ^0.5.16;
import "../Utils/SafeMath.sol";
import "../Utils/IBEP20.sol";

// 代理合约和实现合约都第一个继承了VAIVaultAdminStorage，因此它们 最前面的四个插槽是一样的，不会形成插槽冲突
// 这样设计的目的是除了管理员和实现合约更新是在代理合约中进行，其它所有操作全在实现合约中进行。

contract VAIVaultAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of VAI Vault
     */
    address public vaiVaultImplementation;

    /**
     * @notice Pending brains of VAI Vault
     */
    address public pendingVAIVaultImplementation;
}

contract VAIVaultStorage is VAIVaultAdminStorage {
    /// @notice The XVS TOKEN!
    IBEP20 public xvs;

    /// @notice The VAI TOKEN!
    IBEP20 public vai;

    /// @notice Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice XVS balance of vault
    uint256 public xvsBalance;

    /// @notice Accumulated XVS per share
    // 这个变量是根据总的 pendingRewards 计算得来的
    uint256 public accXVSPerShare;

    //// pending rewards awaiting anyone to update
    uint256 public pendingRewards;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each user that stakes tokens.
    mapping(address => UserInfo) public userInfo;

    /// @notice pause indicator for Vault
    bool public vaultPaused;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
