const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("MasterChef Contract", function () {
  let owner, dev, user1, user2;
  const sushiPerBlock = 10000
  const startBlock = 100
  const bonusEndBlock = 200
  const BONUS_MULTIPLIER = 10
  const ZERO_ADDRESS = ethers.constants.AddressZero;
  const baseAmount = ethers.utils.parseEther("1000000");

  async function deployMasterChef() {
    [owner, dev, user1, user2] = await ethers.getSigners();

    // depoloy sushi token
    const SushiToken = await ethers.getContractFactory("SushiToken");
    const SushiInstance = await SushiToken.deploy();

    const MasterChef = await ethers.getContractFactory("MasterChef");
    const MasterChefInstance = await MasterChef.deploy(SushiInstance.address, dev.address, sushiPerBlock, startBlock, bonusEndBlock);
    await SushiInstance.mint(owner.address, baseAmount);
    await SushiInstance.transferOwnership(MasterChefInstance.address); // need ownerShip while mint sushi

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const LPToken1Instance = await MockERC20.deploy("LPToken1", "LP1", baseAmount);
    const NewTokenInstance = await MockERC20.deploy("NewToken", "NT", baseAmount);
    const MockERC777 = await ethers.getContractFactory("MockERC777");
    const ERC1820Registry = await ethers.getContractFactory("ERC1820Registry");
    const RegistryInstance = await ERC1820Registry.deploy();
    const LPToken2Instance = await MockERC777.deploy(RegistryInstance.address, "LpToken2", "LP2", baseAmount, [owner.address])

    return { MasterChefInstance, SushiInstance, LPToken1Instance, LPToken2Instance, NewTokenInstance, RegistryInstance };
  }

  describe("Test migrate", function () {
    it("Migrator can get all lpToken by function migrate", async function () {
      const { MasterChefInstance, LPToken1Instance, NewTokenInstance } = await loadFixture(deployMasterChef);

      // set migrator
      await time.advanceBlock(bonusEndBlock)
      const MockMigrator = await ethers.getContractFactory("MockMigrator");
      const MockMigratorInstance = await MockMigrator.deploy(MasterChefInstance.address, LPToken1Instance.address, NewTokenInstance.address);
      await MasterChefInstance.setMigrator(MockMigratorInstance.address);
      expect(await MasterChefInstance.migrator()).to.equal(MockMigratorInstance.address)
      // prepare: deposit some lpToken
      const depositAmount = 10000
      await LPToken1Instance.transfer(user1.address, depositAmount)
      await LPToken1Instance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await LPToken1Instance.approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await MasterChefInstance.add(100, LPToken1Instance.address, false);
      await MasterChefInstance.connect(user1).deposit(0, depositAmount)
      await MasterChefInstance.deposit(0, depositAmount)
      await expect(MasterChefInstance.migrate(0)).to.be.revertedWith("migrate: bad")
      // prepare: deposit some newToken
      await NewTokenInstance.transfer(user1.address, depositAmount)
      await NewTokenInstance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await NewTokenInstance.approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await MasterChefInstance.add(100, NewTokenInstance.address, false);
      await MasterChefInstance.connect(user1).deposit(1, depositAmount)
      await MasterChefInstance.deposit(1, depositAmount)
      // check balance 
      expect(await LPToken1Instance.balanceOf(MasterChefInstance.address)).to.equal(depositAmount * 2)
      expect(await LPToken1Instance.balanceOf(owner.address)).to.equal(baseAmount.sub(depositAmount * 2))
      expect(await NewTokenInstance.balanceOf(MasterChefInstance.address)).to.equal(depositAmount * 2)  // migrator need eqaul amount of new token
      // migrate
      await MasterChefInstance.migrate(0)
      // check balance 
      expect(await LPToken1Instance.balanceOf(MasterChefInstance.address)).to.equal(0)
      expect(await LPToken1Instance.balanceOf(owner.address)).to.equal(baseAmount) // owner get all deposit token but cost nothing
    });
  });

  describe("Reentrancy attacks reappear demonstration", function () {
    it("Function withdraw reentrancy", async function () {
      const { MasterChefInstance, SushiInstance, LPToken2Instance, RegistryInstance } = await loadFixture(deployMasterChef);
      const MockERC777Attack = await ethers.getContractFactory("MockERC777Attack")
      const AttackInstance = await MockERC777Attack.deploy(LPToken2Instance.address, RegistryInstance.address, MasterChefInstance.address)
      // prepare
      await AttackInstance.approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await LPToken2Instance.transfer(MasterChefInstance.address, 1000)
      await LPToken2Instance.transfer(AttackInstance.address, 1000)
      expect(await LPToken2Instance.balanceOf(MasterChefInstance.address)).to.equal(1000)
      expect(await LPToken2Instance.balanceOf(AttackInstance.address)).to.equal(1000)
      await MasterChefInstance.add(100, LPToken2Instance.address, false)
      await AttackInstance.depositAll()
      expect(await LPToken2Instance.balanceOf(AttackInstance.address)).to.equal(0)
      expect(await LPToken2Instance.balanceOf(MasterChefInstance.address)).to.equal(2000)
      expect(await LPToken2Instance.balanceOf(owner.address)).to.equal(baseAmount.sub(2000))
      // withdraw
      await time.advanceBlock(10);
      await AttackInstance.withdrawAttack(100);
      expect(await LPToken2Instance.balanceOf(MasterChefInstance.address)).to.equal(100)
      expect(await LPToken2Instance.balanceOf(owner.address)).to.equal(baseAmount.sub(100))
    });

    it("Function emergencyWithdraw reentrancy", async function () {
      const { MasterChefInstance, LPToken2Instance, RegistryInstance } = await loadFixture(deployMasterChef);
      // 添加 ERC77 作为质押代币的池子
      // 用户质押 （保证池子中有大于这个用户质押的LP代币）
      const MockERC777Attack = await ethers.getContractFactory("MockERC777Attack")
      const AttackInstance = await MockERC777Attack.deploy(LPToken2Instance.address, RegistryInstance.address, MasterChefInstance.address)
      // prepare
      await AttackInstance.approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await LPToken2Instance.transfer(MasterChefInstance.address, 1000)
      await LPToken2Instance.transfer(AttackInstance.address, 1000)
      expect(await LPToken2Instance.balanceOf(MasterChefInstance.address)).to.equal(1000)
      expect(await LPToken2Instance.balanceOf(AttackInstance.address)).to.equal(1000)
      await MasterChefInstance.add(100, LPToken2Instance.address, false)
      await AttackInstance.depositAll()
      expect(await LPToken2Instance.balanceOf(AttackInstance.address)).to.equal(0)
      expect(await LPToken2Instance.balanceOf(MasterChefInstance.address)).to.equal(2000)
      expect(await LPToken2Instance.balanceOf(owner.address)).to.equal(baseAmount.sub(2000))
      // withdraw
      await time.advanceBlock(10);
      await AttackInstance.withdrawAllAttack();
      expect(await LPToken2Instance.balanceOf(MasterChefInstance.address)).to.equal(0)
      expect(await LPToken2Instance.balanceOf(AttackInstance.address)).to.equal(0)
      expect(await LPToken2Instance.balanceOf(owner.address)).to.equal(baseAmount)
    });
  });

  describe("Test add the same lpToken", function () {
    it("Add the same lpToken pool", async function () {
      const { MasterChefInstance, LPToken1Instance } = await loadFixture(deployMasterChef);
      const LP1AllocPoint = 100
      const depositAmount = 10000
      // add two same pools
      await MasterChefInstance.add(LP1AllocPoint, LPToken1Instance.address, false);
      await MasterChefInstance.add(LP1AllocPoint, LPToken1Instance.address, false);
      // prepare
      await LPToken1Instance.transfer(user1.address, baseAmount.div(2));
      await LPToken1Instance.transfer(user2.address, baseAmount.div(2));
      await LPToken1Instance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await LPToken1Instance.connect(user2).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await time.advanceBlock(startBlock)
      const rewardPerblockEachPool = sushiPerBlock / 2
      // user deposit and update for pool0
      await MasterChefInstance.connect(user1).deposit(0, depositAmount);
      const user1Info = await MasterChefInstance.userInfo(0, user1.address);
      expect(user1Info.amount).to.equal(depositAmount)
      expect(user1Info.rewardDebt).to.equal(0)
      await time.advanceBlock(10)
      await MasterChefInstance.updatePool(0);
      let blockNumber = await time.latestBlock();
      const multiplier1 = await MasterChefInstance.getMultiplier(blockNumber - 11, blockNumber);
      const accSushiPerShare1 = multiplier1 * rewardPerblockEachPool * 1e12 / depositAmount
      let pool0Info = await MasterChefInstance.poolInfo(0);
      expect(pool0Info.lpToken).to.equal(LPToken1Instance.address)
      expect(pool0Info.lastRewardBlock).to.equal(blockNumber)
      expect(pool0Info.accSushiPerShare).to.equal(accSushiPerShare1)
      // update pool1
      let pool1Info = await MasterChefInstance.poolInfo(1);
      expect(pool1Info.lpToken).to.equal(LPToken1Instance.address)
      expect(pool1Info.lastRewardBlock).to.equal(startBlock)
      expect(pool1Info.accSushiPerShare).to.equal(0)
      await MasterChefInstance.updatePool(1); // nobody deposit in pool1, should have return and haven't update pool.accSushiPerShare
      blockNumber = await time.latestBlock();
      pool1Info = await MasterChefInstance.poolInfo(1);
      expect(pool1Info.lastRewardBlock).to.equal(blockNumber)
      expect(pool1Info.accSushiPerShare).to.gt(0) // should have been 0 for the first deposit
      // nobody deposit at pool1, but pool1Info.accSushiPerShare add
      await MasterChefInstance.connect(user2).deposit(1, depositAmount);
      const user2Info = await MasterChefInstance.userInfo(1, user2.address);
      expect(user2Info.amount).to.equal(depositAmount)
      expect(user2Info.rewardDebt).to.gt(0) // should have been 0 for the first deposit
    });

    it("Deposit sushi for lpToken", async function () {
      const { MasterChefInstance, SushiInstance, LPToken1Instance } = await loadFixture(deployMasterChef);
      // 更新池子的时候 会把mint出来的奖励代币也算到质押代币的总量中 导致奖励代币和质押代币混淆 计算accSushiPerShare时与预想的有很大偏差
      const depositAmount = 10000
      // prepare 
      await SushiInstance.transfer(user1.address, depositAmount)
      await SushiInstance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await time.advanceBlock(startBlock)
      // add pool: SushiInstance as lpToken
      await MasterChefInstance.add(100, SushiInstance.address, false);
      await MasterChefInstance.connect(user1).deposit(0, depositAmount)
      await time.advanceBlock(10)
      // update pool after 10 block
      await MasterChefInstance.updatePool(0);
      let blockNumber = await time.latestBlock();
      // cuaculate 
      const multiplier1 = await MasterChefInstance.getMultiplier(blockNumber - 11, blockNumber);
      const accSushiPerShare1 = multiplier1 * sushiPerBlock * 1e12 / depositAmount
      let pool0Info = await MasterChefInstance.poolInfo(0);
      expect(pool0Info.lastRewardBlock).to.equal(blockNumber)
      expect(pool0Info.accSushiPerShare).to.equal(accSushiPerShare1)
      // update pool again after 10 block
      await time.advanceBlock(10)
      await MasterChefInstance.updatePool(0);
      // console.log(await SushiInstance.balanceOf(MasterChefInstance.address),);

      blockNumber = await time.latestBlock();
      // cuaculate: nobody deposit more, new accSushiPerShare should add the same amount as before
      const multiplier2 = await MasterChefInstance.getMultiplier(blockNumber - 11, blockNumber);
      const accSushiPerShare2 = accSushiPerShare1 + multiplier2 * sushiPerBlock * 1e12 / depositAmount
      // when updatePool, supply is diposit sushi + reward sushi, caculate accSushiPerShare2 will div (depositAmount add reward sushi)
      pool0Info = await MasterChefInstance.poolInfo(0);
      expect(pool0Info.lastRewardBlock).to.equal(blockNumber)
      expect(pool0Info.accSushiPerShare).to.lte(accSushiPerShare2)
    });

    it("Test by the same way above for other lpToken", async function () {
      const { MasterChefInstance, SushiInstance, LPToken1Instance } = await loadFixture(deployMasterChef);
      const depositAmount = 10000
      // prepare 
      await LPToken1Instance.transfer(user1.address, depositAmount)
      await LPToken1Instance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await time.advanceBlock(startBlock)
      // add pool: LPToken1Instance as lpToken
      await MasterChefInstance.add(100, LPToken1Instance.address, false);
      await MasterChefInstance.connect(user1).deposit(0, depositAmount)
      await time.advanceBlock(10)
      // update pool after 10 block
      await MasterChefInstance.updatePool(0);
      let blockNumber = await time.latestBlock();
      // cuaculate 
      const multiplier1 = await MasterChefInstance.getMultiplier(blockNumber - 11, blockNumber);
      const accSushiPerShare1 = multiplier1 * sushiPerBlock * 1e12 / depositAmount
      let pool0Info = await MasterChefInstance.poolInfo(0);
      expect(pool0Info.lastRewardBlock).to.equal(blockNumber)
      expect(pool0Info.accSushiPerShare).to.equal(accSushiPerShare1)
      // update pool again after 10 block
      await time.advanceBlock(10)
      await MasterChefInstance.updatePool(0);
      blockNumber = await time.latestBlock();
      // cuaculate: nobody deposit more, new accSushiPerShare should add the same amount as before
      const multiplier2 = await MasterChefInstance.getMultiplier(blockNumber - 11, blockNumber);
      const accSushiPerShare2 = accSushiPerShare1 + multiplier2 * sushiPerBlock * 1e12 / depositAmount
      pool0Info = await MasterChefInstance.poolInfo(0);
      expect(pool0Info.lastRewardBlock).to.equal(blockNumber)
      expect(pool0Info.accSushiPerShare).to.equal(accSushiPerShare2)
      const pendingSushi = accSushiPerShare2 * depositAmount / 1e12
      expect(await MasterChefInstance.pendingSushi(0, user1.address)).to.equal(pendingSushi)
      expect(await SushiInstance.balanceOf(user1.address)).to.equal(0)
      expect(await SushiInstance.balanceOf(MasterChefInstance.address)).to.equal(pendingSushi)
      // widthdraw will success
      await MasterChefInstance.connect(user1).withdraw(0, depositAmount)
      expect(await LPToken1Instance.balanceOf(user1.address)).to.equal(depositAmount)
      expect(await SushiInstance.balanceOf(user1.address)).to.equal(pendingSushi + sushiPerBlock * 10) // new block reward when widthdraw
    });
  });



  describe("Check mata data", function () {
    it("Should set the correct constructor data", async function () {
      const { MasterChefInstance, SushiInstance } = await loadFixture(deployMasterChef);
      expect(await MasterChefInstance.sushi()).to.equal(SushiInstance.address)
      expect(await MasterChefInstance.devaddr()).to.equal(dev.address)
      expect(await MasterChefInstance.bonusEndBlock()).to.equal(bonusEndBlock)
      expect(await MasterChefInstance.sushiPerBlock()).to.equal(sushiPerBlock)
      expect(await MasterChefInstance.BONUS_MULTIPLIER()).to.equal(BONUS_MULTIPLIER)
      expect(await MasterChefInstance.migrator()).to.equal(ZERO_ADDRESS)
      expect(await MasterChefInstance.startBlock()).to.equal(startBlock)
    });
  });

  describe("Test add pool", function () {
    it("Should set the correct pool infomation", async function () {
      const { MasterChefInstance, SushiInstance, LPToken1Instance } = await loadFixture(deployMasterChef);

      const LP1AllocPoint = 100
      expect(await MasterChefInstance.totalAllocPoint()).to.equal(0)
      // add pool
      await MasterChefInstance.add(LP1AllocPoint, LPToken1Instance.address, false);
      // check data
      expect(await MasterChefInstance.totalAllocPoint()).to.equal(LP1AllocPoint)
      const blockNumber = await time.latestBlock();
      const poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.lpToken).to.equal(LPToken1Instance.address)
      expect(poolInfo.allocPoint).to.equal(LP1AllocPoint)
      expect(poolInfo.lastRewardBlock).to.equal(blockNumber > startBlock ? blockNumber : startBlock)
      expect(poolInfo.accSushiPerShare).to.equal(0)
    });
  });

  describe("Test deposit", function () {
    it("First deposit should set the correct infomation", async function () {
      const { MasterChefInstance, LPToken1Instance } = await loadFixture(deployMasterChef);

      const LP1AllocPoint = 100
      const depositAmount = 10000
      await MasterChefInstance.add(LP1AllocPoint, LPToken1Instance.address, false);
      await LPToken1Instance.transfer(user1.address, baseAmount);
      await LPToken1Instance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await time.advanceBlock(startBlock)
      // first deposit
      await expect(MasterChefInstance.connect(user1).deposit(0, depositAmount))
        .to.emit(MasterChefInstance, "Deposit")
        .withArgs(user1.address, 0, depositAmount);
      // check data
      let blockNumber = await time.latestBlock();
      const poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.allocPoint).to.equal(LP1AllocPoint)
      expect(poolInfo.lastRewardBlock).to.equal(blockNumber)
      expect(poolInfo.accSushiPerShare).to.equal(0)
      const user1Info = await MasterChefInstance.userInfo(0, user1.address);
      expect(user1Info.amount).to.equal(depositAmount)
      expect(user1Info.rewardDebt).to.equal(0)
    });

    it("Deposit more times should set the correct reward", async function () {
      const { MasterChefInstance, SushiInstance, LPToken1Instance } = await loadFixture(deployMasterChef);

      // prepare data
      const LP1AllocPoint = 100
      const depositAmount = 10000
      await MasterChefInstance.add(LP1AllocPoint, LPToken1Instance.address, false);
      await LPToken1Instance.transfer(user1.address, baseAmount);
      await LPToken1Instance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await time.advanceBlock(startBlock)

      // first deposit
      await expect(MasterChefInstance.connect(user1).deposit(0, depositAmount))
        .to.emit(MasterChefInstance, "Deposit")
        .withArgs(user1.address, 0, depositAmount);
      // first check data
      let blockNumber = await time.latestBlock();
      let poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.allocPoint).to.equal(LP1AllocPoint)
      expect(poolInfo.accSushiPerShare).to.equal(0)
      expect(poolInfo.lastRewardBlock).to.equal(blockNumber)
      let user1Info = await MasterChefInstance.userInfo(0, user1.address);
      expect(user1Info.amount).to.equal(depositAmount)
      expect(user1Info.rewardDebt).to.equal(0)
      expect(await MasterChefInstance.pendingSushi(0, user1.address)).to.equal(0)

      /**
       *                      第一次质押前       第一次质押完后   =>    第二次质押前       第二次质押完后     =>     第三次质押前       第三次质押完后
       *   user.amount             0              10000               10000            20000                  20000              30000
       *   user.rewardDebt         0                0                   0           number2(20000)            20000              450000
       *   pendingReward-Sushi             0                                  10000                                    10000             
       *  pool.accSushiPerShare    0                0                   0           number1(1e12)             1e12               3e12/2
       *  pool.amount              0              10000                10000           20000                  20000              30000
       *  pool.lastRewardBlock   block           block+1              block+1          block+2                block+2            block+3         (这里也不一定，反正是记录上一次更新池子数据的区块号)
       * 
       * 
       *  其中 number1 的计算为：
       *   sushiReward = multiplier * sushiPerBlock * pool.allocPoint / totalAllocPoint
       *               = (block+1-block) * 10000 * 100 / 100 = 10000
       *   pool.accSushiPerShare = pool.accSushiPerShare + sushiReward * 1e12 / pool.amount（第一次pool.accSushiPerShare为0）
       *                         = 0 + 10000 * 1e12 / 10000 = 1e12
       *   number1 = pool.accSushiPerShare = 1e12
       *   如果每个这个池子每个区块被分配到的奖励 sushiReward 保持不变的话，user.rewardDebt 在每一次更新池子时都会根据更新当前池子中lptoken的数量更新和累加奖励
       * 
       * 
       *  其中 number2 的计算为：
       *  user.rewardDebt = user.amount * pool.accSushiPerShare / 1e12   （这里）
       *                  = 20000 * 1e12 / 1e12 = 20000
       *  number2 = user.rewardDebt = 20000
       *  注意第二次质押之后给 user1 已经发放的奖励是 10000 但是记录的 user.rewardDebt 为 20000     
       * 
       * 
       *  第一次质押完后 user.rewardDebt 为0主要是因为第一次时 pool.lastRewardBlock 为 0
       * 
       * 
       *  第二次 user1 质押期间会发送的奖励数量：（注意此时用到的池子数据是执行了updatePool池子数据被更新之后的-也就是上表中第二次质押完后的pool数据计算的值，算好之后直接将奖励发给user1）
       *    pending = user.amount * pool.accSushiPerShare / 1e12 - user.rewardDebt 
       *            = 10000 * 1e12 / 1e12 - 0 = 10000
       *    pending 在理解上其实是第二次质押之前根据第一次的质押数量计算第一次质押到现在这段时间应获得的奖励，保证这次质押数量的增加不会影响之前的奖励
       * 
       * 
       *  注意：每次质押之前都会使用上一次质押后的数据更新池子的数据
       *       updatePool 主要会更新：pool.accSushiPerShare 和 pool.lastRewardBlock
       *                  并且计算当前区块距离上一次更新区块之间整个池子的奖励并且mint出来
       * 
       * 
       *  需要注意的重难点：
       *  1. 为什么 pool.accSushiPerShare 是累加的？
       *  2. 为什么 user.rewardDebt 是根据当前质押完成之后总的质押数量和 pool.accSushiPerShare 计算出来的？
       *  
       * 
       */

      // second deposit
      await MasterChefInstance.connect(user1).deposit(0, depositAmount);
      // second check data
      blockNumber = await time.latestBlock();
      let multiplier = await MasterChefInstance.getMultiplier(blockNumber - 1, blockNumber); // will mul 10 between startBlock and bonusEndBlock(block 100-200)
      let sushiReward = multiplier * sushiPerBlock * LP1AllocPoint / 100; // only one pool => this pool will get all reward 
      const accSushiPerShare1 = sushiReward * 1e12 / depositAmount; // user.amount only the first deposit amount while computing reward
      let mintedSushiAmount = sushiReward / 10 + sushiReward
      const pending1 = depositAmount * accSushiPerShare1 / 1e12 - user1Info.rewardDebt
      expect(await SushiInstance.totalSupply()).to.equal(baseAmount.add(mintedSushiAmount))
      expect(await SushiInstance.balanceOf(dev.address)).to.equal(sushiReward / 10)
      expect(await SushiInstance.balanceOf(MasterChefInstance.address)).to.equal(0)
      expect(await SushiInstance.balanceOf(user1.address)).to.equal(pending1) // user1 is the only one user,so pending = mintedSushiAmount
      poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.allocPoint).to.equal(LP1AllocPoint)
      expect(poolInfo.accSushiPerShare).to.equal(accSushiPerShare1)
      expect(poolInfo.lastRewardBlock).to.equal(blockNumber)
      user1Info = await MasterChefInstance.userInfo(0, user1.address);
      expect(user1Info.amount).to.equal(depositAmount * 2)
      expect(user1Info.rewardDebt).to.equal(depositAmount * 2 * accSushiPerShare1 / 1e12)
      expect(await LPToken1Instance.balanceOf(MasterChefInstance.address)).to.equal(depositAmount * 2)
      expect(await MasterChefInstance.pendingSushi(0, user1.address)).to.equal(0)

      // third deposit
      await MasterChefInstance.connect(user1).deposit(0, depositAmount);
      // third check data
      blockNumber = await time.latestBlock();
      multiplier = await MasterChefInstance.getMultiplier(blockNumber - 1, blockNumber);
      sushiReward = multiplier * sushiPerBlock * LP1AllocPoint / 100; // sushiReward is the same as the second deposit
      const accSushiPerShare2 = (sushiReward * 1e12) / (depositAmount * 2) + accSushiPerShare1; // 20000 * 1e12 / 20000 *2 + 1e12 = 3e12/2
      // //  accSushiPerShare2 need to add up the previous accSushiPerShare
      mintedSushiAmount = sushiReward / 10 + sushiReward
      const pending2 = depositAmount * 2 * accSushiPerShare2 / 1e12 - user1Info.rewardDebt // 20000 *  3e12 / 2e12 - 20000 = 10000
      expect(await SushiInstance.totalSupply()).to.equal(baseAmount.add(mintedSushiAmount * 2)) // mint 2 times
      expect(await SushiInstance.balanceOf(dev.address)).to.equal(sushiReward / 10 * 2)
      expect(await SushiInstance.balanceOf(MasterChefInstance.address)).to.equal(0)
      expect(await SushiInstance.balanceOf(user1.address)).to.equal(pending1 + pending2)
      poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.allocPoint).to.equal(LP1AllocPoint)
      expect(poolInfo.accSushiPerShare).to.equal(accSushiPerShare2)
      expect(poolInfo.lastRewardBlock).to.equal(blockNumber)
      user1Info = await MasterChefInstance.userInfo(0, user1.address);
      expect(user1Info.amount).to.equal(depositAmount * 3)
      expect(user1Info.rewardDebt).to.equal(depositAmount * 3 * accSushiPerShare2 / 1e12)
      expect(await LPToken1Instance.balanceOf(MasterChefInstance.address)).to.equal(depositAmount * 3)
    });

    it("Deposit more times with more people should set the correct reward", async function () {
      const { MasterChefInstance, SushiInstance, LPToken1Instance } = await loadFixture(deployMasterChef);

      // prepare data
      const LP1AllocPoint = 100
      const user1DepositAmount = 10000
      const user2DepositAmount = 20000
      await MasterChefInstance.add(LP1AllocPoint, LPToken1Instance.address, false);
      await LPToken1Instance.transfer(user1.address, baseAmount.div(2));
      await LPToken1Instance.transfer(user2.address, baseAmount.div(2));
      await LPToken1Instance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await LPToken1Instance.connect(user2).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await time.advanceBlock(startBlock)

      // user1 first deposit
      await MasterChefInstance.connect(user1).deposit(0, user1DepositAmount)
      const accSushiPerShare1 = 0
      let poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.accSushiPerShare).to.equal(accSushiPerShare1)

      // user2 first deposit
      await MasterChefInstance.connect(user2).deposit(0, user2DepositAmount)
      const multiplier = 10 // 我现在测试的区块区间都会在bonus区间，一个区块的奖励都会乘以10，这里直接记录下来就不每次都获取一次了，方便计算
      const poolAlloc = 1 // 当前池子在所有池子中所占的总权重，目前只有一个池子，所以每个区块奖励全都会给这个池子，也是为了好计算直接记录
      const sushiReward = multiplier * sushiPerBlock * poolAlloc

      const lpSupply2 = user1DepositAmount
      const accSushiPerShare2 = accSushiPerShare1 + sushiReward * 1e12 / lpSupply2
      poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.accSushiPerShare).to.equal(accSushiPerShare2)

      // user1 second deposit
      await MasterChefInstance.connect(user1).deposit(0, user1DepositAmount)
      const lpSupply3 = user1DepositAmount + user2DepositAmount
      const accSushiPerShare3 = accSushiPerShare2 + sushiReward * 1e12 / lpSupply3
      poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.accSushiPerShare).to.equal(Math.floor(accSushiPerShare3))

      // user2 second deposit
      await MasterChefInstance.connect(user2).deposit(0, user2DepositAmount)
      const lpSupply4 = user1DepositAmount * 2 + user2DepositAmount
      const accSushiPerShare4 = accSushiPerShare3 + sushiReward * 1e12 / lpSupply4

      // // check pool data
      const blockNumber = await time.latestBlock();
      poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.allocPoint).to.equal(LP1AllocPoint)
      expect(poolInfo.accSushiPerShare).to.equal(Math.floor(accSushiPerShare4))
      expect(poolInfo.lastRewardBlock).to.equal(blockNumber)
      // // check user1 data
      const user1Info = await MasterChefInstance.userInfo(0, user1.address);
      const user1Debt = user1DepositAmount * 2 * accSushiPerShare3 / 1e12
      const user1Pending = user1DepositAmount * accSushiPerShare3 / 1e12 - 0
      expect(user1Info.amount).to.equal(user1DepositAmount * 2)
      expect(user1Info.rewardDebt).to.equal(Math.floor(user1Debt))
      expect(await SushiInstance.balanceOf(user1.address)).to.equal(Math.floor(user1Pending))

      // // check user2 data
      poolInfo = await MasterChefInstance.poolInfo(0);
      expect(poolInfo.allocPoint).to.equal(LP1AllocPoint)
      expect(poolInfo.accSushiPerShare).to.equal(Math.floor(accSushiPerShare4))
      expect(poolInfo.lastRewardBlock).to.equal(blockNumber)
      // // check user1 data
      const user2Info = await MasterChefInstance.userInfo(0, user2.address);
      const user2Debt = user2DepositAmount * 2 * accSushiPerShare4 / 1e12
      const user2Pending = user2DepositAmount * accSushiPerShare4 / 1e12 - 0
      expect(user2Info.amount).to.equal(user2DepositAmount * 2)
      expect(user2Info.rewardDebt).to.equal(Math.floor(user2Debt))
      // 这里 user2 的最后拿到的 pending 值计算有问题，还没看出来是哪里出错了
      // console.log(await SushiInstance.balanceOf(user2.address), user2Pending, user2Debt);
      // expect(await SushiInstance.balanceOf(user2.address)).to.equal(Math.floor(user2Pending))
    });
  });

  describe("Test pendingSushi", function () {
    it("Should get correct pendingSushi", async function () {
      const { MasterChefInstance, LPToken1Instance } = await loadFixture(deployMasterChef);

      // prepare data
      const LP1AllocPoint = 100
      const depositAmount = 10000
      await MasterChefInstance.add(LP1AllocPoint, LPToken1Instance.address, false);
      await LPToken1Instance.transfer(user1.address, baseAmount);
      await LPToken1Instance.connect(user1).approve(MasterChefInstance.address, ethers.constants.MaxUint256);
      await time.advanceBlock(startBlock)

      // first deposit
      await MasterChefInstance.connect(user1).deposit(0, depositAmount)
      let blockNumber = await time.latestBlock();
      await time.advanceBlock(10)
      let multiplier = await MasterChefInstance.getMultiplier(blockNumber, blockNumber + 10)
      let sushiReward = multiplier * sushiPerBlock
      let accSushiPerShare = sushiReward * 1e12 / depositAmount
      let pending = depositAmount * accSushiPerShare / 1e12
      expect(await MasterChefInstance.pendingSushi(0, user1.address)).to.equal(pending)

    });
  });
});

