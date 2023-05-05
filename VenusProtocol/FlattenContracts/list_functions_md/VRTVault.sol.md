### File: VRTVault.sol


(Empty elements in the table represent things that are not required or relevant)

contract: VRTVault is VRTVaultStorage, AccessControlledV5

| Index | Function | Visibility | Permission Check | Re-entrancy Check | Injection Check| Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|initialize(address,uint256) |public| | | | |
|2|pause() |external| | | | |
|3|resume() |external| | | | |
|4|deposit(uint256) |external| | | | |
|5|getAccruedInterest(address) |public| | | | |
|6|claim() |external| | | | |
|7|claim(address) |external| | | | |
|8|withdraw() |external| | | | |
|9|withdrawBep20(address,address,uint256) |external| | | | |
|10|setLastAccruingBlock(uint256) |external| | | | |
|11|getBlockNumber() |public| | | | |
|12|_become(IVRTVaultProxy) |external| | | | |
|13|setAccessControl(address) |external| | | | |
|14|accessControlManager() |external| | | | |



