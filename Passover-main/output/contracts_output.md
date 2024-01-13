### File: contracts/INS20.sol

contract: INS20 is IERC7583, ERC721, Ownable, IERC20, IERC2981

(Empty fields in the table represent things that are not required or relevant)


| Index | Function | StateMutability | Modifier | Param Check | IsUserInterface | Unit Test | Miscellaneous |
| :-: | :----- | :-- | :------ | :--- | :--- | :--- | :------ |
|1|inscribe(uint256,bytes32[])||`recordSlot(address(0),, msg.sender,, tokenId)`| | Yes | <font color="green">Passed</font> | |
|2|balanceOf(address)|view|| | | <font color="green">Passed</font> | |
|3|decimals()|pure|| | | <font color="green">Passed</font> | |
|4|totalSupply()|view|| | | <font color="green">Passed</font> | |
|5|allowance(address,address)|view|| | | <font color="green">Passed</font> | |
|6|approve(address,uint256)||| | Yes | <font color="green">Passed</font> | |
|7|transfer(address,uint256)||| | Yes | <font color="green">Passed</font> | |
|8|waterToWine(uint256,uint256,uint256)||| | Yes | <font color="green">Passed</font> | |
|9|transferFrom(address,address,uint256)||| | Yes | <font color="green">Passed</font> | |
|10|safeTransferFrom(address,address,uint256)||| | Yes | <font color="green">Passed</font> | |
|11|safeTransferFrom(address,address,uint256,bytes)||`recordSlot(from,, to,, tokenId)`| | Yes | <font color="green">Passed</font> | |
|12|tokenURI(uint256)|view|| | | <font color="green">Passed</font> | |
|13|royaltyInfo(uint256,uint256)|view|| | | <font color="green">Passed</font> | |
|14|setMerkleRoot(bytes32)||`onlyOwner`| | | <font color="green">Passed</font> | |
|15|openFT()||`onlyOwner`| | | <font color="green">Passed</font> | |
|16|openInscribe()||`onlyOwner`| | | <font color="green">Passed</font> | |
|17|setRoyaltyRecipient(address)||`onlyOwner`| | | <font color="green">Passed</font> | |





### File: contracts/Passover.sol

contract: Passover is ERC20, IERC7583, Ownable, Pausable

(Empty fields in the table represent things that are not required or relevant)


| Index | Function | StateMutability | Modifier | Param Check | IsUserInterface | Unit Test | Miscellaneous |
| :-: | :----- | :-- | :------ | :--- | :--- | :--- | :------ |
|1|claimLossesDirect(uint256,uint256,bytes32,uint256,bytes32[])||`whenNotPaused`| | Yes | <font color="green">Passed</font> | |
|2|refund(uint256,uint256,bytes32,uint256,bytes32[])|payable|`whenNotPaused`| | Yes | <font color="green">Passed</font> | |
|3|claimLossesAfterRefund(uint256,uint256,bytes32,uint256,bytes32[])||`whenNotPaused`| | Yes | <font color="green">Passed</font> | |
|4|setClaimLossesDirectRoot(bytes32)||`onlyOwner`| | | <font color="green">Passed</font> | |
|5|setRefundRoot(bytes32)||`onlyOwner`| | | <font color="green">Passed</font> | |
|6|setClaimLossesAfterRefundRoot(bytes32)||`onlyOwner`| | | <font color="green">Passed</font> | |
|7|pause()||`onlyOwner`| | | <font color="green">Passed</font> | |
|8|unpause()||`onlyOwner`| | | <font color="green">Passed</font> | |




