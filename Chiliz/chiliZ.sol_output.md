### File: contracts/chiliZ.sol


(Empty fields in the table represent things that are not required or relevant)

contract: chiliZ is ERC20, ERC20Detailed, ERC20Pausable

| Index | Function | Visibility | StateMutability | Permission Check | IsUserInterface | Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|transfer(address,uint256)|public||| Yes | <font color="green">Passed</font> | whenNotPaused |
|2|transferFrom(address,address,uint256)|public||| Yes | <font color="green">Passed</font> | whenNotPaused |
|3|approve(address,uint256)|public||| Yes | <font color="green">Passed</font> | whenNotPaused |
|6|paused()|public|view|| | <font color="green">Passed</font> | |
|7|pause()|public||| | <font color="green">Passed</font> | onlyPauser、whenNotPaused |
|8|unpause()|public||| | <font color="green">Passed</font> | onlyPauser、whenNotPaused |
|9|isPauser(address)|public|view|| | <font color="green">Passed</font> | |
|10|addPauser(address)|public||| | <font color="green">Passed</font> | onlyPauser |
|11|renouncePauser()|public||| | <font color="green">Passed</font> | onlyPauser |
|12|totalSupply()|public|view|| | <font color="green">Passed</font> | |
|13|balanceOf(address)|public|view|| | <font color="green">Passed</font> | |
|14|allowance(address,address)|public|view|| | <font color="green">Passed</font> | |
|15|increaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | whenNotPaused |
|16|decreaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | whenNotPaused |
|17|name()|public|view|| | <font color="green">Passed</font> | |
|18|symbol()|public|view|| | <font color="green">Passed</font> | |
|19|decimals()|public|view|| | <font color="green">Passed</font> | |



