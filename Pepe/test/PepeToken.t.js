const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PepeToken Test", function () {
  let owner, addr1, addr2, uniswapV2PairMock;
  const totalSupply = ethers.parseEther("420690000000000")
  const AddressZero = "0x0000000000000000000000000000000000000000"


  async function deployToken() {
    [owner, addr1, addr2, uniswapV2PairMock] = await ethers.getSigners();
    const PepeToken = await ethers.getContractFactory("PepeToken");
    const instance = await PepeToken.deploy(totalSupply);
    return { instance };
  }

  describe("Deployment test", function () {
    it("Should set the correct metadata", async function () {
      const { instance } = await deployToken();

      // ERC20 metadata
      expect(await instance.totalSupply()).equal(totalSupply);
      expect(await instance.balanceOf(owner.address)).equal(totalSupply);
      expect(await instance.name()).equal("Pepe");
      expect(await instance.symbol()).equal("PEPE");
      expect(await instance.decimals()).equal(18);

      // PepeToken metadata
      expect(await instance.limited()).equal(false);
      expect(await instance.maxHoldingAmount()).equal(0);
      expect(await instance.minHoldingAmount()).equal(0);
      expect(await instance.uniswapV2Pair()).equal(AddressZero);
    });
  });

  describe("Function beforeTokenTransfer test", function () {
    it("Only owner can transfer until uniswapV2Pair is set", async function () {
      const { instance } = await deployToken();

      await expect(instance.connect(addr1).transfer(addr2.address, 1)).to.be.revertedWith("trading is not started");
      await instance.setRule(false, uniswapV2PairMock, 0, 0)
      await instance.transfer(addr1.address, 1);
      await instance.connect(addr1).transfer(addr2.address, 1);
    });

    it("Should respect maxHoldingAmount and minHoldingAmount", async () => {
      const { instance } = await deployToken();

      await instance.setRule(true, uniswapV2PairMock.address, 5000, 1000);

      await instance.transfer(uniswapV2PairMock.address, 6000)
      await expect(instance.connect(uniswapV2PairMock).transfer(addr1.address, 6000)).to.revertedWith("Forbid");
      await expect(instance.connect(uniswapV2PairMock).transfer(addr1.address, 500)).to.revertedWith("Forbid");
      await instance.connect(uniswapV2PairMock).transfer(addr1.address, 1200)
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

      await expect(instance.transferFrom(owner.address, addr1.address, transferAmount)).to.revertedWith("ERC20: transfer amount exceeds allowance")
      await instance.approve(owner.address, transferAmount);
      await expect(instance.transferFrom(owner.address, addr1.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(owner.address, addr1.address, transferAmount);
      expect(await instance.balanceOf(addr1.address)).to.equal(transferAmount);

      await instance.connect(addr1).approve(owner.address, transferAmount);
      await instance.transferFrom(addr1.address, owner.address, transferAmount)
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
    });
  });


  describe("Burn test", function () {
    it("Allows users to burn their own tokens", async function () {
      const { instance } = await deployToken();

      await instance.setRule(true, uniswapV2PairMock.address, 5000, 1000);
      await instance.transfer(addr1.address, 1000);
      expect(await instance.balanceOf(addr1.address)).to.equal(1000);
      await instance.connect(addr1).burn(1000);
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
      expect(await instance.totalSupply()).equal(totalSupply - (BigInt("1000")));
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

      // decrease allowance
      await expect(instance.decreaseAllowance(addr1.address, approveAmount))
        .to.emit(instance, "Approval").withArgs(owner.address, addr1.address, approveAmount);
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

    it("Should lose ownership if the owner renounces ownership", async function () {
      const { instance } = await deployToken();

      expect(await instance.owner()).to.equal(owner.address);
      await instance.renounceOwnership();
      expect(await instance.owner()).to.equal(AddressZero);

      // lose ownership
      await expect(instance.blacklist(addr1.address, true)).to.revertedWith("Ownable: caller is not the owner");
      await expect(instance.setRule(true, AddressZero, AddressZero, AddressZero)).to.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("BlackLists test", function () {
    it("Users in blacklist should not be able to transfer", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;

      await instance.blacklist(addr1.address, true);
      await expect(instance.transfer(addr1.address, transferAmount)).to.revertedWith("Blacklisted");
      await expect(instance.connect(addr1).transfer(owner.address, transferAmount)).to.revertedWith("Blacklisted");
      expect(await instance.balanceOf(addr1.address)).to.equal(0);

      await instance.blacklist(addr1.address, false);
      await instance.transfer(addr1.address, transferAmount)
      expect(await instance.balanceOf(addr1.address)).to.equal(transferAmount);
    });

    it("The owner can manage the blacklist himself", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;

      await instance.blacklist(owner.address, true);
      await expect(instance.transfer(addr1.address, transferAmount)).to.revertedWith("Blacklisted");
      await instance.blacklist(owner.address, false);
      await instance.transfer(addr1.address, transferAmount)
    });
  });
});