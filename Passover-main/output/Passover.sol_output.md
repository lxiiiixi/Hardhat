
### File: contracts/Passover.sol
contract: Passover is ERC20, IERC7583, Ownable, Pausable

(Empty fields in the table represent things that are not required or relevant)


| Index | Function | StateMutability | Modifier | Param Check | IsUserInterface | Unit Test | Miscellaneous |
| :-: | :----- | :-- | :------ | :--- | :--- | :--- | :------ |
|1|claimLossesDirect(uint256,uint256,bytes32,uint256,bytes32[])||`whenNotPaused`| | | | |
|2|refund(uint256,uint256,bytes32,uint256,bytes32[])|payable|`whenNotPaused`| | | | |
|3|claimLossesAfterRefund(uint256,uint256,bytes32,uint256,bytes32[])||`whenNotPaused`| | | | |
|4|setClaimLossesDirectRoot(bytes32)||`onlyOwner`| | | | |
|5|setRefundRoot(bytes32)||`onlyOwner`| | | | |
|6|setClaimLossesAfterRefundRoot(bytes32)||`onlyOwner`| | | | |
|7|pause()||`onlyOwner`| | | | |
|8|unpause()||`onlyOwner`| | | | |




