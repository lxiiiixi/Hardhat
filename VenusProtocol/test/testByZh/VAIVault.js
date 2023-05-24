const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const zero_address = ethers.constants.AddressZero;

describe("VAIVault Unit Test", function () {
    async function deployAndBindFixture() {
        // get users;
        const [Owner, Alice,Bob,...users] = await ethers.getSigners();
        // Deploy access_controller
        const MockAccessControlManagerV5 = await ethers.getContractFactory("MockAccessControlManagerV5");
        const access_controller = await MockAccessControlManagerV5.deploy();
        // deploy VAIVault;
        const VAIVault = await ethers.getContractFactory("VAIVault");
        const vault = await VAIVault.deploy();
        // deploy proxy
        const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
        let proxy = await VAIVaultProxy.deploy();
        // binding
        await proxy._setPendingImplementation(vault.address);
        await vault._become(proxy.address);
        proxy = VAIVault.attach(proxy.address);
        await proxy.setAccessControl(access_controller.address);
        // deploy token
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const xvs = await MockERC20.deploy("XVS","XVS",ethers.utils.parseEther("100000000"));
        const vai = await MockERC20.deploy("VAI","VAI",ethers.utils.parseEther("100000000"));
        await proxy.setVenusInfo(xvs.address,vai.address);
        // return
        return {
            Owner,Alice,Bob,users,proxy,vault,xvs,vai,access_controller
        };
    }

    describe("Initial state check", function() {
        it("VAIVaultStorage state check", async function() {
            const {Owner,proxy,vault,xvs,vai,access_controller} = await loadFixture(deployAndBindFixture);
            expect(await proxy.admin()).to.equal(Owner.address);
            expect(await proxy.pendingAdmin()).to.equal(zero_address);
            expect(await proxy.vaiVaultImplementation()).to.equal(vault.address);
            expect(await proxy.pendingVAIVaultImplementation()).to.equal(zero_address);
            expect(await proxy.xvs()).to.equal(xvs.address);
            expect(await proxy.vai()).to.equal(vai.address);
            expect(await proxy.xvsBalance()).to.equal(0);
            expect(await proxy.accXVSPerShare()).to.equal(0);
            expect(await proxy.pendingRewards()).to.equal(0);
            expect(await proxy.vaultPaused()).to.equal(false);
            expect(await proxy.accessControlManager()).to.equal(access_controller.address);
        });
    });

    describe("Change admin and implement test", function() {
        it("only admin can change admin or implement", async function() {
            const {Alice,proxy,users} = await loadFixture(deployAndBindFixture);
            const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
            let instance = VAIVaultProxy.attach(proxy.address);
            await expect(instance.connect(Alice)._setPendingAdmin(users[0].address)).to.emit(
                instance,"Failure"
            ).withArgs(1,2,0);
            expect(await proxy.pendingAdmin()).to.equal(zero_address);

            await expect(instance.connect(Alice)._setPendingImplementation(users[0].address)).to.emit(
                instance,"Failure"
            ).withArgs(1,3,0);
            expect(await proxy.pendingVAIVaultImplementation()).to.equal(zero_address);
        });

        it("only pending can accept", async function() {
            const {Owner,Alice,Bob,proxy,vault} = await loadFixture(deployAndBindFixture);
            const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
            let instance = VAIVaultProxy.attach(proxy.address);

            // set pending
            await expect(instance._setPendingAdmin(Alice.address)).to.emit(
                instance,"NewPendingAdmin"
            ).withArgs(zero_address,Alice.address);
            expect(await proxy.pendingAdmin()).to.equal(Alice.address);
            await expect(instance._setPendingImplementation(Bob.address)).to.emit(
                instance,"NewPendingImplementation"
            ).withArgs(zero_address,Bob.address);
            expect(await proxy.pendingVAIVaultImplementation()).to.equal(Bob.address);

            // accept without pending
            await expect(instance._acceptAdmin()).to.emit(
                instance,"Failure"
            ).withArgs(1,0,0);
            expect(await proxy.pendingAdmin()).to.equal(Alice.address);
            await expect(instance._acceptImplementation()).to.emit(
                instance,"Failure"
            ).withArgs(1,1,0);
            expect(await proxy.pendingVAIVaultImplementation()).to.equal(Bob.address);

            // accept with pending
            await expect(instance.connect(Alice)._acceptAdmin()).to.emit(
                instance,"NewAdmin"
            ).withArgs(Owner.address,Alice.address);
            
            await expect(instance.connect(Bob)._acceptImplementation()).to.emit(
                instance,"NewImplementation"
            ).withArgs(vault.address,Bob.address);

            // check final state
            expect(await proxy.admin()).to.equal(Alice.address);
            expect(await proxy.pendingAdmin()).to.equal(zero_address);
            expect(await proxy.vaiVaultImplementation()).to.equal(Bob.address);
            expect(await proxy.pendingVAIVaultImplementation()).to.equal(zero_address);
        });
    });

    describe("Pause and resume test", function() {
        it("pause  and resume contract test", async function() {
            const {Owner,Alice,proxy} = await loadFixture(deployAndBindFixture);
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

    // 
    describe("setVenusInfo test", function() {
        it("only admin can set info", async function() {
            const {proxy,Alice,users} = await loadFixture(deployAndBindFixture);
            await expect(proxy.connect(Alice).setVenusInfo(users[0].address,users[1].address)).to.revertedWith("only admin can");
        });

        // reset 
        it("VenusInfo can't be reset", async function() {
            const {proxy,users} = await loadFixture(deployAndBindFixture);
            await expect(proxy.setVenusInfo(users[0].address,users[1].address)).to.revertedWith("addresses already set");
        });
    });

    // describe("Get/Set Admin or Burn Admin test", function() {
    //     // redundant
    //     it("get  and burn admin test", async function() {
    //         const {Owner,proxy} = await loadFixture(deployAndBindFixture);
    //         expect(await proxy.getAdmin()).to.equal(Owner.address);
    //     });

    //     it("only admin can burn admin", async function () {
    //         const {Alice,proxy} = await loadFixture(deployAndBindFixture);
    //         await expect(proxy.connect(Alice).burnAdmin()).to.revertedWith("only admin can");
    //     });

    //     // AdminTransfered => AdminTransferred
    //     it("Burn admin should emit event and change state", async function() {
    //         const {Owner,proxy} = await loadFixture(deployAndBindFixture);
    //         await expect(proxy.burnAdmin()).to.emit(
    //             proxy,"AdminTransfered"
    //         ).withArgs(Owner.address,zero_address);
    //     });

    //     // redundant
    //     it("Set only admin", async function() {
    //         const {Alice,proxy} = await loadFixture(deployAndBindFixture);
    //         await expect(proxy.connect(Alice).setNewAdmin(Alice.address)).to.revertedWith("only admin can");
    //     });

    //     it("Set to zero address should be failed", async function() {
    //         const {proxy} = await loadFixture(deployAndBindFixture);
    //         await expect(proxy.setNewAdmin(zero_address)).to.revertedWith("new owner is the zero address");
    //     });

    //     // AdminTransfered => AdminTransferred
    //     it("Set new admin should emit event and change state", async function() {
    //         const {Owner,proxy,Alice} = await loadFixture(deployAndBindFixture);
    //         await expect(proxy.setNewAdmin(Alice.address)).to.emit(
    //             proxy,"AdminTransfered"
    //         ).withArgs(Owner.address,Alice.address);
    //     });
    // });

    describe("setAccessControl test", function() {
        it("Only admin can set", async function() {
            const {Alice,proxy} = await loadFixture(deployAndBindFixture);
            await expect(proxy.connect(Alice).setAccessControl(zero_address)).to.revertedWith("only admin can");
        });
        it("Can not set to zero address", async function() {
            const {proxy} = await loadFixture(deployAndBindFixture);
            await expect(proxy.setAccessControl(zero_address)).to.revertedWith("invalid acess control manager address");
        });
        it("setAccessControl should change state and emit event", async function() {
            const {proxy,access_controller,Bob} = await loadFixture(deployAndBindFixture);
            await expect(proxy.setAccessControl(Bob.address)).to.emit(
                proxy,"NewAccessControlManager"
            ).withArgs(access_controller.address,Bob.address);
            expect(await proxy.accessControlManager()).to.equal(Bob.address);
        });
    });

    describe("updatePendingRewards test", function() {
        it("updatePending should change records", async function() {
            let value = ethers.constants.WeiPerEther;
            const {xvs,proxy} = await loadFixture(deployAndBindFixture);
            await xvs.transfer(proxy.address, value);
            await proxy.updatePendingRewards();
            expect(await proxy.xvsBalance()).to.equal(value);
            expect(await proxy.pendingRewards()).to.equal(value);
        });
    });

    //
    describe("Deposit test", function () {
        it("Deposit should be failed while paused", async function() {
            const {Alice,proxy} = await loadFixture(deployAndBindFixture);
            await proxy.pause();
            await expect(proxy.connect(Alice).deposit(10000)).to.revertedWith("Vault is paused");
        });

        it("Deposit should change state and emit event", async function() {
            const {xvs,vai,Alice,Bob,proxy} = await loadFixture(deployAndBindFixture);
            // prepare
            await xvs.transfer(proxy.address,ethers.constants.WeiPerEther);
            await proxy.updatePendingRewards();
            await vai.transfer(Alice.address,ethers.utils.parseEther("10000"));
            await vai.transfer(Bob.address,ethers.utils.parseEther("10000"));
            await vai.connect(Alice).approve(proxy.address,ethers.constants.MaxInt256);
            await vai.connect(Bob).approve(proxy.address,ethers.constants.MaxInt256);
            // Alice deposit
            let deposit_amount = ethers.utils.parseEther("100");
            await expect(proxy.connect(Alice).deposit(deposit_amount)).to.emit(
                proxy,"Deposit"
            ).withArgs(Alice.address,deposit_amount);
            let alice_info = await proxy.userInfo(Alice.address);
            expect(alice_info.amount).to.equal(deposit_amount);
            expect(alice_info.rewardDebt).to.equal(0);
            expect(await proxy.accXVSPerShare()).to.equal(0);
            // Bob deposit
            await proxy.connect(Bob).deposit(deposit_amount);
            expect(await proxy.accXVSPerShare()).to.equal(ethers.constants.WeiPerEther.div(100));
            let bob_info = await proxy.userInfo(Bob.address);
            expect(bob_info.amount).to.equal(deposit_amount);
            expect(bob_info.rewardDebt).to.equal(ethers.constants.WeiPerEther);
            // check pending
            expect(await proxy.pendingXVS(Alice.address)).to.equal(ethers.constants.WeiPerEther);
            expect(await proxy.pendingXVS(Bob.address)).to.equal(0);

            // bob deposit again
            await proxy.connect(Bob).deposit(deposit_amount); 
            bob_info = await proxy.userInfo(Bob.address);
            expect(bob_info.amount).to.equal(deposit_amount.mul(2));
            expect(bob_info.rewardDebt).to.equal(ethers.constants.WeiPerEther.mul(2));

            // bob claim ;
            await proxy.functions["claim(address)"](Bob.address); 
            bob_info = await proxy.userInfo(Bob.address);
            expect(bob_info.amount).to.equal(deposit_amount.mul(2));
            expect(bob_info.rewardDebt).to.equal(ethers.constants.WeiPerEther.mul(2));

            // rewards again;
            await xvs.transfer(proxy.address,ethers.constants.WeiPerEther);
            await proxy.updatePendingRewards();
            
            let share = ethers.constants.WeiPerEther.div(100).add(ethers.constants.WeiPerEther.div(300));
            let pending = share.mul(100);

            // Alice withdraw
            await expect(proxy.connect(Alice).withdraw(0)).to.emit(
                xvs,"Transfer"
            ).withArgs(proxy.address,Alice.address,pending);
            expect(await proxy.accXVSPerShare()).to.equal(share);
            
            alice_info = await proxy.userInfo(Alice.address);
            expect(alice_info.amount).to.equal(deposit_amount);
            expect(alice_info.rewardDebt).to.equal(pending);

            bob_info = await proxy.userInfo(Bob.address);
            expect(bob_info.amount).to.equal(deposit_amount.mul(2));
            expect(bob_info.rewardDebt).to.equal(ethers.constants.WeiPerEther.mul(2));
            
            // withdraw should transfer all the xvs(精度)
            let balance = await xvs.balanceOf(proxy.address);
            await expect(proxy.connect(Bob).functions["claim()"]()).to.emit(
                xvs,"Transfer"
            ).withArgs(proxy.address,Bob.address,balance.sub(100));
        });
    });


    describe("Bug Demo", function () {
        it("Rewards can convert to xvsBalance",async function () {
            const {xvs,vai,Alice,Bob,proxy} = await loadFixture(deployAndBindFixture);
            // prepare
            await xvs.transfer(proxy.address,ethers.constants.WeiPerEther);
            await proxy.updatePendingRewards();
            await vai.transfer(Alice.address,ethers.utils.parseEther("10000"));
            await vai.transfer(Bob.address,ethers.utils.parseEther("10000"));
            await vai.connect(Alice).approve(proxy.address,ethers.constants.MaxInt256);
            await vai.connect(Bob).approve(proxy.address,ethers.constants.MaxInt256);
            // Alice deposit
            let deposit_amount = ethers.utils.parseEther("100");
            await expect(proxy.connect(Alice).deposit(deposit_amount)).to.emit(
                proxy,"Deposit"
            ).withArgs(Alice.address,deposit_amount);
            // Bob deposit before updatePendingRewards()
            await proxy.connect(Bob).deposit(deposit_amount);
            // transfer xvs to proxy;
            await xvs.transfer(proxy.address,ethers.constants.WeiPerEther);
            // Alice withdraw between transfer xvs and updatePendingRewards
            await proxy.connect(Alice).withdraw(deposit_amount);
            // updatePendingRewards
            await proxy.updatePendingRewards(); 

            let balance = await xvs.balanceOf(proxy.address);
            expect(balance).to.equal(ethers.constants.WeiPerEther);
            // 
            let alice_info = await proxy.userInfo(Alice.address);
            expect(alice_info.amount).to.equal(0);
            expect(alice_info.rewardDebt).to.equal(0);
            
            // dead coin
            let xvsBalance = await proxy.xvsBalance();
            expect(xvsBalance).to.equal(balance);

            let pending = await proxy.pendingRewards();
            expect(pending).to.equal(0);
            // Bob has no rewards
            let pending_bob = await proxy.pendingXVS(Bob.address);
            expect(pending_bob).to.equal(0);
        });
    });

    // describe("Recover owner demo", function() {
    //     it("Recover owner after burn owner", async function() {
    //         const {Alice,proxy,Bob} = await loadFixture(deployAndBindFixture);
    //         const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
    //         let instance = VAIVaultProxy.attach(proxy.address);
    //         await instance._setPendingAdmin(Alice.address);
    //         expect(await proxy.pendingAdmin()).to.equal(Alice.address);
    //         await proxy.burnAdmin();
    //         expect(await proxy.admin()).to.equal(zero_address);
    //         await instance.connect(Alice)._acceptAdmin();
    //         expect(await proxy.admin()).to.equal(Alice.address);
    //         expect(await proxy.pendingAdmin()).to.equal(zero_address);
    //     });

    //     it("Recover owner after setNewAdmin", async function() {
    //         const {Alice,proxy,Bob} = await loadFixture(deployAndBindFixture);
    //         const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
    //         let instance = VAIVaultProxy.attach(proxy.address);
    //         await instance._setPendingAdmin(Alice.address);
    //         expect(await proxy.pendingAdmin()).to.equal(Alice.address);
    //         await proxy.setNewAdmin(Bob.address);
    //         expect(await proxy.admin()).to.equal(Bob.address);
    //         await instance.connect(Alice)._acceptAdmin();
    //         expect(await proxy.admin()).to.equal(Alice.address);
    //         expect(await proxy.pendingAdmin()).to.equal(zero_address);
    //     });
    // });
});