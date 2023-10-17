require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.9",
  networks: {
    hardhat: {
      chainId: 43114,
      forking: {
        enabled: true,
        url: "https://fluent-quaint-lambo.avalanche-mainnet.quiknode.pro/8d3e82362b0c12d4f08591857852449c3cf4fc7c/ext/bc/C/rpc/",
        blockNumber: 36136400 // 36136406
      },
    }
  }
};
