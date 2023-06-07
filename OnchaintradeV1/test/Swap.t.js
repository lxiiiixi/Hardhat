const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Onchain Trade Swap Test", function () {
  let admin, user1, user2, user3;
  const ZERO_ADDRESS = ethers.constants.AddressZero
  const baseAmount = ethers.utils.parseEther("1000000");


  async function deploySwap() {
    [admin, user1, user2, user3] = await ethers.getSigners();

    // depoloy osd
    const Osd = await ethers.getContractFactory("Osd");
    const OsdInstance = await Osd.deploy();
    // deploy swap
    const Swap = await ethers.getContractFactory("Swap");
    const SwapInstance = await Swap.deploy(OsdInstance.address);

    // deploy Mock FastPriceFeed
    const MockOracle = await ethers.getContractFactory("MockOracle");
    const PriceFeedInstance = await MockOracle.deploy();

    // depoloy ERC20
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const PT1Instance = await MockERC20.deploy("Pool Token 1", "PT1", baseAmount);
    const PT2Instance = await MockERC20.deploy("Pool Token 2", "PT2", baseAmount);

    // depoloy borrow 
    const MockBorrow = await ethers.getContractFactory("MockBorrow");
    const BorrowInstance = await MockBorrow.deploy();

    // set
    await SwapInstance.setBorrow(BorrowInstance.address);
    await OsdInstance.setMinter(SwapInstance.address, true);
    await SwapInstance.setPriceFeed(PriceFeedInstance.address);
    await PriceFeedInstance.setPrice(PT1Instance.address, 1e8, 18); // set a fake price for PT1
    await PriceFeedInstance.setPrice(PT2Instance.address, 1e8, 18); // set a fake price for PT2

    return { OsdInstance, SwapInstance, PriceFeedInstance, PT1Instance, PT2Instance, BorrowInstance };
  }

  describe("Deployment", function () {
    it("Check meta data", async function () {
      const { OsdInstance, SwapInstance, PriceFeedInstance, BorrowInstance } = await loadFixture(deploySwap);
      expect(await SwapInstance.osd()).to.equal(OsdInstance.address);
      expect(await SwapInstance.$borrow()).to.equal(BorrowInstance.address);
      expect(await SwapInstance.priceFeed()).to.equal(PriceFeedInstance.address);
      const poolTokenList = await SwapInstance.getPoolTokenList()
      expect(poolTokenList.length).to.equal(0);
    });
  });

  describe("Test function listToken", function () {
    it("Osd and existed token can't be add as a pool", async function () {
      const { SwapInstance, OsdInstance, PT1Instance } = await loadFixture(deploySwap);

      // Swap should have engouh allowance
      await expect(SwapInstance.listToken(PT1Instance.address, 10000, 10000, user1.address))
        .to.revertedWith("ERC20: insufficient allowance");
      await PT1Instance.approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.listToken(PT1Instance.address, 10000, 10000, user1.address)
      // add the same token
      await expect(SwapInstance.listToken(OsdInstance.address, 10000, 10000, user1.address))
        .to.revertedWith("CANNOT_LIST_OSD");
      // add osd
      await expect(SwapInstance.listToken(PT1Instance.address, 10000, 10000, user1.address))
        .to.revertedWith("POOL_EXISTS");
    });

    it("ListToken will set correct pool data and emit event", async function () {
      const { SwapInstance, PT1Instance } = await loadFixture(deploySwap);

      const amount = 1000;
      const amountOsd = 10000;
      await PT1Instance.approve(SwapInstance.address, ethers.constants.MaxUint256)

      const txPromise = SwapInstance.listToken(PT1Instance.address, amount, amountOsd, user1.address);
      await txPromise;
      const liquidityAmount = amount - 300; // liquidity: amount 1000 => mint 700 to user1 + mint 300 to SwapInstance
      const poolInfo = await SwapInstance.pools(PT1Instance.address);
      // check event
      await expect(txPromise).to.emit(SwapInstance, "TokenListed").withArgs(PT1Instance.address, poolInfo.liquidity);
      await expect(txPromise).to.emit(SwapInstance, "PoolAmountUpdated").withArgs(PT1Instance.address, amount, 0, amount, amountOsd);
      await expect(txPromise).to.emit(SwapInstance, "AddLiquidity").withArgs(PT1Instance.address, amount, liquidityAmount, user1.address);
      // check poolInfo
      expect(poolInfo.reserve).to.equal(amount)
      expect(poolInfo.lastRatioToken).to.equal(amount)
      expect(poolInfo.lastRatioOsd).to.equal(amountOsd)
      expect(poolInfo.osd).to.equal(0)
      expect(poolInfo.rebalancible).to.equal(false)
      expect(poolInfo.usePriceFeed).to.equal(false)
      expect(poolInfo.feeType).to.equal(0)
      expect(poolInfo.revenueRate).to.equal(70)
      expect(poolInfo.revenueOsd).to.equal(0)
      expect(poolInfo.tokenDecimal).to.equal(18)
      const PoolLiquidityInstance = await ethers.getContractAt("Liquidity", poolInfo.liquidity);
      expect(await PoolLiquidityInstance.balanceOf(user1.address)).to.equal(liquidityAmount)
      expect(await PoolLiquidityInstance.balanceOf(SwapInstance.address)).to.equal(300)
      expect(await PoolLiquidityInstance.totalSupply()).to.equal(amount)
      // check balance
      expect(await PT1Instance.balanceOf(admin.address)).to.equal(baseAmount.sub(amount))
      expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(amount)
    });

    it("ListToken can be called by anyone without limit", async function () {
      const { SwapInstance, PT2Instance, PT1Instance } = await loadFixture(deploySwap);
      const amount = 1000;
      const amountOsd = 10000;
      await PT1Instance.approve(SwapInstance.address, ethers.constants.MaxUint256)
      await PT2Instance.transfer(user1.address, 10000)
      await PT2Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)

      await SwapInstance.listToken(PT1Instance.address, amount, amountOsd, user1.address);
      await SwapInstance.connect(user1).listToken(PT2Instance.address, amount, amountOsd, user1.address)
    });
  });

  describe("Test function addLiquidity and getLiquidityOut", function () {
    it("AddLiquidity should set correct data", async function () {
      const { SwapInstance, PT2Instance, PT1Instance } = await loadFixture(deploySwap);

      // prepare
      const amount = 1000;
      const amountOsd = 10000;
      const liquidityAmount = amount - 300;
      await PT1Instance.transfer(user1.address, baseAmount)
      await PT1Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user1).listToken(PT1Instance.address, amount, amountOsd, user1.address);

      // add liquidity
      await expect(SwapInstance.connect(user1).addLiquidity(PT2Instance.address, amount, user1.address, 0))
        .to.revertedWith("POOL_NOT_EXISTS");
      let outAmount = await SwapInstance.getLiquidityOut(PT1Instance.address, amount)
      const txPromise = SwapInstance.connect(user1).addLiquidity(PT1Instance.address, amount, user1.address, 0)
      await txPromise;
      const poolInfo = await SwapInstance.pools(PT1Instance.address);
      // check event
      let netValue = amount + amount * poolInfo.osd / amountOsd;
      let liquidityOutAmount = amount * amount / netValue;
      await expect(txPromise).to.emit(SwapInstance, "PoolAmountUpdated").withArgs(PT1Instance.address, amount * 2, 0, amount, amountOsd);
      await expect(txPromise).to.emit(SwapInstance, "AddLiquidity").withArgs(PT1Instance.address, amount, liquidityOutAmount, user1.address);
      expect(outAmount).to.equal(liquidityOutAmount)
      // check poolInfo 
      expect(poolInfo.reserve).to.equal(amount * 2)
      expect(poolInfo.lastRatioToken).to.equal(amount)
      expect(poolInfo.lastRatioOsd).to.equal(amountOsd)
      expect(poolInfo.osd).to.equal(0)
      // get reserve
      const poolReserve = await SwapInstance.getPoolReserve(PT1Instance.address)
      expect(poolReserve[0]).to.equal(amount * 2)
      expect(poolReserve[1]).to.equal(amountOsd * 2)
      // check balance
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(baseAmount.sub(amount * 2))
      expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(amount * 2)
      const PoolLiquidityInstance = await ethers.getContractAt("Liquidity", poolInfo.liquidity);
      expect(await PoolLiquidityInstance.balanceOf(user1.address)).to.equal(liquidityAmount + liquidityOutAmount)
      expect(await PoolLiquidityInstance.balanceOf(SwapInstance.address)).to.equal(300)
      expect(await PoolLiquidityInstance.totalSupply()).to.equal(amount + liquidityOutAmount)


      // add again
      outAmount = await SwapInstance.getLiquidityOut(PT1Instance.address, amount)
      await SwapInstance.connect(user1).addLiquidity(PT1Instance.address, amount, user1.address, 0)
      // check balance
      netValue = amount * 2 + amount * 2 * poolInfo.osd / amountOsd;
      liquidityOutAmount = amount * amount * 4 / netValue;
      expect(outAmount).to.equal(liquidityOutAmount - amount)
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(baseAmount.sub(amount * 3))
      expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(amount * 3)
      expect(await PoolLiquidityInstance.balanceOf(user1.address)).to.equal(liquidityAmount + liquidityOutAmount)
      expect(await PoolLiquidityInstance.balanceOf(SwapInstance.address)).to.equal(300)
      expect(await PoolLiquidityInstance.totalSupply()).to.equal(amount + liquidityOutAmount)
    });
  });

  describe("Test function removeLiquidity and getLiquidityIn", function () {
    it("RemoveLiquidity should set correct data", async function () {
      const { SwapInstance, PT1Instance } = await loadFixture(deploySwap);
      // prepare
      const amount = 1000;
      const amountOsd = 10000;
      const liquidityAmount = amount - 300;
      await PT1Instance.transfer(user1.address, baseAmount)
      await PT1Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user1).listToken(PT1Instance.address, amount, amountOsd, user1.address);
      // add liquidity
      await SwapInstance.connect(user1).addLiquidity(PT1Instance.address, amount, user1.address, 0)
      let poolInfo = await SwapInstance.pools(PT1Instance.address);
      let netValue = amount + amount * poolInfo.osd / amountOsd;
      let liquidityOutAmount = amount * amount / netValue;
      // check balance
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(baseAmount.sub(amount * 2))
      expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(amount * 2)
      const PoolLiquidityInstance = await ethers.getContractAt("Liquidity", poolInfo.liquidity);
      expect(await PoolLiquidityInstance.balanceOf(user1.address)).to.equal(liquidityAmount + liquidityOutAmount)
      expect(await PoolLiquidityInstance.balanceOf(SwapInstance.address)).to.equal(300)
      expect(await PoolLiquidityInstance.totalSupply()).to.equal(amount + liquidityOutAmount)

      // remove liquidity
      const inAmount = await SwapInstance.getLiquidityIn(PT1Instance.address, amount / 2)
      const txPromise = SwapInstance.connect(user1).removeLiquidity(PT1Instance.address, amount / 2, user1.address, 0)
      await txPromise;
      poolInfo = await SwapInstance.pools(PT1Instance.address);
      const liquidityInAmount = (amount * 2 * amount / 2) / (amount + liquidityOutAmount)
      const liquidityInAmountOsd = 0
      expect(inAmount[0]).to.equal(liquidityInAmount)
      expect(inAmount[1]).to.equal(liquidityInAmountOsd)
      // check event
      await expect(txPromise).to.emit(SwapInstance, "PoolAmountUpdated").withArgs(PT1Instance.address, amount * 2 - amount / 2, 0, amount, amountOsd);
      await expect(txPromise).to.emit(SwapInstance, "RemoveLiquidity").withArgs(PT1Instance.address, amount / 2, liquidityInAmountOsd, user1.address);
      // check poolInfo
      expect(poolInfo.reserve).to.equal(amount * 2 - amount / 2)
      expect(poolInfo.osd).to.equal(0)
      // check balance
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(baseAmount.sub(amount * 2).add(amount / 2))
      expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(amount * 2 - amount / 2)
      expect(await PoolLiquidityInstance.balanceOf(user1.address)).to.equal(liquidityAmount + liquidityOutAmount - liquidityInAmount)
      expect(await PoolLiquidityInstance.balanceOf(SwapInstance.address)).to.equal(300)
      expect(await PoolLiquidityInstance.totalSupply()).to.equal(amount + liquidityOutAmount - liquidityInAmount)
    });

    it("Remove over reserved amount will fail", async function () {
      const { SwapInstance, PT1Instance } = await loadFixture(deploySwap);
      // prepare
      const amount = 1000;
      const amountOsd = 10000;
      await PT1Instance.transfer(user1.address, amount)
      await PT1Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user1).listToken(PT1Instance.address, amount, amountOsd, user1.address);
      let poolInfo = await SwapInstance.pools(PT1Instance.address);
      const PoolLiquidityInstance = await ethers.getContractAt("Liquidity", poolInfo.liquidity);
      expect(poolInfo.reserve).to.equal(amount)
      // user need sufficient liquidity
      await expect(SwapInstance.connect(user1).removeLiquidity(PT1Instance.address, amount, user1.address, 0))
        .to.revertedWith("INSUFF_RESERVE");
      expect(await PoolLiquidityInstance.balanceOf(user1.address)).to.equal(amount - 300)
      expect(await PoolLiquidityInstance.balanceOf(SwapInstance.address)).to.equal(300)
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(0)
      expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(amount)

      await expect(SwapInstance.connect(user1).removeLiquidity(PT1Instance.address, amount - 299, user1.address, 0))
        .to.revertedWith("ERC20: burn amount exceeds balance");
      // MIN_LIQUIDITY amount  liquidity is needed
      await SwapInstance.connect(user1).removeLiquidity(PT1Instance.address, amount - 300, user1.address, 0)
      const inAmount = await SwapInstance.getLiquidityIn(PT1Instance.address, amount - 300)
      expect(inAmount[0]).to.equal(amount - 300)
      expect(await PoolLiquidityInstance.balanceOf(user1.address)).to.equal(0)
      expect(await PoolLiquidityInstance.balanceOf(SwapInstance.address)).to.equal(300)
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(amount - 300)
      expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(300)
    });
  });

  describe("Test withdrawRevenueOsd", function () {
    it("Only owner can call this", async function () {
      const { SwapInstance, PT1Instance } = await loadFixture(deploySwap);
      // prepare
      const amount = 1000;
      const amountOsd = 10000;
      await PT1Instance.transfer(user1.address, baseAmount)
      await PT1Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user1).listToken(PT1Instance.address, amount, amountOsd, user1.address);
      await expect(SwapInstance.connect(user1).withdrawRevenueOsd(PT1Instance.address, user1.address, amount))
        .to.revertedWith("Ownable: caller is not the owner");
    });

    it("Will generate revenueOsd only swap enought amount", async function () {
      const { SwapInstance, PT2Instance, OsdInstance, PT1Instance } = await loadFixture(deploySwap);
      // prepare
      const amount = 10000;
      const amountOsd = 10000;
      await PT1Instance.transfer(user1.address, baseAmount)
      await PT2Instance.transfer(user2.address, baseAmount)
      await PT1Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await PT2Instance.connect(user2).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user1).listToken(PT1Instance.address, amount * 2, amountOsd, user1.address);
      await SwapInstance.connect(user2).listToken(PT2Instance.address, amount * 2, amountOsd, user1.address);
      // need sufficient revenue
      await expect(SwapInstance.withdrawRevenueOsd(PT1Instance.address, user1.address, amount))
        .to.revertedWith("INSUFF_REVENUE");
      await SwapInstance.updatePool(PT1Instance.address, 0, 0, true, true, 0, 70, [300, 150, 300])
      await SwapInstance.updatePool(PT2Instance.address, 0, 0, true, true, 0, 70, [300, 150, 300])
      // once swap will generate fee once
      await SwapInstance.connect(user1).swapIn(PT1Instance.address, PT2Instance.address, 100, 0, user1.address, 0)
      expect(await SwapInstance.getRevenueOsd(PT1Instance.address)).to.equal(0)
      await SwapInstance.connect(user1).swapIn(PT1Instance.address, PT2Instance.address, amount, 0, user1.address, 0)
      await SwapInstance.connect(user2).swapIn(PT2Instance.address, PT1Instance.address, amount, 0, user1.address, 0)
      const revenueOsd = await SwapInstance.getRevenueOsd(PT1Instance.address)
      await SwapInstance.withdrawRevenueOsd(PT1Instance.address, user1.address, revenueOsd)
      expect(await OsdInstance.balanceOf(user1.address)).to.equal(revenueOsd)
    });
  });

  describe("Test swapIn", function () {
    it("SwapIn will get correct token", async function () {
      const { SwapInstance, PT2Instance, PT1Instance, OsdInstance } = await loadFixture(deploySwap);
      // prepare
      const amount = 1000;
      const amountOsd = 10000;
      await PT1Instance.transfer(user1.address, baseAmount)
      await PT2Instance.transfer(user2.address, baseAmount)
      await PT1Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await PT2Instance.connect(user2).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user1).listToken(PT1Instance.address, amount, amountOsd, user1.address);
      await SwapInstance.connect(user2).listToken(PT2Instance.address, amount, amountOsd, user2.address);

      // check reserve
      const [PT1ReserveToken, PT1ReserveOsd, PT1AvailableToken, PT1AvailableOsd] = await SwapInstance.getPoolReserve(PT1Instance.address);
      const [PT2ReserveToken, PT2ReserveOsd, PT2AvailableToken, PT2AvailableOsd] = await SwapInstance.getPoolReserve(PT2Instance.address);
      expect(PT1ReserveToken).to.equal(amount)
      expect(PT1ReserveOsd).to.equal(amountOsd)
      expect(PT1AvailableToken).to.equal(amount)
      expect(PT1AvailableOsd).to.equal(0)
      expect(PT2ReserveToken).to.equal(amount)
      expect(PT2ReserveOsd).to.equal(amountOsd)
      expect(PT2AvailableToken).to.equal(amount)
      expect(PT2AvailableOsd).to.equal(0)

      // balance
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(baseAmount.sub(amount))
      expect(await PT2Instance.balanceOf(user1.address)).to.equal(0)
      await SwapInstance.updatePool(PT1Instance.address, 0, 0, true, true, 0, 70, [300, 150, 300])
      // swapIn: input PT1 to get output PT2
      const amountOut = await SwapInstance.getAmountOut(PT1Instance.address, PT2Instance.address, 100)
      await SwapInstance.connect(user1).swapIn(PT1Instance.address, PT2Instance.address, 100, amountOut, user1.address, 0)
      expect(await PT1Instance.balanceOf(user1.address)).to.equal(baseAmount.sub(amount + 100))
      expect(await PT2Instance.balanceOf(user1.address)).to.equal(amountOut)

      // swap osd
      const outOsd = await SwapInstance.getAmountOut(PT1Instance.address, OsdInstance.address, 100)
      await SwapInstance.connect(user1).swapIn(PT1Instance.address, OsdInstance.address, 100, 0, user1.address, 0)
      expect(await OsdInstance.balanceOf(user1.address)).to.equal(outOsd)
    });
  });

  describe("Test swapOut", function () {
    it("SwapOut will get correct token", async function () {
      const { SwapInstance, PT2Instance, PT1Instance, OsdInstance } = await loadFixture(deploySwap);
      // prepare
      const amount = 1000;
      const amountOsd = 10000;
      await PT1Instance.transfer(user1.address, amount * 2)
      await PT2Instance.transfer(user2.address, amount * 2)
      await PT1Instance.transfer(user3.address, amount * 2)
      await PT2Instance.transfer(user3.address, amount)
      // list token
      await PT1Instance.connect(user1).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await PT2Instance.connect(user2).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user1).listToken(PT1Instance.address, amount * 2, amountOsd, user1.address);
      await SwapInstance.connect(user2).listToken(PT2Instance.address, amount, amountOsd, user2.address);

      await SwapInstance.updatePool(PT1Instance.address, 0, 0, true, true, 0, 70, [300, 150, 300])
      await SwapInstance.updatePool(PT2Instance.address, 0, 0, true, true, 0, 70, [300, 150, 300])
      const amountIn = await SwapInstance.connect(user1).getAmountIn(PT2Instance.address, PT1Instance.address, 100)
      expect(await PT1Instance.balanceOf(user3.address)).to.equal(amount * 2) // 2000
      expect(await PT2Instance.balanceOf(user3.address)).to.equal(amount)
      await PT1Instance.connect(user3).approve(SwapInstance.address, ethers.constants.MaxUint256)
      await SwapInstance.connect(user3).swapOut(PT1Instance.address, PT2Instance.address, 100000, 100, user1.address, 0)
      expect(await PT2Instance.balanceOf(user3.address)).to.equal(amount)
      console.log(amountIn); // 100
      console.log(await SwapInstance.getPriceRatio(PT1Instance.address));
      // console.log(await PT1Instance.balanceOf(user3.address)); // 883
    });
  });
});

/**
 * 疑问：
 * 1. modifier expires(uint256 deadline)的作用是什么
 * 2. pool.lastRatioToken pool.lastRatioOsd 用于在 _getReserve 中根据token的reserve计算得到osd的reserve，
 *     每次代币更新都会更新这两个值比如listToken和swap时，为什么在添加流动性的时候不更改这两个值的记录呢，会不会导致计算结果有什么影响呢
 *     而且为什么 pool.usePriceFeed 为false时才更新呢
 * 3. pool.rebalancible 到底存在的意义是什么
 * 4. pool.osd 为什么在 _swapOsd 中是被直接赋值，而在 _swapToken 中是累加赋值
 *    pool.osd 这个值的作用到底是什么，
 * 5. 可以提出建议的地方：在 swapIn 和 swapOut 中并没有检查池子是否存在，会出现 _getReserve 中  pool.lastRatioToken 为0的情况，并且这里也没有处零检查
 * 6. 现在还有 borrow 的几个函数都还没有测
 */

