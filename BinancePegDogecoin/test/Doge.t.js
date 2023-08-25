const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Binance Peg Dogecoin Test", function () {
  let owner, admin, addr1;
  const totalSupply = ethers.parseEther("100000")
  const AddressZero = "0x0000000000000000000000000000000000000000"

  async function deployToken() {
    [owner, admin, addr1] = await ethers.getSigners();
    const BEP20TokenImplementation = await ethers.getContractFactory("BEP20TokenImplementation");
    const data = BEP20TokenImplementation.interface
      .encodeFunctionData("initialize", ["Dogecoin", "DOGE", 8, totalSupply, true, owner.address])
    const tokenInstance = await BEP20TokenImplementation.deploy();

    const BEP20UpgradeableProxy = await ethers.getContractFactory("BEP20UpgradeableProxy");
    const proxy = await BEP20UpgradeableProxy.deploy(await tokenInstance.getAddress(), admin.address, data);
    const instance = BEP20TokenImplementation.attach(await proxy.getAddress());
    return { instance };
  }

  describe("Deployment test", function () {
    it("Should set the correct metadata", async function () {
      const { instance } = await deployToken();

      expect(await instance.totalSupply()).equal(totalSupply);
      expect(await instance.balanceOf(owner.address)).equal(totalSupply);
      expect(await instance.name()).equal("Dogecoin");
      expect(await instance.symbol()).equal("DOGE");
      expect(await instance.decimals()).equal(8);
    });
  });


  describe("Ownership test", function () {
    it("Should transfer ownership correctly", async function () {
      const { instance } = await deployToken();

      expect(await instance.getOwner()).to.equal(owner.address);
      await expect(instance.transferOwnership(addr1.address))
        .be.emit(instance, "OwnershipTransferred").withArgs(owner.address, addr1.address);
      await expect(instance.renounceOwnership()).to.revertedWith("Ownable: caller is not the owner");
      await instance.connect(addr1).renounceOwnership();
    });

    it("Should lose ownership if the owner renounces ownership", async function () {
      const { instance } = await deployToken();

      await expect(instance.renounceOwnership())
        .be.emit(instance, "OwnershipTransferred").withArgs(owner.address, AddressZero);
      await expect(instance.renounceOwnership()).to.revertedWith("Ownable: caller is not the owner");
      expect(await instance.getOwner()).to.equal(AddressZero);

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
      await expect(instance.connect(addr1).transfer(owner.address, 1)).to.revertedWith("BEP20: transfer amount exceeds balance");
      expect(await instance.balanceOf(owner.address)).to.equal(initialOwnerBalance);
    });

    it("Should be failed if sender transfer to zero address", async function () {
      const { instance } = await deployToken();
      const transferAmount = 5000;
      await expect(instance.transfer(AddressZero, transferAmount)).to.revertedWith("BEP20: transfer to the zero address");
      await instance.approve(owner.address, transferAmount);
      await expect(instance.transferFrom(owner.address, AddressZero, transferAmount)).to.revertedWith("BEP20: transfer to the zero address");
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

      await expect(instance.transferFrom(owner.address, addr1.address, transferAmount)).to.revertedWith("BEP20: transfer amount exceeds allowance")
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
      // decrease allowance
      await expect(instance.decreaseAllowance(addr1.address, approveAmount))
        .to.emit(instance, "Approval").withArgs(owner.address, addr1.address, approveAmount);
    });
  });


  describe("Mint test", function () {
    it("State _mintable should be true", async function () {
      const { instance } = await deployToken();

      expect(await instance.mintable()).to.equal(true);
      await instance.mint(1);
    });

    it("Onlyowner can mint", async function () {
      const { instance } = await deployToken();

      await instance.mint(1);
      expect(await instance.totalSupply()).equal(totalSupply + BigInt("1"));
      expect(await instance.balanceOf(owner.address)).equal(totalSupply + BigInt("1"));
    });
  });

  describe("Burn test", function () {
    it("Allows users to burn their own tokens", async function () {
      const { instance } = await deployToken();

      await instance.transfer(addr1.address, 1000);
      expect(await instance.balanceOf(addr1.address)).to.equal(1000);
      await instance.connect(addr1).burn(1000);
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
      expect(await instance.totalSupply()).equal(totalSupply - (BigInt("1000")));
    });
  });
});