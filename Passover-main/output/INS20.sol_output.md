
### File: contracts/INS20.sol
contract: INS20 is IERC7583, ERC721, Ownable, IERC20, IERC2981

(Empty fields in the table represent things that are not required or relevant)


| Index | Function | StateMutability | Modifier | Param Check | IsUserInterface | Unit Test | Miscellaneous |
| :-: | :----- | :-- | :------ | :--- | :--- | :--- | :------ |
|1|inscribe(uint256,bytes32[])||`recordSlot(address(0),, msg.sender,, tokenId)`| | | | |
|2|balanceOf(address)|view|| | | | |
|3|decimals()|pure|| | | | |
|4|totalSupply()|view|| | | | |
|5|allowance(address,address)|view|| | | | |
|6|approve(address,uint256)||| | | | |
|7|transfer(address,uint256)||| | | | |
|8|waterToWine(uint256,uint256,uint256)||| | | | |
|9|transferFrom(address,address,uint256)||| | | | |
|10|safeTransferFrom0(address,address,uint256,bytes)||`recordSlot(from,, to,, tokenId)`| | | | |
|11|tokenURI(uint256)|view|| | | | |
|12|royaltyInfo(uint256,uint256)|view|| | | | |
|13|setMerkleRoot(bytes32)||`onlyOwner`| | | | |
|14|openFT()||`onlyOwner`| | | | |
|15|openInscribe()||`onlyOwner`| | | | |
|16|setRoyaltyRecipient(address)||`onlyOwner`| | | | |




