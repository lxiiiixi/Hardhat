const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Compound", function () {
  async function deployCompoundFixture() {
    const [owner, Alice, Bob, users] = await ethers.getSigners();
    // 1 部署两个代币
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const tokenA = await MockERC20.deploy("TokenA", 'TAC', ethers.utils.parseEther("1000000000"));
    const tokenB = await MockERC20.deploy("TokenB", 'TBC', ethers.utils.parseEther("2000000000"));
    // 2 部署compound
    // 2.1 部署预言机
    const SimplePriceOracle = await ethers.getContractFactory("SimplePriceOracle");
    const oracle = await SimplePriceOracle.deploy();
    // 2.2 部署 COMP 代币
    const Comp = await ethers.getContractFactory("Comp");
    const comp = await Comp.deploy(owner.address);
    // 2.3 部署 Comptroller 与 Unitroller
    //     任务模块合约，它用来验证用户行为权限。当用户不满足特定任务条件时，便会关闭该行为。
    const Comptroller = await ethers.getContractFactory("Comptroller");
    let comptroller = await Comptroller.deploy();
    const Unitroller = await ethers.getContractFactory("Unitroller");
    let unitroller = await Unitroller.deploy();
    await unitroller._setPendingImplementation(comptroller.address);
    await comptroller._become(unitroller.address);
    // 更新 unitroller
    unitroller = Comptroller.attach(unitroller.address);
    // 设置预言机
    await unitroller._setPriceOracle(oracle.address);
    // 部署利息模块
    const WhitePaperInterestRateModel = await ethers.getContractFactory("WhitePaperInterestRateModel");
    const interest_model = await WhitePaperInterestRateModel.deploy(ethers.utils.parseEther("0.02"), ethers.utils.parseEther("0.15"));
    // 部署 CErc20Delegate 
    const CErc20Delegate = await ethers.getContractFactory("CErc20Delegate");
    const delegate = await CErc20Delegate.deploy();

    // 部署cTokenA与cTokenB
    const CErc20Delegator = await ethers.getContractFactory("CErc20Delegator");
    const cTokenA = await CErc20Delegator.deploy(
      tokenA.address,
      unitroller.address,
      interest_model.address,
      ethers.utils.parseEther("1.0"),
      "Compound TokenA Token",
      "cTokenA",
      18,
      owner.address,
      delegate.address,
      "0x"
    );
    const cTokenB = await CErc20Delegator.deploy(
      tokenB.address,
      unitroller.address,
      interest_model.address,
      ethers.utils.parseEther("1.0"),
      "Compound TokenB Token",
      "cTokenB",
      18,
      owner.address,
      delegate.address,
      "0x"
    );
    await expect(unitroller._supportMarket(cTokenA.address)).emit(
      unitroller, "MarketListed"
    ).withArgs(cTokenA.address);
    await expect(unitroller._supportMarket(cTokenB.address)).emit(
      unitroller, "MarketListed"
    ).withArgs(cTokenB.address);
    return {
      owner,
      Alice,
      Bob,
      users,
      tokenA,
      tokenB,
      oracle,
      unitroller,
      interest_model,
      cTokenA,
      cTokenB
    };
  }

  it("Add market and deposit:", async function () {
    const { owner, unitroller, tokenA, cTokenA, cTokenB } = await loadFixture(deployCompoundFixture);
    let all_markets = await unitroller.getAllMarkets();
    expect(all_markets[0]).eq(cTokenA.address);
    expect(all_markets[1]).eq(cTokenB.address);
    await tokenA.approve(cTokenA.address, ethers.constants.MaxUint256);
    let value = ethers.utils.parseEther("10000");
    await expect(cTokenA.mint(value)).emit(
      cTokenA, "Mint"
    ).withArgs(owner.address, value, value);
  });

  it("Mint Bug Demo", async function () {

  });

  // it("Borrow test", async function() {
  //   const {owner,unitroller,tokenA,tokenB,cTokenA,cTokenB,Alice,Bob,oracle} = await loadFixture(deployCompoundFixture);
  //   // add market
  //   await unitroller._supportMarket(cTokenA.address);
  //   await unitroller._supportMarket(cTokenB.address);
  //   let value = ethers.utils.parseEther("100000");
  //   // 2 Bob deposit
  //   await tokenA.transfer(Bob.address,value);
  //   await tokenB.transfer(Bob.address,value);
  //   await tokenA.connect(Bob).approve(cTokenA.address,ethers.constants.MaxUint256);
  //   await tokenB.connect(Bob).approve(cTokenB.address,ethers.constants.MaxUint256);
  //   await cTokenA.connect(Bob).mint(value);
  //   await cTokenB.connect(Bob).mint(value);

  //   // 3 set price
  //   await oracle.setUnderlyingPrice(cTokenA.address, ethers.utils.parseEther("1.0"));
  //   await oracle.setUnderlyingPrice(cTokenB.address, ethers.utils.parseEther("2.0"));

  //   // 3 Alice deposit tokenA
  //   await tokenA.transfer(Alice.address,value.div(10));
  //   await tokenA.connect(Alice).approve(cTokenA.address,ethers.constants.MaxUint256);

  //   // 4 Alice enter cTokenB
  //   await unitroller.connect(Alice).enterMarkets([cTokenA.address]);
  //   let asset_in = await unitroller.getAssetsIn(Alice.address);
  //   expect(asset_in.length).eq(1);
  //   expect(asset_in[0]).eq(cTokenA.address);

  //   // 5 borrow from cTokenB
  //   await cTokenB.borrow(value.div(2));
  // });

});