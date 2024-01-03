### File: contracts/Inscription.sol

contract: INS20 is IERC20, ERC721

(Empty fields in the table represent things that are not required or relevant)


| Index | Function | StateMutability | Modifier | Param Check | IsUserInterface | Unit Test | Miscellaneous |
| :-: | :----- | :-- | :------ | :--- | :--- | :--- | :------ |
|1|inscribe(bytes)||| | Yes | <font color="green">Passed</font> | |
|2|symbol()|view|| | | <font color="green">Passed</font> | |
|3|decimals()|view|| | | <font color="green">Passed</font> | |
|4|totalSupply()|view|| | | <font color="green">Passed</font> | |
|5|balanceOf(address)|view|| | | <font color="green">Passed</font> | |
|6|allowance(address,address)|view|| | | <font color="green">Passed</font> | |
|7|approve(address,uint256)||| | Yes | <font color="green">Passed</font> | |
|8|setApprovalForAll(address,bool)||| | Yes | <font color="green">Passed</font> | |
|9|transfer(address,uint256)||| | Yes | <font color="green">Passed</font> | |
|10|transferFrom(address,address,uint256)||| | Yes | <font color="green">Passed</font> | |
|11|safeTransferFrom(address,address,uint256)||| | Yes | <font color="green">Passed</font> | |
|12|safeTransferFrom(address,address,uint256,bytes)||| | Yes | <font color="green">Passed</font> | |
|13|toFT()||| | | <font color="green">Passed</font> | Only msg.sender is proxy |
|14|tokenURI(uint256)|view|| | | <font color="green">Passed</font> | |



