const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { network } = require("hardhat");
const { BigNumber } = require("ethers");

describe("Liquity", function () {
  let owner, bountyAddress, beneficiary, multisigAddress, user1, user2;
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  const _1_MILLION = BigNumber.from("1000000000000000000000000");
  const LockupBeneficiary = 100000

  // open trove: origin data
  const MaxFeePercentage = BigNumber.from("10000077136631066")
  const ETHAmount = ethers.utils.parseEther("18")
  const LUSDAmount = BigNumber.from("15000000000000000000000")
  // open trove: constant data
  const LUSD_GAS_COMPENSATION = BigNumber.from("200000000000000000000")
  const NICR_PRECISION = BigNumber.from("100000000000000000000")

  // _coll:抵押的ETH数量
  // _debt:借贷的LUSD数量
  // _price:ETH:USD价格
  const computeCR = (_coll, _debt, _price) => {
    if (_debt > 0) {
      let newCollRatio = _coll.mul(_price).div(_debt);
      return newCollRatio;
    } else { // if (_debt == 0)  Represents "infinite" CR.
      return 2 ** 256 - 1;
    }
  }


  // 部署流程参考：https://github.com/liquity/dev#launch-sequence-and-vesting-process

  async function deployLiquity() {
    [owner, bountyAddress, beneficiary, multisigAddress, user1, user2] = await ethers.getSigners();

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
    const LQTYInstance = await LQTYToken.deploy(CommunityIssuanceInstance.address, LQTYStakingInstance.address, LockupContractFactoryInstance.address, owner.address, UnipoolInstance.address, multisigAddress.address);

    // 部署 DefaultPool
    const DefaultPool = await ethers.getContractFactory("DefaultPool");
    const DefaultPoolInstance = await DefaultPool.deploy();

    // 部署 ActivePool
    const ActivePool = await ethers.getContractFactory("ActivePool");
    const ActivePoolInstance = await ActivePool.deploy();

    // 部署 GasPool
    const GasPool = await ethers.getContractFactory("GasPool");
    const GasPoolInstance = await GasPool.deploy();

    // 部署 CollSurplusPool
    const CollSurplusPool = await ethers.getContractFactory("CollSurplusPool");
    const CollSurplusPoolInstance = await CollSurplusPool.deploy();

    // 部署 SortedTroves
    const SortedTroves = await ethers.getContractFactory("SortedTroves");
    const SortedTrovesInstance = await SortedTroves.deploy();

    // 部署 PriceFeed
    const PriceFeed = await ethers.getContractFactory("PriceFeed");
    const PriceFeedInstance = await PriceFeed.deploy();
    const PriceAggregatorInstance = await ethers.getContractAt("EACAggregatorProxy", "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419");
    const TellorCallerInstance = await ethers.getContractAt("TellorCaller", "0xAd430500ECDa11E38C9bCB08a702274b94641112");
    await PriceFeedInstance.setAddresses(PriceAggregatorInstance.address, TellorCallerInstance.address)
    // const PriceFeedInstance = await ethers.getContractAt("TellorCaller", "0x4c517D4e2C851CA76d7eC94B805269Df0f2201De");

    // sets LQTYToken address in LockupContractFactory, CommunityIssuance, LQTYStaking and Unipool
    await LockupContractFactoryInstance.setLQTYTokenAddress(LQTYInstance.address)
    await CommunityIssuanceInstance.setAddresses(LQTYInstance.address, StabilityPoolInstance.address)
    await LQTYStakingInstance.setAddresses(LQTYInstance.address, LusdInstance.address, TroveManagerInstance.address, BorrowerOperationsInstance.address, ActivePoolInstance.address)

    await DefaultPoolInstance.setAddresses(TroveManagerInstance.address, ActivePoolInstance.address)
    await BorrowerOperationsInstance.setAddresses(TroveManagerInstance.address, ActivePoolInstance.address, DefaultPoolInstance.address, StabilityPoolInstance.address, GasPoolInstance.address, CollSurplusPoolInstance.address, PriceFeedInstance.address, SortedTrovesInstance.address, LusdInstance.address, LQTYStakingInstance.address)

    await TroveManagerInstance.setAddresses(BorrowerOperationsInstance.address, ActivePoolInstance.address, DefaultPoolInstance.address, StabilityPoolInstance.address, GasPoolInstance.address, CollSurplusPoolInstance.address, PriceFeedInstance.address, LusdInstance.address, SortedTrovesInstance.address, LQTYInstance.address, LQTYStakingInstance.address)
    await SortedTrovesInstance.setParams(10000000, TroveManagerInstance.address, BorrowerOperationsInstance.address)
    await ActivePoolInstance.setAddresses(BorrowerOperationsInstance.address, TroveManagerInstance.address, StabilityPoolInstance.address, DefaultPoolInstance.address)

    // 部署 uniToken
    const UnitokenInstance = await ethers.getContractAt("UniswapV2Pair", "0xF20EF17b889b437C151eB5bA15A47bFc62bfF469");
    await UnipoolInstance.setParams(LQTYInstance.address, UnitokenInstance.address, 2592000) // 30 天

    // deploy a LockupContract for each beneficiary
    const LQTYDeployStartTime = await LQTYInstance.getDeploymentStartTime();
    await LockupContractFactoryInstance.deployLockupContract(beneficiary.address, LQTYDeployStartTime + 31536000); // lock time: one year
    // transfers LQTY to each LockupContract
    await LQTYInstance.transfer(beneficiary.address, LockupBeneficiary)

    /**
     * During one year lockup period:
     * 1. Liquity admin periodically transfers newly vested tokens to team & partners’ LockupContracts, as per their vesting schedules
     * 2. Liquity admin may only transfer LQTY to LockupContracts
     * 3. Anyone may deploy new LockupContracts via the Factory, setting any unlockTime that is >= 1 year from system deployment
     * 
     * Upon end of one year lockup period:
     * 1. All beneficiaries may withdraw their entire entitlements
     * 2. Liquity admin address restriction on LQTY transfers is automatically lifted, and Liquity admin may now transfer LQTY to any address
     * 3. Anyone may deploy new LockupContracts via the Factory, setting any unlockTime in the future 
     * 
     * Post-lockup period:
     * Liquity admin periodically transfers newly vested tokens to team & partners, directly to their individual addresses, or to a fresh lockup contract if required.
     */


    return {
      Instances: {
        LusdInstance, TroveManagerInstance, BorrowerOperationsInstance,
        LQTYInstance, CommunityIssuanceInstance, LQTYStakingInstance, LockupContractFactoryInstance,
        StabilityPoolInstance, ActivePoolInstance, DefaultPoolInstance,
        GasPoolInstance, SortedTrovesInstance, CollSurplusPoolInstance, UnipoolInstance,
        PriceFeedInstance, TellorCallerInstance, PriceAggregatorInstance
      }
    };
  }

  // Hardhat 默认使用的本地测试链网络ID为 31337

  // describe("Test Deploy", function () {
  //   it("Test constructor arguments", async function () {
  //     const { Instances } = await loadFixture(deployLiquity);
  //     const { LusdInstance, TroveManagerInstance, BorrowerOperationsInstance,
  //       LQTYInstance, CommunityIssuanceInstance, LQTYStakingInstance, LockupContractFactoryInstance,
  //       StabilityPoolInstance, ActivePoolInstance, DefaultPoolInstance,
  //       GasPoolInstance, SortedTrovesInstance, CollSurplusPoolInstance, UnipoolInstance,
  //       PriceFeedInstance, TellorCallerInstance, PriceAggregatorInstance } = Instances;

  //     expect(await LusdInstance.troveManagerAddress()).to.equal(TroveManagerInstance.address);
  //     expect(await LusdInstance.stabilityPoolAddress()).to.equal(StabilityPoolInstance.address);
  //     expect(await LusdInstance.borrowerOperationsAddress()).to.equal(BorrowerOperationsInstance.address);


  //     expect(await LQTYInstance.communityIssuanceAddress()).to.equal(CommunityIssuanceInstance.address);
  //     expect(await LQTYInstance.lqtyStakingAddress()).to.equal(LQTYStakingInstance.address);
  //     expect(await LQTYInstance.lockupContractFactory()).to.equal(LockupContractFactoryInstance.address);

  //     const bountyEntitlement = _1_MILLION.mul(2)
  //     const depositorsAndFrontEndsEntitlement = _1_MILLION.mul(32)
  //     const lpRewardsEntitlement = _1_MILLION.mul(4).div(3)
  //     const multisigEntitlement = _1_MILLION.mul(100).sub(bountyEntitlement).sub(depositorsAndFrontEndsEntitlement).sub(lpRewardsEntitlement)
  //     expect(await LQTYInstance.balanceOf(owner.address)).to.equal(bountyEntitlement.sub(LockupBeneficiary));
  //     expect(await LQTYInstance.balanceOf(CommunityIssuanceInstance.address)).to.equal(depositorsAndFrontEndsEntitlement);
  //     expect(await LQTYInstance.balanceOf(multisigAddress.address)).to.equal(multisigEntitlement);
  //     expect(await LQTYInstance.getLpRewardsEntitlement()).to.equal(lpRewardsEntitlement);
  //     expect(await LQTYInstance.totalSupply()).to.equal(bountyEntitlement.add(depositorsAndFrontEndsEntitlement).add(lpRewardsEntitlement).add(multisigEntitlement));

  //     // test right LQTYToken address in LockupContractFactory, CommunityIssuance, LQTYStaking, and Unipool
  //     expect(await LockupContractFactoryInstance.lqtyTokenAddress()).to.equal(LQTYInstance.address);
  //     expect(await CommunityIssuanceInstance.lqtyToken()).to.equal(LQTYInstance.address);
  //     expect(await CommunityIssuanceInstance.stabilityPoolAddress()).to.equal(StabilityPoolInstance.address);
  //     expect(await LQTYStakingInstance.lqtyToken()).to.equal(LQTYInstance.address);
  //     expect(await LQTYStakingInstance.lusdToken()).to.equal(LusdInstance.address);
  //     expect(await LQTYStakingInstance.troveManagerAddress()).to.equal(TroveManagerInstance.address);
  //     expect(await LQTYStakingInstance.borrowerOperationsAddress()).to.equal(BorrowerOperationsInstance.address);
  //     expect(await LQTYStakingInstance.activePoolAddress()).to.equal(ActivePoolInstance.address);

  //     expect(await DefaultPoolInstance.troveManagerAddress()).to.equal(TroveManagerInstance.address);
  //     expect(await DefaultPoolInstance.activePoolAddress()).to.equal(ActivePoolInstance.address);
  //     expect(await BorrowerOperationsInstance.lqtyStakingAddress()).to.equal(LQTYStakingInstance.address);

  //     expect(await SortedTrovesInstance.getSize()).to.equal(0);
  //     expect(await SortedTrovesInstance.getFirst()).to.equal(ZERO_ADDRESS);
  //     expect(await SortedTrovesInstance.borrowerOperationsAddress()).to.equal(BorrowerOperationsInstance.address);
  //     expect(await SortedTrovesInstance.troveManager()).to.equal(TroveManagerInstance.address);

  //     expect(await PriceFeedInstance.priceAggregator()).to.equal(PriceAggregatorInstance.address);
  //     expect(await PriceFeedInstance.tellorCaller()).to.equal(TellorCallerInstance.address);

  //     expect(await ActivePoolInstance.borrowerOperationsAddress()).to.equal(BorrowerOperationsInstance.address);
  //     expect(await ActivePoolInstance.troveManagerAddress()).to.equal(TroveManagerInstance.address);
  //     expect(await ActivePoolInstance.stabilityPoolAddress()).to.equal(StabilityPoolInstance.address);
  //     expect(await ActivePoolInstance.defaultPoolAddress()).to.equal(DefaultPoolInstance.address);
  //   });
  // });

  // describe("Test Borrower Operations", function () {
  //   it("Test open trove", async function () {
  //     const { Instances } = await loadFixture(deployLiquity);
  //     const { LusdInstance, TroveManagerInstance, BorrowerOperationsInstance,
  //       LQTYInstance, CommunityIssuanceInstance, LQTYStakingInstance, LockupContractFactoryInstance,
  //       StabilityPoolInstance, ActivePoolInstance, DefaultPoolInstance,
  //       GasPoolInstance, SortedTrovesInstance, CollSurplusPoolInstance, UnipoolInstance, PriceFeedInstance } = Instances;

  //     // computed data
  //     const VarPrice = await PriceFeedInstance.fetchPrice();
  //     const VarLUSDFee = await TroveManagerInstance.getBorrowingFee(LUSDAmount);
  //     const VarnetDebt = LUSDAmount.add(VarLUSDFee)
  //     const VarCompositeDebt = VarnetDebt.add(LUSD_GAS_COMPENSATION)  // 所有的混合债务：用户想要借款的数量 LUSDAmount + 本次借款所需费用 VarLUSDFee + 存储到gas池中的数量 LUSD_GAS_COMPENSATION
  //     const VarStake = ETHAmount // troveManager 中 totalCollateralSnapshot == 0 时
  //     const VarNicr = ETHAmount.mul(NICR_PRECISION).div(VarCompositeDebt)

  //     const txPromise = BorrowerOperationsInstance.openTrove(MaxFeePercentage, LUSDAmount, ZERO_ADDRESS, ZERO_ADDRESS, { value: ETHAmount })

  //     const trove = await TroveManagerInstance.Troves(owner.address)
  //     expect(trove.debt.toString()).to.equal(VarCompositeDebt);
  //     expect(trove.coll.toString()).to.equal(ETHAmount);
  //     expect(trove.stake.toString()).to.equal(ETHAmount);
  //     expect(trove.status.toString()).to.equal("1");
  //     expect(trove.arrayIndex.toString()).to.equal("0");
  //     expect(await TroveManagerInstance.getTroveOwnersCount()).to.equal(1);
  //     expect(await TroveManagerInstance.getTroveFromTroveOwnersArray(0)).to.equal(owner.address);
  //     expect(await TroveManagerInstance.getTroveStake(owner.address)).to.equal(ETHAmount);
  //     expect(await TroveManagerInstance.getTroveDebt(owner.address)).to.equal(VarCompositeDebt);

  //     expect(await ActivePoolInstance.getETH()).to.equal(ETHAmount);
  //     expect(await ActivePoolInstance.getLUSDDebt()).to.equal(VarCompositeDebt);

  //     // LUSD 总共 mint 三次分别给三个地址
  //     expect(await LusdInstance.totalSupply()).to.equal(VarCompositeDebt);
  //     expect(await LusdInstance.balanceOf(GasPoolInstance.address)).to.equal(LUSD_GAS_COMPENSATION);
  //     expect(await LusdInstance.balanceOf(owner.address)).to.equal(LUSDAmount);
  //     expect(await LusdInstance.balanceOf(LQTYStakingInstance.address)).to.equal(VarLUSDFee);

  //     // 第一次 totalLQTYStaked 为 0 
  //     expect(await LQTYStakingInstance.F_LUSD()).to.equal(0);
  //     expect(await BorrowerOperationsInstance.getCompositeDebt(VarnetDebt)).to.equal(VarCompositeDebt);

  //     // test events
  //     await expect(txPromise).to.emit(BorrowerOperationsInstance, "TroveCreated").withArgs(owner.address, 0);
  //     await expect(txPromise).to.emit(TroveManagerInstance, "TroveSnapshotsUpdated").withArgs(0, 0);
  //     await expect(txPromise).to.emit(TroveManagerInstance, "TotalStakesUpdated").withArgs(VarStake);
  //     await expect(txPromise).to.emit(SortedTrovesInstance, "NodeAdded").withArgs(owner.address, VarNicr);
  //     await expect(txPromise).to.emit(BorrowerOperationsInstance, "TroveUpdated").withArgs(owner.address, VarCompositeDebt, ETHAmount, VarStake, BorrowerOperationsInstance.openTrove);
  //     await expect(txPromise).to.emit(BorrowerOperationsInstance, "LUSDBorrowingFeePaid").withArgs(owner.address, VarLUSDFee);
  //   });

  //   it("Test close trove", async function () {
  //     const { Instances } = await loadFixture(deployLiquity);
  //     const { LusdInstance, TroveManagerInstance, BorrowerOperationsInstance,
  //       LQTYInstance, CommunityIssuanceInstance, LQTYStakingInstance, LockupContractFactoryInstance,
  //       StabilityPoolInstance, ActivePoolInstance, DefaultPoolInstance,
  //       GasPoolInstance, SortedTrovesInstance, CollSurplusPoolInstance, UnipoolInstance, PriceFeedInstance } = Instances;

  //     // computed data
  //     const VarLUSDFee = await TroveManagerInstance.getBorrowingFee(LUSDAmount);
  //     const VarnetDebt = LUSDAmount.add(VarLUSDFee)
  //     const VarCompositeDebt = VarnetDebt.add(LUSD_GAS_COMPENSATION)  // 所有的混合债务：LUSDAmount + VarLUSDFee + LUSD_GAS_COMPENSATION

  //     // open two troves
  //     await BorrowerOperationsInstance.openTrove(MaxFeePercentage, LUSDAmount, ZERO_ADDRESS, ZERO_ADDRESS, { value: ETHAmount })
  //     await BorrowerOperationsInstance.connect(user1).openTrove(MaxFeePercentage, LUSDAmount, ZERO_ADDRESS, ZERO_ADDRESS, { value: ETHAmount })

  //     expect(await LusdInstance.balanceOf(owner.address)).to.equal(LUSDAmount);
  //     expect(await TroveManagerInstance.getTroveStake(owner.address)).to.equal(ETHAmount);
  //     expect(await TroveManagerInstance.getTroveDebt(owner.address)).to.equal(VarCompositeDebt);
  //     await expect(BorrowerOperationsInstance.connect(user2).closeTrove()).to.revertedWith("BorrowerOps: Trove does not exist or is closed")

  //     // close 之前需要有更多的 LUSD 支付借款费用
  //     const newLUSDAmount = BigNumber.from("150000000000000000000")
  //     await LusdInstance.connect(user1).transfer(owner.address, newLUSDAmount)
  //     // owner close trove
  //     expect(await BorrowerOperationsInstance.closeTrove())
  //       .to.be.emit(BorrowerOperationsInstance, "TroveUpdated")
  //       .withArgs(owner.address, 0, 0, 0, BorrowerOperationsInstance.openTrove);

  //     const trove = await TroveManagerInstance.Troves(owner.address)
  //     expect(trove.debt.toString()).to.equal("0");
  //     expect(trove.coll.toString()).to.equal("0");
  //     expect(trove.stake.toString()).to.equal("0");
  //     expect(trove.status.toString()).to.equal("2");
  //     expect(trove.arrayIndex.toString()).to.equal("0");

  //     // _repayLUSD 这一步
  //     expect(await ActivePoolInstance.getLUSDDebt()).to.equal(VarCompositeDebt);
  //     expect(await ActivePoolInstance.getETH()).to.equal(ETHAmount);
  //     expect(await LusdInstance.totalSupply()).to.equal(VarCompositeDebt);
  //     expect(await LusdInstance.balanceOf(owner.address)).to.equal(LUSDAmount.add(newLUSDAmount).sub(VarnetDebt));
  //     expect(await LusdInstance.balanceOf(user1.address)).to.equal(LUSDAmount.sub(newLUSDAmount));
  //     expect(await TroveManagerInstance.getTroveOwnersCount()).to.equal(1);
  //   });

  //   it("Test adjust trove", async function () {
  //     const { Instances } = await loadFixture(deployLiquity);
  //     const { LusdInstance, TroveManagerInstance, BorrowerOperationsInstance, ActivePoolInstance } = Instances;

  //     // computed data
  //     const VarLUSDFee = await TroveManagerInstance.getBorrowingFee(LUSDAmount);
  //     const VarnetDebt = LUSDAmount.add(VarLUSDFee)
  //     const VarCompositeDebt = VarnetDebt.add(LUSD_GAS_COMPENSATION)  // 所有的混合债务：LUSDAmount + VarLUSDFee + LUSD_GAS_COMPENSATION
  //     // adjust data
  //     const newETHAmount = ethers.utils.parseEther("1") // 打算存入的新的ETH
  //     const newLUSDAmount = BigNumber.from("1500000000000000000000") // 打算借的新的LUSD
  //     const newVarnetDebt = newLUSDAmount.add(await TroveManagerInstance.getBorrowingFee(newLUSDAmount))
  //     const newVarCompositeDebt = newVarnetDebt // adjustTrove 不会产生 LUSD_GAS_COMPENSATION 费用

  //     await BorrowerOperationsInstance.openTrove(MaxFeePercentage, LUSDAmount, ZERO_ADDRESS, ZERO_ADDRESS, { value: ETHAmount })
  //     expect(await LusdInstance.balanceOf(owner.address)).to.equal(LUSDAmount);
  //     expect(await TroveManagerInstance.getTroveStake(owner.address)).to.equal(ETHAmount);
  //     expect(await TroveManagerInstance.getTroveDebt(owner.address)).to.equal(VarCompositeDebt);

  //     await expect(BorrowerOperationsInstance.adjustTrove(MaxFeePercentage, newETHAmount, 0, true, ZERO_ADDRESS, ZERO_ADDRESS, { value: ETHAmount }))
  //       .to.revertedWith("BorrowerOps: Debt increase requires non-zero debtChange")
  //     // 继续抵押和借款的操作
  //     await BorrowerOperationsInstance.adjustTrove(MaxFeePercentage, 0, newLUSDAmount, true, ZERO_ADDRESS, ZERO_ADDRESS, { value: newETHAmount })
  //     expect(await LusdInstance.balanceOf(owner.address)).to.equal(LUSDAmount.add(newLUSDAmount));
  //     expect(await TroveManagerInstance.getTroveStake(owner.address)).to.equal(ETHAmount.add(newETHAmount));
  //     expect(await TroveManagerInstance.getTroveDebt(owner.address)).to.equal(VarCompositeDebt.add(newVarCompositeDebt));

  //     expect(await ActivePoolInstance.getLUSDDebt()).to.equal(VarCompositeDebt.add(newVarCompositeDebt));
  //     expect(await ActivePoolInstance.getETH()).to.equal(ETHAmount.add(newETHAmount));
  //     expect(await LusdInstance.totalSupply()).to.equal(VarCompositeDebt.add(newVarCompositeDebt));
  //   });

  //   it("Test withdraw coll from a trove", async function () {
  //     const { Instances } = await loadFixture(deployLiquity);
  //     const { LusdInstance, TroveManagerInstance, BorrowerOperationsInstance, ActivePoolInstance } = Instances;

  //     // computed data
  //     const VarLUSDFee = await TroveManagerInstance.getBorrowingFee(LUSDAmount);
  //     const VarnetDebt = LUSDAmount.add(VarLUSDFee)
  //     const VarCompositeDebt = VarnetDebt.add(LUSD_GAS_COMPENSATION)  // 所有的混合债务：LUSDAmount + VarLUSDFee + LUSD_GAS_COMPENSATION
  //     // withdraw data
  //     const withdrawETHAmount = ethers.utils.parseEther("3") // 打算取出的ETH

  //     // open a trove
  //     await BorrowerOperationsInstance.openTrove(MaxFeePercentage, LUSDAmount, ZERO_ADDRESS, ZERO_ADDRESS, { value: ETHAmount })
  //     expect(await LusdInstance.balanceOf(owner.address)).to.equal(LUSDAmount);
  //     expect(await TroveManagerInstance.getTroveStake(owner.address)).to.equal(ETHAmount);
  //     expect(await TroveManagerInstance.getTroveDebt(owner.address)).to.equal(VarCompositeDebt);

  //     // withdraw coll from a trove
  //     await expect(BorrowerOperationsInstance.withdrawColl(ETHAmount, ZERO_ADDRESS, ZERO_ADDRESS)).to.revertedWith("BorrowerOps: An operation that would result in ICR < MCR is not permitted")
  //     await BorrowerOperationsInstance.withdrawColl(withdrawETHAmount, ZERO_ADDRESS, ZERO_ADDRESS)
  //     expect(await LusdInstance.balanceOf(owner.address)).to.equal(LUSDAmount);
  //     expect(await TroveManagerInstance.getTroveDebt(owner.address)).to.equal(VarCompositeDebt);
  //     expect(await TroveManagerInstance.getTroveStake(owner.address)).to.equal(ETHAmount.sub(withdrawETHAmount));
  //     expect(await ActivePoolInstance.getLUSDDebt()).to.equal(VarCompositeDebt);
  //     expect(await ActivePoolInstance.getETH()).to.equal(ETHAmount.sub(withdrawETHAmount));
  //   });
  // });

  describe("Test Trove Manager", function () {
    it("Test constructor arguments", async function () {
      const { Instances } = await loadFixture(deployLiquity);
      const { LusdInstance, TroveManagerInstance, BorrowerOperationsInstance, ActivePoolInstance, PriceFeedInstance } = Instances;

      // computed data
      const VarLUSDFee = await TroveManagerInstance.getBorrowingFee(LUSDAmount);
      const VarnetDebt = LUSDAmount.add(VarLUSDFee)
      const VarCompositeDebt = VarnetDebt.add(LUSD_GAS_COMPENSATION)
      // open a trove
      await BorrowerOperationsInstance.openTrove(MaxFeePercentage, LUSDAmount, ZERO_ADDRESS, ZERO_ADDRESS, { value: ETHAmount })

      const VarPrice = await PriceFeedInstance.fetchPrice();
      VarPrice.wait()
      const NominalICR = await TroveManagerInstance.getNominalICR(owner.address)
      // const CurrentICR = await TroveManagerInstance.getCurrentICR(owner.address, VarPrice)

      console.log("VarPrice: ", VarPrice, "NominalICR: ", NominalICR.toString(),);
      // console.log("CurrentICR: ", CurrentICR.toString());
    });
  });
});