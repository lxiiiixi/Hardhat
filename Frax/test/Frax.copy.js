const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { days } = require("@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time/duration");
const { ethers } = require("hardhat");
const { Network, Alchemy, AlchemySubscription } = require('alchemy-sdk');

const settings = {
  apiKey: "Z2xliWVjYToNgU62-55w8-UuY28l79Zq",
  network: Network.ETH_MAINNET,
};
const alchemy = new Alchemy(settings);


describe("FRAX TEST", function () {
  async function deployFRAXStablecoin() {
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    const [Owner, TimeLockAdmin, Alice, Bob, ...Users] = await ethers.getSigners();

    // 部署 Timelock 合约
    const Timelock = await ethers.getContractFactory("Timelock");
    const timelockInstance = await Timelock.deploy(TimeLockAdmin.address, days(3));


    // 部署 WETH
    const WETH = await ethers.getContractFactory("WETH");
    const wethInstance = await WETH.deploy(Owner.address);
    // 部署 UniswapV2Factory
    const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factoryInstance = await UniswapV2Factory.deploy(Owner.address);
    // 部署 UniswapV2Router
    const UniswapV2Router02 = await ethers.getContractFactory("UniswapV2Router02");
    const routerInstance = await UniswapV2Router02.deploy(factoryInstance.address, wethInstance.address);



    // 部署 UniswapPairOracle 合约 (WETH-FRAX)
    const UniswapPairOracle = await ethers.getContractFactory("UniswapPairOracle");
    const oracleInstance = await UniswapPairOracle.deploy(factoryInstance.address, wethInstance.address, fraxInstance.address, Owner.address, timelockInstance.address);



    // 部署 FRAXStablecoin 合约
    const FRAXStablecoin = await ethers.getContractFactory("FRAXStablecoin");
    const fraxInstance = await FRAXStablecoin.deploy("Frax", "FRAX", Owner.address, timelockInstance.address);
    const genesis_supply = await fraxInstance.genesis_supply();
    // 初始化Chainlink预言机 => eth_usd_pricer
    const ChainlinkETHUSDPriceConsumer = await ethers.getContractFactory("ChainlinkETHUSDPriceConsumer");
    const chainlinkETHUSDPrice = await ChainlinkETHUSDPriceConsumer.deploy();
    await fraxInstance.setETHUSDOracle(chainlinkETHUSDPrice.address)
    // 设置Uniswap预言机 => fraxEthOracle(frax-weth)
    const UniswapPairOracle_FRAX_WETH = await ethers.getContractFactory("UniswapPairOracle_FRAX_WETH");
    // const uniswapUSDTWETHPriceOracle = await UniswapPairOracle_FRAX_WETH.deploy(factoryInstance.address, fraxInstance.address, wethInstance.address, Owner.address, timelockInstance.address);

    // await fraxInstance.setFRAXEthOracle(uniswapUSDTWETHPriceOracle.address, wethInstance.address);


    // 添加流动性（PairOralcle中需要流动性）
    const amount = genesis_supply.div(10); // 代币总量的一半
    await fraxInstance.approve(routerInstance.address, genesis_supply.div(9));
    await wethInstance.approve(routerInstance.address, genesis_supply.div(9));
    expect(await fraxInstance.allowance(Owner.address, routerInstance.address)).to.equal(genesis_supply.div(9));
    expect(await fraxInstance.balanceOf(Owner.address)).to.equal(genesis_supply);
    await routerInstance.addLiquidity(wethInstance.address, fraxInstance.address, amount, amount, 1, 1, Owner.address, 9876543210);




    // 部署 FRAXShares 合约
    const FRAXShares = await ethers.getContractFactory("FRAXShares");
    const fxsInstance = await FRAXShares.deploy("FRAXShares", "FXS", oracleInstance.address, Owner.address, timelockInstance.address);

    // 部署 collateral_token（ERC20）- USDC
    const CollateralToken1 = await ethers.getContractFactory("ERC20");
    const usdcInstance = await CollateralToken1.deploy("USDC", "USDC");

    // 部署 Pool_USDC 合约（USDC作为抵押物collateral_token）
    const Lib = await ethers.getContractFactory("FraxPoolLibrary");
    const lib = await Lib.deploy();
    await lib.deployed(); // 如果 libary 中全都是 internal 函数就不能单独部署（不太确定）
    // https://hardhat.org/hardhat-runner/plugins/nomiclabs-hardhat-ethers#library-linking
    const Pool_USDC = await ethers.getContractFactory("Pool_USDC", {
      libraries: {
        FraxPoolLibrary: lib.address,
      },
    });
    const poolUsdcInstance = await Pool_USDC.deploy(fraxInstance.address, fxsInstance.address, usdcInstance.address, Owner.address, timelockInstance.address, 1000000);


    return { fraxInstance, fxsInstance, timelockInstance, usdcInstance, poolUsdcInstance, factoryInstance, wethInstance, Owner, TimeLockAdmin, ZERO_ADDRESS, Alice, genesis_supply, amount };
  }

  // describe("Deploy and check some datas", function () {
  //   it("Should set the right creator_address and timelock_address", async function () {
  //     const { fraxInstance, timelockInstance, Owner } = await loadFixture(deployFRAXStablecoin);

  //     expect(await fraxInstance.creator_address()).to.equal(Owner.address);
  //     expect(await fraxInstance.timelock_address()).to.equal(timelockInstance.address);
  //   });

  //   it("Check the meta data", async function () {
  //     const { fraxInstance, Owner, genesis_supply, amount } = await loadFixture(deployFRAXStablecoin);

  //     expect(await fraxInstance.DEFAULT_ADMIN_ADDRESS()).to.equal(Owner.address);
  //     expect(await fraxInstance.owner_address()).to.equal(Owner.address);
  //     expect(await fraxInstance.totalSupply()).to.equal(genesis_supply);
  //     // expect(await fraxInstance.balanceOf(Owner.address)).to.equal(genesis_supply - amount);
  //     expect(await fraxInstance.frax_step()).to.equal(2500);
  //     expect(await fraxInstance.global_collateral_ratio()).to.equal(1000000);
  //     expect(await fraxInstance.refresh_cooldown()).to.equal(3600);
  //     expect(await fraxInstance.price_target()).to.equal(1000000);
  //     expect(await fraxInstance.price_band()).to.equal(5000);
  //   });

  //   it("Check initialized access control", async function () {
  //     const { fraxInstance, timelockInstance, Owner } = await loadFixture(deployFRAXStablecoin);
  //     const COLLATERAL_RATIO_PAUSER = await fraxInstance.COLLATERAL_RATIO_PAUSER();

  //     expect(await fraxInstance.hasRole(COLLATERAL_RATIO_PAUSER, Owner.address)).to.equal(true);
  //     expect(await fraxInstance.hasRole(COLLATERAL_RATIO_PAUSER, timelockInstance.address)).to.equal(true);
  //     expect(await fraxInstance.getRoleMemberCount(COLLATERAL_RATIO_PAUSER)).to.equal(2);
  //   });


  //   it("Should set the right timelock information", async function () {
  //     const { timelockInstance, TimeLockAdmin } = await loadFixture(deployFRAXStablecoin);

  //     expect(await timelockInstance.admin()).to.equal(TimeLockAdmin.address);
  //     expect(await timelockInstance.delay()).to.equal(days(3));
  //   });
  // });


  describe("Test pool", function () {
    it("Get price", async function () {
      const { fraxInstance, Owner, genesis_supply, amount } = await loadFixture(deployFRAXStablecoin);
      // expect(await fraxInstance.frax_price()).to.equal(Owner.address);
      // const frax_price = await fraxInstance.frax_price();
      const eth_usd_price = await fraxInstance.eth_usd_price();


      console.log(eth_usd_price);
      // console.log(frax_price, eth_usd_price);
    });
  });

  describe("Test pool", function () {
    it("Add and remove pool will be successful", async function () {
      const { fraxInstance, poolUsdcInstance } = await loadFixture(deployFRAXStablecoin);

      await fraxInstance.addPool(poolUsdcInstance.address);
      expect(await fraxInstance.frax_pools(poolUsdcInstance.address)).to.equal(true);

      await fraxInstance.removePool(poolUsdcInstance.address);
      expect(await fraxInstance.frax_pools(poolUsdcInstance.address)).to.equal(false);
    });

    // it("Test mint1t1FRAX while collateral ratio is 100%", async function () {
    //   const { fraxInstance, poolUsdcInstance, wethInstance, factoryInstance, usdcInstance, timelockInstance, Owner } = await loadFixture(deployFRAXStablecoin);
    //   await fraxInstance.addPool(poolUsdcInstance.address);

    //   // 部署 UniswapPairOracle_USDC_WETH
    //   // const UniswapPairOracle_USDC_WETH = await ethers.getContractFactory("UniswapPairOracle_USDC_WETH");
    //   // const oracleInstance = await UniswapPairOracle_USDC_WETH.deploy(factoryInstance.address, wethInstance.address, usdcInstance.address, Owner.address, timelockInstance.address);
    //   // console.log(factoryInstance.address);
    //   // console.log(wethInstance.address);
    //   // console.log(usdcInstance.address);
    //   // console.log(timelockInstance.address);
    //   // console.log(Owner.address);


    //   const uniswapOracleInstance = await ethers.getContractAt("UniswapPairOracle_USDT_WETH", "0xD18660Ab8d4eF5bE062652133fe4348e0cB996DA");
    //   await poolUsdcInstance.setCollatETHOracle(uniswapOracleInstance.address, wethInstance.address);

    //   const chainlinkETHUSDInstance = await ethers.getContractAt("ChainlinkETHUSDPriceConsumer", "0xBa6C6EaC41a24F9D39032513f66D738B3559f15a");


    //   // 给Frax设置 Oracle
    //   await fraxInstance.setETHUSDOracle(chainlinkETHUSDInstance.address);

    //   // const global_collateral_ratio = await fraxInstance.global_collateral_ratio()
    //   // const eth_usd_price = await fraxInstance.eth_usd_price()

    //   const CollatETHOracle = await poolUsdcInstance.getCollateralPrice()
    //   // await poolUsdcInstance.mint1t1FRAX(10000, 10)

    // });

  });

});



  // it("Should set the right owner", async function () {
    //   const { lock, owner } = await loadFixture(deployOneYearLockFixture);

    //   expect(await lock.owner()).to.equal(owner.address);
    // });

    // it("Should receive and store the funds to lock", async function () {
    //   const { lock, lockedAmount } = await loadFixture(
    //     deployOneYearLockFixture
    //   );

    //   expect(await ethers.provider.getBalance(lock.address)).to.equal(
    //     lockedAmount
    //   );
    // });

    // it("Should fail if the unlockTime is not in the future", async function () {
    //   // We don't use the fixture here because we want a different deployment
    //   const latestTime = await time.latest();
    //   const Lock = await ethers.getContractFactory("Lock");
    //   await expect(Lock.deploy(latestTime, { value: 1 })).to.be.revertedWith(
    //     "Unlock time should be in the future"
    //   );
    // });


      // describe("Withdrawals", function () {
  //   describe("Validations", function () {
  //     it("Should revert with the right error if called too soon", async function () {
  //       const { lock } = await loadFixture(deployOneYearLockFixture);

  //       await expect(lock.withdraw()).to.be.revertedWith(
  //         "You can't withdraw yet"
  //       );
  //     });

  //     it("Should revert with the right error if called from another account", async function () {
  //       const { lock, unlockTime, otherAccount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // We can increase the time in Hardhat Network
  //       await time.increaseTo(unlockTime);

  //       // We use lock.connect() to send a transaction from another account
  //       await expect(lock.connect(otherAccount).withdraw()).to.be.revertedWith(
  //         "You aren't the owner"
  //       );
  //     });

  //     it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
  //       const { lock, unlockTime } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // Transactions are sent using the first signer by default
  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).not.to.be.reverted;
  //     });
  //   });

  //   describe("Events", function () {
  //     it("Should emit an event on withdrawals", async function () {
  //       const { lock, unlockTime, lockedAmount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw())
  //         .to.emit(lock, "Withdrawal")
  //         .withArgs(lockedAmount, anyValue); // We accept any value as `when` arg
  //     });
  //   });

  //   describe("Transfers", function () {
  //     it("Should transfer the funds to the owner", async function () {
  //       const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).to.changeEtherBalances(
  //         [owner, lock],
  //         [lockedAmount, -lockedAmount]
  //       );
  //     });
  //   });
  // });