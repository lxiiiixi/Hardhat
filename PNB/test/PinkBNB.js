const { expect, assert } = require("chai");
const { ethers } = require("hardhat");

describe("CustomERC20", function () {
  let owner, user1, user2;
  const init_supply_unit = ethers.constants.WeiPerEther;
  let TokenInstance;
  const initialSupply = 10000;
  const tradeBurnRatio = 1000;
  const tradeFeeRatio = 500;

  async function deployCustomERC20() {
    const CustomERC20 = await ethers.getContractFactory("CustomERC20");
    TokenInstance = await CustomERC20.deploy()
  }

  // before只执行一次
  before(async () => {
    [owner, user1, user2, _] = await ethers.getSigners();

  })
  // 在每个测试前，都要部署合约，并准备一些测试数据
  beforeEach(async () => {
    await deployCustomERC20();
    await TokenInstance.init(
      owner.address, // initOwner(owner.address)
      initialSupply,  // totalSupply
      "TEST TOKEN",
      "TT",
      18,
      tradeBurnRatio, // _tradeBurnRatio
      tradeFeeRatio, // _tradeFeeRatio
      owner.address // team
    )
    // 疑问：init时传入的_creator会不会是合约本身的地址address(this)
  });

  describe("Init state test", () => {
    it("Init will emit Tansfer event once", async () => {
      const events = await TokenInstance.queryFilter("Transfer");
      expect(events.length).to.equal(1);
    });

    it("Init state check", async () => {
      expect(await TokenInstance.totalSupply()).to.be.equal(initialSupply);
      expect(await TokenInstance.balanceOf(owner.address)).to.be.equal(initialSupply);
    });

    it("Init can only use once", async () => {
      await expect(TokenInstance.init(owner.address, initialSupply, "TEST TOKEN", "TT", 18, tradeBurnRatio, tradeFeeRatio, owner.address)).to.be.rejectedWith("DODO_INITIALIZED");
    });
  });

  describe("Approval test", () => {
    it("Approve should change state and emit event", async () => {
      // Contract.connect(user1)方法可以讲合约连接到user1账户并让user1以msg.sender的身份调用合约方法
      await expect(TokenInstance.connect(user1).approve(user2.address, 100)).to.be.emit(
        TokenInstance, "Approval"
      ).withArgs(user1.address, user2.address, 100);
      expect(await TokenInstance.allowance(user1.address, user2.address)).to.be.equal(100);
    });

    // approve() 如果被重复授权会不会产生问题
  });


  describe("Tansfer test", function () {
    it("Transfer to zero should be failed", async () => {
      await expect(TokenInstance.transfer(ethers.constants.AddressZero, 0)).to.be.rejectedWith("ERC20: transfer to the zero address");
    });

    // 不确定：如果传入零个Token是否会有问题
    it("Transfer zero token should be successfully", async () => {
      await TokenInstance.transfer(user1.address, 0);
    });

    it("Should transfer tokens between accounts and emit event", async function () {
      const transferAmount = 100
      const burnAmount = transferAmount * tradeFeeRatio / 10000
      const feeAmount = transferAmount * tradeBurnRatio / 10000
      // 这里应该是有方法计算而不是手动计算
      await TokenInstance.transfer(user1.address, transferAmount);
      expect(await TokenInstance.balanceOf(owner.address)).to.equal(ethers.BigNumber.from(initialSupply - transferAmount + burnAmount));
      expect(await TokenInstance.balanceOf(user1.address)).to.equal(ethers.BigNumber.from(transferAmount - burnAmount - feeAmount));
    });

    it("Should fail if sender doesn't have enough tokens", async function () {
      const initialOwnerBalance = await TokenInstance.balanceOf(owner.address);
      await expect(
        TokenInstance.transfer(user1.address, initialOwnerBalance + 1)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      expect(await TokenInstance.balanceOf(owner.address)).to.equal(
        initialOwnerBalance
      );
      expect(await TokenInstance.balanceOf(user1.address)).to.equal(0);
    });

    it("TransferFrom beyond approval should be failed", async () => {
      expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(0);
      await expect(TokenInstance.transferFrom(user1.address, user2.address, 1000)).to.be.revertedWith("ALLOWANCE_NOT_ENOUGH");
    });

    it("TransferFrom will return true", async () => {
      expect(await TokenInstance.connect(owner).approve(user1.address, 1000));
      expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(1000);
      // expect(await TokenInstance.connect(user1).transferFrom(owner.address, user1.address, 100)).to.be.equal(true);
    });

    it("TransferFrom should change approval", async () => {
      await TokenInstance.approve(user1.address, 1000);
      await TokenInstance.transfer(user1.address, 1200);
      // expect(await TokenInstance.balanceOf(user1.address)).to.equal(ethers.BigNumber.from(1200 * (1 - (tradeFeeRatio + tradeBurnRatio) / 10000)));
      // expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(ethers.BigNumber.from(1000));
      expect(await TokenInstance.balanceOf(user1.address)).to.equal(1200 * (1 - (tradeFeeRatio + tradeBurnRatio) / 10000));
      expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(1000);
      // await TokenInstance.transferFrom(user1.address, user2.address, 1000) // 疑问：这里明明有权限但是提示失败 许可不足
    });
  });

  describe("Team test", () => {
    it("Team should change and emit event", async () => {
      await expect(TokenInstance.connect(owner).changeTeamAccount(user1.address)).to.be.emit(
        TokenInstance, "ChangeTeam"
      ).withArgs(owner.address, user1.address);
    });

    it("Old team will not get fee", async () => {
      await TokenInstance.changeTeamAccount(user1.address)
      expect(await TokenInstance.team()).to.be.equal(user1.address);
      await TokenInstance.transfer(user1.address, 1000);
      // team 变为 user1 后交易的费用将会给 user1
      expect(await TokenInstance.balanceOf(user1.address)).to.equal(1000 * (1 - (tradeBurnRatio) / 10000));
    });
  });

  describe("Owner test", () => {
    it("Ownership can be transfer successfully and oldowner lose Ownership", async () => {
      await TokenInstance.transferOwnership(user1.address)
      await TokenInstance.connect(user1).claimOwnership()
      await expect(TokenInstance.transferOwnership(user1.address)).to.be.revertedWith("NOT_OWNER");
    });

    it("Ownership abandon", async () => {
      // abandonOwnership 执行后就没有 owner 了
      const AddressZero = ethers.constants.AddressZero
      await TokenInstance.abandonOwnership(AddressZero)
      expect(await TokenInstance._OWNER_()).to.be.equal(AddressZero);
    });
  });
});
