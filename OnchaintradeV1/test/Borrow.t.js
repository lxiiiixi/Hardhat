const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect, use } = require("chai");
const { ethers } = require("hardhat");


describe("Onchain Trade borrow Test", function () {
    let admin, user1, user2, user3;
    const ZERO_ADDRESS = ethers.constants.AddressZero
    const baseAmount = ethers.utils.parseEther("1000000");
    const WeiPerEther = ethers.constants.WeiPerEther;
    const oneYear = 31536000

    async function deployBorrow() {
        [admin, user1, user2, user3] = await ethers.getSigners();

        const WETH9 = await ethers.getContractFactory("WETH9");
        const WETHInstance = await WETH9.deploy();
        const MockSwap = await ethers.getContractFactory("MockSwap");
        const SwapInstance = await MockSwap.deploy();
        const MockOracle = await ethers.getContractFactory("MockOracle");
        const OracleInstance = await MockOracle.deploy();
        // deploy borrow
        const VariableBorrow = await ethers.getContractFactory("VariableBorrow");
        const BorrowInstance = await VariableBorrow.deploy(SwapInstance.address, OracleInstance.address);
        // depoloy VariableBorrowRouter
        const VariableBorrowRouter = await ethers.getContractFactory("VariableBorrowRouter");
        const BorrowRouterInstance = await VariableBorrowRouter.deploy(WETHInstance.address, BorrowInstance.address);

        console.log(BorrowInstance.address, BorrowRouterInstance.address);

        // depoloy ERC20
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const Asset1Instance = await MockERC20.deploy("Asset Token 1", "Asset1", baseAmount);
        const Asset2Instance = await MockERC20.deploy("Asset Token 2", "Asset2", baseAmount);
        const Collateral1Instance = await MockERC20.deploy("Collateral Token 1", "Collateral1", baseAmount);
        const Collateral2Instance = await MockERC20.deploy("Collateral Token 2", "Collateral2", baseAmount);

        // prerare
        await OracleInstance.setPrice(Asset1Instance.address, 1 * 1e8, 18);
        await OracleInstance.setPrice(Asset2Instance.address, 4 * 1e8, 18);
        await OracleInstance.setPrice(Collateral1Instance.address, 1 * 1e8, 18);
        await OracleInstance.setPrice(Collateral2Instance.address, 2 * 1e8, 18);

        return { BorrowInstance, SwapInstance, OracleInstance, Asset1Instance, Asset2Instance, Collateral1Instance, Collateral2Instance };
    }

    describe("Test function updateAsset", function () {
        it("UpdateAsset will be used to add or update asset", async function () {
            const { BorrowInstance, SwapInstance, Asset1Instance, Collateral1Instance } = await loadFixture(deployBorrow);

            const base = 100
            const optimal = 100
            await Asset1Instance.transfer(SwapInstance.address, baseAmount)
            // first update => add
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 10, 10, 10)
            let newRate = 10000 + 100 + 0 / optimal
            let relativeInterestRate = WeiPerEther.mul((0 / 10000) ** 0)
            let assetInfo = await BorrowInstance.assets(Asset1Instance.address)
            expect(assetInfo.interestRate).to.equal(newRate);
            expect(assetInfo.relativeInterest).to.equal(relativeInterestRate);
            expect(assetInfo.base).to.equal(base);
            expect(assetInfo.optimal).to.equal(optimal);
            expect(assetInfo.borrowCredit).to.equal(10);
            let assetList = await BorrowInstance.getAssetList();
            expect(assetList[0]).to.equal(Asset1Instance.address);

            // update 
            await BorrowInstance.updateAsset(Asset1Instance.address, base + 100, optimal + 100, 10, 20, 10, 10, 10)
            assetList = await BorrowInstance.getAssetList();
            expect(assetList[0]).to.equal(Asset1Instance.address);
            assetInfo = await BorrowInstance.assets(Asset1Instance.address)
            newRate = 10000 + base + 100 + 0 / optimal
            expect(assetInfo.base).to.equal(base + 100);
            expect(assetInfo.optimal).to.equal(optimal + 100);
            expect(assetInfo.interestRate).to.equal(newRate);
            expect(assetInfo.relativeInterest).to.gt(relativeInterestRate);

        });
    });

    describe("Test function borrow", function () {
        it("Require test", async function () {
            const { BorrowInstance, SwapInstance, Asset1Instance, Collateral1Instance } = await loadFixture(deployBorrow);

            const base = 100
            const optimal = 100
            const collateralCredit = 10
            await Asset1Instance.transfer(SwapInstance.address, baseAmount) // if not will reverted with panic code 0x12
            await Collateral1Instance.transfer(SwapInstance.address, baseAmount.div(2))
            await expect(BorrowInstance.borrow(Asset1Instance.address, 10000, [{ token: Collateral1Instance.address, amount: 15000 }], admin.address))
                .to.revertedWith("ASSET_NOT_EXIST")
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await BorrowInstance.updateAsset(Collateral1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await expect(BorrowInstance.borrow(Asset1Instance.address, 10000, [{ token: Collateral1Instance.address, amount: 15000 }], user1.address))
                .to.revertedWith("PERMISSION DENY")
            await expect(BorrowInstance.borrow(Asset1Instance.address, 10000, [{ token: Collateral1Instance.address, amount: 15000 }], admin.address))
                .to.revertedWith("ERC20: insufficient allowance")
            await Collateral1Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)
            const CollateralArr = [{ token: Collateral1Instance.address, amount: 15000 }]
            const maxAmountCanBorrow = await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, CollateralArr, admin.address);
            await expect(BorrowInstance.borrow(Asset1Instance.address, maxAmountCanBorrow, CollateralArr, admin.address))
                .to.revertedWith("INSUFF_COLLATERAL")
            const borrowAmount = maxAmountCanBorrow.sub(1)
            await BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            const positionsInfo = await BorrowInstance.getPositionsView(Asset1Instance.address, admin.address)
            expect(positionsInfo.debt).to.equal(borrowAmount);
            expect(positionsInfo.collateralTokens[0]).to.equal(Collateral1Instance.address);
            expect(positionsInfo.collateralAmounts[0]).to.equal(15000);
        });

        it("Borrow should emit event and set correct data", async function () {
            const { BorrowInstance, SwapInstance, Asset1Instance, Collateral1Instance } = await loadFixture(deployBorrow);

            const base = 100
            const optimal = 100
            const collateralCredit = 10
            await Asset1Instance.transfer(SwapInstance.address, baseAmount) // if not will reverted with panic code 0x12
            await Collateral1Instance.transfer(SwapInstance.address, baseAmount.div(2))
            // 需要保证借贷的资产和抵押的资产都有被保存在BorrowInstance中
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await BorrowInstance.updateAsset(Collateral1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await Collateral1Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)
            const CollateralArr = [{ token: Collateral1Instance.address, amount: 15000 }]
            const maxAmountCanBorrow = await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, CollateralArr, admin.address);
            const borrowAmount = maxAmountCanBorrow.sub(1)
            const txPromise = BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            await txPromise;
            // check event
            await expect(txPromise).to.emit(BorrowInstance, "Borrow").withArgs(Asset1Instance.address, admin.address, borrowAmount);
            await expect(txPromise).to.emit(BorrowInstance, "UpdateDebtPosition").withArgs(Asset1Instance.address, admin.address, borrowAmount);
            await expect(txPromise).to.emit(BorrowInstance, "CollateralAdd").withArgs(Asset1Instance.address, admin.address, Collateral1Instance.address, 15000);
            // check balance
            expect(await Asset1Instance.balanceOf(admin.address)).to.equal(borrowAmount);
            expect(await Collateral1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).sub(15000));
            // check position and asset debt
            const adminPosition = await BorrowInstance.positions(Asset1Instance.address, admin.address);
            expect(adminPosition.debt).to.equal(borrowAmount);
            const assetInfo = await BorrowInstance.assets(Asset1Instance.address)
            expect(assetInfo.debt).to.equal(borrowAmount);

            // console.log(adminPosition);
            // console.log(assetInfo);
        });

        it("Borrow more times", async function () {
            const { BorrowInstance, SwapInstance, Asset1Instance, Collateral1Instance, Collateral2Instance } = await loadFixture(deployBorrow);

            const base = 100
            const optimal = 100
            const collateralCredit = 10
            await Asset1Instance.transfer(SwapInstance.address, baseAmount)
            await Collateral1Instance.transfer(SwapInstance.address, baseAmount.div(2))
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await BorrowInstance.updateAsset(Collateral1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await Collateral1Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)

            const CollateralArr = [{ token: Collateral1Instance.address, amount: 15000 }]
            const maxAmountCanBorrow = await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, CollateralArr, admin.address);
            const borrowAmount = maxAmountCanBorrow.sub(1000)
            await BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            await BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            // check position and asset debt
            const adminPosition = await BorrowInstance.positions(Asset1Instance.address, admin.address);
            expect(adminPosition.debt).to.equal(borrowAmount.mul(2));
            const assetInfo = await BorrowInstance.assets(Asset1Instance.address)
            expect(assetInfo.debt).to.equal(borrowAmount.mul(2));
            // borrow more without collateral 
            await BorrowInstance.borrow(Asset1Instance.address, 1800, [{ token: Collateral1Instance.address, amount: 0 }], admin.address);
            // exceed max will revert
            await expect(BorrowInstance.borrow(Asset1Instance.address, 300, [{ token: Collateral1Instance.address, amount: 0 }], admin.address))
                .to.revertedWith("INSUFF_COLLATERAL")
        });

        it("Borrow different collateral", async function () {
            const { BorrowInstance, SwapInstance, Asset1Instance, Collateral1Instance, Collateral2Instance } = await loadFixture(deployBorrow);

            const base = 100
            const optimal = 100
            const collateralCredit = 10
            await Asset1Instance.transfer(SwapInstance.address, baseAmount)
            await Collateral1Instance.transfer(SwapInstance.address, baseAmount.div(2))
            await Collateral2Instance.transfer(SwapInstance.address, baseAmount.div(2))
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await BorrowInstance.updateAsset(Collateral1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await BorrowInstance.updateAsset(Collateral2Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await Collateral1Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)
            await Collateral2Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)

            const CollateralArr = [{ token: Collateral1Instance.address, amount: 15000 }]
            const maxAmountCanBorrow = await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, CollateralArr, admin.address);
            const borrowAmount = maxAmountCanBorrow.sub(1000)
            await BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            await expect(BorrowInstance.borrow(Asset1Instance.address, 100, [{ token: Collateral2Instance.address, amount: 100 }, { token: Collateral1Instance.address, amount: 100 }], admin.address))
                .to.revertedWith("INVALID_COLLATERAL")
            await BorrowInstance.borrow(Asset1Instance.address, 100, [{ token: Collateral2Instance.address, amount: 0 }, { token: Collateral1Instance.address, amount: 100 }], admin.address) // 会导致用户持仓资产添加重复的记录，并且之后都要按照重复的顺序
            await expect(BorrowInstance.borrow(Asset1Instance.address, 100, [{ token: Collateral2Instance.address, amount: 100 }, { token: Collateral1Instance.address, amount: 100 }], admin.address))
                .to.revertedWith("INVALID_COLLATERAL")
            await BorrowInstance.borrow(Asset1Instance.address, 100, [{ token: Collateral1Instance.address, amount: 0 }, { token: Collateral1Instance.address, amount: 100 }], admin.address)
            await expect(BorrowInstance.borrow(Asset1Instance.address, 100, [{ token: Collateral1Instance.address, amount: 100 }, { token: Collateral2Instance.address, amount: 100 }], admin.address))
                .to.revertedWith("INVALID_COLLATERAL")
            // will emit event twice with same collateral
            const txPromise = BorrowInstance.borrow(Asset1Instance.address, 100, [{ token: Collateral1Instance.address, amount: 200 }, { token: Collateral1Instance.address, amount: 100 }, { token: Collateral2Instance.address, amount: 100 }], admin.address)
            await txPromise;
            await expect(txPromise).to.emit(BorrowInstance, "CollateralAdd").withArgs(Asset1Instance.address, admin.address, Collateral1Instance.address, 200);
            await expect(txPromise).to.emit(BorrowInstance, "CollateralAdd").withArgs(Asset1Instance.address, admin.address, Collateral1Instance.address, 100);

            // console.log(await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, [{ token: Collateral1Instance.address, amount: 0 }, { token: Collateral2Instance.address, amount: 100 }], admin.address));

            // 第一次 borrow 传入抵押品为： [Collateral1Instance(非0)]
            //       此时记录的用户持仓抵押品为 [Collateral1Instance(非0)]
            // 第二次 borrow 传入抵押品为： [Collateral2Instance(0), Collateral1Instance(非0)]
            //      此时记录的用户持仓抵押品为 [Collateral1Instance(非0), Collateral1Instance(非0)]

            // 也就是说这里存在设计问题：可以添加相同的抵押品记录，这样是有一定的设计问题的，但是有没有风险或者计算错误还未知
        });
    });

    describe("Test function repay", function () {
        it("Require test and repay will emit events", async function () {
            const { BorrowInstance, SwapInstance, Asset1Instance, Collateral1Instance, Collateral2Instance } = await loadFixture(deployBorrow);

            const base = 100
            const optimal = 100
            const collateralCredit = 10
            await Asset1Instance.transfer(SwapInstance.address, baseAmount)
            await Collateral1Instance.transfer(SwapInstance.address, baseAmount.div(2))
            await expect(BorrowInstance.repay(Asset1Instance.address, 100, [{ token: Collateral1Instance.address, amount: 100 }], admin.address))
                .to.revertedWith("ASSET_NOT_EXIST")
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await expect(BorrowInstance.repay(Asset1Instance.address, 100, [{ token: Collateral1Instance.address, amount: 100 }], user1.address))
                .to.revertedWith("PERMISSION DENY")
            await BorrowInstance.updateAsset(Collateral1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await Collateral1Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)
            const CollateralArr = [{ token: Collateral1Instance.address, amount: 15000 }]
            const maxAmountCanBorrow = await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, CollateralArr, admin.address);
            const borrowAmount = maxAmountCanBorrow.sub(1)
            await BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            // repay
            expect(await Collateral1Instance.balanceOf(BorrowInstance.address)).to.equal(15000);
            const repayCollateralArr = [{ token: Collateral1Instance.address, amount: 1000 }]
            await expect(BorrowInstance.repay(Asset1Instance.address, 100, repayCollateralArr, admin.address))
                .to.revertedWith("ERC20: insufficient allowance")
            await Asset1Instance.approve(SwapInstance.address, ethers.constants.MaxUint256)
            await expect(BorrowInstance.repay(Asset1Instance.address, 100, repayCollateralArr, admin.address))
                .to.revertedWith("COLLATERALs_INSUFF")
            const txPromise = BorrowInstance.repay(Asset1Instance.address, 1000, repayCollateralArr, admin.address)
            await txPromise;
            // check events
            await expect(txPromise).to.emit(BorrowInstance, "Repay").withArgs(Asset1Instance.address, admin.address, 1000);
            await expect(txPromise).to.emit(BorrowInstance, "UpdateDebtPosition").withArgs(Asset1Instance.address, admin.address, borrowAmount.sub(1000));
            await expect(txPromise).to.emit(BorrowInstance, "CollateralRemove").withArgs(Asset1Instance.address, admin.address, Collateral1Instance.address, 1000);

            // const maxRepayAmount = await BorrowInstance.getMaxAmountOfRepay(Asset1Instance.address, repayCollateralArr)

            // console.log(await BorrowInstance.getMaxAmountOfRepay(Collateral1Instance.address, repayCollateralArr));

            // console.log(await BorrowInstance.getAccountDebt(Collateral1Instance.address, admin.address, 0));
            // console.log(await BorrowInstance.getAccountDebt(Collateral1Instance.address, admin.address, 1000));
        });

        it("Test repay exceed debt", async function () {
            const { BorrowInstance, SwapInstance, Asset1Instance, Collateral1Instance, Collateral2Instance } = await loadFixture(deployBorrow);
            const base = 100
            const optimal = 100
            const collateralCredit = 10
            await Asset1Instance.transfer(SwapInstance.address, baseAmount)
            await Collateral1Instance.transfer(SwapInstance.address, baseAmount.div(2))
            await expect(BorrowInstance.repay(Asset1Instance.address, 100, [{ token: Collateral1Instance.address, amount: 100 }], admin.address))
                .to.revertedWith("ASSET_NOT_EXIST")
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await expect(BorrowInstance.repay(Asset1Instance.address, 100, [{ token: Collateral1Instance.address, amount: 100 }], user1.address))
                .to.revertedWith("PERMISSION DENY")
            await BorrowInstance.updateAsset(Collateral1Instance.address, base, optimal, 10, 20, 10, collateralCredit, 10)
            await Collateral1Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)
            const CollateralArr = [{ token: Collateral1Instance.address, amount: 15000 }]
            const maxAmountCanBorrow = await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, CollateralArr, admin.address);
            const borrowAmount = maxAmountCanBorrow.sub(1)
            await BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            // repay
            expect(await BorrowInstance.getAccountDebt(Asset1Instance.address, admin.address, 0)).to.equal(borrowAmount);
            const repayCollateralArr = [{ token: Collateral1Instance.address, amount: 1000 }]
            // console.log(await BorrowInstance.getMaxAmountOfRepay(Asset1Instance.address, CollateralArr));
            await Asset1Instance.approve(SwapInstance.address, ethers.constants.MaxUint256)
            const txPromise = BorrowInstance.repay(Asset1Instance.address, 15100, repayCollateralArr, admin.address)
            await expect(txPromise).to.emit(BorrowInstance, "Repay").withArgs(Asset1Instance.address, admin.address, borrowAmount);
            await expect(txPromise).to.emit(BorrowInstance, "UpdateDebtPosition").withArgs(Asset1Instance.address, admin.address, 0);
            await expect(txPromise).to.emit(BorrowInstance, "CollateralRemove").withArgs(Asset1Instance.address, admin.address, Collateral1Instance.address, 1000);
            // check balance
            expect(await Asset1Instance.balanceOf(admin.address)).to.equal(0);
            expect(await Collateral1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).sub(15000 - 1000));
            // user have no debt anymore => can get all 
            await BorrowInstance.repay(Asset1Instance.address, 0, [{ token: Collateral1Instance.address, amount: 15000 - 1000 }], admin.address)
            expect(await Collateral1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2));
            expect(await BorrowInstance.getAccountDebt(Asset1Instance.address, admin.address, 0)).to.equal(0);
        });
    });

    describe("Test function liquidate", function () {
        it("Liquidate will emit events", async function () {
            const { BorrowInstance, SwapInstance, OracleInstance, Asset1Instance, Collateral1Instance, Collateral2Instance } = await loadFixture(deployBorrow);

            const base = 100
            const optimal = 100
            const collateralCredit = 10
            await Asset1Instance.transfer(SwapInstance.address, baseAmount)
            await Collateral1Instance.transfer(SwapInstance.address, baseAmount.div(2))
            await expect(BorrowInstance.liquidate(Asset1Instance.address, admin.address, 1000, user1.address))
                .to.revertedWith("ASSET_NOT_EXIST")
            await BorrowInstance.updateAsset(Collateral1Instance.address, base, optimal, 10, 10, 10, collateralCredit, 10)
            await BorrowInstance.updateAsset(Asset1Instance.address, base, optimal, 10, 20, 20, collateralCredit, 10)
            await Collateral1Instance.approve(BorrowInstance.address, ethers.constants.MaxUint256)
            const CollateralArr = [{ token: Collateral1Instance.address, amount: 15000 }]
            const maxAmountCanBorrow = await BorrowInstance.getMaxAmountOfBorrow(Asset1Instance.address, CollateralArr, admin.address);
            const borrowAmount = maxAmountCanBorrow.sub(1000)
            await expect(BorrowInstance.liquidate(Asset1Instance.address, admin.address, 1000, user1.address))
                .to.revertedWith("NO_DEBT")
            await BorrowInstance.borrow(Asset1Instance.address, borrowAmount, CollateralArr, admin.address);
            // change price
            await OracleInstance.setPrice(Asset1Instance.address, 2 * 1e8, 18)
            expect(await BorrowInstance.liquidatable(Asset1Instance.address, admin.address)).to.equal(true)
            const amount = await BorrowInstance.liquidatableAmount(Asset1Instance.address, admin.address)
            await expect(BorrowInstance.liquidate(Asset1Instance.address, admin.address, 1000, user1.address))
                .to.revertedWith("ERC20: insufficient allowance")
            await Asset1Instance.approve(SwapInstance.address, ethers.constants.MaxUint256)
            const txPromise = await BorrowInstance.liquidate(Asset1Instance.address, admin.address, amount.div(2), user1.address)
            await expect(txPromise).to.emit(BorrowInstance, "Liquidate").withArgs(Asset1Instance.address, admin.address, amount.div(2));
            await expect(txPromise).to.emit(BorrowInstance, "UpdateDebtPosition").withArgs(Asset1Instance.address, user1.address, borrowAmount.sub(amount.div(2)));

            // console.log(ethers.utils.id("totalSupply()"));
            // console.log(ethers.utils.id("transfer(address, uint256)"));
            // console.log(ethers.utils.id("transfer(address 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, uint256 100)"));

            const transferSelector = ethers.utils.hexDataSlice(ethers.utils.id("transfer(address, uint256)"), 0, 4)
            const param1 = ethers.utils.defaultAbiCoder.encode(['address'], ['0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2'])
            const param2 = ethers.utils.defaultAbiCoder.encode(['uint256'], ['100'])
            const callData = ethers.utils.hexConcat([transferSelector, param1, param2]);
            console.log(callData); // 0x9d61d234000000000000000000000000ab8483f64d9c6d1ecf9b849ae677dd3315835cb20000000000000000000000000000000000000000000000000000000000000064
            console.log(transferSelector);// 0x9d61d234
            console.log(param1); // 0x000000000000000000000000ab8483f64d9c6d1ecf9b849ae677dd3315835cb2
            console.log(param2); // 0x0000000000000000000000000000000000000000000000000000000000000064
        });
    });
});
