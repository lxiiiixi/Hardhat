const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ChiliZ Token Test", function () {
  let owner, addr1;
  const totalSupply = ethers.parseEther("8888888888")
  const AddressZero = "0x0000000000000000000000000000000000000000"

  async function deployToken() {
    [owner, addr1] = await ethers.getSigners();
    const TorumToken = await ethers.getContractFactory("chiliZ");
    const instance = await TorumToken.deploy();
    return { instance };
  }

  describe("Deployment test", function () {
    it("Should set the correct metadata", async function () {
      const { instance } = await deployToken();

      expect(await instance.totalSupply()).equal(totalSupply);
      expect(await instance.balanceOf(owner.address)).equal(totalSupply);
      expect(await instance.name()).equal("chiliZ");
      expect(await instance.symbol()).equal("CHZ");
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
      await expect(instance.connect(addr1).transfer(owner.address, 1)).to.reverted;
      expect(await instance.balanceOf(owner.address)).to.equal(initialOwnerBalance);
    });

    it("Should be failed if sender transfer to zero address", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;
      await expect(instance.transfer(AddressZero, transferAmount)).to.reverted;
      await instance.approve(owner.address, transferAmount);
      await expect(instance.transferFrom(owner.address, AddressZero, transferAmount)).to.reverted;
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

      await expect(instance.transferFrom(owner.address, addr1.address, transferAmount)).to.reverted;
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
    it("Should update the allowance after approving", async function () {
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

    it("Should overflow when increasing allowance with a very large number", async function () {
      const { instance } = await deployToken();
      const largeNumber = ethers.MaxUint256;

      await expect(instance.increaseAllowance(addr1.address, largeNumber))
        .to.emit(instance, "Approval").withArgs(owner.address, addr1.address, largeNumber);

      expect(await instance.allowance(owner.address, addr1.address)).to.equal(largeNumber);
      await expect(instance.increaseAllowance(addr1.address, 1)).to.reverted;
    });

    it("Should underflow when decreasing allowance below zero", async function () {
      const { instance } = await deployToken();
      const approveAmount = ethers.parseEther("1000");
      await instance.approve(addr1.address, approveAmount);

      await expect(instance.decreaseAllowance(addr1.address, approveAmount + 1n))
        .to.reverted;
      expect(await instance.allowance(owner.address, addr1.address)).to.equal(approveAmount);
    });
  });

  describe("Pausable functionality tests", function () {
    it("Should not allow non-pausers to pause/unpause the contract", async function () {
      const { instance } = await deployToken();

      await expect(instance.connect(addr1).pause()).to.be.reverted;
      await expect(instance.connect(addr1).unpause()).to.be.reverted;
    });

    it("Should pause the contract by pauser and emit Paused event", async function () {
      const { instance } = await deployToken();

      await expect(instance.pause()).to.emit(instance, "Paused")
        .withArgs(owner.address);

      expect(await instance.paused()).to.equal(true);
    });

    it("Should not allow pausing if already paused", async function () {
      const { instance } = await deployToken();

      await instance.pause();
      await expect(instance.pause()).to.be.reverted;
    });

    it("Should unpause the contract by pauser and emit Unpaused event", async function () {
      const { instance } = await deployToken();

      await instance.pause();
      await expect(instance.unpause()).to.emit(instance, "Unpaused")
        .withArgs(owner.address);

      expect(await instance.paused()).to.equal(false);
    });

    it("Should not allow unpausing if not paused", async function () {
      const { instance } = await deployToken();

      await expect(instance.unpause()).to.be.reverted;
    });

    // Assuming "transfer" is modified with "whenNotPaused" modifier in the ERC20Pausable contract
    it("Should not allow token functions to be called when paused", async function () {
      const { instance } = await deployToken();
      const transferAmount = 1000;

      await instance.pause();
      await expect(instance.transfer(addr1.address, transferAmount)).to.be.reverted;
      await expect(instance.approve(addr1.address, transferAmount)).to.be.reverted;
    });
  });

  describe("PauserRole functionality tests", function () {
    it("Should set the contract deployer as the initial pauser", async function () {
      const { instance } = await deployToken();
      expect(await instance.isPauser(owner.address)).to.equal(true);
    });

    it("Should allow pauser to add another pauser and emit PauserAdded event", async function () {
      const { instance } = await deployToken();

      await expect(instance.addPauser(addr1.address)).to.emit(instance, "PauserAdded").withArgs(addr1.address);
      expect(await instance.isPauser(addr1.address)).to.equal(true);
    });

    it("Should not allow non-pausers to add a pauser", async function () {
      const { instance } = await deployToken();
      await expect(instance.connect(addr1).addPauser(addr1.address)).to.be.reverted;
    });

    it("Should allow a pauser to renounce its role and emit PauserRemoved event", async function () {
      const { instance } = await deployToken();
      await instance.addPauser(addr1.address);
      await expect(instance.connect(addr1).renouncePauser()).to.emit(instance, "PauserRemoved").withArgs(addr1.address);
      expect(await instance.isPauser(addr1.address)).to.equal(false);
    });

    it("Should not allow non-pausers to renounce pauser role", async function () {
      const { instance } = await deployToken();
      await expect(instance.connect(addr1).renouncePauser()).to.be.reverted;
    });
  });

});