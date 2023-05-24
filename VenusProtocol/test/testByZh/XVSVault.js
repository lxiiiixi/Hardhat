const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { describe } = require("node:test");

const zero_address = ethers.constants.AddressZero;
const GAIN = ethers.utils.parseUnits("1.0", 12);

describe("XVSVault Unit Test", function () {
    async function deployAndBindFixture() {
        // get users;
        const [Owner, Alice, Bob, ...users] = await ethers.getSigners();
        // Deploy access_controller
        const MockAccessControlManagerV5 = await ethers.getContractFactory("MockAccessControlManagerV5");
        const access_controller = await MockAccessControlManagerV5.deploy();
        // deploy XVSVault;
        const XVSVault = await ethers.getContractFactory("XVSVault");
        const vault = await XVSVault.deploy();
        // deploy proxy
        const XVSVaultProxy = await ethers.getContractFactory("XVSVaultProxy");
        let proxy = await XVSVaultProxy.deploy();
        // deploy XVSStore
        const XVSStore = await ethers.getContractFactory("XVSStore");
        let store = await XVSStore.deploy();
        await store.setNewOwner(proxy.address);
        // binding
        await proxy._setPendingImplementation(vault.address);
        await vault._become(proxy.address);
        proxy = XVSVault.attach(proxy.address);
        await proxy.setAccessControl(access_controller.address);
        // deploy token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const xvs = await MockERC20.deploy("XVS", "XVS", ethers.utils.parseEther("100000000"));
        const vai = await MockERC20.deploy("VAI", "VAI", ethers.utils.parseEther("100000000"));
        const token_a = await MockERC20.deploy("TokenA", "TAT", ethers.utils.parseEther("100000000"));
        const token_b = await MockERC20.deploy("TokenB", "TBT", ethers.utils.parseEther("100000000"));
        await proxy.setXvsStore(xvs.address, store.address);
        // return
        return {
            Owner, Alice, Bob, users, proxy, vault, xvs, vai, access_controller, store, token_a, token_b
        };
    }

    describe("Initial State check", function () {
        it("Check all state vars", async function () {
            const { proxy, vault, Owner, xvs, store } = await loadFixture(deployAndBindFixture);
            expect(await proxy.admin()).to.equal(Owner.address);
            expect(await proxy.pendingAdmin()).to.equal(zero_address);
            expect(await proxy.implementation()).to.equal(vault.address);
            expect(await proxy.pendingXVSVaultImplementation()).to.equal(zero_address);
            expect(await proxy.xvsStore()).to.equal(store.address);
            expect(await proxy.xvsAddress()).to.equal(xvs.address);
            expect(await proxy.vaultPaused()).to.equal(false);
        });
    });

    describe("Pause and resume unit test", function () {
        it("pause  and resume contract test", async function () {
            const { Owner, Alice, proxy } = await loadFixture(deployAndBindFixture);
            // only Owner
            await expect(proxy.connect(Alice).pause()).to.revertedWith("Unauthorized");
            await expect(proxy.connect(Alice).resume()).to.revertedWith("Unauthorized");
            // pause emit event
            await expect(proxy.pause()).to.emit(
                proxy, "VaultPaused"
            ).withArgs(Owner.address);
            expect(await proxy.vaultPaused()).to.equal(true);
            // pause twice should be failed
            await expect(proxy.pause()).to.revertedWith("Vault is already paused");

            // resume emit event
            await expect(proxy.resume()).to.emit(
                proxy, "VaultResumed"
            ).withArgs(Owner.address);
            expect(await proxy.vaultPaused()).to.equal(false);
            // resume twice should be failed
            await expect(proxy.resume()).to.revertedWith("Vault is not paused");
        });
    });

    describe("Change admin and implement test", function () {
        it("only admin can change admin or implement", async function () {
            const { Alice, proxy, users } = await loadFixture(deployAndBindFixture);
            const XVSVaultProxy = await ethers.getContractFactory("XVSVaultProxy");
            let instance = XVSVaultProxy.attach(proxy.address);
            await expect(instance.connect(Alice)._setPendingAdmin(users[0].address)).to.emit(
                instance, "Failure"
            ).withArgs(1, 2, 0);
            expect(await proxy.pendingAdmin()).to.equal(zero_address);

            await expect(instance.connect(Alice)._setPendingImplementation(users[0].address)).to.emit(
                instance, "Failure"
            ).withArgs(1, 3, 0);
            expect(await proxy.pendingXVSVaultImplementation()).to.equal(zero_address);
        });

        it("only pending can accept", async function () {
            const { Owner, Alice, Bob, proxy, vault } = await loadFixture(deployAndBindFixture);
            const XVSVaultProxy = await ethers.getContractFactory("XVSVaultProxy");
            let instance = XVSVaultProxy.attach(proxy.address);

            // set pending
            await expect(instance._setPendingAdmin(Alice.address)).to.emit(
                instance, "NewPendingAdmin"
            ).withArgs(zero_address, Alice.address);
            expect(await proxy.pendingAdmin()).to.equal(Alice.address);
            await expect(instance._setPendingImplementation(Bob.address)).to.emit(
                instance, "NewPendingImplementation"
            ).withArgs(zero_address, Bob.address);
            expect(await proxy.pendingXVSVaultImplementation()).to.equal(Bob.address);

            // accept without pending
            await expect(instance._acceptAdmin()).to.emit(
                instance, "Failure"
            ).withArgs(1, 0, 0);
            expect(await proxy.pendingAdmin()).to.equal(Alice.address);
            await expect(instance._acceptImplementation()).to.emit(
                instance, "Failure"
            ).withArgs(1, 1, 0);
            expect(await proxy.pendingXVSVaultImplementation()).to.equal(Bob.address);

            // accept with pending
            await expect(instance.connect(Alice)._acceptAdmin()).to.emit(
                instance, "NewAdmin"
            ).withArgs(Owner.address, Alice.address);

            await expect(instance.connect(Bob)._acceptImplementation()).to.emit(
                instance, "NewImplementation"
            ).withArgs(vault.address, Bob.address);

            // check final state
            expect(await proxy.admin()).to.equal(Alice.address);
            expect(await proxy.pendingAdmin()).to.equal(zero_address);
            expect(await proxy.implementation()).to.equal(Bob.address);
            expect(await proxy.pendingXVSVaultImplementation()).to.equal(zero_address);
        });
    });

    describe("Add pool unit test", function () {
        it("only user with access_allowed can add pool", async function () {
            const { Alice, token_a, xvs, proxy, vai } = await loadFixture(deployAndBindFixture);
            await expect(proxy.connect(Alice).add(xvs.address, 50, token_a.address, 50, 300)).to.revertedWith("Unauthorized");
        });

        it("Add pool should change state and emit event", async function () {
            const { token_a, token_b, xvs, vai, proxy, store } = await loadFixture(deployAndBindFixture);
            await expect(proxy.add(xvs.address, 50, token_a.address, 100, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(xvs.address, 0, token_a.address, 50, 100, 300);
            let block = await time.latestBlock();
            expect(await store.rewardTokens(xvs.address)).to.equal(true);
            let { token, allocPoint, lastRewardBlock, accRewardPerShare, lockPeriod } = await proxy.poolInfos(xvs.address, 0);
            expect(token).to.equal(token_a.address);
            expect(allocPoint).to.equal(50);
            expect(lastRewardBlock).to.equal(block);
            expect(accRewardPerShare).to.equal(0);
            expect(lockPeriod).to.equal(300);

            expect(await proxy.rewardTokenAmountsPerBlock(xvs.address)).to.equal(100);
            expect(await proxy.totalAllocPoints(xvs.address)).to.equal(50);
            expect(await proxy.poolLength(xvs.address)).to.equal(1);

            // add same should be failed
            await expect(proxy.add(xvs.address, 50, token_a.address, 100, 300)).to.revertedWith("Pool already added");
            // add token_b
            await expect(proxy.add(xvs.address, 50, token_b.address, 200, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(xvs.address, 1, token_b.address, 50, 200, 300);

            block = await time.latestBlock();
            ({ token, allocPoint, lastRewardBlock, accRewardPerShare, lockPeriod } = await proxy.poolInfos(xvs.address, 1));
            expect(token).to.equal(token_b.address);
            expect(allocPoint).to.equal(50);
            expect(lastRewardBlock).to.equal(block);
            expect(accRewardPerShare).to.equal(0);
            expect(lockPeriod).to.equal(300);

            expect(await proxy.rewardTokenAmountsPerBlock(xvs.address)).to.equal(200);
            expect(await proxy.totalAllocPoints(xvs.address)).to.equal(100);
            expect(await proxy.poolLength(xvs.address)).to.equal(2);

            // check token_a
            ({ token, allocPoint, lastRewardBlock, accRewardPerShare, lockPeriod } = await proxy.poolInfos(xvs.address, 0));
            expect(token).to.equal(token_a.address);
            expect(allocPoint).to.equal(50);
            expect(lastRewardBlock).to.equal(block);
            expect(accRewardPerShare).to.equal(0);
            expect(lockPeriod).to.equal(300);

            // add another reward token;
            await expect(proxy.add(token_a.address, 50, xvs.address, 100, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(token_a.address, 0, xvs.address, 50, 100, 300);

            // add same deposit token
            await expect(proxy.add(vai.address, 50, token_a.address, 100, 300)).to.revertedWith("Token exists in other pool");
        });
    });

    describe("Reset _allocPoint unit test", function () {
        it("only user with access_allowed can reset pool", async function () {
            const { Alice, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.connect(Alice).set(xvs.address, 50, 300)).to.revertedWith("Unauthorized");
        });
        it("only valid pool can be reset", async function () {
            const { xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.set(xvs.address, 50, 300)).to.revertedWith("vault: pool exists?");
        });

        it("Reset must update pool", async function () {
            const { token_a, token_b, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.add(xvs.address, 50, token_a.address, 100, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(xvs.address, 0, token_a.address, 50, 100, 300);
            await expect(proxy.add(xvs.address, 50, token_b.address, 100, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(xvs.address, 1, token_b.address, 50, 100, 300);
            // reset
            expect(await proxy.totalAllocPoints(xvs.address)).to.equal(100);
            await expect(proxy.set(xvs.address, 0, 100)).to.emit(
                proxy, "PoolUpdated"
            ).withArgs(xvs.address, 0, 50, 100);
            // check state
            let block = await time.latestBlock();
            let { token, allocPoint, lastRewardBlock, accRewardPerShare, lockPeriod } = await proxy.poolInfos(xvs.address, 0);
            expect(token).to.equal(token_a.address);
            expect(allocPoint).to.equal(100);
            expect(lastRewardBlock).to.equal(block);
            expect(accRewardPerShare).to.equal(0);
            expect(lockPeriod).to.equal(300);
            expect(await proxy.totalAllocPoints(xvs.address)).to.equal(150);
        });
    });

    describe("setRewardAmountPerBlock unit test", function () {
        it("only user with access_allowed can reset reward", async function () {
            const { Alice, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.connect(Alice).setRewardAmountPerBlock(xvs.address, 300)).to.revertedWith("Unauthorized");
        });

        it("set should update pool and change state", async function () {
            const { token_a, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.add(xvs.address, 50, token_a.address, 100, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(xvs.address, 0, token_a.address, 50, 100, 300);

            expect(await proxy.rewardTokenAmountsPerBlock(xvs.address)).to.equal(100);
            await expect(proxy.setRewardAmountPerBlock(xvs.address, 200)).to.emit(
                proxy, "RewardAmountUpdated"
            ).withArgs(xvs.address, 100, 200);
            // check state after set
            expect(await proxy.rewardTokenAmountsPerBlock(xvs.address)).to.equal(200);
            let block = await time.latestBlock();
            let info = await proxy.poolInfos(xvs.address, 0);
            expect(info.lastRewardBlock).to.equal(block);
        });
    });

    describe("setWithdrawalLockingPeriod unit test", function () {
        it("only user with access_allowed can reset locking period", async function () {
            const { Alice, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.connect(Alice).setWithdrawalLockingPeriod(xvs.address, 0, 300)).to.revertedWith("Unauthorized");
        });

        it("Pool must be valid", async function () {
            const { xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.setWithdrawalLockingPeriod(xvs.address, 0, 300)).to.revertedWith("vault: pool exists?");
        });

        it("period must be greater than zero", async function () {
            const { token_a, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.add(xvs.address, 50, token_a.address, 100, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(xvs.address, 0, token_a.address, 50, 100, 300);
            await expect(proxy.setWithdrawalLockingPeriod(xvs.address, 0, 0)).to.revertedWith("Invalid new locking period");
        });

        it("Reset should change state and emit event", async function () {
            const { token_a, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.add(xvs.address, 50, token_a.address, 100, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(xvs.address, 0, token_a.address, 50, 100, 300);
            await expect(proxy.setWithdrawalLockingPeriod(xvs.address, 0, 400)).to.emit(
                proxy, "WithdrawalLockingPeriodUpdated"
            ).withArgs(xvs.address, 0, 300, 400);
            let block = await time.latestBlock();
            let info = await proxy.poolInfos(xvs.address, 0);
            expect(info.lastRewardBlock).to.equal(block - 1);
            expect(info.lockPeriod).to.equal(400);
        });
    });

    describe("delegate unit test", function () {
        it("Delegate should emit event", async function () {
            const { Alice, Bob, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.connect(Alice).delegate(Bob.address)).to.emit(
                proxy, "DelegateChangedV2"
            ).withArgs(Alice.address, zero_address, Bob.address);
        });
    });

    describe("Deposit unit test", function () {
        it("The pool must be valid", async function () {
            const { xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.deposit(xvs.address, 1, 100)).to.revertedWith("vault: pool exists?");
        });
        it("Deposit should update pool and change user's state", async function () {
            const { token_a, Alice, Bob, xvs, vai, proxy, store } = await loadFixture(deployAndBindFixture);
            // prepare
            await token_a.transfer(Alice.address, 100000000);
            await token_a.transfer(Bob.address, 100000000);
            await xvs.transfer(Alice.address, 100000000);
            await xvs.transfer(Bob.address, 100000000);
            await token_a.connect(Alice).approve(proxy.address, ethers.constants.MaxUint256);
            await xvs.connect(Alice).approve(proxy.address, ethers.constants.MaxUint256);
            await token_a.connect(Bob).approve(proxy.address, ethers.constants.MaxUint256);
            await xvs.connect(Bob).approve(proxy.address, ethers.constants.MaxUint256);
            await vai.transfer(store.address, ethers.utils.parseEther("100000000"))

            let all_rewards = ethers.utils.parseEther("1");
            // add pool
            await expect(proxy.add(vai.address, 50, token_a.address, all_rewards, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(vai.address, 0, token_a.address, 50, all_rewards, 300);
            await expect(proxy.add(vai.address, 100, xvs.address, all_rewards, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(vai.address, 1, xvs.address, 100, all_rewards, 300);
            let block = await time.latestBlock();
            // Alice deposit token_a;
            await expect(proxy.connect(Alice).deposit(vai.address, 0, 10000)).to.emit(
                proxy, "Deposit"
            ).withArgs(Alice.address, vai.address, 0, 10000);

            let alice_info = await proxy.getUserInfo(vai.address, 0, Alice.address);
            expect(alice_info.amount).equal(10000);
            expect(alice_info.rewardDebt).equal(0);
            expect(alice_info.pendingWithdrawals).equal(0);
            let pool_info = await proxy.poolInfos(vai.address, 0);
            expect(pool_info.lastRewardBlock).to.eq(block + 1);
            expect(pool_info.accRewardPerShare).to.eq(0);
            // Bob deposit token_a;
            await expect(proxy.connect(Bob).deposit(vai.address, 0, 10000)).to.emit(
                proxy, "Deposit"
            ).withArgs(Bob.address, vai.address, 0, 10000);

            pool_info = await proxy.poolInfos(vai.address, 0);
            expect(pool_info.lastRewardBlock).to.eq(block + 2);
            let reward_pershare = all_rewards.mul(50).div(150).mul(GAIN).div(10000);
            expect(pool_info.accRewardPerShare).to.eq(reward_pershare);
            // Alice deposit again;
            let offset = all_rewards.mul(50).div(150).mul(GAIN).div(20000);
            reward_pershare = reward_pershare.add(offset);
            let pending = reward_pershare.mul(10000).div(GAIN);
            // expect(await proxy.pendingReward(vai.address,0,Alice.address)).to.equal(pending);
            // claim or deposit should transfer reward
            await expect(proxy.connect(Alice).claim(Alice.address, vai.address, 0)).to.emit(
                vai, "Transfer"
            ).withArgs(store.address, Alice.address, pending);
            await expect(proxy.connect(Alice).deposit(vai.address, 0, 10000)).to.emit(
                vai, "Transfer"
            ).withArgs(store.address, Alice.address, anyValue);
        });
    });



    describe("Claim unit test", function () {
        it("The pool must be valid", async function () {
            const { Alice, xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.claim(Alice.address, xvs.address, 1)).to.revertedWith("vault: pool exists?");
        });
    });



    describe("requestWithdrawal unit test", function () {
        it("The pool must be valid", async function () {
            const { xvs, proxy } = await loadFixture(deployAndBindFixture);
            await expect(proxy.requestWithdrawal(xvs.address, 1, 100)).to.revertedWith("vault: pool exists?");
        });

        it("requestWithdrawal should emit event and change state", async function () {
            const { token_a, Alice, Bob, xvs, vai, proxy, store } = await loadFixture(deployAndBindFixture);
            // prepare
            await token_a.transfer(Alice.address, 100000000);
            await token_a.transfer(Bob.address, 100000000);
            await xvs.transfer(Alice.address, 100000000);
            await xvs.transfer(Bob.address, 100000000);
            await token_a.connect(Alice).approve(proxy.address, ethers.constants.MaxUint256);
            await xvs.connect(Alice).approve(proxy.address, ethers.constants.MaxUint256);
            await token_a.connect(Bob).approve(proxy.address, ethers.constants.MaxUint256);
            await xvs.connect(Bob).approve(proxy.address, ethers.constants.MaxUint256);
            await vai.transfer(store.address, ethers.utils.parseEther("100000000"))
            let all_rewards = ethers.utils.parseEther("1");
            // add pool
            await expect(proxy.add(vai.address, 50, token_a.address, all_rewards, 300)).to.emit(
                proxy, "PoolAdded"
            ).withArgs(vai.address, 0, token_a.address, 50, all_rewards, 300);
            await proxy.connect(Alice).deposit(vai.address, 0, 10000);
            time.increase(9);
            await proxy.connect(Alice).deposit(vai.address, 0, 20000);
            time.increase(9);
            // requestWithdrawal
            let amount = 5000;

            await expect(proxy.connect(Alice).requestWithdrawal(vai.address, 0, amount)).to.emit(
                proxy, "RequestedWithdrawal"
            ).withArgs(Alice.address, vai.address, 0, 5000);
            expect(await proxy.getRequestedAmount(vai.address, 0, Alice.address)).to.equal(5000);
            await time.increase(9);
            await proxy.connect(Alice).requestWithdrawal(vai.address, 0, 6000);
            await time.increase(9);
            await proxy.setWithdrawalLockingPeriod(vai.address, 0, 200);
            await proxy.connect(Alice).requestWithdrawal(vai.address, 0, 3000);
            await time.increase(9);
            await proxy.setWithdrawalLockingPeriod(vai.address, 0, 250);
            await proxy.connect(Alice).requestWithdrawal(vai.address, 0, 2000);
            // check sort
            let requests = await proxy.getWithdrawalRequests(vai.address, 0, Alice.address);
            expect(requests.length).to.equal(4);
            expect(requests[0].amount).to.equal(6000);
            expect(requests[1].amount).to.equal(5000);
            expect(requests[2].amount).to.equal(2000);
            expect(requests[3].amount).to.equal(3000);


            expect(await proxy.getRequestedAmount(vai.address, 0, Alice.address)).to.equal(6000 + 5000 + 3000 + 2000);
            expect(await proxy.pendingWithdrawalsBeforeUpgrade(vai.address, 0, Alice.address)).to.equal(0);

            let user_info = await proxy.getUserInfo(vai.address, 0, Alice.address);
            expect(user_info.amount).to.equal(30000);
            expect(user_info.pendingWithdrawals).to.equal(16000);
            expect(await proxy.getRequestedAmount(vai.address, 0, Alice.address)).to.equal(16000);
            await time.increase(253);
            let can_withdraw = await proxy.getEligibleWithdrawalAmount(vai.address, 0, Alice.address);
            expect(can_withdraw).to.equal(5000);

            // exec withdraw
            await expect(proxy.connect(Alice).executeWithdrawal(vai.address, 0)).to.emit(
                proxy, "ExecutedWithdrawal"
            ).withArgs(Alice.address, vai.address, 0, 5000);

            requests = await proxy.getWithdrawalRequests(vai.address, 0, Alice.address);
            expect(requests.length).to.equal(2);

            user_info = await proxy.getUserInfo(vai.address, 0, Alice.address);
            expect(user_info.amount).to.equal(25000);
            expect(user_info.pendingWithdrawals).to.equal(11000);
        });
    });

    describe("Deposit | withdraw with delegates", function () {
        it("delegate before deposit", async function () {
            const { Alice, Bob, xvs, proxy, store, users } = await loadFixture(deployAndBindFixture);
            // delegate first;
            await proxy.connect(Alice).delegate(Bob.address);

            await xvs.transfer(Alice.address, 10000000);
            await xvs.transfer(store.address, ethers.utils.parseEther("10000"));
            await xvs.connect(Alice).approve(proxy.address, ethers.constants.MaxInt256);
            // add pool
            await proxy.add(xvs.address, 100, xvs.address, ethers.utils.parseEther("1.0"), 200);

            // deposit
            await expect(proxy.connect(Alice).deposit(xvs.address, 0, 10000)).to.emit(
                proxy, "DelegateVotesChangedV2"
            ).withArgs(Bob.address, 0, 10000);
            await expect(proxy.connect(Alice).deposit(xvs.address, 0, 10000)).to.emit(
                proxy, "DelegateVotesChangedV2"
            ).withArgs(Bob.address, 10000, 20000);
            let block = await time.latestBlock();
            expect(await proxy.getCurrentVotes(Bob.address)).to.equal(20000);
            expect(await proxy.getCurrentVotes(Alice.address)).to.equal(0);
            expect(await proxy.getPriorVotes(Bob.address, block - 1)).to.equal(10000);
            // withdraw 
            await proxy.connect(Alice).requestWithdrawal(xvs.address, 0, 2000);
            expect(await proxy.getPriorVotes(Bob.address, block)).to.equal(20000);
            expect(await proxy.getCurrentVotes(Bob.address)).to.equal(18000);
        });

        it("Delegate after deposit", async function () {
            const { Alice, Bob, xvs, proxy, store, users } = await loadFixture(deployAndBindFixture);
            await xvs.transfer(Alice.address, 10000000);
            await xvs.transfer(store.address, ethers.utils.parseEther("10000"));
            await xvs.connect(Alice).approve(proxy.address, ethers.constants.MaxInt256);
            // add pool
            await proxy.add(xvs.address, 100, xvs.address, ethers.utils.parseEther("1.0"), 200);
            // deposit
            await proxy.connect(Alice).deposit(xvs.address, 0, 10000);
            expect(await proxy.getCurrentVotes(Alice.address)).to.equal(0);
            // delegate
            await proxy.connect(Alice).delegate(Bob.address);
            expect(await proxy.getCurrentVotes(Alice.address)).to.equal(0);
            expect(await proxy.getCurrentVotes(Bob.address)).to.equal(10000);
            // withdraw
            let block = await time.latestBlock();
            await proxy.connect(Alice).requestWithdrawal(xvs.address, 0, 2000);
            expect(await proxy.getPriorVotes(Bob.address, block)).to.equal(10000);
            expect(await proxy.getCurrentVotes(Bob.address)).to.equal(8000);
        });
    });
});