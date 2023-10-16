const {
  loadFixture,
  impersonateAccount
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ZeroAddress } = require("ethers");
const { ethers } = require("hardhat");

describe("OCD Token Test", function () {
  let addr1, addr2;
  const totalSupply = ethers.parseEther("1000000000")
  const Depoloyer = "0xeCAB3064B0FCa52fdcc8422280a927EF8f51fE8D"
  const DexRouter = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
  const OCD = "0x017E9Db34fC69Af0dC7c7b4b33511226971cDdc7"
  const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  const MarketWallet = "0xdBBa71D308125218B1cD0fa4f93662EbDc28b43D"
  const minSwapAmount = totalSupply / BigInt(4000)
  const percentDivider = BigInt(100)
  const marketFeeOnBuy = BigInt(1)
  const marketFeeOnSell = BigInt(9)
  const addr1Balance = ethers.parseEther("100")

  const getTotalBuyFeePerTx = (amount) => (amount * marketFeeOnBuy) / percentDivider
  const getTotalSellFeePerTx = (amount) => (amount * marketFeeOnSell) / percentDivider

  async function deployToken() {
    [addr1, addr2] = await ethers.getSigners();
    // const OCD = await ethers.getContractFactory("OCD");
    // const instance = await OCD.deploy();
    const instance = await ethers.getContractAt("OCD", OCD);
    await impersonateAccount(Depoloyer);
    const DepoloySigner = await ethers.getSigner(Depoloyer)
    await instance.connect(DepoloySigner).transfer(addr1.address, addr1Balance);

    const transferOwnership = async () => {
      await impersonateAccount(Depoloyer);
      const DepoloySigner = await ethers.getSigner(Depoloyer)
      await instance.connect(DepoloySigner).transferOwnership(addr1.address);
      expect(await instance.owner()).to.equal(addr1.address);
    }
    return { instance, DepoloySigner, transferOwnership };
  }

  describe("Read contract test", function () {
    it("Should have the correct erc20 metadata", async function () {
      const { instance } = await loadFixture(deployToken);

      expect(await instance.name()).to.equal("On-Chain Dynamics");
      expect(await instance.symbol()).to.equal("OCD");
      expect(await instance.decimals()).to.equal(18);
      expect(await instance.owner()).to.equal(Depoloyer);
      expect(await instance.totalSupply()).to.equal(totalSupply);
      expect(await instance.balanceOf(Depoloyer)).to.lt(totalSupply);
    });

    it("Should have the correct state", async function () {
      const { instance } = await loadFixture(deployToken);

      expect(await instance.dexRouter()).to.equal(DexRouter);
      expect(await instance.distributeAndLiquifyStatus()).to.equal(true);
      expect(await instance.feesStatus()).to.equal(true);
      expect(await instance.percentDivider()).to.equal(percentDivider);
      expect(await instance.marketWallet()).to.equal(MarketWallet);
      expect(await instance.minSwapAmount()).to.equal(minSwapAmount);
      expect(await instance.marketFeeOnBuy()).to.equal(marketFeeOnBuy);
      expect(await instance.marketFeeOnSell()).to.equal(marketFeeOnSell);

      expect(await instance.isExcludedFromFee(Depoloyer)).to.equal(true);
      expect(await instance.isExcludedFromFee(OCD)).to.equal(true);
    });

    it("Should have the correct fee getter", async function () {
      const { instance } = await loadFixture(deployToken);

      const amount = BigInt(100)
      expect(await instance.totalBuyFeePerTx(amount)).to.equal(getTotalBuyFeePerTx(amount));
      expect(await instance.totalSellFeePerTx(amount)).to.equal(getTotalSellFeePerTx(amount));
    });
  });

  describe("Transactions between eoa accounts test", function () {
    it("Should transfer tokens between accounts", async function () {
      const { instance } = await loadFixture(deployToken);
      expect(await instance.balanceOf(addr1.address)).to.equal(addr1Balance);
      const transferAmount = BigInt(5000);
      await expect(instance.transfer(addr2.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(addr1.address, addr2.address, transferAmount);
      expect(await instance.balanceOf(addr2.address)).to.equal(transferAmount);
      expect(await instance.balanceOf(addr1.address)).to.equal(addr1Balance - transferAmount);
    });

    it("Should be failed if sender doesn’t have enough tokens", async function () {
      const { instance } = await loadFixture(deployToken);
      expect(await instance.balanceOf(addr2.address)).to.equal(0);
      await expect(instance.connect(addr2).transfer(addr1.address, 1)).to.reverted;
      expect(await instance.balanceOf(addr1.address)).to.equal(addr1Balance);
    });

    it("Should be failed if sender transfer to or transfer from zero address", async function () {
      const { instance } = await loadFixture(deployToken);
      const transferAmount = BigInt(5000);
      await expect(instance.transfer(ZeroAddress, transferAmount)).to.revertedWith("OCD: transfer to the zero address");
      await expect(instance.transferFrom(addr1.address, ZeroAddress, transferAmount)).to.revertedWith("OCD: transfer to the zero address");
      await expect(instance.transferFrom(ZeroAddress, addr1.address, transferAmount)).to.revertedWith("OCD: transfer from the zero address");
      await expect(instance.transferFrom(addr1.address, addr2.address, 0)).to.revertedWith("OCD: Amount must be greater than zero");
    });

    it("Should be successful if sender transfer to himself, and will loose fees ", async function () {
      const { instance } = await loadFixture(deployToken);
      const transferAmount = BigInt(5000);

      await expect(instance.transfer(addr2.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(addr1.address, addr2.address, transferAmount);
      await instance.approve(addr1.address, transferAmount);
      await expect(instance.transferFrom(addr1.address, addr1.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(addr1.address, addr1.address, transferAmount);
      expect(await instance.balanceOf(addr1.address)).to.equal(addr1Balance - transferAmount);
    });

    it("TransferFrom should need enough allowance", async function () {
      const { instance } = await loadFixture(deployToken);

      const transferAmount = BigInt(5000);

      await instance.transfer(addr2.address, transferAmount)
      await expect(instance.transferFrom(addr2.address, addr1.address, transferAmount)).to.reverted;

      await instance.connect(addr2).approve(addr1.address, transferAmount);
      await expect(instance.transferFrom(addr2.address, addr1.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(addr2.address, addr1.address, transferAmount);
      expect(await instance.balanceOf(addr1.address)).to.equal(addr1Balance);
    });
  });

  describe("Allowance test", function () {
    it("Should update the allowance after approving", async function () {
      const { instance } = await loadFixture(deployToken);
      const approveAmount = BigInt(1000)

      await expect(instance.approve(addr2.address, approveAmount))
        .to.emit(instance, "Approval").withArgs(addr1.address, addr2.address, approveAmount);
      const allowance = await instance.allowance(addr1.address, addr2.address);
      expect(allowance).to.equal(approveAmount);
      // increse allowance again
      await expect(instance.increaseAllowance(addr2.address, approveAmount))
        .to.emit(instance, "Approval").withArgs(addr1.address, addr2.address, approveAmount * BigInt(2));
      expect(await instance.allowance(addr1.address, addr2.address)).to.equal(approveAmount * BigInt(2));
      // decrease allowance
      await expect(instance.decreaseAllowance(addr2.address, approveAmount))
        .to.emit(instance, "Approval").withArgs(addr1.address, addr2.address, approveAmount);
    });

    it("Should underflow when decreasing allowance below zero", async function () {
      const { instance } = await loadFixture(deployToken);
      const approveAmount = ethers.parseEther("1000");
      await instance.approve(addr2.address, approveAmount);

      await expect(instance.decreaseAllowance(addr2.address, approveAmount + 1n))
        .to.reverted;
      expect(await instance.allowance(addr1.address, addr2.address)).to.equal(approveAmount);
    });
  });

  describe("Ownership test", function () {
    it("Should transfer and renounce ownership correctly", async function () {
      const { instance } = await loadFixture(deployToken);

      expect(await instance.owner()).to.equal(Depoloyer);
      await impersonateAccount(Depoloyer);
      const DepoloySigner = await ethers.getSigner(Depoloyer)
      await instance.connect(DepoloySigner).transferOwnership(addr1.address);
      expect(await instance.owner()).to.equal(addr1.address);

      await instance.connect(addr1).renounceOwnership();
      expect(await instance.owner()).to.equal(ZeroAddress);
    });
  });

  describe("Ownable functions test", function () {
    it("Only owner can call function setIncludeOrExcludeFromFee", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.setIncludeOrExcludeFromFee(addr1.address, true)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      expect(await instance.isExcludedFromFee(addr1.address)).to.equal(false);
      await expect(instance.setIncludeOrExcludeFromFee(addr1.address, true))
        .be.emit(instance, "ExcludeFromFee")
        .withArgs(addr1.address, true);
      expect(await instance.isExcludedFromFee(addr1.address)).to.equal(true);
    });

    it("Only owner can call function updateSwapAmount", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.updateSwapAmount(1000)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      expect(await instance.minSwapAmount()).to.equal(minSwapAmount);
      await expect(instance.updateSwapAmount(1000))
        .be.emit(instance, "NewSwapAmount").withArgs(ethers.parseEther("1000"));
      expect(await instance.minSwapAmount()).to.equal(ethers.parseEther("1000"));
    });

    it("Only owner can call function updateBuyFee", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.updateBuyFee(2)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      expect(await instance.marketFeeOnBuy()).to.equal(marketFeeOnBuy);
      await expect(instance.updateBuyFee(2))
        .be.emit(instance, "FeeUpdated").withArgs(2);
      expect(await instance.marketFeeOnBuy()).to.equal(2);
    });

    it("Only owner can call function updateSellFee", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.updateSellFee(10)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      expect(await instance.marketFeeOnSell()).to.equal(marketFeeOnSell);
      await expect(instance.updateSellFee(10))
        .be.emit(instance, "FeeUpdated").withArgs(10);
      expect(await instance.marketFeeOnSell()).to.equal(10);
    });

    it("Only owner can call function setDistributionStatus", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.setDistributionStatus(false)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      await expect(instance.setDistributionStatus(true)).be.revertedWith("Value must be different from current state")
      expect(await instance.distributeAndLiquifyStatus()).to.equal(true);
      await expect(instance.setDistributionStatus(false))
        .be.emit(instance, "DistributionStatus").withArgs(false);
      expect(await instance.distributeAndLiquifyStatus()).to.equal(false);
    });

    it("Only owner can call function enableOrDisableFees", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.enableOrDisableFees(false)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      await expect(instance.enableOrDisableFees(true)).be.revertedWith("Value must be different from current state")
      expect(await instance.feesStatus()).to.equal(true);
      await expect(instance.enableOrDisableFees(false))
        .be.emit(instance, "FeeStatus").withArgs(false);
      expect(await instance.feesStatus()).to.equal(false);
    });

    it("Only owner can call function updatemarketWallet", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.updatemarketWallet(addr2.address)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      await expect(instance.updatemarketWallet(ZeroAddress)).be.revertedWith("Ownable: new marketWallet is the zero address")
      expect(await instance.marketWallet()).to.equal(MarketWallet);
      await expect(instance.updatemarketWallet(addr2.address))
        .be.emit(instance, "marketWalletUpdated").withArgs(addr2.address, MarketWallet);
      expect(await instance.marketWallet()).to.equal(addr2.address);
    });
  });

  describe("Send ETH and withdrawETH test", function () {
    it("Contract can receive ETH", async function () {
      const initialBalance = await ethers.provider.getBalance(OCD)
      const amount = ethers.parseEther("1.0");
      await addr1.sendTransaction({
        to: OCD,
        value: amount
      });
      expect(await ethers.provider.getBalance(OCD)).to.gt(initialBalance);
    });

    it("Only owner can call withdrawETH", async function () {
      const { instance, transferOwnership } = await loadFixture(deployToken);
      await expect(instance.withdrawETH(100)).be.revertedWith("Ownable: caller is not the owner")
      await transferOwnership()
      const initialBalance = await ethers.provider.getBalance(OCD)
      await expect(instance.withdrawETH(initialBalance + BigInt(100))).be.revertedWith("Invalid Amount")
      const amount = ethers.parseEther("1.0");
      await addr1.sendTransaction({
        to: OCD,
        value: amount
      });
      await expect(instance.withdrawETH(100))
        .be.emit(instance, "Transfer").withArgs(OCD, addr1.address, 100);
    });
  });

  describe("Transfer fee unit test", function () {
    it("Add liquidity will take fee", async function () {
      const { instance } = await loadFixture(deployToken);

      const dexPairAddress = await instance.dexPair()
      expect(await instance.isExcludedFromFee(dexPairAddress)).to.equal(false)
      const initialDexPairBalance = await instance.balanceOf(dexPairAddress)
      const initialOcdBalance = await instance.balanceOf(OCD)

      const DexRouterInstance = await ethers.getContractAt("UniswapV2Router02", DexRouter);
      const amountETH = ethers.parseEther("1");
      await instance.approve(DexRouter, addr1Balance);
      await DexRouterInstance.addLiquidityETH(
        OCD,
        addr1Balance,
        0,
        0,
        addr1.address,
        Date.now() + 1000 * 60 * 10,
        { value: amountETH }
      )

      const allFee = getTotalSellFeePerTx(addr1Balance)
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
      expect(await instance.balanceOf(OCD)).to.equal(initialOcdBalance + allFee);
      expect(await instance.balanceOf(dexPairAddress)).to.equal(initialDexPairBalance + addr1Balance - allFee);
    });

    it("Tansfer to dexPair will take fee", async function () {
      const { instance } = await loadFixture(deployToken);

      const dexPairAddress = await instance.dexPair()
      expect(await instance.isExcludedFromFee(dexPairAddress)).to.equal(false)
      const initialDexPairBalance = await instance.balanceOf(dexPairAddress)
      const initialOcdBalance = await instance.balanceOf(OCD)

      await instance.transfer(dexPairAddress, addr1Balance)
      const allFee = getTotalSellFeePerTx(addr1Balance)
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
      expect(await instance.balanceOf(OCD)).to.equal(initialOcdBalance + allFee);
      expect(await instance.balanceOf(dexPairAddress)).to.equal(initialDexPairBalance + addr1Balance - allFee);
    });

    it("Remove liquidity will not take fee if router is excludedFromFee", async function () {
      const { instance } = await loadFixture(deployToken);

      const dexPairAddress = await instance.dexPair()
      expect(await instance.isExcludedFromFee(dexPairAddress)).to.equal(false)
      expect(await instance.balanceOf(addr2.address)).to.equal(0);

      const DexRouterInstance = await ethers.getContractAt("UniswapV2Router02", DexRouter);
      const amountETH = ethers.parseEther("1");
      await instance.approve(DexRouter, addr1Balance);
      // add liquidiy first
      await DexRouterInstance.addLiquidityETH(OCD, addr1Balance, 0, 0, addr1.address, Date.now() + 1000 * 60 * 10, { value: amountETH })
      const initialPairBalance = await instance.balanceOf(dexPairAddress)
      const initialOcdBalance = await instance.balanceOf(OCD)
      const dexPairInstance = await ethers.getContractAt("UniswapV2Pair", dexPairAddress);
      const liquidityAmount = await dexPairInstance.balanceOf(addr1.address)
      expect(liquidityAmount).to.gt(0)

      // remove liqudity
      await dexPairInstance.approve(DexRouter, liquidityAmount)
      await DexRouterInstance.removeLiquidityETH(OCD, liquidityAmount, 0, 0, addr2.address, Date.now() + 1000 * 60 * 10)
      const [reserve0, reserve1] = await dexPairInstance.getReserves()
      const totalLiquidity = await dexPairInstance.totalSupply()
      const amount0 = liquidityAmount * reserve0 / totalLiquidity
      const amount1 = liquidityAmount * reserve1 / totalLiquidity
      const allFee = getTotalBuyFeePerTx(amount0)
      expect(await instance.balanceOf(addr2.address)).to.equal(amount0);
      expect(await instance.balanceOf(dexPairAddress)).to.equal(initialPairBalance - amount0);
    });

    it("Transfer include buy fee test", async () => {
      const { instance } = await loadFixture(deployToken);
      const dexPairAddress = await instance.dexPair()
      const DexRouterInstance = await ethers.getContractAt("UniswapV2Router02", DexRouter);
      const dexPairInstance = await ethers.getContractAt("UniswapV2Pair", dexPairAddress);
      const amountETH = ethers.parseEther("1");
      await instance.approve(DexRouter, addr1Balance);
      await DexRouterInstance.addLiquidityETH(
        OCD,
        addr1Balance,
        0,
        0,
        addr1.address,
        Date.now() + 1000 * 60 * 10,
        { value: amountETH }
      )

      const [reserve0, reserve1, blockTimestampLast] = await dexPairInstance.getReserves()
      const amountIn = ethers.parseEther('0.5')
      const amountOut = await DexRouterInstance.getAmountOut(amountIn, reserve1, reserve0)
      const allFee = getTotalBuyFeePerTx(amountOut)
      const initialOcdBalance = await instance.balanceOf(OCD)
      await DexRouterInstance.swapExactETHForTokensSupportingFeeOnTransferTokens(
        0,
        [WETH, OCD],
        addr2.address,
        Date.now() + 1000 * 60 * 10,
        { value: amountIn }
      )
      expect(await instance.balanceOf(OCD)).to.equal(initialOcdBalance + allFee);
      expect(await instance.balanceOf(addr2.address)).to.be.equal(amountOut - (allFee))
    })

    it("Function distributeAndLiquify will excute while contractTokenBalance reach minSwapAmount", async () => {
      const { instance, DepoloySigner } = await loadFixture(deployToken);

      const DexRouterInstance = await ethers.getContractAt("UniswapV2Router02", DexRouter);
      await instance.connect(DepoloySigner).setIncludeOrExcludeFromFee(Depoloyer, false)
      const amountETH = ethers.parseEther("15");
      await instance.connect(DepoloySigner).approve(DexRouter, totalSupply / BigInt(2));
      await DexRouterInstance.connect(DepoloySigner).addLiquidityETH(
        OCD,
        totalSupply / BigInt(2),
        0,
        0,
        addr1.address,
        Date.now() + 1000 * 60 * 10,
        { value: amountETH }
      )
      const contractTokenBalance = await instance.balanceOf(OCD)
      expect(contractTokenBalance).to.gt(minSwapAmount);

      // distributeAndLiquify will excute
      await instance.transfer(addr2.address, BigInt(100))
      expect(await instance.balanceOf(OCD)).to.equal(contractTokenBalance - minSwapAmount);
    });

  });


});
