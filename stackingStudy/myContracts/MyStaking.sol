// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./RewardToken.sol";

contract Staking is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // LPtoken amount deposited by the user
        uint256 rewardDebt; // A record of user reward debt
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint accRewardPerLptoken; // The number of reward that can be obtained for a lp token
    }

    RewardToken public rewardToken;
    uint256 public rewardPerBlock;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // poolId => user address => user info
    mapping(IERC20 => bool) public existingLpTokenPool; // token address => bool - Record the existing pool with one tolen
    uint256 public totalAllocPoint = 0; // Total allocation poitns (The sum of all allocation points)

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    function ifLpTokenExist(IERC20 _lpToken) public view returns (bool) {
        return existingLpTokenPool[_lpToken];
    }

    function addPool(uint256 _allocPoint, IERC20 _lpToken) public onlyOwner {
        // update pool
        massUpdatePools();
        // Don't allow to add the same Lptoken more than once.
        require(
            !ifLpTokenExist(_lpToken),
            "A pool which deposit this token have already exsited"
        );
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        existingLpTokenPool[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerLptoken: 0
            })
        );
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.lastRewardBlock > 0, "Pool exists?");
        updatePool(_pid); // 1. update pool
        // 2. transfer former reward to user first
        if (user.amount > 0) {
            uint256 pendingReward = user
                .amount
                .mul(pool.accRewardPerLptoken)
                .div(1e12)
                .sub(user.rewardDebt);
            safeRewardTransfer(msg.sender, pendingReward);
        }
        // 3. user deposit (contract should have enough lpToken allowance of the user)
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        // 4. update user info
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerLptoken).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withDraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "You have nothing to withdraw");
        updatePool(_pid);
        uint256 pendingReward = user
            .amount
            .mul(pool.accRewardPerLptoken)
            .div(1e12)
            .sub(user.rewardDebt);
        safeRewardTransfer(msg.sender, pendingReward);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerLptoken).div(1e12);
        user.amount = user.amount.sub(_amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claim(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pendingReward = user
            .amount
            .mul(pool.accRewardPerLptoken)
            .div(1e12)
            .sub(user.rewardDebt);
        if (pendingReward > 0) {
            safeRewardTransfer(msg.sender, pendingReward);
            user.rewardDebt = user.amount.mul(pool.accRewardPerLptoken).div(
                1e12
            );
            emit Claim(msg.sender, _pid, pendingReward);
        }
    }

    function getPendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 accRewardPerLptoken = pool.accRewardPerLptoken;
        uint256 lpTotalAmount = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpTotalAmount != 0) {
            uint256 blockGap = block.number - pool.lastRewardBlock;
            uint256 rewardAmount = blockGap
                .mul(rewardPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            uint256 newAccRewardPerLptoken = rewardAmount.mul(1e12).div(
                lpTotalAmount
            );
            accRewardPerLptoken = accRewardPerLptoken.add(
                newAccRewardPerLptoken
            );
        }
        return
            user.amount.mul(accRewardPerLptoken).div(1e12).sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint256 poolLength = poolInfo.length;
        for (uint256 pid = 0; pid < poolLength; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        // ensure valid pool
        require(pool.lastRewardBlock > 0, "Pool exists?");
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpTotalAmount = pool.lpToken.balanceOf(address(this));
        if (lpTotalAmount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockGap = block.number - pool.lastRewardBlock;
        // The reward amount between now and the block last updated which this pool should be allocated
        uint256 rewardAmount = blockGap
            .mul(rewardPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        uint256 newAccRewardPerLptoken = rewardAmount.mul(1e12).div(
            lpTotalAmount
        );
        pool.accRewardPerLptoken = pool.accRewardPerLptoken.add(
            newAccRewardPerLptoken
        );
        pool.lastRewardBlock = block.number;
    }

    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (_amount > rewardBalance) {
            rewardToken.transfer(_to, rewardBalance);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 userAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), userAmount);
    }

    function resetRewardPerBlock(uint _rewardPerblock) public onlyOwner {
        rewardPerBlock = _rewardPerblock;
    }

    function resetAllocPoint(
        uint256 _pid,
        uint256 _allocPoint
    ) public onlyOwner {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }
}
