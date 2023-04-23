// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/SafeMath.sol";
import "../Interfaces/ILQTYToken.sol";

/**
锁定合约架构采用单一的LockupContract，其中包括一个unlockTime。
unlockTime作为参数传递给LockupContract的构造函数。
当区块时间戳大于unlockTime时，受益人可以提取合约的余额。
在构造时，合约会检查unlockTime是否至少晚于Liquity系统的部署时间一年。

在部署的第一年内，LQTYToken的部署者（即Liquity AG的地址）只能将LQTY转移到有效的LockupContracts，而不能转移到其他地址（这在LQTYToken.sol的transfer()函数中得到执行）。
上述两个限制条件确保在系统部署后一年内，来自Liquity AG的LQTY代币不能进入流通供应，并且不能被抵押以赚取系统收入。
 */

/*
* The lockup contract architecture utilizes a single LockupContract, with an unlockTime. The unlockTime is passed as an argument 
* to the LockupContract's constructor. The contract's balance can be withdrawn by the beneficiary when block.timestamp > unlockTime. 
* At construction, the contract checks that unlockTime is at least one year later than the Liquity system's deployment time. 

* Within the first year from deployment, the deployer of the LQTYToken (Liquity AG's address) may transfer LQTY only to valid 
* LockupContracts, and no other addresses (this is enforced in LQTYToken.sol's transfer() function).
* 
* The above two restrictions ensure that until one year after system deployment, LQTY tokens originating from Liquity AG cannot 
* enter circulating supply and cannot be staked to earn system revenue.
*/
contract LockupContract {
    using SafeMath for uint;

    // --- Data ---
    string public constant NAME = "LockupContract";

    uint public constant SECONDS_IN_ONE_YEAR = 31536000;

    address public immutable beneficiary;

    ILQTYToken public lqtyToken;

    // Unlock time is the Unix point in time at which the beneficiary can withdraw.
    uint public unlockTime; // 指受益人可以提取资金的Unix时间戳。

    // --- Events ---

    event LockupContractCreated(address _beneficiary, uint _unlockTime);
    event LockupContractEmptied(uint _LQTYwithdrawal);

    // --- Functions ---

    constructor(
        address _lqtyTokenAddress,
        address _beneficiary,
        uint _unlockTime
    ) public {
        lqtyToken = ILQTYToken(_lqtyTokenAddress);

        /*
         * Set the unlock time to a chosen instant in the future, as long as it is at least 1 year after
         * the system was deployed
         */
        _requireUnlockTimeIsAtLeastOneYearAfterSystemDeployment(_unlockTime);
        unlockTime = _unlockTime;

        beneficiary = _beneficiary;
        emit LockupContractCreated(_beneficiary, _unlockTime);
    }

    function withdrawLQTY() external {
        _requireCallerIsBeneficiary();
        _requireLockupDurationHasPassed();

        ILQTYToken lqtyTokenCached = lqtyToken;
        uint LQTYBalance = lqtyTokenCached.balanceOf(address(this));
        lqtyTokenCached.transfer(beneficiary, LQTYBalance);
        emit LockupContractEmptied(LQTYBalance);
    }

    // --- 'require' functions ---

    function _requireCallerIsBeneficiary() internal view {
        require(
            msg.sender == beneficiary,
            "LockupContract: caller is not the beneficiary"
        );
    }

    function _requireLockupDurationHasPassed() internal view {
        require(
            block.timestamp >= unlockTime,
            "LockupContract: The lockup duration must have passed"
        );
    }

    function _requireUnlockTimeIsAtLeastOneYearAfterSystemDeployment(
        uint _unlockTime
    ) internal view {
        uint systemDeploymentTime = lqtyToken.getDeploymentStartTime();
        require(
            _unlockTime >= systemDeploymentTime.add(SECONDS_IN_ONE_YEAR),
            "LockupContract: unlock time must be at least one year after system deployment"
        );
    }
}
