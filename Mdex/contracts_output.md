### File: contracts/MdxToken.sol

(Empty fields in the table represent things that are not required or relevant)

contract: MdxToken is ERC20Votes, Ownable

| Index | Function              | Visibility | StateMutability | Permission Check | IsUserInterface | Unit Test | Notes |
| :---: | :-------------------- | :--------- | :-------------- | :--------------- | :-------------- | :-------- | :---- |
|   1   | mint(address,uint256) | external   |                 | onlyMiner        |                 | pass      |       |
|   2   | addMiner(address)     | external   |                 | onlyOwner        |                 | pass      |       |
|   3   | delMiner(address)     | external   |                 | onlyOwner        |                 | pass      |       |
|   4   | getMinerLength()      | public     | view            |                  | yes             | pass      |       |
|   5   | isMiner(address)      | public     | view            |                  | yes             | pass      |       |
|   6   | getMiner(uint256)     | external   | view            | onlyOwner        |                 | pass      |       |
