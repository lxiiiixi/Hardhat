### File: contracts/MdxToken.sol

(Empty fields in the table represent things that are not required or relevant)

contract: MdxToken is ERC20Votes, Ownable

| Index | Function              | Visibility | StateMutability | Permission Check | IsUserInterface | Unit Test                        | Notes |
| :---: | :-------------------- | :--------- | :-------------- | :--------------- | :-------------- | :------------------------------- | :---- |
|   1   | mint(address,uint256) | external   |                 | onlyMiner        |                 | <font color=green> Passed</font> |       |
|   2   | addMiner(address)     | external   |                 | onlyOwner        |                 | <font color=green> Passed</font> |       |
|   3   | delMiner(address)     | external   |                 | onlyOwner        |                 | <font color=green> Passed</font> |       |
|   4   | getMinerLength()      | public     | view            |                  | yes             | <font color=green> Passed</font> |       |
|   5   | isMiner(address)      | public     | view            |                  | yes             | <font color=green> Passed</font> |       |
|   6   | getMiner(uint256)     | external   | view            | onlyOwner        |                 | <font color=green> Passed</font> |       |
