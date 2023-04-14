const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { days } = require("@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time/duration");
const { ethers } = require("hardhat");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("FRAX TEST", function () {
  async function deployFRAXStablecoin() {
    const [Owner, Creator, TimeLockAdmin, Alice, Bob, ...Users] = await ethers.getSigners();

    // 部署时间锁合约
    const Timelock = await ethers.getContractFactory("Timelock");
    const TimelockInstance = await Timelock.deploy(TimeLockAdmin.address, days(3));

    // 部署 WETH
    // const WETH = await ethers.getContractFactory("WETH");
    // const WethInstance = await WETH.deploy(Creator.address);
    const WethInstance = await ethers.getContractAt("WETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");

    // 部署 UniswapV2Factory
    const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factoryInstance = await UniswapV2Factory.deploy(Creator.address);

    // 部署 Frax 并初始化一些参数
    const FRAXStablecoin = await ethers.getContractFactory("FRAXStablecoin");
    const FraxInstance = await FRAXStablecoin.deploy("Frax", "FRAX", Creator.address, TimelockInstance.address);
    await FraxInstance.connect(Creator).setOwner(Owner.address);
    const frax_genesis_supply = await FraxInstance.genesis_supply();

    // 部署并初始化Chainlink预言机
    const ChainlinkETHUSDPriceConsumer = await ethers.getContractFactory("ChainlinkETHUSDPriceConsumer");
    const ChainlinkETHUSDPrice = await ChainlinkETHUSDPriceConsumer.deploy();

    // 部署 fxs
    const FRAXShares = await ethers.getContractFactory("FRAXShares");
    const FxsInstance = await FRAXShares.deploy("FRAXShares", "FXS", Alice.address, Owner.address, TimelockInstance.address);
    const fxs_genesis_supply = await FxsInstance.genesis_supply();

    // 部署 Frax-Weth Oralce (需要创建pair并且添加流动性)
    // const UniswapPairOracle_FRAX_WETH = await ethers.getContractFactory("UniswapPairOracle_FRAX_WETH");
    // // await factoryInstance.createPair(FraxInstance.address, WethInstance.address);
    // const FraxWethOralceInstance = await UniswapPairOracle_FRAX_WETH.deploy(factoryInstance.address, FraxInstance.address, WethInstance.address, Owner.address, TimelockInstance.address);

    // Frax-Weth 和 FXS-Weth Oralce 实例（直接fork主网数据）
    // const FraxWethOralceInstance = await ethers.getContractAt("UniswapPairOracle_FRAX_WETH", "0x2A6ddD9401B14d0443d0738B8a78fd5B99829A80");
    // const FxsWethOralceInstance = await ethers.getContractAt("UniswapPairOracle_FXS_WETH", "0x3B11DA52030420c663d263Ad4415a8A02E5f8cf8");
    const FraxWethOralceInstance = await ethers.getContractAt("FRAXOracleWrapper", "0x2A6ddD9401B14d0443d0738B8a78fd5B99829A80");
    const FxsWethOralceInstance = await ethers.getContractAt("UniswapPairOracle_USDT_WETH", "0x9e483C76D7a66F7E1feeBEAb54c349Df2F00eBdE");

    // 给 Frax 设置 Frax-Weth oracle、 ETH-USD oracle、
    await FraxInstance.setFXSAddress(FxsInstance.address)
    await FraxInstance.setETHUSDOracle(ChainlinkETHUSDPrice.address)
    await FraxInstance.setFRAXEthOracle(FraxWethOralceInstance.address, WethInstance.address);
    await FraxInstance.setFXSEthOracle(FxsWethOralceInstance.address, WethInstance.address)


    const UsdcInstance = await ethers.getContractAt("FiatTokenProxy", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
    const Lib = await ethers.getContractFactory("FraxPoolLibrary");
    const lib = await Lib.deploy();
    await lib.deployed(); // 如果 libary 中全都是 internal 函数就不能单独部署（不太确定）
    // https://hardhat.org/hardhat-runner/plugins/nomiclabs-hardhat-ethers#library-linking
    const Pool_USDC = await ethers.getContractFactory("Pool_USDC", {
      libraries: {
        FraxPoolLibrary: lib.address,
      },
    });
    const Pool_USDCInstance = await Pool_USDC.deploy(FraxInstance.address, FxsInstance.address, UsdcInstance.address, Owner.address, TimelockInstance.address, 100000000);


    return {
      instance: { FraxInstance, TimelockInstance, FxsInstance, WethInstance, Pool_USDCInstance },
      oracle: { ChainlinkETHUSDPrice, FraxWethOralceInstance, FxsWethOralceInstance },
      users: { Owner, Creator, Alice, TimeLockAdmin },
      data: { frax_genesis_supply, fxs_genesis_supply }
    };
  }

  describe("Deploy and check some datas", async function () {
    it("Check the meta data of frax", async function () {
      const { instance, oracle, users, data } = await loadFixture(deployFRAXStablecoin);
      const { FraxInstance, TimelockInstance, FxsInstance, WethInstance } = instance;
      const { FraxWethOralceInstance, ChainlinkETHUSDPrice, FxsWethOralceInstance } = oracle;
      const { Owner, Creator, TimeLockAdmin } = users;
      const { frax_genesis_supply } = data;

      expect(await FraxInstance.DEFAULT_ADMIN_ADDRESS()).to.equal(Owner.address);
      expect(await FraxInstance.owner_address()).to.equal(Owner.address);
      expect(await FraxInstance.timelock_address()).to.equal(TimelockInstance.address);
      expect(await FraxInstance.totalSupply()).to.equal(frax_genesis_supply);
      expect(await FraxInstance.controller_address()).to.equal(ZERO_ADDRESS);
      expect(await FraxInstance.balanceOf(Creator.address)).to.equal(frax_genesis_supply);

      expect(await FraxInstance.frax_eth_oracle_address()).to.equal(FraxWethOralceInstance.address);
      expect(await FraxInstance.fxs_eth_oracle_address()).to.equal(FxsWethOralceInstance.address);
      expect(await FraxInstance.eth_usd_consumer_address()).to.equal(ChainlinkETHUSDPrice.address);
      expect(await FraxInstance.weth_address()).to.equal(WethInstance.address);
      expect(await FraxInstance.fxs_address()).to.equal(FxsInstance.address);
    });
  });

  describe("Oracle data test", async function () {
    it("Oracle data test", async function () {
      const { instance, oracle, users, data } = await loadFixture(deployFRAXStablecoin);
      const { FraxInstance, TimelockInstance, FxsInstance, WethInstance } = instance;
      const { FraxWethOralceInstance, ChainlinkETHUSDPrice, FxsWethOralceInstance } = oracle;

      const eth_usd_price = await FraxInstance.eth_usd_price();
      const frax_price = await FraxInstance.frax_price();
      const fxs_price = await FraxInstance.fxs_price();

      console.log(eth_usd_price);
      console.log(frax_price);
      console.log(fxs_price);
    });
  });

  describe("Test refreshCollateralRatio function", async function () {
    it("Function can't be called during the interval", async function () {
      const { instance } = await loadFixture(deployFRAXStablecoin);
      const { FraxInstance } = instance;
      const ONE_HOUR_IN_SECONDS = 3600;
      expect(await FraxInstance.refresh_cooldown()).to.equal(3600);

      await FraxInstance.refreshCollateralRatio();
      await time.increase(1000);
      await expect(FraxInstance.refreshCollateralRatio()).to.be.revertedWith("Must wait for the refresh cooldown since last refresh");
      await time.increase(ONE_HOUR_IN_SECONDS);
      await FraxInstance.refreshCollateralRatio();
    });


    it("Collateral ratio should get a correct solution", async function () {
      const { instance, oracle, users, data } = await loadFixture(deployFRAXStablecoin);
      const { FraxInstance, TimelockInstance, FxsInstance, WethInstance } = instance;
      const { FraxWethOralceInstance, ChainlinkETHUSDPrice, FxsWethOralceInstance } = oracle;
      const { Owner, Creator, TimeLockAdmin } = users;

      const ONE_HOUR_IN_SECONDS = 3600;
      const price_target = await FraxInstance.price_target();
      const price_band = await FraxInstance.price_band();
      const frax_price_cur = await FraxInstance.frax_price();
      const global_collateral_ratio = await FraxInstance.global_collateral_ratio();
      const frax_step = await FraxInstance.frax_step();

      expect(await price_target).to.equal(1000000);
      expect(await price_band).to.equal(5000);
      expect(await global_collateral_ratio).to.equal(1000000);
      expect(await frax_step).to.equal(2500);

      function getCollateralRatio(price_target, price_band, frax_price_cur, global_collateral_ratio, frax_step) {
        // frax_price_cur > price_target + price_band   =>   增加 global_collateral_ratio 并使其不超过 1000000
        if (frax_price_cur.lt(price_target.sub(price_band)))
          if (global_collateral_ratio.add(frax_step).gt(1000000)) {
            global_collateral_ratio = 1000000;
          } else {
            global_collateral_ratio = global_collateral_ratio.add(frax_step);
          }
        // frax_price_cur > price_target + price_band   =>   减少 global_collateral_ratio 并使其不低于 0
        else if (frax_price_cur.gt(price_target.add(price_band)))
          if (global_collateral_ratio.lt(frax_step)) {
            global_collateral_ratio = 0;
          } else {
            global_collateral_ratio = global_collateral_ratio.sub(frax_step);
          }
        return ethers.BigNumber.from(global_collateral_ratio);
      }
      await FraxInstance.refreshCollateralRatio();
      expect(await FraxInstance.global_collateral_ratio()).to.equal(getCollateralRatio(price_target, price_band, frax_price_cur, global_collateral_ratio, frax_step));

      await time.increase(ONE_HOUR_IN_SECONDS + 100);
      await FraxInstance.setPriceBand(10000)
      expect(await FraxInstance.global_collateral_ratio()).to.equal(getCollateralRatio(price_target, price_band, frax_price_cur, global_collateral_ratio, frax_step));
    });
  });

  describe("FXS test", async function () {
    it("Check the meta data of FRAXShares", async function () {
      const { instance, users, data } = await loadFixture(deployFRAXStablecoin);
      const { TimelockInstance, FxsInstance } = instance;
      const { Owner } = users;
      const { fxs_genesis_supply } = data;

      expect(await FxsInstance.name()).to.equal("FRAXShares");
      expect(await FxsInstance.owner_address()).to.equal(Owner.address);
      expect(await FxsInstance.timelock_address()).to.equal(TimelockInstance.address);
      expect(await FxsInstance.totalSupply()).to.equal(fxs_genesis_supply);
      expect(await FxsInstance.balanceOf(Owner.address)).to.equal(fxs_genesis_supply);
    });

    it("Test transfer and transferFrom", async function () {
      const { instance, users, data } = await loadFixture(deployFRAXStablecoin);
      const { FxsInstance } = instance;
      const { Owner, Creator, Alice } = users;
      const { fxs_genesis_supply } = data;

      expect(await FxsInstance.balanceOf(Owner.address)).to.equal(fxs_genesis_supply);
      await FxsInstance.transfer(Creator.address, 1000000);
      expect(await FxsInstance.balanceOf(Creator.address)).to.equal(1000000);
      expect(await FxsInstance.balanceOf(Owner.address)).to.equal(fxs_genesis_supply.sub(1000000));
      await expect(FxsInstance.transferFrom(Creator.address, Alice.address, 1000000)).to.revertedWith("ERC20: transfer amount exceeds allowance")
      await FxsInstance.connect(Creator).approve(Owner.address, 1000000);
      await FxsInstance.transferFrom(Creator.address, Alice.address, 1000000);
      expect(await FxsInstance.balanceOf(Creator.address)).to.equal(0);
      expect(await FxsInstance.balanceOf(Alice.address)).to.equal(1000000);

      const votes = await FxsInstance.getCurrentVotes(Creator.address);
      // const Priorvotes = await FxsInstance.getPriorVotes(Creator.address);
      console.log("votes: ", votes.toString());

      const numCheckpoints = await FxsInstance.numCheckpoints(Creator.address);
      const Checkpoint = await FxsInstance.checkpoints(Creator.address, numCheckpoints - 1);
      console.log(Checkpoint, numCheckpoints);
    });
  });

  describe("Pool test", async function () {
    it("Check the meta data of FRAXShares", async function () {
      const { instance, oracle, users } = await loadFixture(deployFRAXStablecoin);
      const { TimelockInstance, FraxInstance, Pool_USDCInstance, WethInstance } = instance;
      const { FxsWethOralceInstance } = oracle
      const { Owner } = users;

      // const Pool_USDCInstance = await ethers.getContractAt("Pool_USDC", "0x1864Ca3d47AaB98Ee78D11fc9DCC5E7bADdA1c0d");


      // await FraxInstance.addPool(Pool_USDCInstance.address)
      // expect(await FraxInstance.frax_pools(Pool_USDCInstance.address)).to.equal(true);

      // mint 之前需要设置 oracle，才能通过 getCollateralPrice() 计算价格，才能mint
      // USDC-ETH
      // const UsdcWethOralceInstance = await ethers.getContractAt("UniswapPairOracle_USDT_WETH", "0x69B9E922ecA72Cda644a8e32B8427000059388c6");
      Pool_USDCInstance.setCollatETHOracle(FxsWethOralceInstance.address, WethInstance.address);
      // await Pool_USDCInstance.mint1t1FRAX(1000000, 100);
      await Pool_USDCInstance.getCollateralPrice();

    });

  });

});
