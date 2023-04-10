require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.11",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.4.24",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        url: "https://eth-mainnet.g.alchemy.com/v2/Z2xliWVjYToNgU62-55w8-UuY28l79Zq",
        // blockNumber: 14913700  // 如果不设置默认就是当前最新的区块
      },
    }
  }
};