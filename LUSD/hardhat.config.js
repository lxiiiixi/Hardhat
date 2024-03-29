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
      }, {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }, {
        version: "0.4.23",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }, {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }, {
        version: "0.6.6",
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
      },
    }
  }
};
