### File: contracts/BEP20TokenImplementation.sol


(Empty fields in the table represent things that are not required or relevant)

contract: BEP20TokenImplementation is Context, IBEP20, Initializable

| Index | Function | Visibility | StateMutability | Permission Check | IsUserInterface | Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|initialize(string,string,uint8,uint256,bool,address)|public||| | | 这个方法由代理合约调用 |
|2|renounceOwnership()|public||onlyOwner| | <font color="green">Passed</font> | |
|3|transferOwnership(address)|public||onlyOwner| | <font color="green">Passed</font> | |
|4|mintable()|external|view|| | <font color="green">Passed</font> | |
|5|getOwner()|external|view|| | <font color="green">Passed</font> | |
|6|decimals()|external|view|| | <font color="green">Passed</font> | |
|7|symbol()|external|view|| | <font color="green">Passed</font> | |
|8|name()|external|view|| | <font color="green">Passed</font> | |
|9|totalSupply()|external|view|| | <font color="green">Passed</font> | |
|10|balanceOf(address)|external|view|| | <font color="green">Passed</font> | |
|11|transfer(address,uint256)|external||| Yes | <font color="green">Passed</font> | |
|12|allowance(address,address)|external|view|| | <font color="green">Passed</font> | |
|13|approve(address,uint256)|external||| Yes | <font color="green">Passed</font> | |
|14|transferFrom(address,address,uint256)|external||| Yes | <font color="green">Passed</font> | |
|15|increaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|16|decreaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|17|mint(uint256)|public||onlyOwner| | <font color="green">Passed</font> | |
|18|burn(uint256)|public||| Yes | | |



