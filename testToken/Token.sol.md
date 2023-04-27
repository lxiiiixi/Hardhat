### File: contracts/Token.sol


(Empty elements in the table represent things that are not required or relevant)

contract: testToken is ERC20, ERC20Burnable, Ownable

| Index | Function | Visibility | Permission Check | Re-entrancy Check | Injection Check| Unit Test | Notes |
| :--: | :---- | :---- | :------ | :------ | :------ | :------ | :-- |
|1|claimStuckedER20(address) |external| onlyOwner | | | Passed ||
|2|owner() |public| | | | Passed |view|
|3|renounceOwnership() |public| onlyOwner | | | Passed ||
|4|transferOwnership(address) |public| onlyOwner | | | Passed ||
|5|burn(uint256) |public| | | | Passed ||
|6|burnFrom(address,uint256) |public| | | | Passed ||
|7|name() |public| | | | Passed |view|
|8|symbol() |public| | | | Passed |view|
|9|decimals() |public| | | | Passed |view|
|10|totalSupply() |public| | | | Passed |view|
|11|balanceOf(address) |public| | | | Passed |view|
|12|transfer(address,uint256) |public| | | | Passed ||
|13|allowance(address,address) |public| | | | Passed |view|
|14|approve(address,uint256) |public| | | | Passed ||
|15|transferFrom(address,address,uint256) |public| | | | Passed ||
|16|increaseAllowance(address,uint256) |public| | | | Passed ||
|17|decreaseAllowance(address,uint256) |public| | | | Passed ||







