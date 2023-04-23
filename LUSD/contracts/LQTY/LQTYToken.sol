// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";
import "../Interfaces/ILQTYToken.sol";
import "../Interfaces/ILockupContractFactory.sol";
import "../Dependencies/console.sol";

/**
 * 这是 LQTY ERC20 合约。它的硬上限供应量为 1 亿，并且在第一年限制从 Liquity 管理地址（由项目公司 Liquity AG 控制的常规以太坊地址）进行的转账。
 * 请注意，Liquity 管理员地址没有额外的特权，并且在部署后不会保留对 Liquity 协议的任何控制权。
 *
 * --- 添加到LQTYToken的特定功能 ---
 * 1）转移保护：在外部transfer()和transferFrom()调用中，无效收件人（即核心Liquity合同）的黑名单。
 *    其目的是保护用户免受通过错误地直接发送LQTY到Liquity核心合同而丢失代币的风险，而应该调用正确的函数。
 * 2）sendToLQTYStaking()：仅由Liquity核心合同调用，将LQTY代币从用户 -> LQTYStaking合同移动。
 * 3）供应被强制上限为1亿枚代币。
 * 4）CommunityIssuance和LockupContractFactory地址在部署时设置。
 * 5）2百万代币的漏洞赏金/黑客松分配在部署时铸造到EOA。
 * 6）3200万代币在部署时铸造到CommunityIssuance合同。
 * 7）（1 + 1/3）百万代币的LP奖励分配在部署时铸造到Staking合同。
 * 8）（64 + 2/3）百万代币在部署时铸造到Liquity多签账户。
 * 9）自部署之日起一年内：
 *    -Liquity多签帐户仅可将代币转移给已通过LockupContractFactory部署并注册的LockupContracts。
 *    -当多签帐户调用approve（），increaseAllowance（），decreaseAllowance（）时，将抛出异常并撤销操作。
 *    -当多签帐户为发送方时，transferFrom（）将抛出异常。
 *    -当多签帐户为发送方时，sendToLQTYStaking（）将抛出异常，阻止多签帐户把其LQTY代币用于质押。
 * 在LQTYToken部署后一年后，多签操作的限制将被解除，多签账户将拥有与任何其他地址相同的权利。
 */

/*
* Based upon OpenZeppelin's ERC20 contract:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol
*  
* and their EIP2612 (ERC20Permit / ERC712) functionality:
* https://github.com/OpenZeppelin/openzeppelin-contracts/blob/53516bc555a454862470e7860a9b5254db4d00f5/contracts/token/ERC20/ERC20Permit.sol
* 
*
*  --- Functionality added specific to the LQTYToken ---
* 
* 1) Transfer protection: blacklist of addresses that are invalid recipients (i.e. core Liquity contracts) in external 
* transfer() and transferFrom() calls. The purpose is to protect users from losing tokens by mistakenly sending LQTY directly to a Liquity
* core contract, when they should rather call the right function.
*
* 2) sendToLQTYStaking(): callable only by Liquity core contracts, which move LQTY tokens from user -> LQTYStaking contract.
*
* 3) Supply hard-capped at 100 million
*
* 4) CommunityIssuance and LockupContractFactory addresses are set at deployment
*
* 5) The bug bounties / hackathons allocation of 2 million tokens is minted at deployment to an EOA

* 6) 32 million tokens are minted at deployment to the CommunityIssuance contract
*
* 7) The LP rewards allocation of (1 + 1/3) million tokens is minted at deployent to a Staking contract
*
* 8) (64 + 2/3) million tokens are minted at deployment to the Liquity multisig
*
* 9) Until one year from deployment:
* -Liquity multisig may only transfer() tokens to LockupContracts that have been deployed via & registered in the 
*  LockupContractFactory 
* -approve(), increaseAllowance(), decreaseAllowance() revert when called by the multisig
* -transferFrom() reverts when the multisig is the sender
* -sendToLQTYStaking() reverts when the multisig is the sender, blocking the multisig from staking its LQTY.
* 
* After one year has passed since deployment of the LQTYToken, the restrictions on multisig operations are lifted
* and the multisig has the same rights as any other address.
*/

contract LQTYToken is CheckContract, ILQTYToken {
    using SafeMath for uint256;

    // --- ERC20 Data ---

    string internal constant _NAME = "LQTY";
    string internal constant _SYMBOL = "LQTY";
    string internal constant _VERSION = "1";
    uint8 internal constant _DECIMALS = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint private _totalSupply;

    // --- EIP 2612 Data ---

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 private constant _PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _TYPE_HASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;

    mapping(address => uint256) private _nonces;

    // --- LQTYToken specific data ---

    uint public constant ONE_YEAR_IN_SECONDS = 31536000; // 60 * 60 * 24 * 365

    // uint for use with SafeMath
    uint internal _1_MILLION = 1e24; // 1e6 * 1e18 = 1e24

    uint internal immutable deploymentStartTime;
    address public immutable multisigAddress;

    address public immutable communityIssuanceAddress;
    address public immutable lqtyStakingAddress;

    uint internal immutable lpRewardsEntitlement;

    ILockupContractFactory public immutable lockupContractFactory;

    // --- Events ---

    event CommunityIssuanceAddressSet(address _communityIssuanceAddress);
    event LQTYStakingAddressSet(address _lqtyStakingAddress);
    event LockupContractFactoryAddressSet(
        address _lockupContractFactoryAddress
    );

    // --- Functions ---

    constructor(
        address _communityIssuanceAddress,
        address _lqtyStakingAddress,
        address _lockupFactoryAddress,
        address _bountyAddress,
        address _lpRewardsAddress, // uniPool
        address _multisigAddress
    ) public {
        checkContract(_communityIssuanceAddress);
        checkContract(_lqtyStakingAddress);
        checkContract(_lockupFactoryAddress);

        multisigAddress = _multisigAddress;
        deploymentStartTime = block.timestamp;

        communityIssuanceAddress = _communityIssuanceAddress;
        lqtyStakingAddress = _lqtyStakingAddress;
        lockupContractFactory = ILockupContractFactory(_lockupFactoryAddress);

        bytes32 hashedName = keccak256(bytes(_NAME));
        bytes32 hashedVersion = keccak256(bytes(_VERSION));

        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = _chainID();
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(
            _TYPE_HASH,
            hashedName,
            hashedVersion
        );

        // --- Initial LQTY allocations ---

        uint bountyEntitlement = _1_MILLION.mul(2); // Allocate 2 million for bounties/hackathons
        _mint(_bountyAddress, bountyEntitlement); // 作为 beneficiary 的奖励

        uint depositorsAndFrontEndsEntitlement = _1_MILLION.mul(32); // Allocate 32 million to the algorithmic issuance schedule
        _mint(_communityIssuanceAddress, depositorsAndFrontEndsEntitlement);

        uint _lpRewardsEntitlement = _1_MILLION.mul(4).div(3); // Allocate 1.33 million for LP rewards
        lpRewardsEntitlement = _lpRewardsEntitlement;
        _mint(_lpRewardsAddress, _lpRewardsEntitlement); // 这 1,333,333个LQTY 将在6周内将奖励给LUSD:ETH Uniswap池的流动性提供者

        // Allocate the remainder to the LQTY Multisig: (100 - 2 - 32 - 1.33) million = 64.66 million
        uint multisigEntitlement = _1_MILLION
            .mul(100)
            .sub(bountyEntitlement)
            .sub(depositorsAndFrontEndsEntitlement)
            .sub(_lpRewardsEntitlement);

        _mint(_multisigAddress, multisigEntitlement);
    }

    // --- External functions ---

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function getDeploymentStartTime() external view override returns (uint256) {
        return deploymentStartTime;
    }

    function getLpRewardsEntitlement()
        external
        view
        override
        returns (uint256)
    {
        return lpRewardsEntitlement;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        // Restrict the multisig's transfers in first year
        if (_callerIsMultisig() && _isFirstYear()) {
            _requireRecipientIsRegisteredLC(recipient);
        }

        _requireValidRecipient(recipient);

        // Otherwise, standard transfer functionality
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        if (_isFirstYear()) {
            _requireCallerIsNotMultisig();
        }

        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_isFirstYear()) {
            _requireSenderIsNotMultisig(sender);
        }

        _requireValidRecipient(recipient);

        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) external override returns (bool) {
        if (_isFirstYear()) {
            _requireCallerIsNotMultisig();
        }

        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external override returns (bool) {
        if (_isFirstYear()) {
            _requireCallerIsNotMultisig();
        }

        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function sendToLQTYStaking(
        address _sender,
        uint256 _amount
    ) external override {
        _requireCallerIsLQTYStaking();
        if (_isFirstYear()) {
            _requireSenderIsNotMultisig(_sender);
        } // Prevent the multisig from staking LQTY
        _transfer(_sender, lqtyStakingAddress, _amount);
    }

    // --- EIP 2612 functionality ---

    function domainSeparator() public view override returns (bytes32) {
        if (_chainID() == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return
                _buildDomainSeparator(
                    _TYPE_HASH,
                    _HASHED_NAME,
                    _HASHED_VERSION
                );
        }
    }

    function permit(
        address owner,
        address spender,
        uint amount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= now, "LQTY: expired deadline");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(
                    abi.encode(
                        _PERMIT_TYPEHASH,
                        owner,
                        spender,
                        amount,
                        _nonces[owner]++,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress == owner, "LQTY: invalid signature");
        _approve(owner, spender, amount);
    }

    function nonces(address owner) external view override returns (uint256) {
        // FOR EIP 2612
        return _nonces[owner];
    }

    // --- Internal operations ---

    function _chainID() private pure returns (uint256 chainID) {
        assembly {
            chainID := chainid()
        }
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 name,
        bytes32 version
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(typeHash, name, version, _chainID(), address(this))
            );
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(
            amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // --- Helper functions ---

    function _callerIsMultisig() internal view returns (bool) {
        return (msg.sender == multisigAddress);
    }

    function _isFirstYear() internal view returns (bool) {
        return (block.timestamp.sub(deploymentStartTime) < ONE_YEAR_IN_SECONDS);
    }

    // --- 'require' functions ---

    function _requireValidRecipient(address _recipient) internal view {
        require(
            _recipient != address(0) && _recipient != address(this),
            "LQTY: Cannot transfer tokens directly to the LQTY token contract or the zero address"
        );
        require(
            _recipient != communityIssuanceAddress &&
                _recipient != lqtyStakingAddress,
            "LQTY: Cannot transfer tokens directly to the community issuance or staking contract"
        );
    }

    function _requireRecipientIsRegisteredLC(address _recipient) internal view {
        require(
            lockupContractFactory.isRegisteredLockup(_recipient),
            "LQTYToken: recipient must be a LockupContract registered in the Factory"
        );
    }

    function _requireSenderIsNotMultisig(address _sender) internal view {
        require(
            _sender != multisigAddress,
            "LQTYToken: sender must not be the multisig"
        );
    }

    function _requireCallerIsNotMultisig() internal view {
        require(
            !_callerIsMultisig(),
            "LQTYToken: caller must not be the multisig"
        );
    }

    function _requireCallerIsLQTYStaking() internal view {
        require(
            msg.sender == lqtyStakingAddress,
            "LQTYToken: caller must be the LQTYStaking contract"
        );
    }

    // --- Optional functions ---

    function name() external view override returns (string memory) {
        return _NAME;
    }

    function symbol() external view override returns (string memory) {
        return _SYMBOL;
    }

    function decimals() external view override returns (uint8) {
        return _DECIMALS;
    }

    function version() external view override returns (string memory) {
        return _VERSION;
    }

    function permitTypeHash() external view override returns (bytes32) {
        return _PERMIT_TYPEHASH;
    }
}
