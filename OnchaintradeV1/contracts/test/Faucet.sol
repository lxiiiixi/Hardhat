// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Faucet is Ownable {
    using SafeERC20 for IERC20;
    uint256 public waitTime = 1 hours;

    struct FaucetToken {
        bool disabled;
        address token;
        uint256 amount;
    }

    FaucetToken[] private faucetTokenList;
    
    mapping(address => uint256) private lastAccessTime;

    mapping(address => uint256) private tokenIndexMapping;

    constructor() {
        FaucetToken memory ft = FaucetToken(true, address(0), 0);
        faucetTokenList.push(ft);
    }

    // 检查
    function _allowedToWithdraw(address _address) internal view returns (bool) {
        if(lastAccessTime[_address] == 0) {
            return true;
        // solhint-disable-next-line not-rely-on-time
        } else if(block.timestamp >= lastAccessTime[_address]) {
            return true;
        }
        return false;
    }

    function requestTokens(address _address) public {
        require(_allowedToWithdraw(_address), "You can only request once every 1 hour");
        // solhint-disable-next-line not-rely-on-time
        lastAccessTime[_address] = block.timestamp + waitTime;
        for (uint256 index = 0; index < faucetTokenList.length; index++) {
            if (faucetTokenList[index].disabled == false) {
                IERC20(faucetTokenList[index].token).transfer(_address, faucetTokenList[index].amount);
            }
        }
    }

    function allowedToWithdraw(address _address) external view returns(bool){
        return _allowedToWithdraw(_address);
    }

    function getFaucetTokenList() external view returns (FaucetToken[] memory) {
        return faucetTokenList;
    }

    function updateFaucet(bool _disabled, address _token, uint256 _amount) external onlyOwner {
        uint256 tokenIndex = tokenIndexMapping[_token];
        require(_amount > 0, "Faucet Amount should gt 0");
        if(tokenIndex == 0) {
            FaucetToken memory ft = FaucetToken(_disabled, _token, _amount);
            faucetTokenList.push(ft);
            tokenIndexMapping[_token] = faucetTokenList.length - 1;
        } else{
            faucetTokenList[tokenIndex].disabled = _disabled;
            faucetTokenList[tokenIndex].amount = _amount;
        }
    }

    function updateWaitTime(uint256 _waitTime) external onlyOwner {
        require(_waitTime > 0, "WaitTime should gt 0");
        waitTime = _waitTime;
    }
}
