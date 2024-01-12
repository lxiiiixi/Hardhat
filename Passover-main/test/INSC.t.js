const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const { ethers } = require("hardhat");

async function deployContract(name, args, options) {
  const contractFactory = await ethers.getContractFactory(name, options)
  return await contractFactory.deploy(...args)
}

describe("INSC Unit Test", function () {
  const abiCoder = new ethers.AbiCoder();
  let add1, add2, otherUsers;
  let maxSupply = 21000000n;
  let tickNumberMax = 63000n

  async function deployFixture() {
    [add1, add2, ...otherUsers] = await ethers.getSigners();
    const instance = await deployContract("INS20", ["INSC", maxSupply, 1000n, tickNumberMax, add1.address]);

    const leaves = [add1.address, add2.address, ...otherUsers.map(u => u.address)]
      .map((x, i) => keccak256(abiCoder.encode(["address", "uint256"], [x, i])));
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const root = tree.getRoot().toString('hex');
    await instance.setMerkleRoot('0x' + root)

    return { instance, tree, root };
  }

  function getProof(tree, address, tokenId) {
    const leaf = keccak256(abiCoder.encode(["address", "uint256"], [address, tokenId]));
    const proof = tree.getProof(leaf).map(x => x.data);
    return [tokenId, proof]
  }

  describe("Test metadata", function () {
    it("Should set the correct ERC20 data", async function () {
      const { instance } = await loadFixture(deployFixture)
      // console.log(await instance.name());
      // console.log(await instance.totalSupply());
      // console.log(await instance.root());
    });
  });

  describe("Test inscribe", function () {
    it("Inscribe twice by the same address", async function () {
      const { instance } = await loadFixture(deployFixture)

      const leaves = [keccak256(abiCoder.encode(["address", "uint256"], [add1.address, 0])), keccak256(abiCoder.encode(["address", "uint256"], [add1.address, 1]))]
      const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
      const root = tree.getRoot().toString('hex');
      await instance.setMerkleRoot('0x' + root)
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.inscribe(...getProof(tree, add1.address, 1))
      await expect(instance.inscribe(...getProof(tree, add1.address, 1))).to.reverted;
      expect(await instance.slotFT(add1.address)).to.equal(1n);
      await expect(instance.transferFrom(add1.address, add2.address, 1)).to
        .revertedWith("Slot can only be transferred at the end")

      expect(await instance.totalSupply()).to.equal(2000n);
      expect(await instance.balanceOf(add1.address)).to.equal(2n);
      await instance.openFT()
      expect(await instance.balanceOf(add1.address)).to.equal(1000n);
      await instance.waterToWine(0n, 1n, 1000n)
      expect(await instance.balanceOf(add1.address)).to.equal(2000n);
      await instance.transfer(add2.address, 1000n)
      expect(await instance.balanceOf(add1.address)).to.equal(1000n);
    });

    it("Should reach correct maxSupply", async function () {
      maxSupply = 2000n
      const { instance, tree } = await deployFixture()
      await instance.openInscribe()

      expect(await instance.totalSupply()).to.equal(0n);
      await instance.inscribe(...getProof(tree, add1.address, 0))
      expect(await instance.totalSupply()).to.equal(1000n);
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      expect(await instance.totalSupply()).to.equal(2000n);
      await instance.connect(otherUsers[0]).inscribe(...getProof(tree, otherUsers[0].address, 2))
      expect(await instance.totalSupply()).to.equal(3000n);
      await expect(instance.connect(otherUsers[1]).inscribe(...getProof(tree, otherUsers[1].address, 3)))
        .to.revertedWith("Exceeded mint limit");
    });
  });

  describe("Test recordSlot", function () {
    it("Reentrancy test", async function () {
      const { instance, tree } = await loadFixture(deployFixture)
      await instance.openInscribe()

      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      const add3 = otherUsers[0]

      expect(await instance.slotFT(add1.address)).to.equal(0n);
      expect(await instance.slotFT(add2.address)).to.equal(1n);

      const mockTransfer = await deployContract("MockTransfer", [instance.target])
      // add2 => MockTransfer => add3

      await instance.connect(add2).approve(mockTransfer.target, 1)

      // add2 => contract => add3
      expect(await instance.slotFT(add2.address)).to.equal(1n);
      expect(await instance.slotFT(add3.address)).to.equal(0n);
      expect(await instance.slotFT(mockTransfer.target)).to.equal(0n);
      await mockTransfer.connect(add2).triggerReentrancy(1, add3.address)
      expect(await instance.slotFT(add2.address)).to.equal(0n);
      expect(await instance.slotFT(add3.address)).to.equal(1n);
      expect(await instance.slotFT(mockTransfer.target)).to.equal(1n);
    });
  });

  describe("Test transfer", function () {
    it("Can't be transfered if tokenId is 0", async function () {
      const { instance, tree } = await loadFixture(deployFixture)
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.openFT()
      await expect(instance.transfer(add2.address, 0)).to.revertedWith("The sender must own a slot")
    });

    it("Transfer to oneself", async function () {
      const { instance, tree } = await loadFixture(deployFixture)
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      await instance.openFT()
      expect(await instance.slotFT(add2.address)).to.equal(1n);
      expect(await instance.balanceOf(add2.address)).to.equal(1000n);
      await instance.connect(add2).transfer(add2.address, 1000n)
      expect(await instance.slotFT(add2.address)).to.equal(1n);
      expect(await instance.balanceOf(add2.address)).to.equal(1000n);
    });

    it("Test reach tickNumberMax", async function () {
      tickNumberMax = 2n
      const { instance, tree } = await deployFixture()
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      await instance.openFT()
      // tickNumber = 2
      await expect(instance.connect(add2).transfer(add1.address, 0)).to.revertedWith("The number of slots has reached the limit") // slotFT[to] == 0
      await expect(instance.connect(add2).transfer(otherUsers[0].address, 0)).to.revertedWith("The number of slots has reached the limit")
    });
  });

  describe("Test transferFrom", function () {
    it("Tansfer From zero address will fail", async function () {
      const { instance, tree } = await loadFixture(deployFixture)
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.isFTOpen()
      expect(await instance.balanceOf(add1.address)).to.equal(1n);
      await expect(instance.transferFrom(ethers.ZeroAddress, add1.address, 0)).to.reverted;
      expect(await instance.balanceOf(add1.address)).to.equal(1n);
    });
  });
});


// 1. recordSlot 重入问题（transferFrom中）
// 2. tick 变量没用
// 3. tickNumber 从 0 开始，inscribe 到 maxSupply 会多一次（不能等于）
// 5. mintLimit 建议直接硬编码为1000
// 11. 一个地址 inscribe 两次的话记录的 tokenId 和 balance 的情况


// 6. 疑问：totalSupply() 的返回值
// 7. approve、transferFrom 函数编译不通过，ERC20 有返回值而ERC721 没有

// 8. _transferFT 中如果到了 tickNumberMax ，再向新地址转会失败。
// 9. transferFrom 中 from 如果是零地址后面会失败，前面的操作没有意义。
// 10. safeTransferFrom 函数不能 override

// 1. claimLossesDirect、claimLossesAfterRefund 没有相关的记录，一个人可以调用领取多次。