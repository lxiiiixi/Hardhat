const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("VAIVault Test", function () {
  const AddressZero = ethers.constants.AddressZero;
  const WeiPerEther = ethers.constants.WeiPerEther;
  const interestRatePerBlock = 10;
  let admin, user1, user2;

  async function deployContracts() {
    [admin, user1, user2, ...otherAccount] = await ethers.getSigners();

    // deploy token: VRT
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const VRTInstance = await MockERC20.deploy("VRT", "VRT", ethers.utils.parseEther("30000000"));
    // deploy VRTVault
    const VRTVault = await ethers.getContractFactory("VRTVault");
    const VRTVaultInstance = await VRTVault.deploy();
    // deploy VRTVaultProxy and set implementation
    const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
    let VRTVaultProxyInstance = await VRTVaultProxy.deploy(VRTVaultInstance.address, VRTInstance.address, interestRatePerBlock);
    VRTVaultProxyInstance = VRTVault.attach(VRTVaultProxyInstance.address);
    // deploy and set accessControl
    const MockAccessControlManagerV5 = await ethers.getContractFactory("MockAccessControlManagerV5");
    const AccessController = await MockAccessControlManagerV5.deploy();
    VRTVaultProxyInstance.setAccessControl(AccessController.address);

    return { VRTVaultInstance, VRTVaultProxyInstance, VRTInstance, AccessController };
  }

  describe("Bugs reoccurrences", function () {
    it("Admin can withdraw vrt arbitrarily to anyone", async function () {
      const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

      const depositVRTAmount = ethers.utils.parseEther("10000000")
      await VRTInstance.transfer(user1.address, depositVRTAmount);
      await VRTInstance.transfer(VRTVaultProxyInstance.address, depositVRTAmount);
      await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
      await VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount)

      const userInfo = await VRTVaultProxyInstance.userInfo(user1.address)
      expect(userInfo.totalPrincipalAmount).to.equal(depositVRTAmount);
      expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(depositVRTAmount.mul(2));
      expect(await VRTInstance.balanceOf(user1.address)).to.equal(0);

      await expect(VRTVaultProxyInstance.withdrawBep20(VRTInstance.address, user1.address, depositVRTAmount))
        .to.be.emit(VRTVaultProxyInstance, "WithdrawToken")
        .withArgs(VRTInstance.address, user1.address, depositVRTAmount);

      const newUserInfo = await VRTVaultProxyInstance.userInfo(user1.address)
      expect(newUserInfo.totalPrincipalAmount).to.equal(depositVRTAmount);
      expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount);
      expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(depositVRTAmount);

      await VRTVaultProxyInstance.connect(user1).withdraw()
      expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(0);
      expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount.mul(2));
    });

    it("User will fail to withdraw while VRT is not enough", async function () {
      const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

      const depositVRTAmount = ethers.utils.parseEther("10000000")
      const interestPerBlock = depositVRTAmount.mul(interestRatePerBlock).div(WeiPerEther)
      await VRTInstance.transfer(user1.address, depositVRTAmount)
      expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount);
      expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(0);
      await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
      await VRTInstance.approve(VRTVaultProxyInstance.address, depositVRTAmount);
      await VRTVaultProxyInstance.setLastAccruingBlock(100)

      // deposit
      await expect(VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount))
        .to.be.emit(VRTVaultProxyInstance, "Deposit").withArgs(user1.address, depositVRTAmount);
      await VRTVaultProxyInstance.deposit(depositVRTAmount)
      expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(depositVRTAmount.mul(2));
      // withdraw
      await VRTVaultProxyInstance.connect(user1).withdraw();
      expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount.add(interestPerBlock.mul(2)));
      expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(depositVRTAmount.sub(interestPerBlock.mul(2)));

      await expect(VRTVaultProxyInstance.withdraw())
        .to.revertedWith("Failed to transfer VRT, Insufficient VRT in Vault.")
    });
  });

  // describe("Deploy and check metadata", function () {
  //   it("Should set the right storage data", async function () {
  //     const { VRTVaultInstance, VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);
  //     expect(await VRTVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await VRTVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);
  //     expect(await VRTVaultProxyInstance.implementation()).to.equal(VRTVaultInstance.address);
  //     expect(await VRTVaultProxyInstance.pendingImplementation()).to.equal(AddressZero);
  //     expect(await VRTVaultProxyInstance.vaultPaused()).to.equal(false);
  //     expect(await VRTVaultProxyInstance.vrt()).to.equal(VRTInstance.address);
  //     expect(await VRTVaultProxyInstance.interestRatePerBlock()).to.equal(interestRatePerBlock);
  //     expect(await VRTVaultProxyInstance.lastAccruingBlock()).to.equal(0);
  //   });

  //   it("Test initialize again will fail", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);
  //     await expect(VRTVaultProxyInstance.initialize(VRTInstance.address, 20))
  //       .to.revertedWith("Vault may only be initialized once")
  //   });
  // });

  // describe("Test admin functions", function () {
  //   it("Test setAccessControl", async function () {
  //     const { VRTVaultProxyInstance, AccessController } = await loadFixture(deployContracts);

  //     await expect(VRTVaultProxyInstance.connect(user1).setAccessControl(user1.address))
  //       .to.revertedWith("only admin allowed")
  //     await expect(VRTVaultProxyInstance.setAccessControl(AddressZero)).to.revertedWith("invalid acess control manager address");
  //     expect(await VRTVaultProxyInstance.accessControlManager()).to.equal(AccessController.address);
  //     await VRTVaultProxyInstance.setAccessControl(user1.address)
  //     expect(await VRTVaultProxyInstance.accessControlManager()).to.equal(user1.address);
  //   });

  //   it("Test _become", async function () {
  //     const { VRTVaultProxyInstance, AccessController } = await loadFixture(deployContracts);

  //     await expect(VRTVaultProxyInstance.connect(user1)._become(VRTVaultProxyInstance.address))
  //       .to.revertedWith("only proxy admin can change brains")
  //     await expect(VRTVaultProxyInstance._become(VRTVaultProxyInstance.address))
  //       .to.revertedWith("only address marked as pendingImplementation can accept Implementation")
  //   });
  //   it("Test setLastAccruingBlock", async function () {
  //     const { VRTVaultProxyInstance, AccessController } = await loadFixture(deployContracts);

  //     await expect(VRTVaultProxyInstance.connect(user1).setLastAccruingBlock(10))
  //       .to.revertedWith("Unauthorized")
  //     const blockNumber = await VRTVaultProxyInstance.getBlockNumber();
  //     console.log(blockNumber);
  //     // set LastAccruingBlock
  //     await expect(VRTVaultProxyInstance.setLastAccruingBlock(100))
  //       .to.be.emit(VRTVaultProxyInstance, "LastAccruingBlockChanged").withArgs(0, 100);
  //     expect(await VRTVaultProxyInstance.lastAccruingBlock()).to.equal(100);

  //     // require currentBlock < lastAccruingBlock
  //     await expect(VRTVaultProxyInstance.setLastAccruingBlock(0))
  //       .to.revertedWith("Invalid _lastAccruingBlock interest have been accumulated")
  //   });
  // });

  // describe("Test proxy functions", function () {
  //   it("Test change implementation", async function () {
  //     let { VRTVaultProxyInstance, VRTVaultInstance } = await loadFixture(deployContracts);

  //     // deploy a new VRTVault contract
  //     const VRTVault = await ethers.getContractFactory("VRTVault");
  //     const NewVRTVaultInstance = await VRTVault.deploy();
  //     const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
  //     VRTVaultProxyInstance = VRTVaultProxy.attach(VRTVaultProxyInstance.address);

  //     // set a new implementation
  //     // Fail: only admin can setPendingImplementation
  //     await expect(VRTVaultProxyInstance.connect(user1)._setPendingImplementation(NewVRTVaultInstance.address))
  //       .to.revertedWith("Only admin can set Pending Implementation");
  //     expect(await VRTVaultProxyInstance.implementation()).to.equal(VRTVaultInstance.address);
  //     expect(await VRTVaultProxyInstance.pendingImplementation()).to.equal(AddressZero);

  //     // Success: admin setPendingImplementation
  //     expect(await VRTVaultProxyInstance._setPendingImplementation(NewVRTVaultInstance.address))
  //       .to.be.emit(VRTVaultProxyInstance, "NewPendingImplementation")
  //       .withArgs(VRTVaultInstance.address, NewVRTVaultInstance.address);
  //     expect(await VRTVaultProxyInstance.implementation()).to.equal(VRTVaultInstance.address);
  //     expect(await VRTVaultProxyInstance.pendingImplementation()).to.equal(NewVRTVaultInstance.address);

  //     // Success: NewVRTVaultInstance acceptImplementation
  //     expect(await NewVRTVaultInstance._become(VRTVaultProxyInstance.address))
  //       .to.be.emit(VRTVaultProxyInstance, "NewImplementation")
  //       .withArgs(VRTVaultInstance.address, NewVRTVaultInstance.address);
  //     expect(await VRTVaultProxyInstance.implementation()).to.equal(NewVRTVaultInstance.address);
  //     expect(await VRTVaultProxyInstance.pendingImplementation()).to.equal(AddressZero);
  //   });

  //   it("Test change implementation by _setImplementation directly", async function () {
  //     let { VRTVaultProxyInstance } = await loadFixture(deployContracts);

  //     const VRTVault = await ethers.getContractFactory("VRTVault");
  //     const NewVRTVaultInstance = await VRTVault.deploy();
  //     const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
  //     VRTVaultProxyInstance = VRTVaultProxy.attach(VRTVaultProxyInstance.address);
  //     await VRTVaultProxyInstance._setImplementation(NewVRTVaultInstance.address)
  //     await expect(VRTVaultProxyInstance._setImplementation(AddressZero))
  //       .to.revertedWith("VRTVaultProxy::_setImplementation: invalid implementation address");
  //     expect(await VRTVaultProxyInstance.implementation()).to.equal(NewVRTVaultInstance.address);
  //     expect(await VRTVaultProxyInstance.pendingImplementation()).to.equal(AddressZero);
  //   });

  //   it("Test change admin", async function () {
  //     let { VRTVaultProxyInstance, VRTVaultInstance } = await loadFixture(deployContracts);

  //     const VRTVaultProxy = await ethers.getContractFactory("VRTVaultProxy");
  //     VRTVaultProxyInstance = VRTVaultProxy.attach(VRTVaultProxyInstance.address);

  //     // set a new admin
  //     // Fail: only admin can setPendingImplementation
  //     await expect(VRTVaultProxyInstance.connect(user1)._setPendingAdmin(user1.address))
  //       .to.revertedWith("only admin can set pending admin");
  //     expect(await VRTVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await VRTVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);

  //     // Success: admin setPendingImplementation
  //     expect(await VRTVaultProxyInstance._setPendingAdmin(user1.address))
  //       .to.be.emit(VRTVaultProxyInstance, "NewPendingAdmin")
  //       .withArgs(admin.address, user1.address);
  //     expect(await VRTVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await VRTVaultProxyInstance.pendingAdmin()).to.equal(user1.address);

  //     // Fail: only pendingAdmin can accept admin
  //     await expect(VRTVaultProxyInstance._acceptAdmin())
  //       .to.revertedWith("only address marked as pendingAdmin can accept as Admin");
  //     // Success: user1 acceptAdmin
  //     await expect(VRTVaultProxyInstance.connect(user1)._acceptAdmin())
  //       .to.be.emit(VRTVaultProxyInstance, "NewAdmin")
  //       .withArgs(admin.address, user1.address);
  //     expect(await VRTVaultProxyInstance.admin()).to.equal(user1.address);
  //     expect(await VRTVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);
  //   });
  // });

  // describe("Test pause and resume", function () {
  //   it("Should need pause and resume access", async function () {
  //     let { VRTVaultProxyInstance } = await loadFixture(deployContracts);
  //     await expect(VRTVaultProxyInstance.connect(user1).pause()).to.revertedWith("Unauthorized")
  //     await expect(VRTVaultProxyInstance.connect(user1).resume()).to.revertedWith("Unauthorized")
  //     expect(await VRTVaultProxyInstance.vaultPaused()).to.equal(false);
  //     await expect(VRTVaultProxyInstance.resume()).to.revertedWith("Vault is not paused")
  //     await VRTVaultProxyInstance.pause()
  //     await expect(VRTVaultProxyInstance.pause()).to.revertedWith("Vault is already paused")
  //   });

  //   it("Should change state", async function () {
  //     let { VRTVaultProxyInstance } = await loadFixture(deployContracts);

  //     await expect(VRTVaultProxyInstance.pause())
  //       .to.be.emit(VRTVaultProxyInstance, "VaultPaused").withArgs(admin.address);
  //     expect(await VRTVaultProxyInstance.vaultPaused()).to.equal(true);
  //     await expect(VRTVaultProxyInstance.deposit(1000)).to.revertedWith("Vault is paused")
  //     await expect(VRTVaultProxyInstance.resume())
  //       .to.be.emit(VRTVaultProxyInstance, "VaultResumed").withArgs(admin.address);
  //     expect(await VRTVaultProxyInstance.vaultPaused()).to.equal(false);
  //   });
  // });

  // describe("Test deposit", function () {
  //   it("Test fist deposit will set the correct data", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //     const depositVRTAmount = ethers.utils.parseEther("10000000")
  //     await VRTInstance.transfer(user1.address, depositVRTAmount)
  //     expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount);
  //     expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(0);
  //     await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //     await VRTVaultProxyInstance.setLastAccruingBlock(100)

  //     // deposit
  //     await expect(VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount))
  //       .to.be.emit(VRTVaultProxyInstance, "Deposit").withArgs(user1.address, depositVRTAmount);
  //     const userInfo = await VRTVaultProxyInstance.userInfo(user1.address)
  //     const currentBlock = await VRTVaultProxyInstance.getBlockNumber()
  //     let accrualStartBlockNumber = 100;
  //     if (currentBlock < 100) accrualStartBlockNumber = currentBlock;
  //     expect(userInfo.userAddress).to.equal(user1.address);
  //     expect(userInfo.totalPrincipalAmount).to.equal(depositVRTAmount);
  //     expect(userInfo.accrualStartBlockNumber).to.equal(accrualStartBlockNumber);
  //     expect(userInfo.lastWithdrawnBlockNumber).to.equal(0);

  //     expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(depositVRTAmount);
  //     // lastWithdrawnBlockNumber 这个变量好像根本没用上 用于记录当前用户最后一次提取的区块号
  //   });

  //   it("Deposit more times will set correct data", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //     const depositVRTAmount = ethers.utils.parseEther("10000000")
  //     await VRTInstance.transfer(user1.address, depositVRTAmount)
  //     await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //     await VRTVaultProxyInstance.setLastAccruingBlock(100)

  //     // first deposit
  //     const firstBlockNumber = await ethers.provider.getBlockNumber()
  //     await VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount.div(2))

  //     // add block
  //     await network.provider.send("evm_mine");
  //     const secondBlockNumber = await ethers.provider.getBlockNumber()

  //     // second deposit
  //     // totalPrincipalAmount: depositVRTAmount.div(2)
  //     // accrualStartBlockNumber: currentBlock
  //     const blockDelta = secondBlockNumber - firstBlockNumber
  //     const interestPerBlock = depositVRTAmount.div(2).mul(interestRatePerBlock).div(WeiPerEther)
  //     const accruedInterest = interestPerBlock.mul(blockDelta)

  //     await expect(VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount.div(2)))
  //       .to.be.emit(VRTVaultProxyInstance, "Claim").withArgs(user1.address, accruedInterest);
  //     // check data
  //     expect(await VRTInstance.balanceOf(user1.address)).to.equal(accruedInterest);
  //     expect(await VRTVaultProxyInstance.getAccruedInterest(admin.address)).to.equal(0); // accruedInterest 只有在 deposit 执行的过程中才不为 0，此时存储的 accrualStartBlockNumber 还没有更新

  //     const newUserInfo = await VRTVaultProxyInstance.userInfo(user1.address)
  //     expect(newUserInfo.totalPrincipalAmount).to.equal(depositVRTAmount);
  //   });

  //   describe("Test user claim", function () {
  //     it("Only user who have deposit can claim", async function () {
  //       const { VRTVaultProxyInstance } = await loadFixture(deployContracts);
  //       await expect(VRTVaultProxyInstance.functions["claim(address)"](user2.address))
  //         .to.revertedWith("User doesnot have any position in the Vault.")
  //     });

  //     it("Should emit event and update state", async function () {
  //       const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //       // prepare and deposit
  //       const depositVRTAmount = ethers.utils.parseEther("10000000")
  //       await VRTInstance.transfer(user1.address, depositVRTAmount)
  //       await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //       await VRTVaultProxyInstance.setLastAccruingBlock(100)
  //       await VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount)
  //       const interestPerBlock = depositVRTAmount.mul(interestRatePerBlock).div(WeiPerEther)

  //       await expect(VRTVaultProxyInstance.functions["claim(address)"](user1.address))
  //         .to.be.emit(VRTVaultProxyInstance, "Claim").withArgs(user1.address, interestPerBlock);

  //       const userInfo = await VRTVaultProxyInstance.userInfo(user1.address)
  //       let accrualStartBlockNumber = await VRTVaultProxyInstance.getBlockNumber()
  //       if (accrualStartBlockNumber > 100) accrualStartBlockNumber = 100
  //       expect(userInfo.accrualStartBlockNumber).to.equal(accrualStartBlockNumber);
  //     });

  //     it("Interest should be none after withrawing", async function () {
  //       const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //       const depositVRTAmount = ethers.utils.parseEther("10000000")
  //       const interestPerBlock = depositVRTAmount.mul(interestRatePerBlock).div(WeiPerEther)
  //       await VRTInstance.transfer(user1.address, depositVRTAmount)
  //       await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //       await VRTInstance.approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //       await VRTVaultProxyInstance.setLastAccruingBlock(100)

  //       // deposit and withdraw
  //       await VRTVaultProxyInstance.deposit(depositVRTAmount)
  //       await VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount)
  //       expect(await VRTInstance.balanceOf(user1.address)).to.equal(0);
  //       await VRTVaultProxyInstance.connect(user1).withdraw()
  //       expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount.add(interestPerBlock));
  //       // claim won't fail but user won't get interest again
  //       await VRTVaultProxyInstance.functions["claim(address)"](user1.address)
  //       expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount.add(interestPerBlock));
  //     });

  //     it("User claim twice", async function () {
  //       const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //       const depositVRTAmount = ethers.utils.parseEther("10000000")
  //       await VRTInstance.transfer(user1.address, depositVRTAmount)
  //       await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //       await VRTVaultProxyInstance.setLastAccruingBlock(100)

  //       // deposit
  //       await VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount)
  //       const userInfo = await VRTVaultProxyInstance.userInfo(user1.address)
  //       expect(userInfo.lastWithdrawnBlockNumber).to.equal(0);

  //       const interestPerBlock = depositVRTAmount.mul(interestRatePerBlock).div(WeiPerEther)
  //       expect(await VRTInstance.balanceOf(user1.address)).to.equal(0);
  //       await VRTVaultProxyInstance.functions["claim(address)"](user1.address)
  //       // claim again: block will add 1, interest will add
  //       await VRTVaultProxyInstance.functions["claim(address)"](user1.address)
  //       expect(await VRTInstance.balanceOf(user1.address)).to.equal(interestPerBlock.mul(2));
  //     });

  //   });
  // });

  // describe("Test withdraw", function () {
  //   it("Insufficient account balance of vault will fail", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);
  //     const depositVRTAmount = ethers.utils.parseEther("10000000")
  //     await VRTInstance.transfer(user1.address, depositVRTAmount)
  //     await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //     await VRTVaultProxyInstance.setLastAccruingBlock(100)
  //     await VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount)
  //     await expect(VRTVaultProxyInstance.connect(user1).withdraw())
  //       .to.revertedWith("Failed to transfer VRT, Insufficient VRT in Vault.")
  //   });

  //   it("Should emit event and update state", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //     const depositVRTAmount = ethers.utils.parseEther("10000000")
  //     const interestPerBlock = depositVRTAmount.mul(interestRatePerBlock).div(WeiPerEther)
  //     await VRTInstance.transfer(user1.address, depositVRTAmount)
  //     await VRTInstance.connect(user1).approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //     await VRTInstance.approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //     await VRTVaultProxyInstance.setLastAccruingBlock(100)

  //     // deposit 
  //     const accruedInterest = interestPerBlock.mul(2)
  //     await VRTVaultProxyInstance.deposit(depositVRTAmount)
  //     await VRTVaultProxyInstance.connect(user1).deposit(depositVRTAmount)

  //     // add block
  //     await network.provider.send("evm_mine");

  //     // withdraw
  //     await expect(VRTVaultProxyInstance.connect(user1).withdraw())
  //       .to.be.emit(VRTVaultProxyInstance, "Withdraw")
  //       .withArgs(user1.address, depositVRTAmount.add(accruedInterest), depositVRTAmount, accruedInterest);
  //     const blockNumber = await VRTVaultProxyInstance.getBlockNumber()
  //     const userInfo = await VRTVaultProxyInstance.userInfo(user1.address)
  //     expect(userInfo.userAddress).to.equal(user1.address);
  //     expect(userInfo.totalPrincipalAmount).to.equal(0);
  //     expect(userInfo.lastWithdrawnBlockNumber).to.equal(0);
  //     expect(userInfo.accrualStartBlockNumber).to.equal(blockNumber);
  //     expect(await VRTInstance.balanceOf(user1.address)).to.equal(interestPerBlock.mul(2).add(depositVRTAmount));
  //   });
  // });

  // describe("Test withdrawBep20", function () {
  //   it("Insufficient account balance of token will fail", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //     await expect(VRTVaultProxyInstance.withdrawBep20(VRTInstance.address, user1.address, 0))
  //       .to.revertedWith("amount is invalid")
  //     await expect(VRTVaultProxyInstance.withdrawBep20(VRTInstance.address, user1.address, 100))
  //       .to.revertedWith("Insufficient amount in Vault")
  //   });

  //   it("Withdraw VRT by withdrawBep20 function", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //     const depositVRTAmount = ethers.utils.parseEther("10000000")
  //     await VRTInstance.approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //     await VRTVaultProxyInstance.deposit(depositVRTAmount)

  //     await expect(VRTVaultProxyInstance.connect(user1).withdrawBep20(VRTInstance.address, user1.address, depositVRTAmount.div(2)))
  //       .to.revertedWith("Unauthorized")
  //     await expect(VRTVaultProxyInstance.withdrawBep20(VRTInstance.address, user1.address, depositVRTAmount.div(2)))
  //       .to.be.emit(VRTVaultProxyInstance, "WithdrawToken")
  //       .withArgs(VRTInstance.address, user1.address, depositVRTAmount.div(2));
  //     expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(depositVRTAmount.div(2));
  //     expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount.div(2));
  //   });

  //   it("Withdraw VRT by withdrawBep20 function", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //     const depositVRTAmount = ethers.utils.parseEther("10000000")
  //     await VRTInstance.approve(VRTVaultProxyInstance.address, depositVRTAmount);
  //     await VRTVaultProxyInstance.deposit(depositVRTAmount)

  //     await expect(VRTVaultProxyInstance.connect(user1).withdrawBep20(VRTInstance.address, user1.address, depositVRTAmount.div(2)))
  //       .to.revertedWith("Unauthorized")
  //     await expect(VRTVaultProxyInstance.withdrawBep20(VRTInstance.address, user1.address, depositVRTAmount.div(2)))
  //       .to.be.emit(VRTVaultProxyInstance, "WithdrawToken")
  //       .withArgs(VRTInstance.address, user1.address, depositVRTAmount.div(2));
  //     expect(await VRTInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(depositVRTAmount.div(2));
  //     expect(await VRTInstance.balanceOf(user1.address)).to.equal(depositVRTAmount.div(2));

  //     await expect(VRTVaultProxyInstance.withdrawBep20(VRTInstance.address, admin.address, depositVRTAmount.div(2)))
  //       .to.be.emit(VRTVaultProxyInstance, "WithdrawToken")
  //       .withArgs(VRTInstance.address, admin.address, depositVRTAmount.div(2));
  //     expect(await VRTInstance.balanceOf(admin.address)).to.equal(ethers.utils.parseEther("25000000"));
  //   });

  //   it("Withdraw other by withdrawBep20 function", async function () {
  //     const { VRTVaultProxyInstance, VRTInstance } = await loadFixture(deployContracts);

  //     const MockERC20 = await ethers.getContractFactory("MockERC20");
  //     const TestInstance = await MockERC20.deploy("TT", "TT", ethers.utils.parseEther("30000000"));
  //     TestInstance.transfer(VRTVaultProxyInstance.address, ethers.utils.parseEther("10000000"))
  //     expect(await TestInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(ethers.utils.parseEther("10000000"));
  //     VRTVaultProxyInstance.withdrawBep20(TestInstance.address, user1.address, ethers.utils.parseEther("10000000"))
  //     expect(await TestInstance.balanceOf(user1.address)).to.equal(ethers.utils.parseEther("10000000"));
  //     expect(await TestInstance.balanceOf(VRTVaultProxyInstance.address)).to.equal(0);
  //   });

  // });
});
