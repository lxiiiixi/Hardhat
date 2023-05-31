// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakeRevenue is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 internal constant RATE = 31709;
    uint256 internal constant FEE_RATE_PRECISION = 1e12;

    enum EnumUserOp {
        ADD,
        REMOVE
    }

    struct UserInfo {
        address user;
        uint256 amount;
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
    // revenue global variable
    mapping(address => RevenueInfo) public revenueInfoMap;
    address[] public revenueInfoList;
    // revenue op variable
    mapping(uint256 => mapping(address => AddRevenueInfo)) public revenueTimeline;
    uint256[] public revenueTimelineIndexList;
    // user op variable
    mapping (address => UserInfo) public userInfo;
    mapping(address => UserOp[]) public userOpTimeline;
    // global stake token variable
    address public stakeTokenAddress;
    uint8 public stakeTokenDecimal;
    uint256 public stakeTokenAmount;
    uint256 public stakeBpAmount;
    uint256 public stakeLastBpTime;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor(address _stakeTokenAddress) {
        stakeTokenAddress = _stakeTokenAddress;
        stakeTokenDecimal = IERC20Metadata(_stakeTokenAddress).decimals();
        stakeTokenAmount = 0;
        stakeBpAmount = 0;
        stakeLastBpTime = _now();
    }

    modifier updateBoostPoint() {
        UserInfo storage user = userInfo[msg.sender];
        uint256 timestamp = _now();
        if (stakeLastBpTime != 0) {
            // update total bp
            uint256 deltaTime = timestamp - stakeLastBpTime;
            uint256 deltaBp = stakeTokenAmount * deltaTime * RATE / FEE_RATE_PRECISION;
            stakeBpAmount += deltaBp;
            if (deltaBp > 0) {
                stakeLastBpTime = timestamp;        
            }
        }
        _;
    }

    function _now() internal view returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp;
    }

    function addRevenueToken(address _token) external onlyOwner {
        // list revenue token
        require(IERC20(_token).balanceOf(address(this)) >= 0, "need balanceOf");
        require(IERC20Metadata(_token).decimals() >= 0, "need decimals");
        require(bytes(IERC20Metadata(_token).name()).length >= 0, "need name");
        RevenueInfo storage revenueInfo = revenueInfoMap[_token];
        require(address(revenueInfo.rewardToken) == address(0), "revenueInfo need empty");
        revenueInfo.rewardToken = IERC20(_token);
        revenueInfoList.push(_token);
    }

    function addRevenue(address[] memory tokenList, uint256[] memory amountList) external updateBoostPoint() onlyOwner {
        // admin add Revenue token
        require(tokenList.length == amountList.length, "tokenList eq amountList");
        uint256 timestamp = _now();
        for (uint i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 amount = amountList[i];
            require(amount > 0, "addRevenue gt 0");
            RevenueInfo storage revenueInfo = revenueInfoMap[token];
            require(address(revenueInfo.rewardToken) == token, "revenueInfo not exists");
            uint256 supply = stakeTokenAmount + stakeBpAmount;
            require(supply > 0, "no stake token");
            AddRevenueInfo storage addRevenueInfo = revenueTimeline[timestamp][token];
            addRevenueInfo.reward = amount;
            addRevenueInfo.supply = supply;
            IERC20(token).safeTransferFrom(address(msg.sender), address(this), amount);
            revenueInfo.totalReward += amount;
        }
        revenueTimelineIndexList.push(timestamp);
    }
    
    function deposit(uint256 _amount) external updateBoostPoint() {
        // deposit stake token
        require(_amount > 0, "DEPOSIT GT 0");
        UserInfo storage user = userInfo[msg.sender];        
        stakeTokenAmount = stakeTokenAmount.add(_amount);
        IERC20(stakeTokenAddress).safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        userOpTimeline[msg.sender].push(UserOp(
            EnumUserOp.ADD,
            _amount,
            _now()
        ));
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external updateBoostPoint() {
        // withdraw stake token
        require(_amount > 0, "DEPOSIT GT 0");
        UserInfo storage user = userInfo[msg.sender];
        require(_amount <= user.amount, "DEPOSIT LT USER.amount");
        stakeTokenAmount = stakeTokenAmount.sub(_amount);
        stakeBpAmount = stakeBpAmount * stakeTokenAmount / (stakeTokenAmount + _amount);
        IERC20(stakeTokenAddress).transfer(msg.sender, _amount);
        user.amount = user.amount.sub(_amount);
        userOpTimeline[msg.sender].push(UserOp(
            EnumUserOp.REMOVE,
            _amount,
            _now()
        ));
        emit Withdraw(msg.sender, _amount);
    }

    function withdrawReward() external {
        // withdraw reward tokens
        UserInfo storage user = userInfo[msg.sender];
        address[] memory tokens = new address[](revenueInfoList.length);        
        uint256[] memory amountList = new uint256[](revenueInfoList.length);
        for (uint i = 0; i < revenueInfoList.length; i++) {
            tokens[i] = revenueInfoList[i];
        }
        for (uint i = user.lastIndex; i < revenueTimelineIndexList.length; i++) {
            uint256 historyTimestamp = revenueTimelineIndexList[i];
            uint256 userAmount = 0;
            uint256 userBp = 0;
            for (uint _i = 0; _i < userOpTimeline[msg.sender].length; _i++) {
                UserOp memory userOp = userOpTimeline[msg.sender][_i];
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
            for (uint k = 0; k < revenueInfoList.length; k++) {
                AddRevenueInfo memory ad = revenueTimeline[historyTimestamp][revenueInfoList[k]];
                if (ad.reward > 0 && ad.supply > 0) {
                    amountList[k] += ad.reward * (userAmount + userBp) / ad.supply;
                }
            }
            user.lastIndex = i + 1;
        }

        for (uint i = 0; i < tokens.length; i++) {
            revenueInfoMap[tokens[i]].paidOut += amountList[i];
            IERC20(tokens[i]).transfer(msg.sender, amountList[i]);
        }
    }

    function getAccountInfo(address account) public view returns(uint256, uint256, uint256, uint256, uint8[] memory, address[] memory, uint256[] memory) {
        // view user pending reward
        UserInfo memory user = userInfo[account];
        user.user = account;
        address[] memory tokens = new address[](revenueInfoList.length + 1);    
        uint8[] memory tokenDecimals = new uint8[](revenueInfoList.length + 1);            
        uint256[] memory amountList = new uint256[](revenueInfoList.length + 1);
        tokens[0] = stakeTokenAddress;
        tokenDecimals[0] = IERC20Metadata(stakeTokenAddress).decimals();
        for (uint i = 0; i < revenueInfoList.length; i++) {
            tokens[i+1] = revenueInfoList[i];
            tokenDecimals[i+1] = IERC20Metadata(revenueInfoList[i]).decimals();
        }
        for (uint _i = 0; _i < userOpTimeline[account].length; _i++) {
            UserOp memory userOp = userOpTimeline[account][_i];
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
        for (uint i = user.lastIndex; i < revenueTimelineIndexList.length; i++) {
            uint256 historyTimestamp = revenueTimelineIndexList[i];
            uint256 userAmount = 0;
            uint256 userBp = 0;
            for (uint _i = 0; _i < userOpTimeline[user.user].length; _i++) {
                UserOp memory userOp = userOpTimeline[user.user][_i];
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
            for (uint k = 0; k < revenueInfoList.length; k++) {
                AddRevenueInfo memory ad = revenueTimeline[historyTimestamp][revenueInfoList[k]];
                if (ad.reward > 0 && ad.supply > 0) {
                    amountList[k + 1] += ad.reward * (userAmount + userBp) / ad.supply;
                }
            }
        }
        return (
            stakeTokenAmount,
            stakeBpAmount + stakeTokenAmount * (_now() - stakeLastBpTime) * RATE / FEE_RATE_PRECISION,
            user.amount, 
            user.bp, 
            tokenDecimals, 
            tokens, 
            amountList
        );
    }

}
