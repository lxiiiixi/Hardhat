### File: contracts/OCD.sol


(Empty fields in the table represent things that are not required or relevant)

contract: OCD is Context, IERC20, Ownable, ReentrancyGuard

| Index | Function | Visibility | StateMutability | Permission Check | IsUserInterface | Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|setIncludeOrExcludeFromFee(address,bool)|external||onlyOwner| | <font color="green">Passed</font> | |
|2|updateSwapAmount(uint256)|external||onlyOwner| | <font color="green">Passed</font> | |
|3|updateBuyFee(uint256)|external||onlyOwner| | <font color="green">Passed</font> | |
|4|updateSellFee(uint256)|external||onlyOwner| | <font color="green">Passed</font> | |
|5|setDistributionStatus(bool)|external||onlyOwner| | <font color="green">Passed</font> | |
|6|enableOrDisableFees(bool)|external||onlyOwner| | <font color="green">Passed</font> | |
|7|updatemarketWallet(address)|external||onlyOwner| | <font color="green">Passed</font> | |
|8|receive()|external|payable|| | <font color="green">Passed</font> | |
|9|name()|public|view|| | <font color="green">Passed</font> | |
|10|symbol()|public|view|| | <font color="green">Passed</font> | |
|11|decimals()|public|view|| | <font color="green">Passed</font> | |
|12|totalSupply()|public|view|| | <font color="green">Passed</font> | |
|13|balanceOf(address)|public|view|| | <font color="green">Passed</font> | |
|14|transfer(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|15|allowance(address,address)|public|view|| | <font color="green">Passed</font> | |
|16|approve(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|17|transferFrom(address,address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|18|increaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|19|decreaseAllowance(address,uint256)|public||| Yes | <font color="green">Passed</font> | |
|20|totalBuyFeePerTx(uint256)|public|view|| | <font color="green">Passed</font> | |
|21|totalSellFeePerTx(uint256)|public|view|| | <font color="green">Passed</font> | |
|22|withdrawETH(uint256)|external||onlyOwner| | <font color="green">Passed</font> | |
|23|owner()|public|view|| | <font color="green">Passed</font> | |
|24|renounceOwnership()|public||onlyOwner| | <font color="green">Passed</font> | |
|25|transferOwnership(address)|public||onlyOwner| | <font color="green">Passed</font> | |



