const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("XVSVault Test", function () {
  const AddressZero = ethers.constants.AddressZero;
  const WeiPerEther = ethers.constants.WeiPerEther;
  const interestRatePerBlock = 10;
  let admin, user1, user2;

  async function deployContracts() {
    [admin, user1, user2, ...otherAccount] = await ethers.getSigners();

    // deploy XVSStore
    const XVSStore = await ethers.getContractFactory("XVSStore");
    const XVSStoreInstance = await XVSStore.deploy();
    // deploy XVSVault
    const XVSVault = await ethers.getContractFactory("XVSVault");
    const XVSVaultInstance = await XVSVault.deploy();
    // deploy token: XVS
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const XVSInstance = await MockERC20.deploy("XVS", "XVS", ethers.utils.parseEther("30000000"));
    // deploy XVSVaultProxy and set implementation
    const XVSVaultProxy = await ethers.getContractFactory("XVSVaultProxy");
    let XVSVaultProxyInstance = await XVSVaultProxy.deploy();
    await XVSVaultProxyInstance._setPendingImplementation(XVSVaultInstance.address);
    await XVSVaultInstance._become(XVSVaultProxyInstance.address);
    XVSVaultProxyInstance = XVSVault.attach(XVSVaultProxyInstance.address);
    await XVSVaultProxyInstance.setXvsStore(XVSInstance.address, XVSStoreInstance.address);
    await XVSStoreInstance.setNewOwner(XVSVaultProxyInstance.address);

    // deploy accessControl
    const MockAccessControlManagerV5 = await ethers.getContractFactory("MockAccessControlManagerV5");
    const AccessController = await MockAccessControlManagerV5.deploy();
    XVSVaultProxyInstance.setAccessControl(AccessController.address);

    return { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance };
  }

  describe("Bugs reoccurrences", function () {
    it("User can get admin again by pendingAdmin", async function () {
      let { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance } = await loadFixture(deployContracts);
      const XVSVaultProxy = await ethers.getContractFactory("XVSVaultProxy");
      const XVSVault = await ethers.getContractFactory("XVSVault");
      XVSVaultProxyInstance = XVSVaultProxy.attach(XVSVaultProxyInstance.address);

      // set pending admin
      expect(await XVSVaultProxyInstance._setPendingAdmin(user1.address))
        .to.be.emit(XVSVaultProxyInstance, "NewPendingAdmin")
        .withArgs(admin.address, user1.address);
      expect(await XVSVaultProxyInstance.admin()).to.equal(admin.address);
      expect(await XVSVaultProxyInstance.pendingAdmin()).to.equal(user1.address);
      // burn admin
      XVSVaultProxyInstance = XVSVault.attach(XVSVaultProxyInstance.address);
      expect(await XVSVaultProxyInstance.burnAdmin())
        .to.be.emit(XVSVaultProxyInstance, "AdminTransfered")
        .withArgs(admin.address, AddressZero);
      expect(await XVSVaultProxyInstance.admin()).to.equal(AddressZero);
      expect(await XVSVaultProxyInstance.pendingAdmin()).to.equal(user1.address);

      // user1 get admin
      XVSVaultProxyInstance = XVSVaultProxy.attach(XVSVaultProxyInstance.address);
      expect(await XVSVaultProxyInstance.connect(user1)._acceptAdmin())
        .to.be.emit(XVSVaultProxyInstance, "NewAdmin")
        .withArgs(admin.address, user1.address);
      expect(await XVSVaultProxyInstance.admin()).to.equal(user1.address);
    });

    it("Several rewardToken with the same deposit token", async function () {
      let { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance } = await loadFixture(deployContracts);

      // const MockERC20 = await ethers.getContractFactory("MockERC20");
      // const depositAmount = ethers.utils.parseEther("10000000")
      // const RTInstance = await MockERC20.deploy("RewardToken", "RT", ethers.utils.parseEther("30000000"));
      // await XVSInstance.approve(XVSVaultProxyInstance.address, depositAmount)
      // // add new token pool
      // await XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000)
      // await XVSVaultProxyInstance.deposit(RTInstance.address, 0, depositAmount);

      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const depositAmount = ethers.utils.parseEther("10000000")
      const DTInstance = await MockERC20.deploy("DepositToken", "DT", ethers.utils.parseEther("30000000"));
      const RTInstance = await MockERC20.deploy("RewardToken", "RT", ethers.utils.parseEther("30000000"));
      const NRTInstance = await MockERC20.deploy("NewRewardToken", "NRT", ethers.utils.parseEther("30000000"));
      await DTInstance.approve(XVSVaultProxyInstance.address, depositAmount)
      await RTInstance.transfer(XVSVaultProxyInstance.address, depositAmount)
      await XVSInstance.transfer(XVSVaultProxyInstance.address, ethers.utils.parseEther("30000000"))
      // add new token pool
      await XVSVaultProxyInstance.add(RTInstance.address, 100, DTInstance.address, ethers.utils.parseEther("1"), 86400000)
      await XVSVaultProxyInstance.add(NRTInstance.address, 100, DTInstance.address, ethers.utils.parseEther("1"), 86400000)
      await XVSVaultProxyInstance.deposit(RTInstance.address, 0, depositAmount);
      await XVSVaultProxyInstance.updatePool(RTInstance.address, 0)
      console.log(await XVSVaultProxyInstance.pendingReward(RTInstance.address, 0, admin.address));

      await XVSVaultProxyInstance.claim(admin.address, RTInstance.address, 0);
      console.log(await XVSInstance.balanceOf(admin.address));
    });
  });

  describe("Deploy and check metadata", function () {
    it("Should set the right storage data", async function () {
      const { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance } = await loadFixture(deployContracts);
      // check storage data
      expect(await XVSVaultProxyInstance.admin()).to.equal(admin.address);
      expect(await XVSVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);
      expect(await XVSVaultProxyInstance.implementation()).to.equal(XVSVaultInstance.address);
      expect(await XVSVaultProxyInstance.pendingXVSVaultImplementation()).to.equal(AddressZero);
      expect(await XVSVaultProxyInstance.xvsStore()).to.equal(XVSStoreInstance.address);
      expect(await XVSVaultProxyInstance.xvsAddress()).to.equal(XVSInstance.address);
      expect(await XVSVaultProxyInstance.vaultPaused()).to.equal(false);
      // check XVSStore storage data
      expect(await XVSStoreInstance.admin()).to.equal(admin.address);
      expect(await XVSStoreInstance.pendingAdmin()).to.equal(AddressZero);
      expect(await XVSStoreInstance.owner()).to.equal(XVSVaultProxyInstance.address);

    });
  });
});
