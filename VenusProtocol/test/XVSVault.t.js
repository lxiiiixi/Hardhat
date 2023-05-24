const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

describe("XVSVault Test", function () {
  const AddressZero = ethers.constants.AddressZero;
  const unit12 = ethers.utils.parseUnits("1.0", 12);
  const baseAmount = ethers.utils.parseEther("10000000");
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
    const XVSInstance = await MockERC20.deploy("XVS", "XVS", baseAmount.mul(3));
    const RTInstance = await MockERC20.deploy("RewardToken", "RT", baseAmount.mul(3));
    const TTInstance = await MockERC20.deploy("TToken", "TT", baseAmount.mul(3));
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

    return { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance, RTInstance, TTInstance };
  }

  // describe("Bugs reoccurrences", function () {
  //   it("User can get admin again by pendingAdmin", async function () {
  //     let { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance } = await loadFixture(deployContracts);
  //     const XVSVaultProxy = await ethers.getContractFactory("XVSVaultProxy");
  //     const XVSVault = await ethers.getContractFactory("XVSVault");
  //     XVSVaultProxyInstance = XVSVaultProxy.attach(XVSVaultProxyInstance.address);

  //     // set pending admin
  //     expect(await XVSVaultProxyInstance._setPendingAdmin(user1.address))
  //       .to.be.emit(XVSVaultProxyInstance, "NewPendingAdmin")
  //       .withArgs(admin.address, user1.address);
  //     expect(await XVSVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await XVSVaultProxyInstance.pendingAdmin()).to.equal(user1.address);
  //     // burn admin
  //     XVSVaultProxyInstance = XVSVault.attach(XVSVaultProxyInstance.address);
  //     expect(await XVSVaultProxyInstance.burnAdmin())
  //       .to.be.emit(XVSVaultProxyInstance, "AdminTransfered")
  //       .withArgs(admin.address, AddressZero);
  //     expect(await XVSVaultProxyInstance.admin()).to.equal(AddressZero);
  //     expect(await XVSVaultProxyInstance.pendingAdmin()).to.equal(user1.address);

  //     // user1 get admin
  //     XVSVaultProxyInstance = XVSVaultProxy.attach(XVSVaultProxyInstance.address);
  //     expect(await XVSVaultProxyInstance.connect(user1)._acceptAdmin())
  //       .to.be.emit(XVSVaultProxyInstance, "NewAdmin")
  //       .withArgs(admin.address, user1.address);
  //     expect(await XVSVaultProxyInstance.admin()).to.equal(user1.address);
  //   });

  //   it("Several rewardToken with the same deposit token", async function () {
  //     let { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance } = await loadFixture(deployContracts);

  //     // const MockERC20 = await ethers.getContractFactory("MockERC20");
  //     // const depositAmount = ethers.utils.parseUnits("10000000")
  //     // const RTInstance = await MockERC20.deploy("RewardToken", "RT", ethers.utils.parseUnits("30000000"));
  //     // await XVSInstance.approve(XVSVaultProxyInstance.address, depositAmount)
  //     // // add new token pool
  //     // await XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000)
  //     // await XVSVaultProxyInstance.deposit(RTInstance.address, 0, depositAmount);

  //     // const MockERC20 = await ethers.getContractFactory("MockERC20");
  //     // const depositAmount = ethers.utils.parseUnits("10000000")
  //     // const DTInstance = await MockERC20.deploy("DepositToken", "DT", ethers.utils.parseUnits("30000000"));
  //     // const RTInstance = await MockERC20.deploy("RewardToken", "RT", ethers.utils.parseUnits("30000000"));
  //     // const NRTInstance = await MockERC20.deploy("NewRewardToken", "NRT", ethers.utils.parseUnits("30000000"));
  //     // await DTInstance.approve(XVSVaultProxyInstance.address, depositAmount)
  //     // await RTInstance.transfer(XVSVaultProxyInstance.address, depositAmount)
  //     // await XVSInstance.transfer(XVSVaultProxyInstance.address, ethers.utils.parseUnits("30000000"))
  //     // // add new token pool
  //     // await XVSVaultProxyInstance.add(RTInstance.address, 100, DTInstance.address, ethers.utils.parseUnits("1"), 86400000)
  //     // await XVSVaultProxyInstance.add(NRTInstance.address, 100, DTInstance.address, ethers.utils.parseUnits("1"), 86400000)
  //     // await XVSVaultProxyInstance.deposit(RTInstance.address, 0, depositAmount);
  //     // await XVSVaultProxyInstance.updatePool(RTInstance.address, 0)
  //     // console.log(await XVSVaultProxyInstance.pendingReward(RTInstance.address, 0, admin.address));

  //     // await XVSVaultProxyInstance.claim(admin.address, RTInstance.address, 0);
  //     // console.log(await XVSInstance.balanceOf(admin.address));
  //   });
  // });

  // describe("Deploy and check metadata", function () {
  //   it("Should set the right storage data", async function () {
  //     const { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance } = await loadFixture(deployContracts);
  //     // check storage data
  //     expect(await XVSVaultProxyInstance.admin()).to.equal(admin.address);
  //     expect(await XVSVaultProxyInstance.pendingAdmin()).to.equal(AddressZero);
  //     expect(await XVSVaultProxyInstance.implementation()).to.equal(XVSVaultInstance.address);
  //     expect(await XVSVaultProxyInstance.pendingXVSVaultImplementation()).to.equal(AddressZero);
  //     expect(await XVSVaultProxyInstance.xvsStore()).to.equal(XVSStoreInstance.address);
  //     expect(await XVSVaultProxyInstance.xvsAddress()).to.equal(XVSInstance.address);
  //     expect(await XVSVaultProxyInstance.vaultPaused()).to.equal(false);
  //     // check XVSStore storage data
  //     expect(await XVSStoreInstance.admin()).to.equal(admin.address);
  //     expect(await XVSStoreInstance.pendingAdmin()).to.equal(AddressZero);
  //     expect(await XVSStoreInstance.owner()).to.equal(XVSVaultProxyInstance.address);
  //   });
  // });

  // describe("Test XVSStore functions", function () {
  //   it("Only admin or owner can set rewardToken", async function () {
  //     const { XVSStoreInstance, RTInstance } = await loadFixture(deployContracts);
  //     await expect(XVSStoreInstance.connect(user1).setRewardToken(RTInstance.address, 1))
  //       .to.revertedWith("only admin or owner can")
  //     expect(await XVSStoreInstance.rewardTokens(RTInstance.address)).to.equal(false);
  //     await XVSStoreInstance.setRewardToken(RTInstance.address, 1)
  //     expect(await XVSStoreInstance.rewardTokens(RTInstance.address)).to.equal(true);
  //   });

  //   it("Test change admin", async function () {
  //     const { XVSStoreInstance } = await loadFixture(deployContracts);

  //     expect(await XVSStoreInstance.admin()).to.equal(admin.address);
  //     expect(await XVSStoreInstance.pendingAdmin()).to.equal(AddressZero);
  //     // setPendingAdmin
  //     await expect(XVSStoreInstance.connect(user1).setPendingAdmin(user1.address))
  //       .to.revertedWith("only admin can")
  //     await expect(XVSStoreInstance.setPendingAdmin(user1.address))
  //       .to.be.emit(XVSStoreInstance, "NewPendingAdmin")
  //       .withArgs(AddressZero, user1.address);
  //     expect(await XVSStoreInstance.admin()).to.equal(admin.address);
  //     expect(await XVSStoreInstance.pendingAdmin()).to.equal(user1.address);
  //     // acceptAdmin
  //     await expect(XVSStoreInstance.acceptAdmin())
  //       .to.revertedWith("only pending admin")
  //     await expect(XVSStoreInstance.connect(user1).acceptAdmin())
  //       .to.be.emit(XVSStoreInstance, "AdminTransferred")
  //       .withArgs(admin.address, user1.address);
  //     expect(await XVSStoreInstance.admin()).to.equal(user1.address);
  //     expect(await XVSStoreInstance.pendingAdmin()).to.equal(AddressZero);
  //   });

  //   it("Test change owner", async function () {
  //     const { XVSVaultProxyInstance, XVSStoreInstance } = await loadFixture(deployContracts);

  //     expect(await XVSStoreInstance.owner()).to.equal(XVSVaultProxyInstance.address);
  //     await expect(XVSStoreInstance.connect(user1).setNewOwner(user1.address))
  //       .to.revertedWith("only admin can")
  //     await expect(XVSStoreInstance.setNewOwner(AddressZero))
  //       .to.revertedWith("new owner is the zero address")
  //     await expect(XVSStoreInstance.setNewOwner(user1.address))
  //       .to.be.emit(XVSStoreInstance, "OwnerTransferred")
  //       .withArgs(XVSVaultProxyInstance.address, user1.address);
  //     expect(await XVSStoreInstance.owner()).to.equal(user1.address);
  //   });

  //   it("Test safeRewardTransfer", async function () {
  //     const { XVSStoreInstance, RTInstance } = await loadFixture(deployContracts);

  //     await XVSStoreInstance.setRewardToken(RTInstance.address, true)
  //     await expect(XVSStoreInstance.safeRewardTransfer(RTInstance.address, admin.address, baseAmount))
  //       .to.revertedWith("only owner can")
  //     await XVSStoreInstance.setNewOwner(admin.address)
  //     await RTInstance.transfer(XVSStoreInstance.address, baseAmount)
  //     expect(await RTInstance.balanceOf(XVSStoreInstance.address)).to.equal(baseAmount);
  //     await XVSStoreInstance.safeRewardTransfer(RTInstance.address, admin.address, baseAmount)
  //     expect(await RTInstance.balanceOf(XVSStoreInstance.address)).to.equal(0);
  //     expect(await RTInstance.balanceOf(admin.address)).to.equal(baseAmount.mul(3));
  //   });

  //   it("Test emergencyRewardWithdraw", async function () {
  //     const { XVSStoreInstance, RTInstance } = await loadFixture(deployContracts);

  //     await XVSStoreInstance.setRewardToken(RTInstance.address, true)
  //     await expect(XVSStoreInstance.emergencyRewardWithdraw(RTInstance.address, baseAmount))
  //       .to.revertedWith("only owner can")
  //     await XVSStoreInstance.setNewOwner(admin.address)
  //     await RTInstance.transfer(XVSStoreInstance.address, baseAmount)
  //     expect(await RTInstance.balanceOf(XVSStoreInstance.address)).to.equal(baseAmount);
  //     await XVSStoreInstance.emergencyRewardWithdraw(RTInstance.address, baseAmount)
  //     expect(await RTInstance.balanceOf(XVSStoreInstance.address)).to.equal(0);
  //     expect(await RTInstance.balanceOf(admin.address)).to.equal(baseAmount.mul(3));
  //     // if widraw amount > balance
  //     await expect(XVSStoreInstance.emergencyRewardWithdraw(RTInstance.address, baseAmount))
  //       .to.revertedWith("SafeBEP20: low-level call failed")
  //   });
  // });

  // describe("Test pause and resume", function () {
  //   it("Should pause and resume successfully", async function () {
  //     const { XVSVaultProxyInstance, XVSStoreInstance, XVSInstance, RTInstance } = await loadFixture(deployContracts);
  //     // only owner
  //     await expect(XVSVaultProxyInstance.connect(user1).pause()).to.revertedWith("Unauthorized");
  //     await expect(XVSVaultProxyInstance.connect(user1).resume()).to.revertedWith("Unauthorized");
  //     // pause
  //     await expect(XVSVaultProxyInstance.pause())
  //       .to.be.emit(XVSVaultProxyInstance, "VaultPaused").withArgs(admin.address);
  //     await expect(XVSVaultProxyInstance.pause())
  //       .to.be.revertedWith("Vault is already paused");
  //     // resume
  //     await expect(XVSVaultProxyInstance.resume())
  //       .to.be.emit(XVSVaultProxyInstance, "VaultResumed").withArgs(admin.address);
  //     await expect(XVSVaultProxyInstance.resume())
  //       .to.be.revertedWith("Vault is not paused");
  //   });
  // });

  // describe("Test add token pool", function () {
  //   it("Should add and set the correct data successfully", async function () {
  //     const { XVSVaultProxyInstance, XVSStoreInstance, XVSInstance, RTInstance } = await loadFixture(deployContracts);

  //     // only user with access can add 
  //     await expect(XVSVaultProxyInstance.connect(user1).add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000))
  //       .to.revertedWith("Unauthorized");
  //     // add new token pool will emit event
  //     await expect(XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000))
  //       .to.be.emit(XVSVaultProxyInstance, "PoolAdded").withArgs(RTInstance.address, 0, XVSInstance.address, 100, 1000, 86400000);
  //     const blockNumber = await ethers.provider.getBlockNumber();

  //     // check data
  //     const poolInfo = await XVSVaultProxyInstance.poolInfos(RTInstance.address, 0);
  //     expect(poolInfo.token).to.equal(XVSInstance.address);
  //     expect(poolInfo.allocPoint).to.equal(100);
  //     expect(poolInfo.lastRewardBlock).to.equal(blockNumber);
  //     expect(poolInfo.accRewardPerShare).to.equal(0);
  //     expect(poolInfo.lockPeriod).to.equal(86400000);
  //     expect(await XVSStoreInstance.rewardTokens(RTInstance.address)).to.equal(true);
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(1000);
  //     expect(await XVSVaultProxyInstance.totalAllocPoints(RTInstance.address)).to.equal(100);
  //     expect(await XVSVaultProxyInstance.poolLength(RTInstance.address)).to.equal(1);
  //   });

  //   it("Can't set the same token by the same reward token", async function () {
  //     const { XVSVaultProxyInstance, XVSInstance, RTInstance, TTInstance } = await loadFixture(deployContracts);

  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000)
  //     // can't set the same token by the same reward token
  //     await expect(XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000))
  //       .to.revertedWith("Error pool already added")
  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, TTInstance.address, 2000, 86400000)
  //     // check data
  //     expect(await XVSVaultProxyInstance.poolLength(RTInstance.address)).to.equal(2);
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(2000);
  //     expect(await XVSVaultProxyInstance.totalAllocPoints(RTInstance.address)).to.equal(200);
  //   });

  //   it("Test different reward token with same deposit token", async function () {
  //     const { XVSVaultProxyInstance, XVSStoreInstance, XVSInstance, RTInstance, TTInstance } = await loadFixture(deployContracts);

  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000)
  //     await XVSVaultProxyInstance.add(XVSInstance.address, 100, XVSInstance.address, 1000, 86400000)
  //     // check data
  //     expect(await XVSVaultProxyInstance.poolLength(RTInstance.address)).to.equal(1);
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(1000);
  //     expect(await XVSVaultProxyInstance.totalAllocPoints(RTInstance.address)).to.equal(100);
  //     expect(await XVSVaultProxyInstance.poolLength(XVSInstance.address)).to.equal(1);
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(XVSInstance.address)).to.equal(1000);
  //     expect(await XVSVaultProxyInstance.totalAllocPoints(XVSInstance.address)).to.equal(100);

  //     // 这里好像有一个提案是做了修改 不能重复添加相同的质押token
  //   });
  // });

  // // 和 updatePool 相关的操作每次都会更新到最新的区块（pool.lastRewardBlock = block.number;）
  // describe("Test poolInfo change function", function () {
  //   it("Test set _allocPoint function", async function () {
  //     const { XVSVaultProxyInstance, XVSInstance, RTInstance } = await loadFixture(deployContracts);
  //     // allocPoint 是用于 updatePool 时计算奖励的权重比例的

  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000)
  //     const oldPoolInfo = await XVSVaultProxyInstance.poolInfos(RTInstance.address, 0);
  //     expect(oldPoolInfo.allocPoint).to.equal(100);
  //     // set new allocPoint
  //     await expect(XVSVaultProxyInstance.connect(user1).set(RTInstance.address, 0, 101))
  //       .to.revertedWith("Unauthorized")
  //     await expect(XVSVaultProxyInstance.set(RTInstance.address, 0, 101))
  //       .to.be.emit(XVSVaultProxyInstance, "PoolUpdated").withArgs(RTInstance.address, 0, 100, 101);
  //     const blockNumber = await ethers.provider.getBlockNumber();
  //     const newPoolInfo = await XVSVaultProxyInstance.poolInfos(RTInstance.address, 0);
  //     expect(newPoolInfo.allocPoint).to.equal(101);
  //     expect(newPoolInfo.lastRewardBlock).to.equal(blockNumber);
  //   });

  //   it("Test setRewardAmountPerBlock function", async function () {
  //     const { XVSVaultProxyInstance, XVSInstance, RTInstance } = await loadFixture(deployContracts);

  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000)
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(1000);
  //     // set new reward amount
  //     await expect(XVSVaultProxyInstance.connect(user1).setRewardAmountPerBlock(RTInstance.address, 2000))
  //       .to.revertedWith("Unauthorized")
  //     await expect(XVSVaultProxyInstance.setRewardAmountPerBlock(RTInstance.address, 2000))
  //       .to.be.emit(XVSVaultProxyInstance, "RewardAmountUpdated").withArgs(RTInstance.address, 1000, 2000);
  //     const blockNumber = await ethers.provider.getBlockNumber();
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(2000);
  //     const newPoolInfo = await XVSVaultProxyInstance.poolInfos(RTInstance.address, 0);
  //     expect(newPoolInfo.lastRewardBlock).to.equal(blockNumber);
  //   });

  //   it("Test setWithdrawalLockingPeriod function", async function () {
  //     const { XVSVaultProxyInstance, XVSInstance, RTInstance } = await loadFixture(deployContracts);

  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, XVSInstance.address, 1000, 86400000)
  //     const oldPoolInfo = await XVSVaultProxyInstance.poolInfos(RTInstance.address, 0);
  //     expect(oldPoolInfo.lockPeriod).to.equal(86400000);
  //     // set new lockPeriod
  //     await expect(XVSVaultProxyInstance.connect(user1).setWithdrawalLockingPeriod(RTInstance.address, 0, 86500000))
  //       .to.revertedWith("Unauthorized")
  //     await expect(XVSVaultProxyInstance.setWithdrawalLockingPeriod(RTInstance.address, 0, 86500000))
  //       .to.be.emit(XVSVaultProxyInstance, "WithdrawalLockingPeriodUpdated").withArgs(RTInstance.address, 0, 86400000, 86500000);
  //     const blockNumber = await ethers.provider.getBlockNumber();
  //     const newPoolInfo = await XVSVaultProxyInstance.poolInfos(RTInstance.address, 0);
  //     expect(newPoolInfo.lockPeriod).to.equal(86500000);
  //   });
  // });

  // describe("Test deposit function", function () {
  //   it("Test first deposit", async function () {
  //     const { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance, RTInstance, TTInstance } = await loadFixture(deployContracts);
  //     const depositAmount = baseAmount
  //     await XVSInstance.transfer(XVSVaultProxyInstance.address, depositAmount) // 保证 XVSVaultProxyInstance 有足够的 XVS 作为奖励发放
  //     await TTInstance.connect(user1).approve(XVSVaultProxyInstance.address, depositAmount)
  //     await TTInstance.transfer(user1.address, depositAmount)
  //     await RTInstance.transfer(XVSVaultProxyInstance.address, depositAmount)
  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, TTInstance.address, 1000, 86400000)

  //     // user1 deposit  =>   _updatePool
  //     expect(await TTInstance.balanceOf(user1.address)).to.equal(depositAmount);
  //     await expect(XVSVaultProxyInstance.connect(user1).deposit(RTInstance.address, 0, depositAmount))
  //       .to.be.emit(XVSVaultProxyInstance, "Deposit").withArgs(user1.address, RTInstance.address, 0, depositAmount);
  //     expect(await TTInstance.balanceOf(user1.address)).to.equal(0);
  //     expect(await TTInstance.balanceOf(XVSVaultProxyInstance.address)).to.equal(depositAmount);
  //     expect(await XVSInstance.balanceOf(user1.address)).to.equal(0);
  //     expect(await RTInstance.balanceOf(user1.address)).to.equal(0);
  //     expect(await RTInstance.balanceOf(XVSVaultProxyInstance.address)).to.equal(depositAmount);
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(1000);
  //     await XVSVaultProxyInstance.connect(user1).updatePool(RTInstance.address, 0)
  //   });

  //   it("Test more people deposit", async function () {
  //     const { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance, RTInstance, TTInstance } = await loadFixture(deployContracts);
  //     const depositAmount = 100000000
  //     await TTInstance.connect(user1).approve(XVSVaultProxyInstance.address, depositAmount * 2)
  //     await TTInstance.connect(user2).approve(XVSVaultProxyInstance.address, depositAmount)
  //     await TTInstance.approve(XVSVaultProxyInstance.address, depositAmount)
  //     await TTInstance.transfer(user1.address, depositAmount * 2)
  //     await TTInstance.transfer(user2.address, depositAmount)
  //     await RTInstance.transfer(XVSStoreInstance.address, depositAmount)  // 保证 XVSVaultProxyInstance 有足够的奖励代币
  //     expect(await RTInstance.balanceOf(XVSStoreInstance.address)).to.equal(depositAmount);
  //     // add pool
  //     await XVSVaultProxyInstance.add(RTInstance.address, 100, TTInstance.address, 1000, 86400000)

  //     // user1 deposit 
  //     expect(await TTInstance.balanceOf(user1.address)).to.equal(depositAmount * 2);
  //     await expect(XVSVaultProxyInstance.connect(user1).deposit(RTInstance.address, 0, depositAmount))
  //       .to.be.emit(XVSVaultProxyInstance, "Deposit").withArgs(user1.address, RTInstance.address, 0, depositAmount);
  //     expect(await TTInstance.balanceOf(user1.address)).to.equal(depositAmount);
  //     expect(await TTInstance.balanceOf(XVSVaultProxyInstance.address)).to.equal(depositAmount);
  //     // user1 info
  //     const user1Info = await XVSVaultProxyInstance.getUserInfo(RTInstance.address, 0, user1.address);
  //     expect(user1Info.amount).equal(depositAmount);
  //     expect(user1Info.rewardDebt).equal(0);
  //     expect(user1Info.pendingWithdrawals).equal(0);

  //     // user2 deposit 
  //     expect(await TTInstance.balanceOf(user2.address)).to.equal(depositAmount);
  //     await expect(XVSVaultProxyInstance.connect(user2).deposit(RTInstance.address, 0, depositAmount))
  //       .to.be.emit(XVSVaultProxyInstance, "Deposit").withArgs(user2.address, RTInstance.address, 0, depositAmount);
  //     expect(await TTInstance.balanceOf(user2.address)).to.equal(0);
  //     expect(await TTInstance.balanceOf(XVSVaultProxyInstance.address)).to.equal(depositAmount * 2);
  //     // user2 info
  //     const user2Info = await XVSVaultProxyInstance.getUserInfo(RTInstance.address, 0, user1.address);
  //     expect(user2Info.amount).equal(depositAmount);
  //     expect(user2Info.rewardDebt).equal(0);
  //     expect(user2Info.pendingWithdrawals).equal(0);

  //     const rewardTokenAmountsPerBlock = await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)
  //     expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(1000);

  //     // caculate reward
  //     const rewardPerShare = (rewardTokenAmountsPerBlock * 100 / 100)
  //     const poolInfo = await XVSVaultProxyInstance.poolInfos(RTInstance.address, 0);
  //     expect(poolInfo.accRewardPerShare).to.equal(unit12.mul(rewardPerShare).div(depositAmount));
  //     const accRewardPerShare = poolInfo.accRewardPerShare;

  //     // user1 deposit again => will claim first
  //     await expect(XVSVaultProxyInstance.connect(user1).deposit(RTInstance.address, 0, depositAmount))
  //       .to.be.emit(XVSVaultProxyInstance, "Claim").withArgs(user1.address, RTInstance.address, 0, anyValue);
  //   });
  // });

  describe("Test claim function", function () {
    it("The pool must be valid", async function () {
      const { XVSVaultProxyInstance, RTInstance } = await loadFixture(deployContracts);
      await expect(XVSVaultProxyInstance.claim(admin.address, RTInstance.address, 0)).to.revertedWith("vault: pool exists?");
    });

    it("Claim will get the correct reward token", async function () {
      const { XVSVaultProxyInstance, XVSStoreInstance, XVSVaultInstance, XVSInstance, RTInstance, TTInstance } = await loadFixture(deployContracts);

      const depositAmount = 100000000
      await RTInstance.transfer(XVSStoreInstance.address, depositAmount * 2)
      await TTInstance.connect(user1).approve(XVSVaultProxyInstance.address, depositAmount * 2)
      await TTInstance.transfer(user1.address, depositAmount * 2)
      await XVSVaultProxyInstance.add(RTInstance.address, 100, TTInstance.address, 1000, 86400000)
      await expect(XVSVaultProxyInstance.connect(user1).deposit(RTInstance.address, 0, depositAmount))
        .to.be.emit(XVSVaultProxyInstance, "Deposit").withArgs(user1.address, RTInstance.address, 0, depositAmount);

      const rewardTokenAmountsPerBlock = await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)
      expect(await XVSVaultProxyInstance.rewardTokenAmountsPerBlock(RTInstance.address)).to.equal(1000);
      const poolAccRewardPerShare = unit12.mul(rewardTokenAmountsPerBlock * 100 / 100).div(depositAmount)
      const pending = depositAmount * poolAccRewardPerShare / unit12
      console.log(pending);
      await expect(XVSVaultProxyInstance.claim(user1.address, RTInstance.address, 0))
        .to.be.emit(XVSVaultProxyInstance, "Claim").withArgs(user1.address, RTInstance.address, 0, pending);
      expect(await RTInstance.balanceOf(user1.address)).to.equal(pending);
    });
  });


  describe("Test requestWithdrawal function", function () {
    it("The pool must be valid", async function () {
      const { XVSVaultProxyInstance, RTInstance } = await loadFixture(deployContracts);
      await expect(XVSVaultProxyInstance.requestWithdrawal(RTInstance.address, 0, 1000)).to.revertedWith("vault: pool exists?");
    });

    it("RequestWithdrawal will set the correct data", async function () {
      const { XVSVaultProxyInstance, XVSStoreInstance, RTInstance, TTInstance } = await loadFixture(deployContracts);

      const depositAmount = 100000000
      const rewardAmountPerBlock = 1000
      await RTInstance.transfer(XVSStoreInstance.address, depositAmount * 2)
      await TTInstance.connect(user1).approve(XVSVaultProxyInstance.address, depositAmount * 2)
      await TTInstance.transfer(user1.address, depositAmount * 2)
      await XVSVaultProxyInstance.add(RTInstance.address, 100, TTInstance.address, rewardAmountPerBlock, 300)
      // user1 deposit once
      await XVSVaultProxyInstance.connect(user1).deposit(RTInstance.address, 0, depositAmount)
      time.increase(200);

      const amount = 10000
      await expect(XVSVaultProxyInstance.connect(user1).requestWithdrawal(RTInstance.address, 0, amount)).to.emit(
        XVSVaultProxyInstance, "RequestedWithdrawal"
      ).withArgs(user1.address, RTInstance.address, 0, amount);
      expect(await XVSVaultProxyInstance.getRequestedAmount(RTInstance.address, 0, user1.address)).to.equal(amount);
      time.increase(200);
      await XVSVaultProxyInstance.connect(user1).requestWithdrawal(RTInstance.address, 0, amount);
      expect(await XVSVaultProxyInstance.getRequestedAmount(RTInstance.address, 0, user1.address)).to.equal(amount * 2);

      let requests = await XVSVaultProxyInstance.getWithdrawalRequests(RTInstance.address, 0, user1.address);
      expect(requests.length).to.equal(2);
      expect(requests[0].amount).to.equal(amount);
      expect(requests[1].amount).to.equal(amount);

      // withdraw
      expect(await XVSVaultProxyInstance.getEligibleWithdrawalAmount(RTInstance.address, 0, user1.address)).to.equal(amount);
      expect(await TTInstance.balanceOf(user1.address)).to.equal(depositAmount);
      await expect(XVSVaultProxyInstance.connect(user1).executeWithdrawal(RTInstance.address, 0)).to.emit(
        XVSVaultProxyInstance, "ExecutedWithdrawal"
      ).withArgs(user1.address, RTInstance.address, 0, amount);
      expect(await TTInstance.balanceOf(user1.address)).to.equal(depositAmount + amount);
    });
  });

  describe("Test delegates function", function () {
    it("Delegate before deposit", async function () {
      const { XVSVaultProxyInstance, XVSStoreInstance, XVSInstance, RTInstance, TTInstance } = await loadFixture(deployContracts);

      const rewardAmountPerBlock = 1000
      const depositAmount = 100000000
      await expect(XVSVaultProxyInstance.connect(user1).delegate(user2.address))
        .to.be.emit(XVSVaultProxyInstance, "DelegateChangedV2").withArgs(user1.address, AddressZero, user2.address);
      // add pool
      await XVSVaultProxyInstance.add(XVSInstance.address, 100, XVSInstance.address, rewardAmountPerBlock, 200);
      await XVSInstance.transfer(user1.address, depositAmount * 2);
      await XVSInstance.transfer(XVSStoreInstance.address, depositAmount);
      await XVSInstance.connect(user1).approve(XVSVaultProxyInstance.address, ethers.constants.MaxInt256);

      // user1 deposit 
      await expect(XVSVaultProxyInstance.connect(user1).deposit(XVSInstance.address, 0, depositAmount)).to.emit(
        XVSVaultProxyInstance, "DelegateVotesChangedV2"
      ).withArgs(user2.address, 0, depositAmount);
      await expect(XVSVaultProxyInstance.connect(user1).deposit(XVSInstance.address, 0, depositAmount)).to.emit(
        XVSVaultProxyInstance, "DelegateVotesChangedV2"
      ).withArgs(user2.address, depositAmount, depositAmount * 2);
      const blockNumber = await ethers.provider.getBlockNumber();
      // check date
      expect(await XVSVaultProxyInstance.getCurrentVotes(user2.address)).to.equal(depositAmount * 2);
      expect(await XVSVaultProxyInstance.getCurrentVotes(user1.address)).to.equal(0);
      expect(await XVSVaultProxyInstance.getPriorVotes(user1.address, blockNumber - 1)).to.equal(0);
      expect(await XVSVaultProxyInstance.getPriorVotes(user2.address, blockNumber - 1)).to.equal(depositAmount);

      await XVSVaultProxyInstance.connect(user1).requestWithdrawal(XVSInstance.address, 0, depositAmount);
      expect(await XVSVaultProxyInstance.getPriorVotes(user2.address, blockNumber - 1)).to.equal(depositAmount);
      expect(await XVSVaultProxyInstance.getCurrentVotes(user2.address)).to.equal(depositAmount);
    });

    it("Delegate after deposit", async function () {
      const { XVSVaultProxyInstance, XVSStoreInstance, XVSInstance, TTInstance } = await loadFixture(deployContracts);
      const rewardAmountPerBlock = 1000
      const depositAmount = 100000000
      // prepare
      await XVSVaultProxyInstance.add(XVSInstance.address, 100, XVSInstance.address, rewardAmountPerBlock, 200);
      await XVSInstance.transfer(user1.address, depositAmount * 2);
      await XVSInstance.transfer(XVSStoreInstance.address, depositAmount);
      await XVSInstance.connect(user1).approve(XVSVaultProxyInstance.address, ethers.constants.MaxInt256);

      // user1 deposit
      await XVSVaultProxyInstance.connect(user1).deposit(XVSInstance.address, 0, depositAmount)
      expect(await XVSVaultProxyInstance.getCurrentVotes(user1.address)).to.equal(0);
      // user1 delegate to user2
      await expect(XVSVaultProxyInstance.connect(user1).delegate(user2.address))
        .to.be.emit(XVSVaultProxyInstance, "DelegateChangedV2").withArgs(user1.address, AddressZero, user2.address);
      expect(await XVSVaultProxyInstance.getCurrentVotes(user2.address)).to.equal(depositAmount);
      expect(await XVSVaultProxyInstance.getCurrentVotes(user1.address)).to.equal(0);
      // user1 deposit again
      await XVSVaultProxyInstance.connect(user1).deposit(XVSInstance.address, 0, depositAmount)
      expect(await XVSVaultProxyInstance.getCurrentVotes(user2.address)).to.equal(depositAmount * 2);
      expect(await XVSVaultProxyInstance.getCurrentVotes(user1.address)).to.equal(0);
      // user1 withdraw
      await XVSVaultProxyInstance.connect(user1).requestWithdrawal(XVSInstance.address, 0, depositAmount);
      expect(await XVSVaultProxyInstance.getCurrentVotes(user2.address)).to.equal(depositAmount);
      expect(await XVSVaultProxyInstance.getCurrentVotes(user1.address)).to.equal(0);
    });
  });
});
