// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TradeStake is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 private constant REWARD_TIME_UNIT = 60 * 60 * 24;

    struct UserSlot {
        uint256 slotScore;
    }

    struct UserInfo {
        uint256 amount;
        uint256 beginSlotCursor;
        uint256 rewardSlotCursor;
    }

    struct PoolSlot {
        uint256 slotScore;
        uint256 rewardPerUnit;
    }
    
    struct RewardInfo {
        IERC20 rewardToken;
        uint256 paidOut; 
        uint256 rewardPerUnit;
        uint256 totalReward;
        uint256 startTime;
        uint256 endTime;
    }

    RewardInfo public rewardInfo;
    mapping (address => UserInfo) public userInfo;
    mapping (address => mapping(uint256 => UserSlot)) public userInfoSlotMap;
    mapping(uint256 => PoolSlot) public rewardInfoSlotMap;
    mapping(address => bool) public updaters;

    modifier onlyUpdater() {
        require(updaters[_msgSender()], "onlyUpdater");
        _;
    }

    function setRewardPerUnit(uint256 rewardPerUnit) external {
        rewardInfo.rewardPerUnit = rewardPerUnit;
    }

    function updateScore(address _account,uint256 _score) external onlyUpdater {
        // check sender
        if (rewardInfo.rewardPerUnit == 0 ) {
            return;
        }
        UserInfo storage _userInfo = userInfo[_account];
        // solhint-disable-next-line not-rely-on-time
        uint256 slot = block.timestamp / REWARD_TIME_UNIT;
        if (_userInfo.beginSlotCursor == 0) {
            _userInfo.beginSlotCursor = slot;
            _userInfo.rewardSlotCursor = slot;
        }
        if (rewardInfoSlotMap[slot].rewardPerUnit == 0) {
            rewardInfoSlotMap[slot].rewardPerUnit = rewardInfo.rewardPerUnit;
        }
        userInfoSlotMap[_account][slot].slotScore += _score;
        rewardInfoSlotMap[slot].slotScore += _score;
    }

    function getUserTradeInfo(address _account) external view returns (uint256, uint256, uint256, uint256, uint8) {
        uint256 slot = block.timestamp / REWARD_TIME_UNIT;
        uint256 pendingAmount = pending(_account);
        PoolSlot memory poolSlot = rewardInfoSlotMap[slot];
        UserSlot memory userSlot = userInfoSlotMap[_account][slot];
        uint8 decimals = IERC20Metadata(address(rewardInfo.rewardToken)).decimals();
        return (
            poolSlot.slotScore, 
            userSlot.slotScore, 
            rewardInfo.rewardPerUnit, 
            pendingAmount,
            decimals
        );
    }

    function pending(address _account) public view returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        uint256 slot = block.timestamp / REWARD_TIME_UNIT;
        UserInfo memory _userInfo = userInfo[_account];
        if (_userInfo.rewardSlotCursor == 0) {
            return 0;
        } else {
            uint256 _pending;
            for (uint i = _userInfo.rewardSlotCursor; i < slot; i++) {
                UserSlot memory userSlot = userInfoSlotMap[_account][i];
                if (rewardInfoSlotMap[i].slotScore > 0)  {
                    uint256 slotReward = rewardInfoSlotMap[i].rewardPerUnit * userSlot.slotScore / rewardInfoSlotMap[i].slotScore;
                    _pending += slotReward;
                }
            }
            return _pending;
        }
    }

    function setUpdater(address account, bool approved) external onlyOwner {
        updaters[account] = approved;
    }

    function setRewardToken(address _rewardToken) external onlyOwner {
        if (address(rewardInfo.rewardToken) == address(0)){
            rewardInfo.rewardToken = IERC20(_rewardToken);
        }
    }

    function withdraw() external {
        address _account = msg.sender;
        // solhint-disable-next-line not-rely-on-time
        uint256 slot = block.timestamp / REWARD_TIME_UNIT;
        UserInfo storage _userInfo = userInfo[_account];
        if (_userInfo.rewardSlotCursor != 0) {
            uint256 _pending;
            for (uint i = _userInfo.rewardSlotCursor; i < slot; i++) {
                UserSlot storage userSlot = userInfoSlotMap[_account][i];
                if (rewardInfoSlotMap[i].slotScore > 0)  {
                    uint256 slotReward = rewardInfoSlotMap[i].rewardPerUnit * userSlot.slotScore / rewardInfoSlotMap[i].slotScore;
                    _pending += slotReward;
                }
                _userInfo.rewardSlotCursor = i + 1;
            }
            IERC20(rewardInfo.rewardToken).transfer(_account, _pending);
        }
    }

}
