
### File: contracts/DOGECEO.sol
contract: DOGECEO is Context, IBEP20, Ownable

(Empty fields in the table represent things that are not required or relevant)


| Index | Function | StateMutability | Modifier | Param Check | IsUserInterface | Unit Test | Miscellaneous |
| :-: | :----- | :-- | :------ | :--- | :--- | :--- | :------ |
|1|name()|pure|| | | | |
|2|symbol()|pure|| | | | |
|3|decimals()|pure|| | | | |
|4|totalSupply()|view|| | | | |
|5|balanceOf(address)|view|| | | | |
|6|allowance(address,address)|view|| | | | |
|7|approve(address,uint256)||| | | | |
|8|transferFrom(address,address,uint256)||| | | | |
|9|increaseAllowance(address,uint256)||| | | | |
|10|decreaseAllowance(address,uint256)||| | | | |
|11|transfer(address,uint256)||| | | | |
|12|isExcludedFromReward(address)|view|| | | | |
|13|reflectionFromToken(uint256,bool)|view|| | | | |
|14|tokenFromReflection(uint256)|view|| | | | |
|15|excludeFromReward(address)||`onlyOwner`| | | | |
|16|includeInReward(address)||`onlyOwner`| | | | |
|17|excludeFromFee(address)||`onlyOwner`| | | | |
|18|includeInFee(address)||`onlyOwner`| | | | |
|19|isExcludedFromFee(address)|view|| | | | |
|20|bulkExcludeFee(address[],bool)||`onlyOwner`| | | | |
|21|receive()|payable|| | | | |
|22|owner()|view|| | | | |
|23|renounceOwnership()||`onlyOwner`| | | | |




