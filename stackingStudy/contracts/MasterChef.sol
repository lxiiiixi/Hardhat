// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SushiToken.sol";
import "hardhat/console.sol";

interface IMasterChef {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;
}

interface IMigratorChef {
    // Perform LP token migration from legacy UniswapV2 to SushiSwap.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to UniswapV2 LP tokens.
    // SushiSwap must mint EXACTLY the same amount of SushiSwap LP tokens or
    // else something bad will happen. Traditional UniswapV2 does not
    // do that so be careful!
    //
    // 该接口的目的是为了在 UniswapV2 和 SushiSwap 之间进行 LP token 的迁移操作
    // migrate 函数接受一个 IERC20 类型的参数 token，表示当前的 LP token 地址。
    // 该函数应该具有对调用者的 LP token 的完全访问权限，并返回新的 LP token 地址。
    //
    // Migrator 需要拥有对 UniswapV2 LP token 许可
    // SushiSwap 必须严格地铸造与 UniswapV2 LP token 数量相同的 SushiSwap LP token，否则会发生错误。
    // 传统的 UniswapV2 不会这样做，因此需要注意。
    function migrate(IERC20 token) external returns (IERC20);
}

// MasterChef is the master of Sushi. He can make Sushi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SUSHI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSushiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSushiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract. 代币地址
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHIs to distribute per block. 池子权重
        uint256 lastRewardBlock; // Last block number that SUSHIs distribution occurs. 每个池子最后一次分配奖励的区块(updatePool时更新奖励=>更新这个值)
        uint256 accSushiPerShare; // Accumulated SUSHIs per share, times 1e12. See below.
    }
    // The SUSHI TOKEN!
    SushiToken public sushi;
    // Dev address.
    address public devaddr;
    // Block number when bonus SUSHI period ends.
    uint256 public bonusEndBlock;
    // SUSHI tokens created per block.
    uint256 public sushiPerBlock;
    // Bonus muliplier for early sushi makers.
    uint256 public constant BONUS_MULTIPLIER = 10;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0; // 总权重
    // The block number when SUSHI mining starts.
    uint256 public startBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        SushiToken _sushi,
        address _devaddr,
        uint256 _sushiPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        sushi = _sushi;
        devaddr = _devaddr;
        sushiPerBlock = _sushiPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        // 一般添加新池子之前都要结算一遍 注意这个时机
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accSushiPerShare: 0
            })
        );
    }

    // Update the given pool's SUSHI allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // View function to see pending SUSHIs on frontend.
    // 计算用户未领取的奖励
    function pendingSushi(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSushiPerShare = pool.accSushiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 sushiReward = multiplier
                .mul(sushiPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accSushiPerShare = accSushiPerShare.add(
                sushiReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accSushiPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    // 可以注意到更新池子是和用户的信息无关的，只是根据当前池子现有的信息和全局的信息来更新
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        // 上面这里如果不同的池子使用了相同的LPtoken，那么根据这个值计算当前池子的奖励比例的时候，会导致可能有一定的问题
        // 比如一个计算的例子，如果池子AB都是使用的同一个LPtoken，A有人质押了，但是B还没有人质押，那么我更新池子B的时候本来下面会直接return，但是获取到的lpSupply是A+B的总量，还会往下执行
        if (lpSupply == 0) {
            // 很多时候这里容易漏掉，如果没有人质押，那么就不需要更新奖励了
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 sushiReward = multiplier
            .mul(sushiPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        // multiplier 上次更新到现在的区块数
        // sushiPerBlock  全局变量，每个区块产生的sushi奖励
        // pool.allocPoint  当前池子的奖励权重
        // totalAllocPoint  所有池子的奖励权重之和
        // 因此：sushiReward 是上次更新到这次更新这段时间内积累的需要发放的sushi奖励总量
        sushi.mint(devaddr, sushiReward.div(10)); // 给项目方mint（没什么意义）
        sushi.mint(address(this), sushiReward);
        // 上面mint出来的奖励是根据整个池子中的lptoken数量来计算的，每次更新池子都会计算并且mint，但是并不是都会发给用户，有些用户还没有通过其他方法赎回的时候，这部分奖励就会留在合约中
        // 如果极端情况下这个池子多有的质押代币都是一个用户的，那么这个用户就会获得所有的奖励，但其实这里mint出来的是给所有用户按照 pool.accSushiPerShare 分配的
        // 也就是说每个区块的奖励其实都是固定的（sushiPerBlock）=> 同一个区块又根据池子的奖励权重分配给不同的池子（pool.allocPoint/totalAllocPoint） => 同一个池子又根据用户的质押数量分配给不同的用户（pool.accSushiPerShare）
        pool.accSushiPerShare = pool.accSushiPerShare.add(
            sushiReward.mul(1e12).div(lpSupply)
        );
        // 对 pool.accSushiPerShare 的理解： 当前池子中每份LPtoken对应的sushi奖励数量
        // 为什么这里 accSushiPerShare 变量是累加呢？分母lpSupply总是取这个池子中的lptoken总量，分子是根据区块计算的奖励
        // 对这个变量还需要通过测试加深理解
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for SUSHI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid); // 1. 更新池子
        // 2. 用户以前质押过 => 计算奖励
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accSushiPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            // user.amount.mul(pool.accSushiPerShare) 根据本次质押之前的amount数量和当前池子的pool.accSushiPerShare计算出应该给用户的sushi奖励数量
            // user.rewardDebt 上次领取奖励的时候，用户的amount数量对应的奖励数量（还需要加深理解）
            // 因此，pending 数量就是用户上次领取奖励到本次领取奖励之间应该领取的奖励数量
            safeSushiTransfer(msg.sender, pending);
        }
        // 3. 用户质押
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        // 4. 更新用户记录的数量和奖励
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(
            user.rewardDebt
        );
        safeSushiTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount); // 存在重入攻击
        console.log("withdraw:", _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // 紧急提币：异常情况下提取所有本金 放弃奖励
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount); // 存在重入攻击的可能
        console.log("emergencyWithdraw:", user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0; // 如果是用减的方式 执行多次会出错 但这里会重置为0 多少次都可以
        user.rewardDebt = 0;
    }

    // Safe sushi transfer function, just in case if rounding error causes pool to not have enough SUSHIs.
    function safeSushiTransfer(address _to, uint256 _amount) internal {
        uint256 sushiBal = sushi.balanceOf(address(this));
        if (_amount > sushiBal) {
            sushi.transfer(_to, sushiBal);
        } else {
            sushi.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
