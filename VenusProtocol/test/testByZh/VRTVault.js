const {
    time,
    mine,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");


const zero_address = ethers.constants.AddressZero;

describe("VRTVault Unit Test", function () {
    async function deployAndInitializeFixture() {
        // get users;
        const [Owner, Alice,Bob,...users] = await ethers.getSigners();
        // Deploy access_controller
        const MockAccessControlManagerV5 = await ethers.getContractFactory("MockAccessControlManagerV5");
        const access_controller = await MockAccessControlManagerV5.deploy();
        // deploy VRTVault;
        const VRTVault = await ethers.getContractFactory("VRTVault");
        const vault = await VRTVault.deploy();
        // deploy token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const vrt = await MockERC20.deploy("VRT","VRT",ethers.utils.parseEther("100000000"));
        // deploy proxy
        const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
        let proxy = await VRTVaultProxy.deploy(
            vault.address,
            vrt.address,
            ethers.utils.parseEther("0.005")
        );
        proxy = VRTVault.attach(proxy.address);
        await proxy.setAccessControl(access_controller.address);
        return {
            Owner,Alice,Bob,users,proxy,vault,vrt
        };
    }

    describe("initial state unit test", function() {
        it("Check all state vars", async function() {
            const {Owner,proxy,vault,vrt} = await loadFixture(deployAndInitializeFixture);
            const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
            const instance = VRTVaultProxy.attach(proxy.address);
            // instance
            expect(await instance.admin()).to.equal(Owner.address);
            expect(await instance.implementation()).to.equal(vault.address);
            expect(await instance.pendingAdmin()).to.equal(zero_address);
            expect(await instance.pendingImplementation()).to.equal(zero_address);
            // proxy
            expect(await proxy._notEntered()).to.equal(true);
            expect(await proxy.vaultPaused()).to.equal(false);
            expect(await proxy.vrt()).to.equal(vrt.address);
            expect(await proxy.interestRatePerBlock()).to.equal(ethers.utils.parseEther("0.005"));
            expect(await proxy.lastAccruingBlock()).to.equal(0);
        });
    });

    describe("_setImplementation unit test", function() {
        it("_setImplementation only by admin", async function() {
            const {Alice,proxy,users} = await loadFixture(deployAndInitializeFixture);
            const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
            const instance = VRTVaultProxy.attach(proxy.address);
            await expect(instance.connect(Alice)._setImplementation(users[0].address)).to.revertedWith("VRTVaultProxy::_setImplementation: admin only");
        });

        it("implementation_ can't be zero address", async function() {
            const {proxy} = await loadFixture(deployAndInitializeFixture);
            const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
            const instance = VRTVaultProxy.attach(proxy.address);
            await expect(instance._setImplementation(zero_address)).to.revertedWith("VRTVaultProxy::_setImplementation: invalid implementation address");
        });

        it("_setImplementation should change state and emit event", async function() {
            const {proxy,vault,users} = await loadFixture(deployAndInitializeFixture);
            const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
            const instance = VRTVaultProxy.attach(proxy.address);
            expect(await instance._setImplementation(users[0].address)).to.emit(
                instance,"NewImplementation"
            ).withArgs(vault.address,users[0].address);
            expect(await instance.implementation()).to.equal(users[0].address);
        });
    });

    describe("initialize unit test", function(){
        it("initialize twice should be failed", async function() {
            const {proxy,vrt} = await loadFixture(deployAndInitializeFixture);
            await expect(proxy.initialize(vrt.address,ethers.utils.parseEther("0.005"))).to.revertedWith("Vault may only be initialized once");
        });
    });

    describe("Pause and resume test", function() {
        it("pause  and resume contract test", async function() {
            const {Owner,Alice,proxy} = await loadFixture(deployAndInitializeFixture);
            // only Owner
            await expect(proxy.connect(Alice).pause()).to.revertedWith("Unauthorized");
            await expect(proxy.connect(Alice).resume()).to.revertedWith("Unauthorized");
            // pause emit event
            await expect(proxy.pause()).to.emit(
                proxy,"VaultPaused"
            ).withArgs(Owner.address);
            expect(await proxy.vaultPaused()).to.equal(true);
            // pause twice should be failed
            await expect(proxy.pause()).to.revertedWith("Vault is already paused");

            // resume emit event
            await expect(proxy.resume()).to.emit(
                proxy,"VaultResumed"
            ).withArgs(Owner.address);
            expect(await proxy.vaultPaused()).to.equal(false);
            // resume twice should be failed
            await expect(proxy.resume()).to.revertedWith("Vault is not paused");
        });
    });

    describe("withdrawBep20 unit test", function() {
        it("only admin can withdraw", async function() {
            const {Owner,Alice,proxy} = await loadFixture(deployAndInitializeFixture);
            await expect(proxy.connect(Alice).withdrawBep20(Owner.address,Alice.address,100)).to.revertedWith(
                "Unauthorized"
            );
        });

        // High Risk
        it("Can withdraw vrt", async function() {
            const {vrt,Alice,proxy} = await loadFixture(deployAndInitializeFixture);
            await vrt.transfer(proxy.address,10000);
            expect(await vrt.balanceOf(proxy.address)).to.equal(10000);
            expect(await vrt.balanceOf(Alice.address)).to.equal(0);
            await expect(proxy.withdrawBep20(vrt.address,Alice.address,10000)).to.emit(
                proxy,"WithdrawToken"
            ).withArgs(vrt.address,Alice.address,10000);
            expect(await vrt.balanceOf(proxy.address)).to.equal(0);
            expect(await vrt.balanceOf(Alice.address)).to.equal(10000);
        });
    });

    describe("setLastAccruingBlock unit test", function() {
        it("only admin can set", async function() {
            const {Alice,proxy} = await loadFixture(deployAndInitializeFixture);
            await expect(proxy.connect(Alice).setLastAccruingBlock(100)).to.revertedWith("Unauthorized");
        });

        it("Set should change state and emit event", async function() {
            const {proxy} = await loadFixture(deployAndInitializeFixture);
            let block = await time.latestBlock();
            await expect(proxy.setLastAccruingBlock(block + 10)).to.emit(
                proxy,"LastAccruingBlockChanged"
            ).withArgs(0,block + 10);
            expect(await proxy.lastAccruingBlock()).to.equal(block + 10);

            await expect(proxy.setLastAccruingBlock(block + 8)).to.emit(
                proxy,"LastAccruingBlockChanged"
            ).withArgs(block + 10,block + 8); 
            expect(await proxy.lastAccruingBlock()).to.equal(block + 8);
        });

        it("Invalid block setting should be failed", async function(){
            const {proxy} = await loadFixture(deployAndInitializeFixture);
            let block = await time.latestBlock();
            await expect(proxy.setLastAccruingBlock(block + 10)).to.emit(
                proxy,"LastAccruingBlockChanged"
            ).withArgs(0,block + 10);
            expect(await proxy.lastAccruingBlock()).to.equal(block + 10);

            await expect(proxy.setLastAccruingBlock(block + 8)).to.emit(
                proxy,"LastAccruingBlockChanged"
            ).withArgs(block + 10,block + 8); 
            expect(await proxy.lastAccruingBlock()).to.equal(block + 8);

            await expect(proxy.setLastAccruingBlock(block  - 1)).to.rejectedWith(
                "Invalid _lastAccruingBlock interest have been accumulated"
            );
        });
    });

    describe("Deposit | Claim | Withdraw unit test", function() {
        it("Deposit | Claim | Withdraw  ", async function(){
            // prepare 
            const {Alice,vrt,proxy} = await loadFixture(deployAndInitializeFixture);
            await vrt.transfer(Alice.address,10000);
            await vrt.connect(Alice).approve(proxy.address,ethers.constants.MaxUint256);
            let block = await time.latestBlock();
            await proxy.setLastAccruingBlock(block + 10);
            // first deposit
            await expect(proxy.connect(Alice).deposit(1000)).to.emit(
                proxy,"Deposit"
            ).withArgs(Alice.address,1000);
            let info = await proxy.userInfo(Alice.address);
            expect(info.userAddress).to.equal(Alice.address);
            expect(info.accrualStartBlockNumber).to.equal(block + 2);
            expect(info.totalPrincipalAmount).to.equal(1000);
            expect(info.lastWithdrawnBlockNumber).to.equal(0); // unused

            // deposit again;
            await expect(proxy.connect(Alice).deposit(1000)).to.emit(
                proxy,"Claim"
            ).withArgs(Alice.address,1000 * 0.005);

            info = await proxy.userInfo(Alice.address);
            expect(info.userAddress).to.equal(Alice.address);
            expect(info.accrualStartBlockNumber).to.equal(block + 3);
            expect(info.totalPrincipalAmount).to.equal(2000);
            expect(info.lastWithdrawnBlockNumber).to.equal(0);

            await mine(5);
            expect(await proxy.getAccruedInterest(Alice.address)).to.equal(
                2000 * 5 * 0.005
            );
            
            // claim
            await expect(proxy.functions["claim(address)"](Alice.address)).to.emit(
                proxy,"Claim"
            ).withArgs(Alice.address,2000 * 6 * 0.005);
            
            // withdraw should be failed 
            await expect(proxy.connect(Alice).withdraw()).to.revertedWith("Failed to transfer VRT, Insufficient VRT in Vault.");
           
            let start_block = block + 2;
            let end_block = block + 10;
            let deposit_block = await time.latestBlock() + 1;
            
            let interest = 0;
            if (deposit_block >= end_block) {
                interest = 1000 * 0.005 + 2000 * 7 * 0.005;
            } else {
                interest = 1000 * 0.005 + (deposit_block - start_block -1) * 2000 * 0.005;
            }
            await vrt.transfer(proxy.address,interest);
            // withdraw should be successful
            await expect(proxy.connect(Alice).withdraw()).to.emit(
                proxy,"Withdraw"
            ).withArgs(Alice.address,anyValue,2000,anyValue);
            expect(await vrt.balanceOf(proxy.address)).to.equal(0);
        });
    });

});