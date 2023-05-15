const {
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

describe("MdxToken", function () {
  let owner, miner1, miner2, addr1, addr2;
  const maxSupply = ethers.utils.parseEther("1060000000");
  const ZERO_ADDRESS = ethers.constants.AddressZero;

  async function deployMdxToken() {
    [owner, miner1, miner2, addr1, addr2] = await ethers.getSigners();
    const MdxToken = await ethers.getContractFactory("MdxToken");
    const MdxInstance = await MdxToken.deploy();

    return { MdxInstance }
  }

  describe("Test meta data", function () {
    it("Should deploy contract with correct name and symbol", async function () {
      const { MdxInstance } = await loadFixture(deployMdxToken);
      expect(await MdxInstance.name()).to.equal("MDX Token");
      expect(await MdxInstance.symbol()).to.equal("MDX");
      expect(await MdxInstance.decimals()).to.be.equal(18);
      expect(await MdxInstance.maxSupply()).to.equal(maxSupply);
      expect(await MdxInstance.totalSupply()).to.equal(0);
    });
  });

  describe("Test minter functions", function () {
    it("Should add and remove miners correctly", async function () {
      const { MdxInstance } = await loadFixture(deployMdxToken);

      await MdxInstance.addMiner(miner1.address);
      expect(await MdxInstance.isMiner(miner1.address)).to.equal(true);
      expect(await MdxInstance.getMinerLength()).to.equal(1);
      expect(await MdxInstance.getMiner(0)).to.equal(miner1.address);

      await MdxInstance.delMiner(miner1.address);
      expect(await MdxInstance.isMiner(miner1.address)).to.equal(false);
      expect(await MdxInstance.getMinerLength()).to.equal(0);
    });

    it("Should only allow owner to get, add and remove miners", async function () {
      const { MdxInstance } = await loadFixture(deployMdxToken);
      await expect(MdxInstance.connect(addr1).addMiner(miner1.address)).to.be.revertedWith("Ownable: caller is not the owner");
      await expect(MdxInstance.connect(addr1).delMiner(miner1.address)).to.be.revertedWith("Ownable: caller is not the owner");
      await expect(MdxInstance.connect(addr1).getMiner(0)).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Test token transfer", () => {
    it("Transfer to zero address should be failed", async () => {
      const { MdxInstance } = await loadFixture(deployMdxToken);
      await expect(MdxInstance.transfer(ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: transfer to the zero address");
    });

    it("Transfer token beyond balance should be failed", async () => {
      const { MdxInstance } = await loadFixture(deployMdxToken);
      await expect(MdxInstance.connect(addr1).transfer(addr2.address, 10)).to.be.revertedWith("ERC20: transfer amount exceeds balance");
    });
  });

  describe("Test mint functions", function () {
    it("Should mint tokens only if the sender is a miner", async function () {
      const { MdxInstance } = await loadFixture(deployMdxToken);
      await MdxInstance.addMiner(miner1.address);
      const mintAmount = ethers.utils.parseEther("100");

      await expect(MdxInstance.mint(addr1.address, mintAmount)).to.be.revertedWith("caller is not the miner");
      await MdxInstance.connect(miner1).mint(addr1.address, mintAmount);
      expect(await MdxInstance.balanceOf(addr1.address)).to.equal(mintAmount);
    });

    it("Should not mint tokens if max supply would be exceeded", async function () {
      const { MdxInstance } = await loadFixture(deployMdxToken);

      await MdxInstance.addMiner(miner1.address);
      await MdxInstance.connect(miner1).mint(addr1.address, maxSupply)
      expect(await MdxInstance.totalSupply()).to.equal(maxSupply);
      await MdxInstance.connect(miner1).mint(addr1.address, ethers.utils.parseEther("1"))
      expect(await MdxInstance.totalSupply()).to.equal(maxSupply);
    });
  });

});
