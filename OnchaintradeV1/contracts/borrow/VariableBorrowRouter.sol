// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IOracle.sol";

import "hardhat/console.sol";

interface IVariableBorrow {
    struct Collateral {
        address token;
        uint256 amount;
    }

    struct Asset {
        uint256 debt;
        uint256 protocolRevenueAmount;
        uint256 protocolRevenueAmountExtract;
        uint256 r0;
        uint256 relativeInterest;
        uint256 updatedAt;
        // max 65536 => 655.36%
        uint16 interestRate; // year
        uint16 base;
        uint16 optimal;
        uint16 slope1;
        uint16 slope2;
        uint8 borrowCredit;
        uint8 collateralCredit;
        uint8 penaltyRate;
    }

    function oracle() external view returns(address);

    function swap() external view returns (address);

    function assets(address asset) external view returns (Asset memory);
    
    function borrow(
        address _asset,
        uint256 amount,
        Collateral[] calldata collaterals,
        address to
    ) external;

    function repay(
        address _asset,
        uint256 amountMax,
        Collateral[] calldata collaterals,
        address to
    ) external returns (uint256);

    function getDebt(address _asset) external view returns (uint256, uint256, uint256);

    function getAccountDebt(address _asset, address _account, uint256 delaySeconds) external view returns (uint256);

    function getPositionsView(address _asset, address _account) external view returns (
        uint256 debt,
        uint256 r0,
        address[] memory collateralTokens,
        uint256[] memory collateralAmounts
    );
}

contract VariableBorrowRouter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWETH internal immutable WETH;
    IVariableBorrow internal immutable $borrow;

    mapping(address => PoolInfo) public pools;
    mapping(address => mapping(address => Position)) public positions;
    address public oracle;

    struct Position {
        uint256 rewardDebt;
    }
    
    struct PoolInfo {
        address rewardToken;
        uint256 accERC20PerShare;  // Accumulated ERC20s per share, times 1e12.
        uint256 paidOut;
        uint256 startTime;
        uint256 endTime;
        uint256 lastRewardTime;    // Last block number that ERC20s distribution occurs.
        uint256 rewardPerSecond;
        uint256 totalReward;
    }

    constructor(address _weth, address _borrow) {
        WETH = IWETH(_weth);
        $borrow = IVariableBorrow(_borrow);
        oracle = $borrow.oracle();
    }

    function borrow(        
        address _asset,
        uint256 amount,
        IVariableBorrow.Collateral[] calldata collaterals,
        address to
    ) external payable {
        require(to == msg.sender, "PERMISSION DENY");
        // reward
        (uint256 _totalDebt, , ) = $borrow.getDebt(_asset);
        _updateRewardPool(_asset, _totalDebt);
        _withdrawReward(_asset, msg.sender, amount);
        // router call
        for (uint i = 0; i < collaterals.length; i++) {
            IVariableBorrow.Collateral memory col = collaterals[i];
            if (col.token != address(WETH)) {
                IERC20(col.token).safeTransferFrom(to, address(this), col.amount);
            } else {
                require(msg.value == col.amount, "WETH need msg.value");
                WETH.deposit{value: col.amount}();
            }
            IERC20(address(col.token)).approve(address($borrow), col.amount);
        }
        $borrow.borrow(_asset, amount, collaterals, to);
        if (_asset == address(WETH)) {
            WETH.withdraw(amount);
            payable(to).transfer(amount);
        } else {
            IERC20(_asset).transfer(to, amount);
        }
    }

    function repay(
        address _asset,
        uint256 amountMax,
        IVariableBorrow.Collateral[] calldata collaterals,
        address to
    ) external payable {
        require(to == msg.sender, "PERMISSION DENY");
        // reward
        (uint256 _totalDebt, , ) = $borrow.getDebt(_asset);
        _updateRewardPool(_asset, _totalDebt);
        _withdrawReward(_asset, msg.sender, 0);
        // router call
        if (_asset != address(WETH)) {
            IERC20(_asset).safeTransferFrom(to, address(this), amountMax);
        } else {
            require(msg.value == amountMax, "eth need eq amountMax");
            WETH.deposit{value: amountMax}();
        }
        IERC20(_asset).approve($borrow.swap(), amountMax);
        uint256 amountUse = $borrow.repay(_asset, amountMax, collaterals, to);
        for (uint i = 0; i < collaterals.length; i++) {
            IVariableBorrow.Collateral memory col = collaterals[i];
            if (col.token != address(WETH)) {
                IERC20(col.token).transfer(to, col.amount);
            } else {
                // weth -> to
                WETH.withdraw(col.amount);
                payable(to).transfer(col.amount);
            }
        }
        uint256 amountCharge = amountMax - amountUse;
        if (amountCharge > 0) {
            if (_asset != address(WETH)) {
                IERC20(_asset).transfer(to, amountCharge);
            } else {
                WETH.withdraw(amountCharge);
                payable(to).transfer(amountCharge);
            }
        }
    }

    function getWETHAddress() external view returns (address) {
        return address(WETH);
    }

    /**
     * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
     */
    receive() external payable {
        require(msg.sender == address(WETH), "Receive not allowed");
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }

    function _updateRewardPool(address _borrowToken, uint256 _totalDebt) internal {
        PoolInfo storage pool = pools[_borrowToken];
        uint256 lastTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
        if (lastTime < block.timestamp) {
            return;
        }
        if (_totalDebt > 0) {
            uint256 duration = lastTime.sub(pool.lastRewardTime);
            uint256 reward = duration.mul(pool.rewardPerSecond);
            pool.accERC20PerShare = pool.accERC20PerShare + (reward * 1e12) / _totalDebt;
            pool.totalReward += reward;
            pool.lastRewardTime = lastTime;
        } else {
            pool.lastRewardTime = lastTime;
        }
    }

    function _withdrawReward(address _borrowToken, address _account, uint256 newDebt) internal {
        // withdraw
        PoolInfo storage pool = pools[_borrowToken];
        uint256 lastTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
        if (lastTime < block.timestamp) {
            return;
        }
        uint256 userDebt = $borrow.getAccountDebt(_borrowToken, _account, 0);
        Position storage userStake = positions[_borrowToken][_account];
        if (userDebt.mul(pool.accERC20PerShare).div(1e12) > userStake.rewardDebt){
            uint256 pendingAmount = userDebt.mul(pool.accERC20PerShare).div(1e12) - (userStake.rewardDebt);
            IERC20(pool.rewardToken).transfer(_account, pendingAmount);
            pool.paidOut += pendingAmount;
        }
        userStake.rewardDebt = (userDebt + newDebt) * pool.accERC20PerShare / 1e12;
    }

    function withdrawReward(address _borrowToken) external {
        // update reward pool
        (uint256 _totalDebt, , ) = $borrow.getDebt(_borrowToken);
        _updateRewardPool(_borrowToken, _totalDebt);
        // withdrawReward
        _withdrawReward(_borrowToken, msg.sender, 0);
    }

    function getReward(address _borrowToken, address _account) public view returns(uint256, uint256, address) {
        uint256 userDebt = $borrow.getAccountDebt(_borrowToken, _account, 0);
        Position memory positionStake = positions[_borrowToken][_account];
        PoolInfo memory pool = pools[_borrowToken];
        (uint256 _totalDebt, , ) = $borrow.getDebt(_borrowToken);
        uint256 lastTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
        if (_totalDebt > 0) {
            uint256 duration = lastTime.sub(pool.lastRewardTime);
            uint256 reward = duration.mul(pool.rewardPerSecond);
            pool.accERC20PerShare = pool.accERC20PerShare + (reward * 1e12) / _totalDebt;
        }
        if (userDebt.mul(pool.accERC20PerShare).div(1e12) < positionStake.rewardDebt){
            return (0, pool.rewardPerSecond * 86400 , address(pool.rewardToken));
        } else {
            uint256 pendingAmount = userDebt.mul(pool.accERC20PerShare).div(1e12) - positionStake.rewardDebt;
            return (pendingAmount, pool.rewardPerSecond * 86400, address(pool.rewardToken));
        }
    }

    // function bulkBorrowStakeInfo(
    //     address[] memory tokens,
    //     address account
    // ) public view returns (
    //     uint256[] memory accountYeilds,
    //     uint256[] memory dayStaked,
    //     address[] memory rewardTokens,
    //     uint8[] memory rewardTokensDecimal,
    //     uint256[] memory rewardTokenPrices
    // ) {
    //     accountYeilds = new uint256[](tokens.length);
    //     dayStaked = new uint256[](tokens.length);
    //     rewardTokens = new address[](tokens.length);
    //     rewardTokensDecimal = new uint8[](tokens.length);
    //     rewardTokenPrices = new uint256[](tokens.length);
    //     // for (uint i = 0; i < tokens.length; i++) {
    //     //     // (accountYeilds[i], dayStaked[i], rewardTokens[i]) = getReward(tokens[i], account);
    //     //     // rewardTokensDecimal[i] = IERC20Metadata(rewardTokens[i]).decimals();
    //     //     // rewardTokenPrices[i] = IOracle(oracle).getPrice(rewardTokens[i]);
    //     // }
    // }

    function addMintPool(
        address _rewardToken,
        address _asset,
        uint256 _rewardPerSecond,
        uint256 _startTime,
        uint256 _deltaTime
    ) public onlyOwner {
        // setting mint pool
        PoolInfo storage poolInfo = pools[_asset];
        require(address(poolInfo.rewardToken) == address(0), "Asset token exist");
        poolInfo.rewardToken = _rewardToken;
        poolInfo.lastRewardTime = _startTime;
        poolInfo.accERC20PerShare = 0;
        poolInfo.paidOut = 0;
        poolInfo.rewardPerSecond = _rewardPerSecond;
        poolInfo.startTime = _startTime;
        poolInfo.endTime = _startTime + _deltaTime;
    }

    function updateMintPool(        
        address _asset,
        uint256 _rewardPerSecond,
        uint256 _startTime,
        uint256 _deltaTime    
    ) public onlyOwner {
        // update mine time
        PoolInfo storage poolInfo = pools[_asset];
        require(address(poolInfo.rewardToken) != address(0), "LP token not exists");

        if (poolInfo.rewardPerSecond > 0) {
            poolInfo.rewardPerSecond = _rewardPerSecond;
        }
        if (_startTime + _deltaTime > poolInfo.endTime) {
            poolInfo.endTime = _startTime + _deltaTime;
        }
    }
    

}