pragma solidity 0.5.16;

interface IAccessControlManagerV5 {
    event RoleAdminChanged(
        bytes32 indexed role,
        bytes32 indexed previousAdminRole,
        bytes32 indexed newAdminRole
    );
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );

    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function renounceRole(bytes32 role, address account) external;

    function giveCallPermission(
        address contractAddress,
        string calldata functionSig,
        address accountToPermit
    ) external;

    function revokeCallPermission(
        address contractAddress,
        string calldata functionSig,
        address accountToRevoke
    ) external;

    function isAllowedToCall(
        address account,
        string calldata functionSig
    ) external view returns (bool);

    function hasPermission(
        address account,
        address contractAddress,
        string calldata functionSig
    ) external view returns (bool);
}

pragma solidity 0.5.16;

contract AccessControlledV5 {
    IAccessControlManagerV5 private _accessControlManager;
    uint256[49] private __gap;

    event NewAccessControlManager(
        address oldAccessControlManager,
        address newAccessControlManager
    );

    function accessControlManager()
        external
        view
        returns (IAccessControlManagerV5)
    {
        return _accessControlManager;
    }

    function _setAccessControlManager(address accessControlManager_) internal {
        require(
            address(accessControlManager_) != address(0),
            "invalid acess control manager address"
        );
        address oldAccessControlManager = address(_accessControlManager);
        _accessControlManager = IAccessControlManagerV5(accessControlManager_);
        emit NewAccessControlManager(
            oldAccessControlManager,
            accessControlManager_
        );
    }

    function _checkAccessAllowed(string memory signature) internal view {
        bool isAllowedToCall = _accessControlManager.isAllowedToCall(
            msg.sender,
            signature
        );

        if (!isAllowedToCall) {
            revert("Unauthorized");
        }
    }
}

pragma solidity ^0.5.5;

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

        assembly {
            codehash := extcodehash(account)
        }
        return (codehash != accountHash && codehash != 0x0);
    }

    function toPayable(
        address account
    ) internal pure returns (address payable) {
        return address(uint160(account));
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        (bool success, ) = recipient.call.value(amount)("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }
}

pragma solidity ^0.5.0;

interface IBEP20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

pragma solidity ^0.5.16;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return add(a, b, "SafeMath: addition overflow");
    }

    function add(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, errorMessage);

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

pragma solidity ^0.5.0;

library SafeBEP20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IBEP20 token, address to, uint256 value) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IBEP20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeBEP20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(
            value
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            "SafeBEP20: decreased allowance below zero"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function callOptionalReturn(IBEP20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeBEP20: call to non-contract");

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeBEP20: low-level call failed");

        if (returndata.length > 0) {
            require(
                abi.decode(returndata, (bool)),
                "SafeBEP20: BEP20 operation did not succeed"
            );
        }
    }
}

pragma solidity ^0.5.16;

contract VAIVaultErrorReporter {
    enum Error {
        NO_ERROR,
        UNAUTHORIZED
    }

    enum FailureInfo {
        ACCEPT_ADMIN_PENDING_ADMIN_CHECK,
        ACCEPT_PENDING_IMPLEMENTATION_ADDRESS_CHECK,
        SET_PENDING_ADMIN_OWNER_CHECK,
        SET_PENDING_IMPLEMENTATION_OWNER_CHECK
    }

    event Failure(uint error, uint info, uint detail);

    function fail(Error err, FailureInfo info) internal returns (uint) {
        emit Failure(uint(err), uint(info), 0);

        return uint(err);
    }

    function failOpaque(
        Error err,
        FailureInfo info,
        uint opaqueError
    ) internal returns (uint) {
        emit Failure(uint(err), uint(info), opaqueError);

        return uint(err);
    }
}

pragma solidity ^0.5.16;

contract VAIVaultAdminStorage {
    address public admin;

    address public pendingAdmin;

    address public vaiVaultImplementation;

    address public pendingVAIVaultImplementation;
}

contract VAIVaultStorage is VAIVaultAdminStorage {
    IBEP20 public xvs;

    IBEP20 public vai;

    bool internal _notEntered;

    uint256 public xvsBalance;

    uint256 public accXVSPerShare;

    uint256 public pendingRewards;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public userInfo;

    bool public vaultPaused;

    uint256[49] private __gap;
}

pragma solidity 0.5.16;

interface IVAIVaultProxy {
    function _acceptImplementation() external returns (uint);

    function admin() external returns (address);
}

contract VAIVault is VAIVaultStorage, AccessControlledV5 {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    event Deposit(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 amount);

    event AdminTransfered(address indexed oldAdmin, address indexed newAdmin);

    event VaultPaused(address indexed admin);

    event VaultResumed(address indexed admin);

    constructor() public {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can");
        _;
    }

    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true;
    }

    modifier isActive() {
        require(vaultPaused == false, "Vault is paused");
        _;
    }

    function pause() external {
        _checkAccessAllowed("pause()");
        require(!vaultPaused, "Vault is already paused");
        vaultPaused = true;
        emit VaultPaused(msg.sender);
    }

    function resume() external {
        _checkAccessAllowed("resume()");
        require(vaultPaused, "Vault is not paused");
        vaultPaused = false;
        emit VaultResumed(msg.sender);
    }

    function deposit(uint256 _amount) external nonReentrant isActive {
        UserInfo storage user = userInfo[msg.sender];

        updateVault();

        updateAndPayOutPending(msg.sender);

        if (_amount > 0) {
            vai.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(accXVSPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant isActive {
        _withdraw(msg.sender, _amount);
    }

    function claim() external nonReentrant isActive {
        _withdraw(msg.sender, 0);
    }

    function claim(address account) external nonReentrant isActive {
        _withdraw(account, 0);
    }

    function _withdraw(address account, uint256 _amount) internal {
        UserInfo storage user = userInfo[account];
        require(user.amount >= _amount, "withdraw: not good");

        updateVault();
        updateAndPayOutPending(account);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            vai.safeTransfer(address(account), _amount);
        }
        user.rewardDebt = user.amount.mul(accXVSPerShare).div(1e18);

        emit Withdraw(account, _amount);
    }

    function pendingXVS(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        return user.amount.mul(accXVSPerShare).div(1e18).sub(user.rewardDebt);
    }

    function updateAndPayOutPending(address account) internal {
        uint256 pending = pendingXVS(account);

        if (pending > 0) {
            safeXVSTransfer(account, pending);
        }
    }

    function safeXVSTransfer(address _to, uint256 _amount) internal {
        uint256 xvsBal = xvs.balanceOf(address(this));

        if (_amount > xvsBal) {
            xvs.transfer(_to, xvsBal);
            xvsBalance = xvs.balanceOf(address(this));
        } else {
            xvs.transfer(_to, _amount);
            xvsBalance = xvs.balanceOf(address(this));
        }
    }

    function updatePendingRewards() external isActive {
        uint256 newRewards = xvs.balanceOf(address(this)).sub(xvsBalance);

        if (newRewards > 0) {
            xvsBalance = xvs.balanceOf(address(this));
            pendingRewards = pendingRewards.add(newRewards);
        }
    }

    function updateVault() internal {
        uint256 vaiBalance = vai.balanceOf(address(this));
        if (vaiBalance == 0) {
            return;
        }

        accXVSPerShare = accXVSPerShare.add(
            pendingRewards.mul(1e18).div(vaiBalance)
        );
        pendingRewards = 0;
    }

    function getAdmin() external view returns (address) {
        return admin;
    }

    function burnAdmin() external onlyAdmin {
        emit AdminTransfered(admin, address(0));
        admin = address(0);
    }

    function setNewAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "new owner is the zero address");
        emit AdminTransfered(admin, newAdmin);
        admin = newAdmin;
    }

    function _become(IVAIVaultProxy vaiVaultProxy) external {
        require(
            msg.sender == vaiVaultProxy.admin(),
            "only proxy admin can change brains"
        );
        require(
            vaiVaultProxy._acceptImplementation() == 0,
            "change not authorized"
        );
    }

    function setVenusInfo(address _xvs, address _vai) external onlyAdmin {
        require(
            _xvs != address(0) && _vai != address(0),
            "addresses must not be zero"
        );
        xvs = IBEP20(_xvs);
        vai = IBEP20(_vai);

        _notEntered = true;
    }

    function setAccessControl(
        address newAccessControlAddress
    ) external onlyAdmin {
        _setAccessControlManager(newAccessControlAddress);
    }
}
