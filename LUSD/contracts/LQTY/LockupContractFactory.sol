// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Interfaces/ILockupContractFactory.sol";
import "./LockupContract.sol";
import "../Dependencies/console.sol";

/**
 * LockupContractFactory 用于在第一年部署 LockupContracts。
 * 在第一年，LQTYToken 会检查从 Liquity 管理地址到有效 LockupContract 的任何转账，该 LockupContract 在 LockupContractFactory 中注册并通过 LockupContractFactory 部署。
 * 其主要目的是保持有效部署的LockupContracts的注册表。
 *
 * 当Liquity部署者尝试转移LQTY代币时，此注册表将由LQTYToken进行检查。
 * 在系统部署后的第一年中，Liquity部署者只允许将LQTY转移到已由LockupContractFactory部署和记录的有效LockupContracts。
 * 这确保了部署者的LQTY在第一年内无法交易或质押，只能发送到已验证的LockupContract，在系统部署后至少一年后解锁。
 * 当然，LockupContracts可以直接部署，但只有通过LockupContractFactory部署和记录的合同才会被LQTYToken视为“有效”。
 * 这是一种验证目标地址是否是真正的LockupContract方便的方法。
 */

/*
 * The LockupContractFactory deploys LockupContracts - its main purpose is to keep a registry of valid deployed
 * LockupContracts.
 *
 * This registry is checked by LQTYToken when the Liquity deployer attempts to transfer LQTY tokens. During the first year
 * since system deployment, the Liquity deployer is only allowed to transfer LQTY to valid LockupContracts that have been
 * deployed by and recorded in the LockupContractFactory. This ensures the deployer's LQTY can't be traded or staked in the
 * first year, and can only be sent to a verified LockupContract which unlocks at least one year after system deployment.
 *
 * LockupContracts can of course be deployed directly, but only those deployed through and recorded in the LockupContractFactory
 * will be considered "valid" by LQTYToken. This is a convenient way to verify that the target address is a genuine
 * LockupContract.
 */

contract LockupContractFactory is
    ILockupContractFactory,
    Ownable,
    CheckContract
{
    using SafeMath for uint;

    // --- Data ---
    string public constant NAME = "LockupContractFactory";

    uint public constant SECONDS_IN_ONE_YEAR = 31536000;

    address public lqtyTokenAddress;

    mapping(address => address) public lockupContractToDeployer;

    // --- Events ---

    event LQTYTokenAddressSet(address _lqtyTokenAddress);
    event LockupContractDeployedThroughFactory(
        address _lockupContractAddress,
        address _beneficiary,
        uint _unlockTime,
        address _deployer
    );

    // --- Functions ---

    function setLQTYTokenAddress(
        address _lqtyTokenAddress
    ) external override onlyOwner {
        checkContract(_lqtyTokenAddress);

        lqtyTokenAddress = _lqtyTokenAddress;
        emit LQTYTokenAddressSet(_lqtyTokenAddress);

        _renounceOwnership();
    }

    function deployLockupContract(
        address _beneficiary,
        uint _unlockTime
    ) external override {
        address lqtyTokenAddressCached = lqtyTokenAddress;
        _requireLQTYAddressIsSet(lqtyTokenAddressCached);
        LockupContract lockupContract = new LockupContract(
            lqtyTokenAddressCached,
            _beneficiary,
            _unlockTime
        );

        lockupContractToDeployer[address(lockupContract)] = msg.sender;
        emit LockupContractDeployedThroughFactory(
            address(lockupContract),
            _beneficiary,
            _unlockTime,
            msg.sender
        );
    }

    function isRegisteredLockup(
        address _contractAddress
    ) public view override returns (bool) {
        return lockupContractToDeployer[_contractAddress] != address(0);
    }

    // --- 'require'  functions ---
    function _requireLQTYAddressIsSet(address _lqtyTokenAddress) internal pure {
        require(
            _lqtyTokenAddress != address(0),
            "LCF: LQTY Address is not set"
        );
    }
}
