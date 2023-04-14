const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { network } = require("hardhat");
const { BigNumber } = require("ethers");

describe("Liquity", function () {
  let bountyAddress, multisigAddress;

  // 部署流程参考：https://github.com/liquity/dev#launch-sequence-and-vesting-process

  async function deployLiquity() {
    [bountyAddress, multisigAddress] = await ethers.getSigners();

    // 部署 Trove 管理合约地址（immutable）
    const TroveManager = await ethers.getContractFactory("TroveManager");
    const TroveManagerInstance = await TroveManager.deploy();
    // 部署 稳定池 合约地址（immutable）
    const StabilityPool = await ethers.getContractFactory("StabilityPool");
    const StabilityPoolInstance = await StabilityPool.deploy();
    // 部署 借贷操作 合约地址（immutable）
    const BorrowerOperations = await ethers.getContractFactory("BorrowerOperations");
    const BorrowerOperationsInstance = await BorrowerOperations.deploy();

    // 部署 LUSD Token
    const LUSDToken = await ethers.getContractFactory("LUSDToken");
    const LusdInstance = await LUSDToken.deploy(TroveManagerInstance.address, StabilityPoolInstance.address, BorrowerOperationsInstance.address);


    // 部署 communityIssuance
    const CommunityIssuance = await ethers.getContractFactory("CommunityIssuance");
    const CommunityIssuanceInstance = await CommunityIssuance.deploy();
    // 部署 LQTYStaking
    const LQTYStaking = await ethers.getContractFactory("LQTYStaking");
    const LQTYStakingInstance = await LQTYStaking.deploy();
    // 部署 LockupContractFactory
    const LockupContractFactory = await ethers.getContractFactory("LockupContractFactory");
    const LockupContractFactoryInstance = await LockupContractFactory.deploy();

    // creates a Pool in Uniswap for LUSD/ETH and deploys Unipool (LP rewards contract)
    const Unipool = await ethers.getContractFactory("Unipool");
    const UnipoolInstance = await Unipool.deploy();

    // 部署 LQTYToken
    const LQTYToken = await ethers.getContractFactory("LQTYToken");
    const LQTYInstance = await LQTYToken.deploy(CommunityIssuanceInstance.address, LQTYStakingInstance.address, LockupContractFactoryInstance.address, bountyAddress.address, UnipoolInstance.address, multisigAddress.address);

    // 部署 ActivePool
    const ActivePool = await ethers.getContractFactory("ActivePool");
    const ActivePoolInstance = await ActivePool.deploy();

    // sets LQTYToken address in LockupContractFactory, CommunityIssuance, LQTYStaking and Unipool
    await LockupContractFactoryInstance.setLQTYTokenAddress(LQTYInstance.address)
    await CommunityIssuanceInstance.setAddresses(LQTYInstance.address, StabilityPoolInstance.address)
    await LQTYStakingInstance.setAddresses(LQTYInstance.address, LusdInstance.address, TroveManagerInstance.address, BorrowerOperationsInstance.address, ActivePoolInstance.address)

    // 部署 uniToken
    const UnitokenInstance = await ethers.getContractAt("UniswapV2Pair", "0xF20EF17b889b437C151eB5bA15A47bFc62bfF469");
    await UnipoolInstance.setParams(LQTYInstance.address, UnitokenInstance.address, 2592000) // 30 天

    return {
      Instances: {
        LusdInstance, TroveManagerInstance, StabilityPoolInstance, BorrowerOperationsInstance,
        LQTYInstance, CommunityIssuanceInstance, LQTYStakingInstance, LockupContractFactoryInstance,
        StabilityPoolInstance, ActivePoolInstance
      }
    };
  }

  // Hardhat 默认使用的本地测试链网络ID为 31337
  describe("Token test", function () {
    it("Deploy LUSD and test constructor arguments", async function () {
      const { Instances } = await loadFixture(deployLiquity);
      const { LusdInstance, TroveManagerInstance, StabilityPoolInstance, BorrowerOperationsInstance } = Instances;

      expect(await LusdInstance.troveManagerAddress()).to.equal(TroveManagerInstance.address);
      expect(await LusdInstance.stabilityPoolAddress()).to.equal(StabilityPoolInstance.address);
      expect(await LusdInstance.borrowerOperationsAddress()).to.equal(BorrowerOperationsInstance.address);

      // console.log(await LusdInstance.totalSupply());

    });

    it("Deploy LQTY and test constructor arguments", async function () {
      const { Instances } = await loadFixture(deployLiquity);
      const { LQTYInstance, LusdInstance, CommunityIssuanceInstance, LQTYStakingInstance, LockupContractFactoryInstance, StabilityPoolInstance, TroveManagerInstance, BorrowerOperationsInstance, ActivePoolInstance } = Instances;

      expect(await LQTYInstance.communityIssuanceAddress()).to.equal(CommunityIssuanceInstance.address);
      expect(await LQTYInstance.lqtyStakingAddress()).to.equal(LQTYStakingInstance.address);
      expect(await LQTYInstance.lockupContractFactory()).to.equal(LockupContractFactoryInstance.address);

      // let bountyAddress, multisigAddress;
      const _1_MILLION = BigNumber.from("1000000000000000000000000");
      const bountyEntitlement = _1_MILLION.mul(2)
      const depositorsAndFrontEndsEntitlement = _1_MILLION.mul(32)
      const lpRewardsEntitlement = _1_MILLION.mul(4).div(3)
      const multisigEntitlement = _1_MILLION.mul(100).sub(bountyEntitlement).sub(depositorsAndFrontEndsEntitlement).sub(lpRewardsEntitlement)
      expect(await LQTYInstance.balanceOf(bountyAddress.address)).to.equal(bountyEntitlement);
      expect(await LQTYInstance.balanceOf(CommunityIssuanceInstance.address)).to.equal(depositorsAndFrontEndsEntitlement);
      expect(await LQTYInstance.balanceOf(multisigAddress.address)).to.equal(multisigEntitlement);
      expect(await LQTYInstance.getLpRewardsEntitlement()).to.equal(lpRewardsEntitlement);
      expect(await LQTYInstance.totalSupply()).to.equal(bountyEntitlement.add(depositorsAndFrontEndsEntitlement).add(lpRewardsEntitlement).add(multisigEntitlement));
      expect(await LQTYInstance.getLpRewardsEntitlement()).to.equal(lpRewardsEntitlement);

      // test right LQTYToken address in LockupContractFactory, CommunityIssuance, LQTYStaking, and Unipool
      expect(await LockupContractFactoryInstance.lqtyTokenAddress()).to.equal(LQTYInstance.address);
      expect(await CommunityIssuanceInstance.lqtyToken()).to.equal(LQTYInstance.address);
      expect(await CommunityIssuanceInstance.stabilityPoolAddress()).to.equal(StabilityPoolInstance.address);
      expect(await LQTYStakingInstance.lqtyToken()).to.equal(LQTYInstance.address);
      expect(await LQTYStakingInstance.lusdToken()).to.equal(LusdInstance.address);
      expect(await LQTYStakingInstance.troveManagerAddress()).to.equal(TroveManagerInstance.address);
      expect(await LQTYStakingInstance.borrowerOperationsAddress()).to.equal(BorrowerOperationsInstance.address);
      expect(await LQTYStakingInstance.activePoolAddress()).to.equal(ActivePoolInstance.address);

    });
  });
});
