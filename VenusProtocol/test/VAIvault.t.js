const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("VAIVault Test", function () {
  const AddressZero = ethers.constants.AddressZero;
  const WeiPerEther = ethers.constants.WeiPerEther;
  let admin, user1, user2;

  async function deployContracts() {
    [admin, user1, user2, ...otherAccount] = await ethers.getSigners();

    // deploy VAIVault
    const VAIVault = await ethers.getContractFactory("VAIVault");
    const VAIVaultInstance = await VAIVault.deploy();
    // deploy VAIVaultProxy
    const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
    let VAIVaultProxyInstance = await VAIVaultProxy.deploy();
    // set pending Implementation 
    await VAIVaultProxyInstance._setPendingImplementation(VAIVaultInstance.address);
    await VAIVaultInstance._become(VAIVaultProxyInstance.address);
    VAIVaultProxyInstance = VAIVault.attach(VAIVaultProxyInstance.address);

    // deploy token: XVS, VAI
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const XVSInstance = await MockERC20.deploy("XVS", "XVS", ethers.utils.parseEther("30000000"));
    const VAIInstance = await MockERC20.deploy("VAI", "VAI", ethers.utils.parseEther("30000000"));
    // deploy accessControl
    const MockAccessControlManagerV5 = await ethers.getContractFactory("MockAccessControlManagerV5");
    const AccessController = await MockAccessControlManagerV5.deploy();
    // set tokens and accessControl by proxy
    VAIVaultProxyInstance.setVenusInfo(XVSInstance.address, VAIInstance.address);
    VAIVaultProxyInstance.setAccessControl(AccessController.address);

    return { VAIVaultInstance, VAIVaultProxyInstance, XVSInstance, VAIInstance, AccessController };
  }

  // describe("Deploy and check metadata", function () {
  //   it("Should set the right storage data", async function () {
  //     const { VAIVaultInstance, VAIVaultProxyInstance, XVSInstance, VAIInstance } = await loadFixture(deployContracts);
  //     expect(await VAIVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await VAIVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);
  //     expect(await VAIVaultProxyInstance.vaiVaultImplementation()).to.equal(VAIVaultInstance.address);
  //     expect(await VAIVaultProxyInstance.pendingVAIVaultImplementation()).to.equal(AddressZero);
  //     expect(await VAIVaultProxyInstance.xvs()).to.equal(XVSInstance.address);
  //     expect(await VAIVaultProxyInstance.vai()).to.equal(VAIInstance.address);
  //     expect(await VAIVaultProxyInstance.xvsBalance()).to.equal(0);
  //     expect(await VAIVaultProxyInstance.accXVSPerShare()).to.equal(0);
  //     expect(await VAIVaultProxyInstance.pendingRewards()).to.equal(0);
  //     expect(await VAIVaultProxyInstance.vaultPaused()).to.equal(false);
  //   });
  // });

  // describe("Test proxy functions", function () {
  //   it("Test change implementation", async function () {
  //     let { VAIVaultInstance, VAIVaultProxyInstance, XVSInstance, VAIInstance } = await loadFixture(deployContracts);

  //     // deploy a new VAIVault contract
  //     const VAIVault = await ethers.getContractFactory("VAIVault");
  //     const NewVAIVaultInstance = await VAIVault.deploy();
  //     const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
  //     VAIVaultProxyInstance = VAIVaultProxy.attach(VAIVaultProxyInstance.address);

  //     // set a new implementation
  //     // Fail: only admin can setPendingImplementation
  //     await expect(VAIVaultProxyInstance.connect(user1)._setPendingImplementation(NewVAIVaultInstance.address))
  //       .to.be.emit(VAIVaultProxyInstance, "Failure").withArgs(1, 3, 0);
  //     expect(await VAIVaultProxyInstance.vaiVaultImplementation()).to.equal(VAIVaultInstance.address);
  //     expect(await VAIVaultProxyInstance.pendingVAIVaultImplementation()).to.equal(AddressZero);

  //     // Success: admin setPendingImplementation
  //     expect(await VAIVaultProxyInstance._setPendingImplementation(NewVAIVaultInstance.address))
  //       .to.be.emit(VAIVaultProxyInstance, "NewPendingImplementation")
  //       .withArgs(VAIVaultInstance.address, NewVAIVaultInstance.address);
  //     expect(await VAIVaultProxyInstance.vaiVaultImplementation()).to.equal(VAIVaultInstance.address);
  //     expect(await VAIVaultProxyInstance.pendingVAIVaultImplementation()).to.equal(NewVAIVaultInstance.address);

  //     // Success: NewVAIVaultInstance acceptImplementation
  //     expect(await NewVAIVaultInstance._become(VAIVaultProxyInstance.address))
  //       .to.be.emit(VAIVaultProxyInstance, "NewImplementation")
  //       .withArgs(VAIVaultInstance.address, NewVAIVaultInstance.address);
  //     expect(await VAIVaultProxyInstance.vaiVaultImplementation()).to.equal(NewVAIVaultInstance.address);
  //     expect(await VAIVaultProxyInstance.pendingVAIVaultImplementation()).to.equal(AddressZero);
  //   });

  //   it("Test change admin", async function () {
  //     let { VAIVaultInstance, VAIVaultProxyInstance, XVSInstance, VAIInstance } = await loadFixture(deployContracts);

  //     const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
  //     VAIVaultProxyInstance = VAIVaultProxy.attach(VAIVaultProxyInstance.address);

  //     // set a new admin
  //     // Fail: only admin can setPendingImplementation
  //     await expect(VAIVaultProxyInstance.connect(user1)._setPendingAdmin(user1.address))
  //       .to.be.emit(VAIVaultProxyInstance, "Failure").withArgs(1, 2, 0);
  //     expect(await VAIVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await VAIVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);

  //     // Success: admin setPendingImplementation
  //     expect(await VAIVaultProxyInstance._setPendingAdmin(user1.address))
  //       .to.be.emit(VAIVaultProxyInstance, "NewPendingAdmin")
  //       .withArgs(admin.address, user1.address);
  //     expect(await VAIVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await VAIVaultProxyInstance.pendingAdmin()).to.equal(user1.address);

  //     // Fail: only pendingAdmin can accept admin
  //     await expect(VAIVaultProxyInstance._acceptAdmin())
  //       .to.be.emit(VAIVaultProxyInstance, "Failure").withArgs(1, 0, 0);
  //     // Success: user1 acceptAdmin
  //     await expect(VAIVaultProxyInstance.connect(user1)._acceptAdmin())
  //       .to.be.emit(VAIVaultProxyInstance, "NewAdmin")
  //       .withArgs(admin.address, user1.address);
  //     expect(await VAIVaultProxyInstance.admin()).to.equal(user1.address);
  //     expect(await VAIVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);
  //   });
  // });

  // describe("Test setVenusInfo", function () {
  //   it("Should only be called by the admin", async function () {
  //     let { VAIVaultInstance, VAIVaultProxyInstance, XVSInstance, VAIInstance } = await loadFixture(deployContracts);

  //     // deploy new tokens
  //     const MockERC20 = await ethers.getContractFactory("MockERC20");
  //     const NewXVSInstance = await MockERC20.deploy("XVS", "XVS", 30000000);
  //     const NewVAIInstance = await MockERC20.deploy("VAI", "VAI", 30000000);

  //     await expect(VAIVaultProxyInstance.connect(user1).setVenusInfo(NewXVSInstance.address, NewVAIInstance.address))
  //       .to.revertedWith("only admin can")

  //     await VAIVaultProxyInstance.setVenusInfo(NewXVSInstance.address, NewVAIInstance.address)
  //     expect(await VAIVaultProxyInstance.xvs()).to.equal(NewXVSInstance.address);
  //     expect(await VAIVaultProxyInstance.vai()).to.equal(NewVAIInstance.address);
  //   });
  // });

  // describe("Test setAccessControl", function () {
  //   it("Should only be called by the admin and should set a valid address", async function () {
  //     let { VAIVaultProxyInstance, AccessController } = await loadFixture(deployContracts);

  //     await expect(VAIVaultProxyInstance.connect(user1).setAccessControl(user1.address))
  //       .to.revertedWith("only admin can")
  //     await expect(VAIVaultProxyInstance.setAccessControl(AddressZero)).to.revertedWith("invalid acess control manager address");
  //     expect(await VAIVaultProxyInstance.accessControlManager()).to.equal(AccessController.address);
  //     await VAIVaultProxyInstance.setAccessControl(user1.address)
  //     expect(await VAIVaultProxyInstance.accessControlManager()).to.equal(user1.address);
  //   });
  // });

  // describe("Test pause and resume", function () {
  //   it("Should need pause and resume access", async function () {
  //     let { VAIVaultProxyInstance, AccessController } = await loadFixture(deployContracts);
  //     await expect(VAIVaultProxyInstance.connect(user1).pause()).to.revertedWith("Unauthorized")
  //     await expect(VAIVaultProxyInstance.connect(user1).resume()).to.revertedWith("Unauthorized")
  //     expect(await VAIVaultProxyInstance.vaultPaused()).to.equal(false);
  //     await VAIVaultProxyInstance.pause()
  //     await expect(VAIVaultProxyInstance.pause()).to.revertedWith("Vault is already paused")
  //   });

  //   it("Should change state", async function () {
  //     let { VAIVaultProxyInstance, AccessController } = await loadFixture(deployContracts);
  //     await expect(VAIVaultProxyInstance.pause())
  //       .to.be.emit(VAIVaultProxyInstance, "VaultPaused").withArgs(admin.address);
  //     expect(await VAIVaultProxyInstance.vaultPaused()).to.equal(true);
  //     await expect(VAIVaultProxyInstance.deposit(1000)).to.revertedWith("Vault is paused")
  //     await expect(VAIVaultProxyInstance.resume())
  //       .to.be.emit(VAIVaultProxyInstance, "VaultResumed").withArgs(admin.address);
  //     expect(await VAIVaultProxyInstance.vaultPaused()).to.equal(false);
  //   });
  // });

  // describe("Test deposit", function () {
  //   it("Test fist deposit will set the correct data", async function () {
  //     let { VAIVaultProxyInstance, VAIInstance, XVSInstance } = await loadFixture(deployContracts);

  //     const depositVAIAmount = ethers.utils.parseEther("10000000")
  //     const XVSAmount = ethers.utils.parseEther("10000000")
  //     // proxy must have enough allowance
  //     VAIInstance.approve(VAIVaultProxyInstance.address, depositVAIAmount);
  //     expect(await VAIInstance.balanceOf(admin.address)).to.equal(ethers.utils.parseEther("30000000"));
  //     // update pending rewards
  //     await XVSInstance.transfer(VAIVaultProxyInstance.address, XVSAmount)
  //     await VAIVaultProxyInstance.updatePendingRewards()
  //     expect(await VAIVaultProxyInstance.xvsBalance()).to.equal(XVSAmount);
  //     expect(await VAIVaultProxyInstance.pendingRewards()).to.equal(XVSAmount);
  //     // emit event
  //     await expect(VAIVaultProxyInstance.deposit(depositVAIAmount))
  //       .to.be.emit(VAIVaultProxyInstance, "Deposit").withArgs(admin.address, depositVAIAmount);
  //     // check balance and data
  //     expect(await VAIInstance.balanceOf(admin.address)).to.equal(ethers.utils.parseEther("20000000"));
  //     expect(await VAIInstance.balanceOf(VAIVaultProxyInstance.address)).to.equal(depositVAIAmount);
  //     const userInfo = await VAIVaultProxyInstance.userInfo(admin.address)
  //     expect(userInfo.amount).to.equal(depositVAIAmount);
  //     expect(userInfo.rewardDebt).to.equal(0); // accXVSPerShare is 0 now
  //     expect(await VAIVaultProxyInstance.accXVSPerShare()).to.equal(0);
  //   });

  //   it("Test more deposits will set the correct data", async function () {
  //     let { VAIVaultProxyInstance, VAIInstance, XVSInstance } = await loadFixture(deployContracts);

  //     const depositVAIAmount = ethers.utils.parseEther("10000000")
  //     const XVSAmount = ethers.utils.parseEther("10000000")
  //     await VAIInstance.transfer(user1.address, depositVAIAmount);
  //     await VAIInstance.transfer(user2.address, depositVAIAmount);
  //     await VAIInstance.connect(user1).approve(VAIVaultProxyInstance.address, depositVAIAmount);
  //     await VAIInstance.connect(user2).approve(VAIVaultProxyInstance.address, depositVAIAmount);
  //     expect(await VAIInstance.balanceOf(user1.address)).to.equal(depositVAIAmount);
  //     expect(await VAIInstance.balanceOf(user2.address)).to.equal(depositVAIAmount);
  //     await XVSInstance.transfer(VAIVaultProxyInstance.address, XVSAmount)
  //     await VAIVaultProxyInstance.updatePendingRewards()
  //     expect(await VAIVaultProxyInstance.pendingRewards()).to.equal(XVSAmount);
  //     // user1 deposit
  //     await expect(VAIVaultProxyInstance.connect(user1).deposit(depositVAIAmount))
  //       .to.be.emit(VAIVaultProxyInstance, "Deposit").withArgs(user1.address, depositVAIAmount);
  //     expect(await VAIInstance.balanceOf(user1.address)).to.equal(0);
  //     expect(await VAIInstance.balanceOf(VAIVaultProxyInstance.address)).to.equal(depositVAIAmount);
  //     const user1Info = await VAIVaultProxyInstance.userInfo(user1.address)
  //     expect(user1Info.amount).to.equal(depositVAIAmount);
  //     expect(user1Info.rewardDebt).to.equal(0);
  //     // check common data
  //     const VAIBalance = await VAIInstance.balanceOf(VAIVaultProxyInstance.address)
  //     const pendingRewards = await VAIVaultProxyInstance.pendingRewards()
  //     expect(pendingRewards).to.equal(XVSAmount);
  //     expect(await VAIVaultProxyInstance.accXVSPerShare()).to.equal(0);
  //     // user2 deposit
  //     await expect(VAIVaultProxyInstance.connect(user2).deposit(depositVAIAmount))
  //       .to.be.emit(VAIVaultProxyInstance, "Deposit").withArgs(user2.address, depositVAIAmount);
  //     const accXVSPerShare = await VAIVaultProxyInstance.accXVSPerShare()
  //     const user2Info = await VAIVaultProxyInstance.userInfo(user2.address)
  //     expect(accXVSPerShare).to.equal(pendingRewards.mul(WeiPerEther).div(VAIBalance));
  //     expect(user2Info.amount).to.equal(depositVAIAmount);
  //     expect(user2Info.rewardDebt).to.equal(depositVAIAmount.mul(accXVSPerShare).div(WeiPerEther));
  //     expect(await VAIVaultProxyInstance.pendingRewards()).to.equal(0);
  //   });

  //   it("Test claim and withdraw", async function () {
  //     let { VAIVaultProxyInstance, XVSInstance, VAIInstance } = await loadFixture(deployContracts);

  //     const depositVAIAmount = ethers.utils.parseEther("10000000")
  //     const XVSAmount = ethers.utils.parseEther("10000000")
  //     await VAIInstance.transfer(user1.address, depositVAIAmount);
  //     await VAIInstance.transfer(user2.address, depositVAIAmount);
  //     await VAIInstance.connect(user1).approve(VAIVaultProxyInstance.address, depositVAIAmount);
  //     await VAIInstance.connect(user2).approve(VAIVaultProxyInstance.address, depositVAIAmount);
  //     expect(await VAIInstance.balanceOf(user1.address)).to.equal(depositVAIAmount);
  //     expect(await VAIInstance.balanceOf(user2.address)).to.equal(depositVAIAmount);
  //     await XVSInstance.transfer(VAIVaultProxyInstance.address, XVSAmount)
  //     await VAIVaultProxyInstance.updatePendingRewards()
  //     // users deposit 
  //     await VAIVaultProxyInstance.connect(user1).deposit(depositVAIAmount)
  //     await VAIVaultProxyInstance.connect(user2).deposit(depositVAIAmount)
  //     const accXVSPerShare = await VAIVaultProxyInstance.accXVSPerShare()
  //     const user1PendingXVS = depositVAIAmount.mul(accXVSPerShare).div(WeiPerEther)
  //     expect(await VAIVaultProxyInstance.pendingXVS(user1.address)).to.equal(user1PendingXVS);
  //     expect(await VAIVaultProxyInstance.pendingXVS(user2.address)).to.equal(0);
  //     // users claim
  //     // 为什么要这样才能触发 claim  VAIVaultProxyInstance.connect(...).claim is not a function
  //     await expect(VAIVaultProxyInstance.functions["claim(address)"](user1.address))
  //       .to.be.emit(VAIVaultProxyInstance, "Withdraw").withArgs(user1.address, 0);
  //     expect(await XVSInstance.balanceOf(user1.address)).to.equal(user1PendingXVS);
  //     expect(await XVSInstance.balanceOf(user2.address)).to.equal(0);
  //     // users withdraw
  //     await expect(VAIVaultProxyInstance.connect(user1).withdraw(depositVAIAmount.add(depositVAIAmount)))
  //       .to.revertedWith("withdraw: not good")
  //     await expect(VAIVaultProxyInstance.connect(user1).withdraw(depositVAIAmount))
  //       .to.be.emit(VAIVaultProxyInstance, "Withdraw").withArgs(user1.address, depositVAIAmount);
  //     expect(await VAIInstance.balanceOf(user1.address)).to.equal(depositVAIAmount);
  //   });
  // });

  describe("Bugs reoccurrences", function () {
    it("User can do anything between the xvs being transfered to and updatePendingRewards exceuting", async function () {
      let { VAIVaultProxyInstance, VAIInstance, XVSInstance } = await loadFixture(deployContracts);

      const depositVAIAmount = ethers.utils.parseEther("10000000")
      const XVSAmount = ethers.utils.parseEther("10000000")
      await VAIInstance.transfer(user1.address, depositVAIAmount);
      await VAIInstance.connect(user1).approve(VAIVaultProxyInstance.address, depositVAIAmount);
      // update xvs rewards
      await XVSInstance.transfer(VAIVaultProxyInstance.address, XVSAmount)
      expect(await XVSInstance.balanceOf(VAIVaultProxyInstance.address)).to.equal(XVSAmount);
      expect(await VAIVaultProxyInstance.xvsBalance()).to.equal(0);
      expect(await VAIVaultProxyInstance.pendingRewards()).to.equal(0);
      expect(await VAIVaultProxyInstance.accXVSPerShare()).to.equal(0);
      // await VAIVaultProxyInstance.updatePendingRewards()

      // user deposit (will trigger updatePendingRewards)
      await VAIVaultProxyInstance.connect(user1).deposit(depositVAIAmount.div(2))
      console.log(await VAIVaultProxyInstance.accXVSPerShare());
      await VAIVaultProxyInstance.connect(user1).deposit(depositVAIAmount.div(2))
      console.log(await VAIVaultProxyInstance.accXVSPerShare());

      // 在 updatePendingRewards 执行之前 pendingRewards 为 0 
      // 那么 updateVault 时计算得到的 accXVSPerShare 也为 0 
      // pendingXVS 计算得到的当前用户的待领取的 XVS 也为 0
      // updateAndPayOutPending 不会执行 safeXVSTransfer
      // 那么也不会在 safeXVSTransfer 实现 xvsBalance 的更新

      // expect(await VAIVaultProxyInstance.xvsBalance()).to.equal(XVSAmount);
      // console.log(await VAIVaultProxyInstance.xvsBalance());
      // console.log(await VAIVaultProxyInstance.pendingXVS(user1.address));
      // console.log(await XVSInstance.balanceOf(user1.address));
      // console.log(await XVSInstance.balanceOf(VAIVaultProxyInstance.address))

    });

    it("User can repeatedly get vxs", async function () {
      let { VAIVaultProxyInstance, VAIInstance, XVSInstance } = await loadFixture(deployContracts);

      // const depositVAIAmount = ethers.utils.parseEther("10000000")
      // const XVSAmount = ethers.utils.parseEther("10000000")
      // await VAIInstance.transfer(user1.address, depositVAIAmount);
      // await VAIInstance.connect(user1).approve(VAIVaultProxyInstance.address, depositVAIAmount);
      // // update xvs rewards
      // await XVSInstance.transfer(VAIVaultProxyInstance.address, XVSAmount)
      // expect(await XVSInstance.balanceOf(VAIVaultProxyInstance.address)).to.equal(XVSAmount);
      // expect(await VAIVaultProxyInstance.xvsBalance()).to.equal(0);
      // expect(await VAIVaultProxyInstance.pendingRewards()).to.equal(0);
      // expect(await VAIVaultProxyInstance.accXVSPerShare()).to.equal(0);
      // // await VAIVaultProxyInstance.updatePendingRewards()

      // // user deposit (will trigger updatePendingRewards)
      // await VAIVaultProxyInstance.connect(user1).deposit(depositVAIAmount.div(2))
      // await VAIVaultProxyInstance.connect(user1).deposit(depositVAIAmount.div(2))
      // // expect(await VAIVaultProxyInstance.xvsBalance()).to.equal(XVSAmount);

      // // console.log(await VAIVaultProxyInstance.xvsBalance());
      // // console.log(await VAIVaultProxyInstance.pendingXVS(user1.address));
      // // console.log(await XVSInstance.balanceOf(user1.address));
      // // console.log(await XVSInstance.balanceOf(VAIVaultProxyInstance.address))
      // // console.log(await VAIVaultProxyInstance.accXVSPerShare());

    });

    // it("User can get admin by pendingAdmin", async function () {
    //   let { VAIVaultProxyInstance, VAIInstance, XVSInstance } = await loadFixture(deployContracts);
    //   const VAIVaultProxy = await ethers.getContractFactory("VAIVaultProxy");
    //   const VAIVault = await ethers.getContractFactory("VAIVault");
    //   VAIVaultProxyInstance = VAIVaultProxy.attach(VAIVaultProxyInstance.address);

    //   // set pending admin
    //   expect(await VAIVaultProxyInstance._setPendingAdmin(user1.address))
    //     .to.be.emit(VAIVaultProxyInstance, "NewPendingAdmin")
    //     .withArgs(admin.address, user1.address);
    //   expect(await VAIVaultProxyInstance.admin()).to.equal(admin.address);
    //   expect(await VAIVaultProxyInstance.pendingAdmin()).to.equal(user1.address);
    //   // burn admin
    //   VAIVaultProxyInstance = VAIVault.attach(VAIVaultProxyInstance.address);
    //   expect(await VAIVaultProxyInstance.burnAdmin())
    //     .to.be.emit(VAIVaultProxyInstance, "AdminTransfered")
    //     .withArgs(admin.address, AddressZero);
    //   expect(await VAIVaultProxyInstance.admin()).to.equal(AddressZero);
    //   expect(await VAIVaultProxyInstance.pendingAdmin()).to.equal(user1.address);
    //   // user1 get admin
    //   VAIVaultProxyInstance = VAIVaultProxy.attach(VAIVaultProxyInstance.address);
    //   expect(await VAIVaultProxyInstance.connect(user1)._acceptAdmin())
    //     .to.be.emit(VAIVaultProxyInstance, "NewAdmin")
    //     .withArgs(admin.address, user1.address);
    //   expect(await VAIVaultProxyInstance.admin()).to.equal(user1.address);
    // });

    // it("Function setVenusInfo can be called repeated", async function () {
    //   let { VAIVaultProxyInstance, VAIInstance, XVSInstance } = await loadFixture(deployContracts);

    //   const depositVAIAmount = ethers.utils.parseEther("10000000")
    //   const XVSAmount = ethers.utils.parseEther("10000000")
    //   await VAIInstance.transfer(user1.address, depositVAIAmount);
    //   await VAIInstance.connect(user1).approve(VAIVaultProxyInstance.address, depositVAIAmount);
    //   await XVSInstance.transfer(VAIVaultProxyInstance.address, XVSAmount)
    //   await VAIVaultProxyInstance.connect(user1).deposit(depositVAIAmount)
    //   await VAIVaultProxyInstance.updatePendingRewards()

    //   // prepare needed data after setVenusInfo
    //   const MockERC20 = await ethers.getContractFactory("MockERC20");
    //   const NewXVSInstance = await MockERC20.deploy("XVS", "XVS", ethers.utils.parseEther("30000000"));
    //   const NewVAIInstance = await MockERC20.deploy("VAI", "VAI", ethers.utils.parseEther("30000000"));
    //   await NewVAIInstance.connect(user1).approve(NewXVSInstance.address, depositVAIAmount);
    //   await NewXVSInstance.transfer(VAIVaultProxyInstance.address, XVSAmount)

    //   // setVenusInfo again (set a wrong parameter order)
    //   await VAIVaultProxyInstance.setVenusInfo(NewVAIInstance.address, NewXVSInstance.address);
    //   await VAIVaultProxyInstance.connect(user1).withdraw(XVSAmount)
    //   // user1 withdraw VAI but get XVS
    //   expect(await NewXVSInstance.balanceOf(user1.address)).to.equal(XVSAmount);
    //   expect(await NewVAIInstance.balanceOf(user1.address)).to.equal(0);
    // });

    // it("Admin can be directly replace is not safe, _setPendingAdmin is recommend", async function () {
    //   let { VAIVaultProxyInstance } = await loadFixture(deployContracts);
    //   expect(await VAIVaultProxyInstance.admin()).to.equal(admin.address);
    //   await VAIVaultProxyInstance.setNewAdmin(user1.address);
    //   expect(await VAIVaultProxyInstance.admin()).to.equal(user1.address);
    // });
  });
});
