const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const zero_address = ethers.constants.AddressZero;
const GAIN = ethers.utils.parseUnits("1.0",12);

describe("XVSVault Upgrade Unit Test", function () {
    async function deployAndBindFixture() {
        // get users;
        const [Owner, Alice,Bob,...users] = await ethers.getSigners();
        // Deploy old_impl
        const XVSVaultOld = await ethers.getContractFactory("XVSVaultOld");
        const vault = await XVSVaultOld.deploy();
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
        proxy = XVSVaultOld.attach(proxy.address);
        // deploy token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const xvs = await MockERC20.deploy("XVS","XVS",ethers.utils.parseEther("100000000"));
        const vai = await MockERC20.deploy("VAI","VAI",ethers.utils.parseEther("100000000"));
        const token_a = await MockERC20.deploy("TokenA","TAT",ethers.utils.parseEther("100000000"));
        const token_b = await MockERC20.deploy("TokenB","TBT",ethers.utils.parseEther("100000000"));
        await proxy.setXvsStore(xvs.address,store.address);
        // return
        return {
            Owner,Alice,Bob,users,proxy,vault,xvs,vai,store,token_a,token_b
        };
    }

    it("Add a pool and deposit", async function() {
        let {token_a,Alice,Bob,xvs,vai,proxy,store} = await loadFixture(deployAndBindFixture);
        // prepare
        await token_a.transfer(Alice.address,100000000);
        await token_a.transfer(Bob.address,100000000);
        await xvs.transfer(Alice.address,100000000);
        await xvs.transfer(Bob.address,100000000);
        await token_a.connect(Alice).approve(proxy.address,ethers.constants.MaxUint256);
        await xvs.connect(Alice).approve(proxy.address,ethers.constants.MaxUint256);
        await token_a.connect(Bob).approve(proxy.address,ethers.constants.MaxUint256);
        await xvs.connect(Bob).approve(proxy.address,ethers.constants.MaxUint256);
        await vai.transfer(store.address,ethers.utils.parseEther("100000000"))

        let all_rewards = ethers.utils.parseEther("1");
        // add pool
        await expect(proxy.add(vai.address,50,token_a.address,all_rewards,300)).to.emit(
            proxy,"PoolAdded"
        ).withArgs(vai.address,0,token_a.address,50,all_rewards,300);
        await expect(proxy.add(vai.address,100,xvs.address,all_rewards,300)).to.emit(
            proxy,"PoolAdded"
        ).withArgs(vai.address,1,xvs.address,100,all_rewards,300);

        let block = await time.latestBlock();
        // Alice deposit token_a;
        await expect(proxy.connect(Alice).deposit(vai.address,0,10000)).to.emit(
            proxy,"Deposit"
        ).withArgs(Alice.address,vai.address,0,10000);
        let alice_info = await proxy.getUserInfo(vai.address,0,Alice.address);
        expect(alice_info.amount).equal(10000);
        expect(alice_info.rewardDebt).equal(0);
        expect(alice_info.pendingWithdrawals).equal(0);
        let pool_info = await proxy.poolInfos(vai.address,0);
        expect(pool_info.lastRewardBlock).to.eq(block + 1);
        expect(pool_info.accRewardPerShare).to.eq(0);
        await time.increase(9);
        await proxy.connect(Alice).requestWithdrawal(vai.address,0,6000);
        await time.increase(9);
        let requests = await proxy.getWithdrawalRequests(vai.address,0,Alice.address);
        console.log(requests);

        // upgrade
        const XVSVaultNew = await ethers.getContractFactory("XVSVault");
        const vault = await XVSVaultNew.deploy();
        const XVSVaultProxy = await ethers.getContractFactory("XVSVaultProxy");
        proxy = XVSVaultProxy.attach(proxy.address);
        await proxy._setPendingImplementation(vault.address);
        await vault._become(proxy.address);
        proxy = XVSVaultNew.attach(proxy.address);

        requests = await proxy.getWithdrawalRequests(vai.address,0,Alice.address);
        console.log(requests);
    });
});