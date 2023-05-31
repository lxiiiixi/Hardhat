// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Stake is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 internal constant RATE = 31709;
    uint256 internal constant FEE_RATE_PRECISION = 1e12;

    enum EnumUserOp {
        ADD,
        REMOVE
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        // 
        address user;
        uint256 bp;
        uint256 tempAmount;
        uint256 lastIndex;
    }

    struct UserOp {
        EnumUserOp op;
        uint256 amount;
        uint256 timestamp;
    }

    struct RevenueInfo {
        IERC20 rewardToken;
        uint256 paidOut;
        uint256 totalReward;
    }

    struct AddRevenueInfo {
        uint256 reward;
        uint256 supply;
    }
    
    struct PoolInfo {
        IERC20 rewardToken;
        IERC20 lpToken;
        uint256 lastRewardTime;          // Last block number that ERC20s distribution occurs.
        uint256 accERC20PerShare;        // Accumulated ERC20s per share, times 1e12.
        uint256 paidOut; 
        uint256 rewardPerSecond;
        uint256 totalReward;
        uint256 startTime;
        uint256 endTime;
    }

    mapping (address => PoolInfo) public pools;
    address[] public poolsKeyList;
    mapping (address => mapping (address => UserInfo)) public userInfo;
    // lp -> token -> info
    mapping(address => mapping( address => RevenueInfo)) public revenueInfoMap;
    // lp -> revenueInfoList;
    mapping(address => address[] ) public revenueInfoList;
    // lp -> time -> token -> addInfo
    mapping(address => mapping(uint256 => mapping(address => AddRevenueInfo))) public revenueTimeline;
    // lp -> revenueIndexList
    mapping(address => uint256[]) public revenueTimelineIndexList;
    // lp -> user -> UserOp
    mapping(address => mapping(address => UserOp[])) public userOpTimeline;
    mapping(address => uint8) public stakeTokenDecimal;
    mapping(address => uint256) public stakeTokenAmount;
    mapping(address => uint256) public stakeBpAmount;
    mapping(address => uint256) public stakeLastBpTime;    

    event Deposit(address indexed user, address indexed lpToken, uint256 amount);
    event Withdraw(address indexed user, address indexed lpToken, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        address indexed lpToken,
        uint256 amount
    );
    
    // 添加挖矿信息
    function addToken(
        address _rewardToken,
        address _lpToken,
        uint256 _rewardPerSecond, 
        uint256 _startTime,
        uint256 _deltaTime
    ) public onlyOwner {
        // 创建
        PoolInfo storage poolInfo = pools[_lpToken];
        require(address(poolInfo.lpToken) == address(0), "LP token exist");
        poolInfo.rewardToken = IERC20(_rewardToken);
        poolInfo.lpToken = IERC20(_lpToken);
        poolInfo.lastRewardTime = _startTime;
        poolInfo.accERC20PerShare = 0;
        poolInfo.paidOut = 0;
        poolInfo.rewardPerSecond = _rewardPerSecond;
        poolInfo.startTime = _startTime;
        poolInfo.endTime = _startTime + _deltaTime;
        poolsKeyList.push(_lpToken);
    }

    function setPoolInfo(
        address _lpToken,
        uint256 _rewardPerSecond,
        uint256 _endTime
    ) public onlyOwner {
        // 设置
        PoolInfo storage poolInfo = pools[_lpToken];
        require(address(poolInfo.lpToken) != address(0), "LP token not exists");
        updatePool(_lpToken);
        if (poolInfo.rewardPerSecond > 0) {
            poolInfo.rewardPerSecond = _rewardPerSecond;
        }
        if (_endTime > poolInfo.lastRewardTime) {
            poolInfo.endTime = _endTime;
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(address _lpToken) public {
        // 更新池子
        PoolInfo storage pool = pools[_lpToken];
        // solhint-disable-next-line not-rely-on-time
        uint256 lastTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
        if (lastTime <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            // solhint-disable-next-line not-rely-on-time
            pool.lastRewardTime = block.timestamp;
            return;
        } else {
            uint256 duration = lastTime.sub(pool.lastRewardTime);
            uint256 reward = duration.mul(pool.rewardPerSecond);
            // update perShare 
            pool.accERC20PerShare = pool.accERC20PerShare.add(reward.mul(1e12).div(lpSupply));
            pool.totalReward += reward;
            pool.lastRewardTime = lastTime;
        }

    }

    function getTotalReward(address _lpToken) external view returns (uint256) {
        // 查看有多少矿
        PoolInfo memory pool = pools[_lpToken];
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        // solhint-disable-next-line not-rely-on-time
        uint256 lastTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
        uint256 reward = 0;
        // solhint-disable-next-line not-rely-on-time
        if (lastTime > pool.lastRewardTime && block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 duration = lastTime.sub(pool.lastRewardTime);
            reward = duration.mul(pool.rewardPerSecond);
        }
        return pool.totalReward + reward;
    }

    // View function to see pending ERC20s for a user.
    function pending(address _lpToken, address _user) external view returns (uint256, uint256, uint256, uint256, address) {
        // 查看有多少矿
        PoolInfo memory pool = pools[_lpToken];
        if (address(pool.rewardToken) == address(0)) {
            return (0, 0, 0, 0, address(0));
        }
        UserInfo memory user = userInfo[_lpToken][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        // solhint-disable-next-line not-rely-on-time
        uint256 lastTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
        uint256 reward = 0;
        // solhint-disable-next-line not-rely-on-time
        if (lastTime > pool.lastRewardTime && block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 duration = lastTime.sub(pool.lastRewardTime);
            reward = duration.mul(pool.rewardPerSecond);
            accERC20PerShare = accERC20PerShare.add(reward.mul(1e12).div(lpSupply));
        }
        return (
            user.amount.mul(accERC20PerShare).div(1e12).sub(user.rewardDebt), 
            pool.totalReward + reward,
            pool.rewardPerSecond * 86400,
            user.amount,
            address(pool.rewardToken)
        );
    }

    function deposit(address _lpToken, uint256 _amount) external updateBoostPoint(_lpToken) {
        // 将 LP 代币存入 Farm 用于 ERC20 分配。
        // 抵押token
        PoolInfo storage pool = pools[_lpToken];
        stakeTokenAmount[_lpToken] += _amount;
        require(address(pool.lpToken) == _lpToken, "LP token not exist");
        require(_amount > 0, "DEPOSIT GT 0");
        UserInfo storage user = userInfo[_lpToken][msg.sender];
        // 更新pool
        updatePool(_lpToken);
        if (user.amount > 0) {
            // transfer reward
            uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e12).sub(user.rewardDebt);
            IERC20(pool.rewardToken).transfer(msg.sender, pendingAmount);
        }
        // 加仓
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e12);
        userOpTimeline[_lpToken][msg.sender].push(UserOp(
            EnumUserOp.ADD,
            _amount,
            _now()
        ));
        emit Deposit(msg.sender, _lpToken, _amount);
    }
    
    function withdraw(address _lpToken, uint256 _amount) external updateBoostPoint(_lpToken) {
        // 从 Farm 中提取 LP 代币。
        // 提取一定数量的抵押物 并发放奖励
        PoolInfo storage pool = pools[_lpToken];
        UserInfo storage user = userInfo[_lpToken][msg.sender];
        stakeTokenAmount[_lpToken] -= _amount;
        require(user.amount >= _amount, "withdraw more than deposit");
        updatePool(_lpToken);
        // transfer reward
        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            pool.rewardToken.transfer(msg.sender, pendingAmount);
            pool.paidOut.add(pendingAmount);
        }
        // update user
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e12);
        userOpTimeline[_lpToken][msg.sender].push(UserOp(
            EnumUserOp.REMOVE,
            _amount,
            _now()
        ));
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _lpToken, _amount);
    }

    function withdrawReward(address _lpToken) external {
        // 提取奖励
        PoolInfo storage pool = pools[_lpToken];
        UserInfo storage user = userInfo[_lpToken][msg.sender];
        updatePool(_lpToken);
        // transfer reward
        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e12).sub(user.rewardDebt);
        pool.rewardToken.transfer(msg.sender, pendingAmount);
        pool.paidOut.add(pendingAmount);
        // updateUser
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e12);
    }

    function getPoolsKeyList() external view  returns (address[] memory){
        uint256 poolsKeyListLen = poolsKeyList.length;
        address[] memory _poolsKeyList = new address[](poolsKeyListLen);
        for (uint i = 0; i < poolsKeyListLen; i++) {
            _poolsKeyList[i] = poolsKeyList[i];
        }
        return _poolsKeyList;
    }
    
    function _now() internal view returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp;
    }

    modifier updateBoostPoint(address _lpToken ) {
        UserInfo storage user = userInfo[_lpToken][msg.sender];
        uint256 timestamp = _now();
        if (stakeLastBpTime[_lpToken] != 0) {
            // update total bp
            uint256 deltaTime = timestamp - stakeLastBpTime[_lpToken];
            uint256 deltaBp = stakeTokenAmount[_lpToken] * deltaTime * RATE / FEE_RATE_PRECISION;
            stakeBpAmount[_lpToken] += deltaBp;
            if (deltaBp > 0) {
                stakeLastBpTime[_lpToken] = timestamp;        
            }
        }
        _;
    }

    function addRevenueToken(address _lpToken, address _token) external {
        PoolInfo storage pool = pools[_lpToken];
        require(address(pool.lpToken) == _lpToken, "LP token not exist");
        require(IERC20(_token).balanceOf(address(this)) >= 0, "need balanceOf");
        require(IERC20Metadata(_token).decimals() >= 0, "need decimals");
        require(bytes(IERC20Metadata(_token).name()).length >= 0, "need name");
        RevenueInfo storage revenueInfo = revenueInfoMap[_lpToken][_token];
        require(address(revenueInfo.rewardToken) == address(0), "revenueInfo need empty");
        revenueInfo.rewardToken = IERC20(_token);
        revenueInfoList[_lpToken].push(_token);
        stakeLastBpTime[_lpToken] = _now();
    }

    function addRevenue(address _lpToken, address[] memory tokenList, uint256[] memory amountList) external updateBoostPoint(_lpToken) onlyOwner {
        PoolInfo storage pool = pools[_lpToken];
        require(address(pool.lpToken) == _lpToken, "LP token not exist");
        // admin add Revenue token
        require(tokenList.length == amountList.length, "tokenList eq amountList");
        uint256 timestamp = _now();
        for (uint i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 amount = amountList[i];
            require(amount > 0, "addRevenue gt 0");
            RevenueInfo storage revenueInfo = revenueInfoMap[_lpToken][token];
            require(address(revenueInfo.rewardToken) == token, "revenueInfo not exists");
            uint256 supply = stakeTokenAmount[_lpToken] + stakeBpAmount[_lpToken];
            require(supply > 0, "no stake token");
            AddRevenueInfo storage addRevenueInfo = revenueTimeline[_lpToken][timestamp][token];
            addRevenueInfo.reward = amount;
            addRevenueInfo.supply = supply;
            IERC20(token).safeTransferFrom(address(msg.sender), address(this), amount);
            revenueInfo.totalReward += amount;
        }
        revenueTimelineIndexList[_lpToken].push(timestamp);
    }

    function withdrawAccountRevenue(address _lpToken) external {
        PoolInfo storage pool = pools[_lpToken];
        require(address(pool.lpToken) == _lpToken, "LP token not exist");
        UserInfo storage user = userInfo[_lpToken][msg.sender];
        address[] memory tokens = new address[](revenueInfoList[_lpToken].length);        
        uint256[] memory amountList = new uint256[](revenueInfoList[_lpToken].length);
        for (uint i = 0; i < revenueInfoList[_lpToken].length; i++) {
            tokens[i] = revenueInfoList[_lpToken][i];
        }
        for (uint i = user.lastIndex; i < revenueTimelineIndexList[_lpToken].length; i++) {
            uint256 historyTimestamp = revenueTimelineIndexList[_lpToken][i];
            uint256 userAmount = 0;
            uint256 userBp = 0;
            for (uint _i = 0; _i < userOpTimeline[_lpToken][msg.sender].length; _i++) {
                UserOp memory userOp = userOpTimeline[_lpToken][msg.sender][_i];
                if (userOp.timestamp < historyTimestamp) {
                    if (userOp.op == EnumUserOp.ADD) {
                        userBp += userOp.amount * (historyTimestamp - userOp.timestamp) * RATE / FEE_RATE_PRECISION;
                        userAmount += userOp.amount;
                    } else {
                        userBp = userBp * (userAmount - userOp.amount) / userAmount;
                        userAmount -= userOp.amount;
                    }                    
                }
            }
            for (uint k = 0; k < revenueInfoList[_lpToken].length; k++) {
                AddRevenueInfo memory ad = revenueTimeline[_lpToken][historyTimestamp][revenueInfoList[_lpToken][k]];
                if (ad.reward > 0 && ad.supply > 0) {
                    amountList[k] += ad.reward * (userAmount + userBp) / ad.supply;
                }
            }
            user.lastIndex = i + 1;
        }

        for (uint i = 0; i < tokens.length; i++) {
            revenueInfoMap[_lpToken][tokens[i]].paidOut += amountList[i];
            IERC20(tokens[i]).transfer(msg.sender, amountList[i]);
        }

    }

    function getAccountRevenueInfo(address account, address _lpToken) public view returns(uint256, uint256, uint256, uint256, uint8[] memory, address[] memory, uint256[] memory) {
        PoolInfo storage pool = pools[_lpToken];
        require(address(pool.lpToken) == _lpToken, "LP token not exist");
        // view user pending reward
        UserInfo memory user = userInfo[_lpToken][account];
        user.user = account;
        address[] memory tokens = new address[](revenueInfoList[_lpToken].length + 1);    
        uint8[] memory tokenDecimals = new uint8[](revenueInfoList[_lpToken].length + 1);            
        uint256[] memory amountList = new uint256[](revenueInfoList[_lpToken].length + 1);
        tokens[0] = _lpToken;
        tokenDecimals[0] = IERC20Metadata(tokens[0]).decimals();
        for (uint i = 0; i < revenueInfoList[tokens[0]].length; i++) {
            tokens[i+1] = revenueInfoList[tokens[0]][i];
            tokenDecimals[i+1] = IERC20Metadata(revenueInfoList[tokens[0]][i]).decimals();
        }
        for (uint _i = 0; _i < userOpTimeline[tokens[0]][user.user].length; _i++) {
            UserOp memory userOp = userOpTimeline[tokens[0]][user.user][_i];
            if (userOp.timestamp <= _now()) {
                if (userOp.op == EnumUserOp.ADD) {
                    user.bp += userOp.amount * (_now() - userOp.timestamp) * RATE / FEE_RATE_PRECISION;
                    user.tempAmount += userOp.amount;
                } else {
                    user.bp = user.bp * (user.tempAmount - userOp.amount) / user.tempAmount;
                    user.tempAmount -= userOp.amount;
                }
            }
        }
        for (uint i = user.lastIndex; i < revenueTimelineIndexList[tokens[0]].length; i++) {
            uint256 historyTimestamp = revenueTimelineIndexList[tokens[0]][i];
            uint256 userAmount = 0;
            uint256 userBp = 0;
            for (uint _i = 0; _i < userOpTimeline[tokens[0]][user.user].length; _i++) {
                UserOp memory userOp = userOpTimeline[tokens[0]][user.user][_i];
                if (userOp.timestamp < historyTimestamp) {
                    if (userOp.op == EnumUserOp.ADD) {
                        userBp += userOp.amount * (historyTimestamp - userOp.timestamp) * RATE / FEE_RATE_PRECISION;
                        userAmount += userOp.amount;
                    } else {
                        userBp = userBp * (userAmount - userOp.amount) / userAmount;
                        userAmount -= userOp.amount;
                    }
                }
            }
            user.bp += userBp;
            for (uint k = 0; k < revenueInfoList[tokens[0]].length; k++) {
                AddRevenueInfo memory ad = revenueTimeline[tokens[0]][historyTimestamp][revenueInfoList[tokens[0]][k]];
                if (ad.reward > 0 && ad.supply > 0) {
                    amountList[k + 1] += ad.reward * (userAmount + userBp) / ad.supply;
                }
            }
        }
        return (
            stakeTokenAmount[tokens[0]],
            stakeBpAmount[tokens[0]] + stakeTokenAmount[tokens[0]] * (_now() - stakeLastBpTime[tokens[0]]) * RATE / FEE_RATE_PRECISION,
            user.amount, 
            user.bp, 
            tokenDecimals, 
            tokens, 
            amountList
        );
    }

}
