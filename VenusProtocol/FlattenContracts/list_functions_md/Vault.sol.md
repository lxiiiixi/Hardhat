
### File: Vault.sol

No Custom Interfaces


(Empty elements in the table represent things that are not required or relevant)

contract: VAIVault is VAIVaultStorage, AccessControlledV5

| Index | Function | Visibility | Permission Check | Re-entrancy Check | Injection Check| Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|pause() |external| | | | ||
|2|resume() |external| | | | ||
|3|deposit(uint256) |external| | | | ||
|4|withdraw(uint256) |external| | | | ||
|5|claim() |external| | | | ||
|6|claim(address) |external| | | | ||
|7|pendingXVS(address) |public| | | | ||
|8|updatePendingRewards() |external| | | | ||
|9|getAdmin() |external| | | | ||
|10|burnAdmin() |external| | | | ||
|11|setNewAdmin(address) |external| | | | ||
|12|_become(IVAIVaultProxy) |external| onlyAdmin | |  | pass ||
|13|setVenusInfo(address,address) |external| onlyAdmin | | | ||
|14|setAccessControl(address) |external| | | | ||
|15|accessControlManager() |external| | | | ||


