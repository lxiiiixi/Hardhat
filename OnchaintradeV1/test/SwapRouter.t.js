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
    const wethAmount = 10000000

    async function deploySwap() {
        [admin, user1, user2, user3] = await ethers.getSigners();
        // deploy weth
        const WETH9 = await ethers.getContractFactory("WETH9");
        const WETHInstance = await WETH9.deploy();
        // depoloy osd
        const Osd = await ethers.getContractFactory("Osd");
        const OsdInstance = await Osd.deploy();
        // deploy swap
        const Swap = await ethers.getContractFactory("Swap");
        const SwapInstance = await Swap.deploy(OsdInstance.address);
        // deploy Mock FastPriceFeed
        const MockOracle = await ethers.getContractFactory("MockOracle");
        const PriceFeedInstance = await MockOracle.deploy();
        // deplpy SwapPriceProxy
        const SwapPriceProxy = await ethers.getContractFactory("SwapPriceProxy");
        const SwapPriceProxyInstance = await SwapPriceProxy.deploy(PriceFeedInstance.address);
        // deploy tradeStakeUpdater
        const TradeStakeUpdater = await ethers.getContractFactory("MockTradeStakeUpdater");
        const TradeStakeUpdaterInstance = await TradeStakeUpdater.deploy();
        // depoloy borrow 
        const MockBorrow = await ethers.getContractFactory("MockBorrow");
        const BorrowInstance = await MockBorrow.deploy();

        // depoloy ERC20
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const PT1Instance = await MockERC20.deploy("Pool Token 1", "PT1", baseAmount);
        const PT2Instance = await MockERC20.deploy("Pool Token 2", "PT2", baseAmount);
        // set for swap
        await SwapInstance.setBorrow(BorrowInstance.address);
        await OsdInstance.setMinter(SwapInstance.address, true);
        await SwapInstance.setPriceFeed(PriceFeedInstance.address);
        await PriceFeedInstance.setPrice(PT1Instance.address, 1e8, 18); // set a fake price for PT1
        await PriceFeedInstance.setPrice(PT2Instance.address, 1e8, 18); // set a fake price for PT2
        await PriceFeedInstance.setPrice(WETHInstance.address, 1e8, 18); // set a fake price for PT2

        // depoloy SwapRouter
        const SwapRouter = await ethers.getContractFactory("SwapRouter");
        const SwapRouterInstance = await SwapRouter.deploy(WETHInstance.address, SwapInstance.address, OsdInstance.address, TradeStakeUpdaterInstance.address);

        // prepare: add pool
        await PT1Instance.approve(SwapInstance.address, baseAmount.div(2)) // approve for the call of listToken
        await PT2Instance.approve(SwapInstance.address, baseAmount.div(2)) // approve for the call of listToken
        await SwapInstance.listToken(PT1Instance.address, baseAmount.div(2), baseAmount, admin.address);
        await SwapInstance.listToken(PT2Instance.address, baseAmount.div(2), baseAmount, admin.address);
        await WETHInstance.deposit({ value: wethAmount })
        await WETHInstance.approve(SwapInstance.address, ethers.constants.MaxUint256) // approve for the call of listToken
        await SwapInstance.listToken(WETHInstance.address, wethAmount, baseAmount, admin.address);
        await SwapInstance.updatePool(PT1Instance.address, 0, 0, true, true, 0, 70, [300, 150, 300])
        await SwapInstance.updatePool(PT2Instance.address, 0, 0, true, true, 0, 70, [300, 150, 300])
        await SwapInstance.updatePool(WETHInstance.address, 0, 0, true, true, 0, 70, [300, 150, 300])

        await TradeStakeUpdaterInstance.setCaller(SwapRouterInstance.address, true);

        return { SwapRouterInstance, SwapInstance, PT1Instance, PT2Instance, WETHInstance }
    }

    describe("Deployment", function () {
        it("Test receive function", async function () {
            const { SwapRouterInstance, WETHInstance } = await loadFixture(deploySwap);
            expect(await SwapRouterInstance.getWETHAddress()).to.equal(WETHInstance.address);
            const transaction = {
                to: SwapRouterInstance.address,
                value: 1000
            }
            await expect(admin.sendTransaction(transaction))
                .to.revertedWith("Receive not allowed");
        });
    });

    describe("Test addLiquidity function", function () {
        it("Router need enough allowance and will emit event", async function () {
            const { SwapRouterInstance, PT1Instance, SwapInstance } = await loadFixture(deploySwap);

            const addAmount = 10000
            // will revert if not enough allowance
            await expect(SwapRouterInstance.addLiquidity(PT1Instance.address, addAmount, admin.address, 0))
                .to.revertedWith("ERC20: insufficient allowance");
            await PT1Instance.approve(SwapRouterInstance.address, addAmount)
            expect(await PT1Instance.allowance(admin.address, SwapRouterInstance.address)).to.equal(addAmount);
            // will emit event
            const liquidityOut = await SwapInstance.getLiquidityOut(PT1Instance.address, addAmount)
            await expect(SwapRouterInstance.addLiquidity(PT1Instance.address, addAmount, admin.address, 0))
                .to.emit(SwapInstance, "AddLiquidity")
                .withArgs(PT1Instance.address, addAmount, liquidityOut, admin.address);
        });

        it("Test ERC20 token", async function () {
            const { SwapRouterInstance, PT1Instance, SwapInstance } = await loadFixture(deploySwap);

            const addAmount = 10000
            await PT1Instance.approve(SwapRouterInstance.address, addAmount)
            expect(await PT1Instance.allowance(admin.address, SwapRouterInstance.address)).to.equal(addAmount);
            // add liquidity
            await SwapRouterInstance.addLiquidity(PT1Instance.address, addAmount, admin.address, 0)
            // check
            expect(await PT1Instance.allowance(admin.address, SwapRouterInstance.address)).to.equal(0);
            expect(await PT1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).sub(addAmount));
            expect(await PT1Instance.balanceOf(SwapRouterInstance.address)).to.equal(0);
            expect(await PT1Instance.balanceOf(SwapInstance.address)).to.equal(baseAmount.div(2).add(addAmount));
        });

        it("Test WETH", async function () {
            const { SwapRouterInstance, PT1Instance, WETHInstance, SwapInstance } = await loadFixture(deploySwap);

            const addAmount = 10000
            await PT1Instance.approve(SwapRouterInstance.address, addAmount)
            expect(await PT1Instance.allowance(admin.address, SwapRouterInstance.address)).to.equal(addAmount);
            expect(await WETHInstance.balanceOf(admin.address)).to.equal(0);
            // add liquidity
            await SwapRouterInstance.addLiquidity(WETHInstance.address, addAmount, admin.address, 0, { value: addAmount })
            // check
            expect(await WETHInstance.balanceOf(admin.address)).to.equal(0);
            expect(await WETHInstance.balanceOf(SwapRouterInstance.address)).to.equal(0);
            expect(await WETHInstance.balanceOf(SwapInstance.address)).to.equal(wethAmount + addAmount);
            expect(await WETHInstance.totalSupply()).to.equal(wethAmount + addAmount);
        });
    });

    describe("Test removeLiquidity function", function () {
        it("Test ERC20", async function () {
            const { SwapRouterInstance, WETHInstance, SwapInstance } = await loadFixture(deploySwap);

            const removeLiquidityAmount = 1000
            const poolInfo = await SwapInstance.getPoolInfo(WETHInstance.address)
            const PoolLiquidityInstance = await ethers.getContractAt("Liquidity", poolInfo[0]);
            await PoolLiquidityInstance.approve(SwapRouterInstance.address, removeLiquidityAmount)

            expect(await PoolLiquidityInstance.balanceOf(admin.address)).to.equal(wethAmount - 300);
            expect(await WETHInstance.balanceOf(admin.address)).to.equal(0);
            await expect(SwapRouterInstance.removeLiquidity(WETHInstance.address, removeLiquidityAmount, admin.address, 0))
                .to.emit(SwapInstance, "RemoveLiquidity")
                .withArgs(WETHInstance.address, removeLiquidityAmount, 0, SwapRouterInstance.address);
            expect(await PoolLiquidityInstance.balanceOf(admin.address)).to.equal(wethAmount - removeLiquidityAmount - 300);
            expect(await WETHInstance.balanceOf(admin.address)).to.equal(0);
            expect(await WETHInstance.balanceOf(SwapRouterInstance.address)).to.equal(0);
            expect(await WETHInstance.totalSupply()).to.equal(wethAmount - removeLiquidityAmount);
        });

        it("Test ERC20", async function () {
            const { SwapRouterInstance, PT1Instance, SwapInstance } = await loadFixture(deploySwap);

            const removeLiquidityAmount = 10000
            const poolInfo = await SwapInstance.getPoolInfo(PT1Instance.address)
            const PoolLiquidityInstance = await ethers.getContractAt("Liquidity", poolInfo[0]);
            await PoolLiquidityInstance.approve(SwapRouterInstance.address, removeLiquidityAmount)
            expect(await PoolLiquidityInstance.balanceOf(admin.address)).to.equal(baseAmount.div(2).sub(300));
            expect(await PT1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2));
            await expect(SwapRouterInstance.removeLiquidity(PT1Instance.address, removeLiquidityAmount, admin.address, 0))
                .to.emit(SwapInstance, "RemoveLiquidity")
                .withArgs(PT1Instance.address, removeLiquidityAmount, 0, admin.address);
            expect(await PoolLiquidityInstance.balanceOf(admin.address)).to.equal(baseAmount.div(2).sub(300).sub(removeLiquidityAmount));
            expect(await PT1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).add(removeLiquidityAmount));
        });
    });
    describe("Test swapIn function", function () {
        it("Test ERC20", async function () {
            const { SwapRouterInstance, WETHInstance, SwapInstance, PT1Instance, PT2Instance } = await loadFixture(deploySwap);

            const swapAmount = 1000
            await PT1Instance.transfer(user1.address, swapAmount);
            await PT1Instance.connect(user1).approve(SwapRouterInstance.address, swapAmount)

            expect(await PT1Instance.balanceOf(user1.address)).to.equal(swapAmount);
            await SwapRouterInstance.connect(user1).swapIn(PT1Instance.address, PT2Instance.address, swapAmount, 0, user1.address, 0)
            expect(await PT1Instance.balanceOf(user1.address)).to.equal(0);
            const amountOut = await SwapInstance.getAmountOut(PT1Instance.address, PT2Instance.address, swapAmount)
            expect(await PT2Instance.balanceOf(user1.address)).to.equal(amountOut);
        });
    });

    describe("Test swapIn function", function () {
        it("Test swapIn token by weth", async function () {
            const { SwapRouterInstance, WETHInstance, SwapInstance, PT2Instance } = await loadFixture(deploySwap);

            const swapAmount = 1000
            // swapIn
            await expect(SwapRouterInstance.connect(user1).swapIn(WETHInstance.address, PT2Instance.address, swapAmount, 0, user1.address, 0, { value: swapAmount - 1 }))
                .to.revertedWith("AMOUNTIN_EUQAL_ETH")
            await SwapRouterInstance.connect(user1).swapIn(WETHInstance.address, PT2Instance.address, swapAmount, 0, user1.address, 0, { value: swapAmount })
            const amountOut = await SwapInstance.getAmountOut(WETHInstance.address, PT2Instance.address, swapAmount)
            expect(await PT2Instance.balanceOf(user1.address)).to.equal(amountOut);
        });
    });
});
