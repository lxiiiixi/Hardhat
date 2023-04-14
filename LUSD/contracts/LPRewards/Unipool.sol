// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Dependencies/LiquityMath.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Interfaces/ILQTYToken.sol";
import "./Dependencies/SafeERC20.sol";
import "./Interfaces/ILPTokenWrapper.sol";
import "./Interfaces/IUnipool.sol";
import "../Dependencies/console.sol";

// Adapted from: https://github.com/Synthetixio/Unipool/blob/master/contracts/Unipool.sol
// Some more useful references:
// Synthetix proposal: https://sips.synthetix.io/sips/sip-31
// Original audit: https://github.com/sigp/public-audits/blob/master/synthetix/unipool/review.pdf
// Incremental changes (commit by commit) from the original to this version: https://github.com/liquity/dev/pull/271

// LPTokenWrapper contains the basic staking functionality
contract LPTokenWrapper is ILPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public uniToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual override {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        uniToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual override {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        uniToken.safeTransfer(msg.sender, amount);
    }
}

/**
在部署时，将为 LUSD/ETH 对创建一个新的 Uniswap 池，并部署一个 Staking 奖励合约。该合约基于 Synthetix 的 Unipool。有关其流动性奖励计划的更多信息，请参阅原始 SIP 31 和他们的博客。
本质上他的运行方式是：
- 流动性提供者向 Uniswap 池中添加资金，并获得 UNIv2 代币作为交换 
- 流动性提供者将这些 UNIv2 代币抵押到 Unipool 奖励合约中 
- 流动性提供者获得奖励，奖励与质押代币数量和质押时间成正比 
- 流动性提供者可以在需要时领取奖励 
- 流动性提供者可以在需要时取消质押 UNIv2 代币以退出该程序（即停止赚取奖励）

奖励资金只会在部署 LQTY 令牌时添加一次
奖励合约将铸造的 LQTY 代币数量为 133 万，该计划的持续时间为 30 天。
如果在某个时候质押的代币总量为零，时钟将“停止”，因此该时间段将延长质押池为空的时间，以避免 LQTY 代币被锁定。
这也意味着该程序的开始时间将是最先发生的事件：部署 LQTY 代币合约，因此将 LQTY 代币铸造到 Unipool 合约，或者第一个流动性提供者将 UNIv2 代币投入其中。
 */

/*
 * On deployment a new Uniswap pool will be created for the pair LUSD/ETH and its token will be set here.

 * Essentially the way it works is:

 * - Liquidity providers add funds to the Uniswap pool, and get UNIv2 LP tokens in exchange
 * - Liquidity providers stake those UNIv2 LP tokens into Unipool rewards contract
 * - Liquidity providers accrue rewards, proportional to the amount of staked tokens and staking time
 * - Liquidity providers can claim their rewards when they want
 * - Liquidity providers can unstake UNIv2 LP tokens to exit the program (i.e., stop earning rewards) when they want

 * Funds for rewards will only be added once, on deployment of LQTY token,
 * which will happen after this contract is deployed and before this `setParams` in this contract is called.

 * If at some point the total amount of staked tokens is zero, the clock will be “stopped”,
 * so the period will be extended by the time during which the staking pool is empty,
 * in order to avoid getting LQTY tokens locked.
 * That also means that the start time for the program will be the event that occurs first:
 * either LQTY token contract is deployed, and therefore LQTY tokens are minted to Unipool contract,
 * or first liquidity provider stakes UNIv2 LP tokens into it.
 */
contract Unipool is LPTokenWrapper, Ownable, CheckContract, IUnipool {
    string public constant NAME = "Unipool";

    uint256 public duration;
    ILQTYToken public lqtyToken;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event LQTYTokenAddressChanged(address _lqtyTokenAddress);
    event UniTokenAddressChanged(address _uniTokenAddress);
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    // initialization function
    function setParams(
        address _lqtyTokenAddress,
        address _uniTokenAddress,
        uint _duration
    ) external override onlyOwner {
        checkContract(_lqtyTokenAddress);
        checkContract(_uniTokenAddress);

        uniToken = IERC20(_uniTokenAddress);
        lqtyToken = ILQTYToken(_lqtyTokenAddress);
        duration = _duration;

        _notifyRewardAmount(lqtyToken.getLpRewardsEntitlement(), _duration);

        emit LQTYTokenAddressChanged(_lqtyTokenAddress);
        emit UniTokenAddressChanged(_uniTokenAddress);

        _renounceOwnership();
    }

    // Returns current timestamp if the rewards program has not finished yet, end time otherwise
    // 返回当前时间戳，如果奖励计划尚未结束，则返回当前时间戳，否则返回结束时间。
    function lastTimeRewardApplicable() public view override returns (uint256) {
        return LiquityMath._min(block.timestamp, periodFinish);
    }

    // Returns the amount of rewards that correspond to each staked token
    // 返回每个质押代币对应的奖励数量
    function rewardPerToken() public view override returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    // Returns the amount that an account can claim
    // 用于返回账户可以领取的奖励
    function earned(address account) public view override returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    // 抵押贷币
    function stake(uint256 amount) public override {
        require(amount > 0, "Cannot stake 0");
        require(
            address(uniToken) != address(0),
            "Liquidity Pool Token has not been set yet"
        );

        _updatePeriodFinish();
        _updateAccountReward(msg.sender);

        super.stake(amount);

        emit Staked(msg.sender, amount);
    }

    // 提取抵押贷币
    function withdraw(uint256 amount) public override {
        require(amount > 0, "Cannot withdraw 0");
        require(
            address(uniToken) != address(0),
            "Liquidity Pool Token has not been set yet"
        );

        _updateAccountReward(msg.sender);

        super.withdraw(amount);

        emit Withdrawn(msg.sender, amount);
    }

    // Shortcut to be able to unstake tokens and claim rewards in one transaction
    // 在一笔交易中提取抵押代币和领取奖励
    function withdrawAndClaim() external override {
        withdraw(balanceOf(msg.sender));
        claimReward();
    }

    // 领取奖励
    function claimReward() public override {
        require(
            address(uniToken) != address(0),
            "Liquidity Pool Token has not been set yet"
        );

        _updatePeriodFinish();
        _updateAccountReward(msg.sender);

        uint256 reward = earned(msg.sender);

        require(reward > 0, "Nothing to claim");

        rewards[msg.sender] = 0;
        lqtyToken.transfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    // Used only on initialization, sets the reward rate and the end time for the program
    // 在 setParams 函数中初始化时调用，用于设置奖励率和奖励结束时间
    function _notifyRewardAmount(uint256 _reward, uint256 _duration) internal {
        assert(_reward > 0);
        assert(_reward == lqtyToken.balanceOf(address(this)));
        assert(periodFinish == 0);

        _updateReward();

        rewardRate = _reward.div(_duration);

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(_duration);
        emit RewardAdded(_reward);
    }

    // Adjusts end time for the program after periods of zero total supply
    function _updatePeriodFinish() internal {
        if (totalSupply() == 0) {
            assert(periodFinish > 0);
            /*
             * If the finish period has been reached (but there are remaining rewards due to zero stake),
             * to get the new finish date we must add to the current timestamp the difference between
             * the original finish time and the last update, i.e.:
             *
             * periodFinish = block.timestamp.add(periodFinish.sub(lastUpdateTime));
             *
             * If we have not reached the end yet, we must extend it by adding to it the difference between
             * the current timestamp and the last update (the period where the supply has been empty), i.e.:
             *
             * periodFinish = periodFinish.add(block.timestamp.sub(lastUpdateTime));
             *
             * Both formulas are equivalent.
             */
            periodFinish = periodFinish.add(
                block.timestamp.sub(lastUpdateTime)
            );
        }
    }

    function _updateReward() internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
    }

    function _updateAccountReward(address account) internal {
        _updateReward();

        assert(account != address(0));

        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }
}
