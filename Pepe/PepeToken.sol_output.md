
### File: contracts/PepeToken.sol


(Empty fields in the table represent things that are not required or relevant)

contract: PepeToken is Ownable, ERC20

| Index | Function | Visibility | StateMutability | Permission Check | IsUserInterface | Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|blacklist(address,bool)|external||onlyOwner| | <font color="green">Passed</font> | |
|2|setRule(bool,address,uint256,uint256)|external||onlyOwner| | <font color="green">Passed</font> | |
|3|burn(uint256)|external||| Yes | <font color="green">Passed</font> | |
|4|name()|public|view||  | <font color="green">Passed</font> | |
|5|symbol()|public|view||  | <font color="green">Passed</font> | |
|6|decimals()|public|view||  | <font color="green">Passed</font> | |
|7|totalSupply()|public|view||  | <font color="green">Passed</font> | |
|8|balanceOf(address)|public|view||  | <font color="green">Passed</font> | |
|9|transfer(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|10|allowance(address,address)|public|view||  | <font color="green">Passed</font> | |
|11|approve(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|12|transferFrom(address,address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|13|increaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|14|decreaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|15|owner()|public|view||  | <font color="green">Passed</font> | |
|16|renounceOwnership()|public||onlyOwner| | <font color="green">Passed</font> | |
|17|transferOwnership(address)|public||onlyOwner| | <font color="green">Passed</font> | |



