require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.15",
  networks: {
    hardhat: {
      forking: {
        enabled: true,
        url: "https://eth-mainnet.g.alchemy.com/v2/Z2xliWVjYToNgU62-55w8-UuY28l79Zq",
        blockNumber: 13715025
      },
    }
  }
};
