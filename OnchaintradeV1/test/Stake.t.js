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
    async function deployStake() {
        [admin, user1, user2, user3] = await ethers.getSigners();

        const Stake = await ethers.getContractFactory("Stake");
        const StakeInstance = await Stake.deploy();

        // depoloy ERC20
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const LP1Instance = await MockERC20.deploy("LP Token 1", "LP1", baseAmount);
        const LP2Instance = await MockERC20.deploy("LP Token 2", "LP2", baseAmount);
        const Reward1Instance = await MockERC20.deploy("Reward Token 1", "Reward1", baseAmount);
        const Reward2Instance = await MockERC20.deploy("Reward Token 2", "Reward2", baseAmount);
        await Reward1Instance.transfer(StakeInstance.address, baseAmount.div(2)); // will revert if the balance is not enough


        return { StakeInstance, LP1Instance, LP2Instance, Reward1Instance, Reward2Instance };
    }

    function getNowTimeStamp() {
        return Math.floor(new Date().getTime() / 1000);
    }

    // 对于 pool.paidOut 这个变量（withdrawReward、withdrawAccountRevenue、withdraw），用户提取代币时会增加数量，但是 deposit 中却又不记录这个，这个变量很奇怪

    describe("Test function addRevenueToken", function () {
        it("Test require condition", async function () {
            const { StakeInstance, LP1Instance, LP2Instance, Reward1Instance, Reward2Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000

            await expect(StakeInstance.addRevenueToken(LP1Instance.address, Reward2Instance.address))
                .to.be.revertedWith("LP token not exist");
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            // await expect(StakeInstance.addRevenueToken(LP1Instance.address, Reward2Instance.address))
            //     .to.be.revertedWith("need balanceOf");
            // addRevenueToken 对余额检查这里的限制没什么作用 不存在小于零的情况啊
            expect(await Reward2Instance.balanceOf(StakeInstance.address)).to.equal(0)
            await Reward2Instance.transfer(StakeInstance.address, baseAmount)
            await StakeInstance.addRevenueToken(LP1Instance.address, Reward2Instance.address)
            await expect(StakeInstance.addRevenueToken(LP1Instance.address, Reward2Instance.address))
                .to.be.revertedWith("revenueInfo need empty");
            expect(await StakeInstance.revenueInfoList(LP1Instance.address, 0)).to.equal(Reward2Instance.address)
            // different revenue token can be added
            await StakeInstance.addRevenueToken(LP1Instance.address, Reward1Instance.address)
        });

        it("Test require condition", async function () {
            const { StakeInstance, LP1Instance, LP2Instance, Reward1Instance, Reward2Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000

            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            await LP1Instance.approve(StakeInstance.address, ethers.constants.MaxUint256)
            await StakeInstance.deposit(LP1Instance.address, depositAmount)
            await Reward1Instance.approve(StakeInstance.address, ethers.constants.MaxUint256)
            await Reward2Instance.approve(StakeInstance.address, ethers.constants.MaxUint256)
            await StakeInstance.addRevenueToken(LP1Instance.address, Reward1Instance.address)
            await StakeInstance.addRevenueToken(LP1Instance.address, Reward2Instance.address)

            await StakeInstance.addRevenue(LP1Instance.address, [Reward1Instance.address, Reward2Instance.address], [100, 200])

            await StakeInstance.deposit(LP1Instance.address, depositAmount)



            console.log(await StakeInstance.getAccountRevenueInfo(user1.address, LP1Instance.address));
        });
    });

    describe("Test function withdraw and withdrawReward", function () {
        it("Test add an token not exist and test withdraw exceed deposit amount", async function () {
            const { StakeInstance, LP1Instance, LP2Instance, Reward1Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 100;
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000

            // 小问题：最好在withdraw之前添加对池子是否存在的检查和stakeTokenAmount数量减去放在require下面
            // reverted with panic code 0x11

            // await expect(StakeInstance.withdraw(LP2Instance.address, depositAmount))
            //     .to.be.revertedWith("withdraw more than deposit");

            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            await LP1Instance.transfer(user1.address, depositAmount)
            await LP1Instance.approve(StakeInstance.address, depositAmount)
            await LP1Instance.connect(user1).approve(StakeInstance.address, depositAmount)
            await StakeInstance.deposit(LP1Instance.address, depositAmount)
            await StakeInstance.connect(user1).deposit(LP1Instance.address, depositAmount)
            await expect(StakeInstance.withdraw(LP1Instance.address, depositAmount + 1))
                .to.be.revertedWith("withdraw more than deposit");
        });

        it("Test withdraw", async function () {
            const { StakeInstance, LP1Instance, LP2Instance, Reward1Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 100;
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000
            // add pool and deposit
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            await LP1Instance.approve(StakeInstance.address, depositAmount)
            await StakeInstance.deposit(LP1Instance.address, depositAmount)
            // withdraw
            await time.increase(100)
            const pending = await StakeInstance.pending(LP1Instance.address, admin.address)
            await expect(StakeInstance.withdraw(LP1Instance.address, depositAmount))
                .to.emit(StakeInstance, "Withdraw")
                .withArgs(admin.address, LP1Instance.address, depositAmount);
            // check 
            expect(await StakeInstance.stakeTokenAmount(LP1Instance.address)).to.equal(0)
            expect(await LP1Instance.balanceOf(admin.address)).to.equal(baseAmount)
            expect(await Reward1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).add(pending[0]))
        });

        it("More user withdraw and withdrawReward", async function () {
            const { StakeInstance, LP1Instance, LP2Instance, Reward1Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000
            // add pool and deposit
            // admin deposit : depositAmount * 2
            // user1 deposit : depositAmount
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            await LP1Instance.approve(StakeInstance.address, depositAmount * 2)
            await StakeInstance.deposit(LP1Instance.address, depositAmount * 2)
            await LP1Instance.transfer(user1.address, depositAmount)
            await LP1Instance.connect(user1).approve(StakeInstance.address, depositAmount)
            await StakeInstance.connect(user1).deposit(LP1Instance.address, depositAmount)
            expect(await Reward1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2))
            expect(await Reward1Instance.balanceOf(user1.address)).to.equal(0)

            // admin withdraw
            await time.increase(100)
            const adminPending = await StakeInstance.pending(LP1Instance.address, admin.address)
            await StakeInstance.withdrawReward(LP1Instance.address)
            expect(await Reward1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).add(adminPending[0].add(rewardPerSecond)))
            const adminInfo = await StakeInstance.userInfo(LP1Instance.address, admin.address)
            expect(adminInfo.rewardDebt).to.equal(adminPending[0].add(rewardPerSecond))
            // admin withdraw again
            await time.increase(100)
            const adminPending2 = await StakeInstance.pending(LP1Instance.address, admin.address)
            await StakeInstance.withdrawReward(LP1Instance.address)
            const adminInfo2 = await StakeInstance.userInfo(LP1Instance.address, admin.address)
            expect(adminInfo2.rewardDebt).to.equal(adminPending[0].add(adminPending2[0]).add(rewardPerSecond * 2))
            expect(await Reward1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).add(adminPending[0].add(adminPending2[0]).add(rewardPerSecond * 2)))
        });
    });


    describe("Test function deposit", function () {
        it("Test require", async function () {
            const { StakeInstance, LP1Instance, Reward1Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000
            // addtoken and deposit
            await expect(StakeInstance.deposit(LP1Instance.address, depositAmount))
                .to.be.revertedWith("LP token not exist");
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            await expect(StakeInstance.deposit(LP1Instance.address, 0))
                .to.be.revertedWith("DEPOSIT GT 0");
        });

        it("Should set correct data and emit event", async function () {
            const { StakeInstance, LP1Instance, Reward1Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000
            // addtoken and first deposit
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            await LP1Instance.approve(StakeInstance.address, depositAmount)
            await expect(StakeInstance.deposit(LP1Instance.address, depositAmount))
                .to.emit(StakeInstance, "Deposit")
                .withArgs(admin.address, LP1Instance.address, depositAmount);

            const userInfo = await StakeInstance.userInfo(LP1Instance.address, admin.address);
            expect(userInfo.amount).to.equal(depositAmount)
            expect(userInfo.rewardDebt).to.equal(0)
            expect(userInfo.user).to.equal(ZERO_ADDRESS) // no used data
        });

        it("Deposit more times", async function () {
            const { StakeInstance, LP1Instance, Reward1Instance } = await loadFixture(deployStake);
            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000
            // addtoken and first deposit
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            await LP1Instance.approve(StakeInstance.address, depositAmount * 3)
            // deposit more times
            // first deposit
            await StakeInstance.deposit(LP1Instance.address, depositAmount)
            expect(await Reward1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2)) // no reward for the first time
            expect(await StakeInstance.getTotalReward(LP1Instance.address)).to.equal(0)
            // second deposit
            await time.increase(100)
            await StakeInstance.deposit(LP1Instance.address, depositAmount)
            let poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(await StakeInstance.getTotalReward(LP1Instance.address)).to.equal(poolInfo.totalReward)
            const accERC20PerShare = poolInfo.accERC20PerShare
            const pendingReward1 = depositAmount * accERC20PerShare / 1e12 - 0
            expect(await Reward1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).add(pendingReward1))

            // third deposit
            await time.increase(100)
            await StakeInstance.deposit(LP1Instance.address, depositAmount)
            poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(await StakeInstance.getTotalReward(LP1Instance.address)).to.equal(poolInfo.totalReward)
            let lastRewardDebt = depositAmount * 2 * accERC20PerShare / 1e12 // 是上一次质押结束时记录的，用的是上次结时候的 accERC20PerShare
            const pendingReward2 = depositAmount * 2 * poolInfo.accERC20PerShare / 1e12 - lastRewardDebt // 而pending的计算是更新了池子之后的 accERC20PerShare
            expect(await Reward1Instance.balanceOf(admin.address)).to.equal(baseAmount.div(2).add(pendingReward1 + pendingReward2))
            const userInfo = await StakeInstance.userInfo(LP1Instance.address, admin.address);
            expect(userInfo.amount).to.equal(depositAmount * 3)
            expect(userInfo.rewardDebt).to.equal(Math.floor(depositAmount * 3 * poolInfo.accERC20PerShare / 1e12))

            await time.increase(100)
            let newReward = 100 * rewardPerSecond
            expect(await StakeInstance.getTotalReward(LP1Instance.address)).to.equal(poolInfo.totalReward.add(newReward))

            // check pending
            const [pendingAmount, totalReward, oneDayReward, amount, rewardToken] = await StakeInstance.pending(LP1Instance.address, admin.address);
            const lpSupply = await LP1Instance.balanceOf(StakeInstance.address);
            const newPerShare = poolInfo.accERC20PerShare.add(Math.floor(newReward * 1e12 / lpSupply))
            const pending = lpSupply * newPerShare / 1e12 - userInfo.rewardDebt
            expect(pendingAmount).to.equal(Math.floor(pending))
            expect(totalReward).to.equal(poolInfo.totalReward.add(newReward))
            expect(oneDayReward).to.equal(rewardPerSecond * 86400)
            expect(amount).to.equal(depositAmount * 3)
            expect(rewardToken).to.equal(Reward1Instance.address)
        });
    });


    describe("Test function updatePool", function () {
        it("Calling a pool that does not exist will also succeed", async function () {
            const { StakeInstance, LP1Instance } = await loadFixture(deployStake);
            await StakeInstance.updatePool(LP1Instance.address)
        });

        it("If supply of lpToken is zero, state will be unchanged", async function () {
            const { StakeInstance, LP1Instance, Reward1Instance } = await loadFixture(deployStake);

            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            expect(await LP1Instance.balanceOf(StakeInstance.address)).to.equal(0)
            await StakeInstance.updatePool(LP1Instance.address)
            let poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(poolInfo.totalReward).to.equal(0)
            expect(poolInfo.accERC20PerShare).to.equal(0)
            expect(poolInfo.lastRewardTime).to.gte(getNowTimeStamp())
        });

        it("If the last time is exceeded, state will be unchanged", async function () {
            const { StakeInstance, LP1Instance, Reward1Instance } = await loadFixture(deployStake);

            const startTime = getNowTimeStamp()
            const deltaTime = 100;
            const rewardPerSecond = 1; // 每一秒一个奖励代币
            const depositAmount = 10000
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, rewardPerSecond, startTime, deltaTime);
            let poolInfo = await StakeInstance.pools(LP1Instance.address);
            await LP1Instance.approve(StakeInstance.address, depositAmount)
            // first update
            await StakeInstance.deposit(LP1Instance.address, depositAmount)
            expect(await LP1Instance.balanceOf(StakeInstance.address)).to.equal(depositAmount)
            poolInfo = await StakeInstance.pools(LP1Instance.address);
            const lastRewardTime1 = poolInfo.lastRewardTime
            // second update => will exceed the end time
            await time.increase(100)
            await StakeInstance.updatePool(LP1Instance.address)
            poolInfo = await StakeInstance.pools(LP1Instance.address);
            const lastTime = startTime + deltaTime
            const reward = (lastTime - lastRewardTime1) * rewardPerSecond
            expect(poolInfo.lastRewardTime).to.equal(lastTime)
            expect(poolInfo.totalReward).to.equal(reward)
            expect(poolInfo.accERC20PerShare).to.equal(reward * 1e12 / depositAmount)
            // third update => will not update
            const totalReward = await StakeInstance.getTotalReward(LP1Instance.address)
            await StakeInstance.updatePool(LP1Instance.address)
            poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(poolInfo.lastRewardTime).to.equal(lastTime)
            expect(poolInfo.totalReward).to.equal(reward)
            expect(poolInfo.accERC20PerShare).to.equal(reward * 1e12 / depositAmount)
            // reward will not add after end time
            expect(await StakeInstance.getTotalReward(LP1Instance.address)).to.equal(totalReward)
        });
    });

    describe("Test function setPoolInfo", function () {
        it("An existed token can't be set", async function () {
            const { StakeInstance, LP1Instance, LP2Instance, Reward1Instance } = await loadFixture(deployStake);

            await expect(StakeInstance.connect(user1).setPoolInfo(LP1Instance.address, 1000, 100000000))
                .to.revertedWith("Ownable: caller is not the owner");
            await expect(StakeInstance.setPoolInfo(LP1Instance.address, 1000, 100000000))
                .to.revertedWith("LP token not exists");
        });

        it("Should set the correct data", async function () {
            const { StakeInstance, LP1Instance, Reward1Instance } = await loadFixture(deployStake);

            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, 1000, startTime, deltaTime);
            // setPoolInfo
            await StakeInstance.setPoolInfo(LP1Instance.address, 10000, startTime + 60 * 60 * 24)
            let poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(poolInfo.rewardPerSecond).to.equal(10000)
            expect(poolInfo.endTime).to.equal(startTime + 60 * 60 * 24) // reduce 
            // setPoolInfo
            await StakeInstance.setPoolInfo(LP1Instance.address, 0, 1000)
            poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(poolInfo.rewardPerSecond).to.equal(0)
            expect(poolInfo.endTime).to.equal(startTime + 60 * 60 * 24) // stay the same
            // setPoolInfo
            await StakeInstance.setPoolInfo(LP1Instance.address, 1000, 1000)
            poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(poolInfo.rewardPerSecond).to.equal(0)
            // 一旦 rewardPerSecond 被设置为0 之后就再也不能重新设置新值了 这算不算一个问题呢
        });
    });

    describe("Test function addToken", function () {
        it("An existed token can't be add", async function () {
            const { StakeInstance, LP1Instance, Reward1Instance } = await loadFixture(deployStake);

            await expect(StakeInstance.connect(user1).addToken(Reward1Instance.address, LP1Instance.address, 1000, 0, 0))
                .to.revertedWith("Ownable: caller is not the owner");
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, 1000, 0, 0);
            await expect(StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, 1000, 0, 0))
                .to.revertedWith("LP token exist");
        });
        it("Should set the correct data", async function () {
            const { StakeInstance, LP1Instance, LP2Instance, Reward1Instance } = await loadFixture(deployStake);

            const startTime = getNowTimeStamp()
            const deltaTime = 60 * 60 * 24 * 7; // 7 days
            await StakeInstance.addToken(Reward1Instance.address, LP1Instance.address, 1000, startTime, deltaTime);
            const poolInfo = await StakeInstance.pools(LP1Instance.address);
            expect(poolInfo.rewardToken).to.equal(Reward1Instance.address)
            expect(poolInfo.lpToken).to.equal(LP1Instance.address)
            expect(poolInfo.lastRewardTime).to.equal(startTime)
            expect(poolInfo.accERC20PerShare).to.equal(0)
            expect(poolInfo.paidOut).to.equal(0)
            expect(poolInfo.rewardPerSecond).to.equal(1000)
            expect(poolInfo.startTime).to.equal(startTime)
            expect(poolInfo.endTime).to.equal(startTime + deltaTime)
        });
    });
});
