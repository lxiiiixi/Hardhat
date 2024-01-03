require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      // {
      //   version: "0.8.17",
      //   settings: {
      //     optimizer: {
      //       enabled: true,
      //       runs: 200
      //     }
      //   }
      // }, {
      //   version: "0.6.6",
      //   settings: {
      //     optimizer: {
      //       enabled: true,
      //       runs: 200
      //     }
      //   }
      // },
      // {
      //   version: "0.8.22",
      //   settings: {
      //     optimizer: {
      //       enabled: true,
      //       runs: 200
      //     }
      //   }
      // },
      // {
      //   version: "0.8.20",
      //   settings: {
      //     optimizer: {
      //       enabled: true,
      //       runs: 200
      //     }
      //   }
      // },
      // {
      //   version: "0.5.16",
      //   settings: {
      //     optimizer: {
      //       enabled: true,
      //       runs: 200
      //     }
      //   }
      // },
      // {
      //   version: "0.4.18",
      //   settings: {
      //     optimizer: {
      //       enabled: true,
      //       runs: 200
      //     }
      //   }
      // }
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
  // networks: {
  //   hardhat: {
  //     chainId: 56,
  //     forking: {
  //       enabled: true,
  //       url: "https://autumn-dawn-arm.bsc.quiknode.pro/7091c37d7b6798e83e23207a78ee6e8d9ad0624d/",
  //       blockNumber: 34030376 // 34030376
  //     },
  //   }
  // }
};
