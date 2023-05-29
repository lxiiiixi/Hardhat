const {
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("WrappedENaira Test", function () {
  let owner, user1;
  const initialAmount = ethers.utils.parseEther("1300000000000");
  const ZERO_ADDRESS = ethers.constants.AddressZero;

  async function deployOneWrappedENaira() {
    [owner, user1] = await ethers.getSigners();

    const WrappedENaira = await ethers.getContractFactory("WrappedENaira");
    const tokenInstance = await WrappedENaira.deploy();

    return { tokenInstance };
  }

  describe("Initial state uint test", function () {
    it("Initial state should equal with the params of constructor", async function () {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await tokenInstance.name()).to.equal("WrappedENaira");
      expect(await tokenInstance.symbol()).to.equal("WENGN");
      expect(await tokenInstance.decimals()).to.equal(18);
      expect(await tokenInstance.totalSupply()).to.equal(initialAmount);
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount)
      expect(await tokenInstance.owner()).to.equal(owner.address)
    });
  });

  describe("Mint test", async () => {
    it(("Mint will emit Transfer event"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await deployOneWrappedENaira()).to
        .emit(tokenInstance, "Transfer")
        .withArgs(ZERO_ADDRESS, owner.address, initialAmount);
    })

    it(("Mint can only called by owner"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      await expect(tokenInstance.connect(user1).mint(user1.address, initialAmount))
        .to.revertedWith("Ownable: caller is not the owner")
    })

    it(("Mint to zero address will fail"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      await expect(tokenInstance.mint(ZERO_ADDRESS, initialAmount))
        .to.revertedWith("ERC20: mint to the zero address")
    })

    it(("Warning: Owner can mint as much as he can"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await tokenInstance.totalSupply()).to.equal(initialAmount);
      await expect(tokenInstance.mint(user1.address, initialAmount))
        .emit(tokenInstance, "Transfer")
        .withArgs(ZERO_ADDRESS, user1.address, initialAmount);
      expect(await tokenInstance.totalSupply()).to.equal(initialAmount.mul(2));
    })
  })

  describe("Burn test", async () => {
    it(("Burn will emit Transfer event"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount)
      expect(await tokenInstance.totalSupply()).to.equal(initialAmount);
      await expect(tokenInstance.burn(initialAmount.div(2)))
        .emit(tokenInstance, "Transfer")
        .withArgs(owner.address, ZERO_ADDRESS, initialAmount.div(2));
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount.div(2));
      expect(await tokenInstance.totalSupply()).to.equal(initialAmount.div(2));
    });

    it(("Burn can only called by anyone who own enough token"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount)
      await expect(tokenInstance.connect(user1).burn(initialAmount.div(2)))
        .to.revertedWith("ERC20: burn amount exceeds balance")
      await tokenInstance.transfer(user1.address, initialAmount.div(2))
      await expect(tokenInstance.connect(user1).burn(initialAmount.div(2)))
        .emit(tokenInstance, "Transfer")
        .withArgs(user1.address, ZERO_ADDRESS, initialAmount.div(2));
      expect(await tokenInstance.balanceOf(user1.address)).to.equal(0)
      expect(await tokenInstance.totalSupply()).to.equal(initialAmount.div(2));
    });
  });

  describe("Transfer test", async () => {
    it(("Transfer will emit Transfer event"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount)
      await expect(tokenInstance.transfer(user1.address, initialAmount.div(2)))
        .emit(tokenInstance, "Transfer")
        .withArgs(owner.address, user1.address, initialAmount.div(2));
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount.div(2));
      expect(await tokenInstance.balanceOf(user1.address)).to.equal(initialAmount.div(2));
      expect(await tokenInstance.totalSupply()).to.equal(initialAmount);
    });

    it(("Transfer should have enough amount"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount)
      await expect(tokenInstance.connect(user1).transfer(owner.address, initialAmount.div(2)))
        .to.revertedWith("ERC20: transfer amount exceeds balance")
    });
  });

  describe("TransferFrom test", async () => {
    it(("TransferFrom should have enough allowance"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount)
      expect(await tokenInstance.allowance(user1.address, owner.address)).to.equal(0)
      await expect(tokenInstance.connect(user1).transferFrom(owner.address, user1.address, initialAmount.div(2)))
        .to.revertedWith("ERC20: insufficient allowance")
      await tokenInstance.approve(user1.address, initialAmount.div(2))
      expect(await tokenInstance.allowance(owner.address, user1.address)).to.equal(initialAmount.div(2))
      await expect(tokenInstance.connect(user1).transferFrom(owner.address, user1.address, initialAmount.div(2)))
        .emit(tokenInstance, "Transfer")
        .withArgs(owner.address, user1.address, initialAmount.div(2));
      expect(await tokenInstance.balanceOf(owner.address)).to.equal(initialAmount.div(2));
      expect(await tokenInstance.balanceOf(user1.address)).to.equal(initialAmount.div(2));
      expect(await tokenInstance.allowance(owner.address, user1.address)).to.equal(0)
    });

    it(("TransferFrom will emit event"), async () => {
      const { tokenInstance } = await loadFixture(deployOneWrappedENaira);
      await tokenInstance.approve(user1.address, initialAmount.div(2))
      await expect(tokenInstance.connect(user1).transferFrom(owner.address, user1.address, initialAmount.div(2)))
        .emit(tokenInstance, "Transfer")
        .withArgs(owner.address, user1.address, initialAmount.div(2));
      expect(await tokenInstance.allowance(owner.address, user1.address)).to.equal(0)
    });
  });
});

