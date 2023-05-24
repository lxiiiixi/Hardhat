const {
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");

const { expect } = require("chai");
const { ethers } = require("hardhat");

const zero_address = ethers.constants.AddressZero;

describe("XVSStore Unit Test", function () {
    async function deployFixture() {
        // get users;
        const [Owner, Alice, Bob, ...users] = await ethers.getSigners();
        // Deploy XVSStore
        const XVSStore = await ethers.getContractFactory("XVSStore");
        const store = await XVSStore.deploy();
        // token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const xvs = await MockERC20.deploy("XVS", "XVS", ethers.utils.parseEther("100000000"));
        const vai = await MockERC20.deploy("VAI", "VAI", ethers.utils.parseEther("100000000"));
        return {
            store, Owner, Alice, Bob, xvs, vai, users
        };
    }

    describe("Initial state check", function () {
        it("Check all state after deploy", async function () {
            const { store, Owner } = await loadFixture(deployFixture);
            expect(await store.admin()).to.equal(Owner.address);
            expect(await store.pendingAdmin()).to.equal(zero_address);
            expect(await store.owner()).to.equal(zero_address);
        });
    });

    describe("setPendingAdmin unit test", function () {
        it("only admin can call it", async function () {
            const { store, Alice } = await loadFixture(deployFixture);
            await expect(store.connect(Alice).setPendingAdmin(Alice.address)).to.revertedWith("only admin can");
        });

        it("setPendingAdmin should change state and emit event", async function () {
            const { store, Alice, Bob } = await loadFixture(deployFixture);
            await expect(store.setPendingAdmin(Alice.address)).to.emit(
                store, "NewPendingAdmin"
            ).withArgs(zero_address, Alice.address);
            expect(await store.pendingAdmin()).to.equal(Alice.address);
            // can set twice
            await expect(store.setPendingAdmin(Bob.address)).to.emit(
                store, "NewPendingAdmin"
            ).withArgs(Alice.address, Bob.address);
            expect(await store.pendingAdmin()).to.equal(Bob.address);
        });
    });

    describe("acceptAdmin unit test", function () {
        it("only pendingAdmin can call it", async function () {
            const { store, Alice, Bob } = await loadFixture(deployFixture);
            await store.setPendingAdmin(Alice.address);
            await expect(store.connect(Bob).acceptAdmin()).to.revertedWith("only pending admin");
        });

        it("acceptAdmin should change state and emit event", async function () {
            const { store, Alice, Owner } = await loadFixture(deployFixture);
            await store.setPendingAdmin(Alice.address);
            await expect(store.connect(Alice).acceptAdmin()).to.emit(
                store, "AdminTransferred"
            ).withArgs(Owner.address, Alice.address);
            expect(await store.admin()).to.equal(Alice.address);
            expect(await store.pendingAdmin()).to.equal(zero_address);
        });
    });

    describe("setNewOwner", function () {
        it("only admin can call it", async function () {
            const { store, Alice } = await loadFixture(deployFixture);
            await expect(store.connect(Alice).setNewOwner(Alice.address)).to.revertedWith("only admin can");
        });
        it("set to zero address should be failed", async function () {
            const { store } = await loadFixture(deployFixture);
            await expect(store.setNewOwner(zero_address)).to.revertedWith("new owner is the zero address");
        });

        it("set should change state and emit event", async function () {
            const { store, Alice, Bob } = await loadFixture(deployFixture);
            await expect(store.setNewOwner(Alice.address)).to.emit(
                store, "OwnerTransferred"
            ).withArgs(zero_address, Alice.address);
            expect(await store.owner()).to.equal(Alice.address);
            // owner can't call it
            await expect(store.connect(Alice).setNewOwner(Bob.address)).to.revertedWith("only admin can");
            // set again
            await expect(store.setNewOwner(Bob.address)).to.emit(
                store, "OwnerTransferred"
            ).withArgs(Alice.address, Bob.address);
            expect(await store.owner()).to.equal(Bob.address);
        });
    });

    describe("setRewardToken unit test", function () {
        it("Only owner or admin can call", async function () {
            const { store, Alice, Bob, xvs } = await loadFixture(deployFixture);
            await store.setNewOwner(Alice.address);
            await expect(store.connect(Bob).setRewardToken(xvs.address, true)).to.revertedWith("only admin or owner can");

            await store.connect(Alice).setRewardToken(xvs.address, true);
            expect(await store.rewardTokens(xvs.address)).to.equal(true);

            await store.setRewardToken(xvs.address, false);
            expect(await store.rewardTokens(xvs.address)).to.equal(false);
        });
    });

    describe("emergencyRewardWithdraw unit test", function () {
        it("only owner can call it", async function () {
            const { store, Owner } = await loadFixture(deployFixture);
            await expect(store.emergencyRewardWithdraw(Owner.address, 100)).to.rejectedWith("only owner can");
        });

        it("call it will transfer token", async function () {
            const { store, Alice, xvs } = await loadFixture(deployFixture);
            await store.setNewOwner(Alice.address);
            await xvs.transfer(store.address, 10000);
            expect(await xvs.balanceOf(store.address)).to.equal(10000);
            expect(await xvs.balanceOf(Alice.address)).to.equal(0);
            await expect(store.connect(Alice).emergencyRewardWithdraw(xvs.address, 1000)).to.emit(
                xvs, "Transfer"
            ).withArgs(store.address, Alice.address, 1000);

            expect(await xvs.balanceOf(store.address)).to.equal(9000);
            expect(await xvs.balanceOf(Alice.address)).to.equal(1000);
        });
    });

    describe("safeRewardTransfer unit test", function () {
        it("only owner can call it", async function () {
            const { store, Owner, xvs } = await loadFixture(deployFixture);
            await expect(store.safeRewardTransfer(xvs.address, Owner.address, 100)).to.rejectedWith("only owner can");
        });

        it("call should be failed while not set reward token", async function () {
            const { store, Owner, xvs } = await loadFixture(deployFixture);
            await store.setNewOwner(Owner.address);
            await expect(store.safeRewardTransfer(xvs.address, Owner.address, 100)).to.rejectedWith("only reward token can");
        });

        it("Transfer rewards beyond balance test", async function () {
            const { store, Owner, xvs, Alice } = await loadFixture(deployFixture);
            await store.setNewOwner(Owner.address);
            await store.setRewardToken(xvs.address, true);
            await xvs.transfer(store.address, 10000);
            await expect(store.safeRewardTransfer(xvs.address, Alice.address, 200000)).to.emit(
                xvs, "Transfer"
            ).withArgs(store.address, Alice.address, 10000);
            expect(await xvs.balanceOf(store.address)).to.equal(0);
            expect(await xvs.balanceOf(Alice.address)).to.equal(10000);
        });

        it("Transfer rewards not beyond balance test", async function () {
            const { store, Owner, xvs, Alice } = await loadFixture(deployFixture);
            await store.setNewOwner(Owner.address);
            await store.setRewardToken(xvs.address, true);
            await xvs.transfer(store.address, 10000);
            await expect(store.safeRewardTransfer(xvs.address, Alice.address, 2000)).to.emit(
                xvs, "Transfer"
            ).withArgs(store.address, Alice.address, 2000);
            expect(await xvs.balanceOf(store.address)).to.equal(8000);
            expect(await xvs.balanceOf(Alice.address)).to.equal(2000);
        });
    });
});