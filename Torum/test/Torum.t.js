const { expect } = require("chai");
const { ethers } = require("hardhat");

// ERC20 Ownable 代币测试模版

describe("Torum Token Test", function () {
  let owner, addr1;
  const totalSupply = ethers.parseEther("800000000")
  const AddressZero = "0x0000000000000000000000000000000000000000"

  async function deployToken() {
    [owner, addr1] = await ethers.getSigners();
    const TorumToken = await ethers.getContractFactory("Torum");
    const instance = await TorumToken.deploy();
    return { instance };
  }

  describe("Deployment test", function () {
    it("Should set the correct metadata", async function () {
      const { instance } = await deployToken();

      expect(await instance.totalSupply()).equal(totalSupply);
      expect(await instance.balanceOf(owner.address)).equal(totalSupply);
      expect(await instance.name()).equal("Torum");
      expect(await instance.symbol()).equal("XTM");
      expect(await instance.decimals()).equal(18);
    });
  });

  describe("Transactions test", function () {
    it("Should transfer tokens between accounts", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;

      await expect(instance.transfer(addr1.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(owner.address, addr1.address, transferAmount);
      expect(await instance.balanceOf(addr1.address)).to.equal(transferAmount);
    });

    it("Should be failed if sender doesn’t have enough tokens", async function () {
      const { instance } = await deployToken();
      const initialOwnerBalance = await instance.balanceOf(owner.address);
      await expect(instance.connect(addr1).transfer(owner.address, 1)).to.revertedWith("ERC20: transfer amount exceeds balance");
      expect(await instance.balanceOf(owner.address)).to.equal(initialOwnerBalance);
    });

    it("Should be failed if sender transfer to zero address", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;
      await expect(instance.transfer(AddressZero, transferAmount)).to.revertedWith("ERC20: transfer to the zero address");
      await instance.approve(owner.address, transferAmount);
      await expect(instance.transferFrom(owner.address, AddressZero, transferAmount)).to.revertedWith("ERC20: transfer to the zero address");
    });

    it("Should be successful if sender transfer to himself", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;

      await expect(instance.transfer(owner.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(owner.address, owner.address, transferAmount);
      await instance.approve(owner.address, transferAmount);
      await expect(instance.transferFrom(owner.address, owner.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(owner.address, owner.address, transferAmount);
      expect(await instance.balanceOf(owner.address)).to.equal(totalSupply);
    });

    it("Should be successful if sender transfer zero amount", async function () {
      const { instance } = await deployToken();

      await expect(instance.transfer(addr1.address, 0))
        .be.emit(instance, "Transfer").withArgs(owner.address, addr1.address, 0);
      await expect(instance.transferFrom(owner.address, addr1.address, 0))
        .be.emit(instance, "Transfer").withArgs(owner.address, addr1.address, 0);
      expect(await instance.balanceOf(owner.address)).to.equal(totalSupply);
    });

    it("TransferFrom should need enough allowance", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;

      await expect(instance.transferFrom(owner.address, addr1.address, transferAmount)).to.revertedWith("ERC20: insufficient allowance")
      await instance.approve(owner.address, transferAmount);
      await expect(instance.transferFrom(owner.address, addr1.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(owner.address, addr1.address, transferAmount);
      expect(await instance.balanceOf(addr1.address)).to.equal(transferAmount);

      await instance.connect(addr1).approve(owner.address, transferAmount);
      await instance.transferFrom(addr1.address, owner.address, transferAmount)
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
    });
  });


  describe("Allowance test", function () {
    it("Should update the allowance when approving", async function () {
      const { instance } = await deployToken();
      const approveAmount = 1000

      await expect(instance.approve(addr1.address, approveAmount))
        .to.emit(instance, "Approval").withArgs(owner.address, addr1.address, approveAmount);
      const allowance = await instance.allowance(owner.address, addr1.address);
      expect(allowance).to.equal(approveAmount);
      // increse allowance again
      await expect(instance.increaseAllowance(addr1.address, approveAmount))
        .to.emit(instance, "Approval").withArgs(owner.address, addr1.address, approveAmount * 2);
      expect(await instance.allowance(owner.address, addr1.address)).to.equal(approveAmount * 2);
    });
  });

  describe("Ownership test", function () {
    it("Should transfer and renounce ownership correctly", async function () {
      const { instance } = await deployToken();

      expect(await instance.owner()).to.equal(owner.address);
      await instance.transferOwnership(addr1.address);
      expect(await instance.owner()).to.equal(addr1.address);

      await instance.connect(addr1).renounceOwnership();
      expect(await instance.owner()).to.equal(AddressZero);
    });
  });
});