
### File: XVSVault.sol


(Empty elements in the table represent things that are not required or relevant)

contract: XVSVault is XVSVaultStorage, ECDSA, AccessControlledV5

| Index | Function | Visibility | Permission Check | Re-entrancy Check | Injection Check| Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|pause() |external| | | | |
|2|resume() |external| | | | |
|3|poolLength(address) |external| | | | |
|4|add(address,uint256,IBEP20,uint256,uint256) |external| | | | |
|5|set(address,uint256,uint256) |external| | | | |
|6|setRewardAmountPerBlock(address,uint256) |external| | | | |
|7|setWithdrawalLockingPeriod(address,uint256,uint256) |external| | | | |
|8|deposit(address,uint256,uint256) |external| | | | |
|9|claim(address,address,uint256) |external| | | | |
|10|executeWithdrawal(address,uint256) |external| | | | |
|11|requestWithdrawal(address,uint256,uint256) |external| | | | |
|12|getEligibleWithdrawalAmount(address,uint256,address) |external| | | | |
|13|getRequestedAmount(address,uint256,address) |external| | | | |
|14|getWithdrawalRequests(address,uint256,address) |external| | | | |
|15|pendingReward(address,uint256,address) |external| | | | |
|16|updatePool(address,uint256) |external| | | | |
|17|getUserInfo(address,uint256,address) |external| | | | |
|18|pendingWithdrawalsBeforeUpgrade(address,uint256,address) |public| | | | |
|19|delegate(address) |external| | | | |
|20|delegateBySig(address,uint,uint,uint8,bytes32,bytes32) |external| | | | |
|21|getCurrentVotes(address) |external| | | | |
|22|getPriorVotes(address,uint256) |external| | | | |
|23|getAdmin() |external| | | | |
|24|burnAdmin() |external| | | | |
|25|_become(IXVSVaultProxy) |external| | | | |
|26|setXvsStore(address,address) |external| | | | |
|27|setAccessControl(address) |external| | | | |
|28|accessControlManager() |external| | | | |



No Custom Interfaces


