const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
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
  const mintString = 'data:text/plain;charset=utf-8,{"p":"ins-20","op":"mint","tick":"INSC+","amt":"1000"}'
  const transferString = 'data:text/plain;charset=utf-8,{"p":"ins-20","op":"transfer","tick":"INSC+","amt":"1000"}'
  let add1, add2, otherUsers;
  let maxSupply = 21000000n;
  let mintLimit = 1000n

  async function deployFixture() {
    [add1, add2, ...otherUsers] = await ethers.getSigners();
    const instance = await deployContract("INS20", [maxSupply, mintLimit, add1.address]);

    const leaves = [add1.address, add2.address, ...otherUsers.map(u => u.address)]
      .map((x, i) => keccak256(keccak256(abiCoder.encode(["address", "uint256"], [x, i]))));
    const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const root = tree.getRoot().toString('hex');
    await instance.setMerkleRoot('0x' + root)

    return { instance, tree, root };
  }

  function getProof(tree, address, tokenId) {
    const leaf = keccak256(keccak256(abiCoder.encode(["address", "uint256"], [address, tokenId])));
    const proof = tree.getProof(leaf).map(x => x.data);
    return [tokenId, proof]
  }

  function convertUint8ToHexStr(byteArray) {
    return Array.from(byteArray, function (byte) {
      return ('0' + (byte & 0xFF).toString(16)).slice(-2);
    }).join('');
  }

  function getInscribeBytes(amount, mintOrTransfer = "transfer") {
    const transferString = `data:text/plain;charset=utf-8,{"p":"ins-20","op":"transfer","tick":"INSC+","amt":"${amount}"}`;
    const mintString = `data:text/plain;charset=utf-8,{"p":"ins-20","op":"mint","tick":"INSC+","amt":"${amount}"}`
    return mintOrTransfer === "transfer" ? ethers.toUtf8Bytes(transferString) : ethers.toUtf8Bytes(mintString);
  }

  function typedUint256(amount) {
    return ethers.Typed.uint256(amount)
  }

  describe("Test view functions", function () {
    it("Should set the correct mata data", async function () {
      const { instance, root } = await loadFixture(deployFixture)

      expect(await instance.owner()).to.equal(add1.address);
      expect(await instance.name()).to.equal("INSC Plus");
      expect(await instance.symbol()).to.equal("INSC+");
      expect(await instance.decimals()).to.equal(0);
      expect(await instance.totalSupply()).to.equal(0n);
      expect(await instance.root()).to.equal('0x' + root);
      expect(await instance.maxSupply()).to.equal(maxSupply);
      expect(await instance.mintLimit()).to.equal(mintLimit);
      expect(await instance.transferInsData()).to.equal("0x" + convertUint8ToHexStr(ethers.toUtf8Bytes(transferString)));
    });

    it("Test tokenURI", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await expect(instance.tokenURI(0n)).to.revertedWithCustomError(instance, "ERC721NonexistentToken");
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.tokenURI(0n)
      await instance.openFT()
      await instance.tokenURI(0n)
    });
  });

  describe("Test inscribe", function () {
    it("Inscribe can be called afer the owner openInscribe", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await expect(instance.inscribe(...getProof(tree, add1.address, 0)))
        .to.revertedWith("Is not open");
      await expect(instance.connect(add2).openInscribe())
        .to.revertedWithCustomError(instance, "OwnableUnauthorizedAccount");
    });

    it("Inscribe will emit an event", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await expect(instance.inscribe(...getProof(tree, add1.address, 0)))
        .to.emit(instance, "Inscribe")
        .withArgs(0, ethers.toUtf8Bytes(mintString))
      await expect(instance.connect(add2).inscribe(...getProof(tree, add2.address, 1)))
        .to.emit(instance, "Inscribe")
        .withArgs(1, ethers.toUtf8Bytes(mintString))
    });

    it("Inscribe twice by the same address", async function () {
      const { instance } = await loadFixture(deployFixture)

      const leaves = [keccak256(keccak256(abiCoder.encode(["address", "uint256"], [add1.address, 0]))),
      keccak256(keccak256(abiCoder.encode(["address", "uint256"], [add1.address, 1])))]
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
      await instance.waterToWine(typedUint256(0n), typedUint256(1n), typedUint256(1000n))
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
      await expect(instance.connect(otherUsers[0]).inscribe(...getProof(tree, otherUsers[0].address, 2)))
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
      expect(await instance.slotFT(mockTransfer.target)).to.equal(0n);
    });
  });

  describe("Test transfer", function () {
    it("Transfer can be called afer the owner openFT", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))

      await expect(instance.transfer(add2.address, 1000n))
        .to.revertedWith('The ability of FT has not been granted')
    });

    it("Transfer when not reach the limit", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()

      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      expect(await instance.slotFT(add2)).to.equal(1n);

      await instance.openFT()
      const add3 = otherUsers[0]

      await expect(instance.connect(add2).transfer(add3.address, 1000n))
        .to.revertedWithCustomError(instance, "ERC721InvalidSender");
    });

    it("Transfer will emit event", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      await instance.openFT()
      const add3 = otherUsers[0]
      await instance.connect(add2).transfer(add3.address, 1000n)
    });

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

    it("Test transfer from or to address whose slot is 0", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      await instance.openFT()

      // will fail to transfer if the slot of the sender is 0
      await expect(instance.transfer(add2.address, 1000n))
        .to.revertedWith("The sender must own a slot")
      await instance.connect(add2).transfer(add1.address, 1000n)

      expect(await instance.slotFT(add2.address)).to.equal(1n);
      expect(await instance.slotFT(add1.address)).to.equal(2n);
      expect(await instance.balanceOf(add2.address)).to.equal(0n);
      await instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(1000n))
      expect(await instance.balanceOf(add1.address)).to.equal(2000n);
    });

    it("Slots can be minted until the limit is reached", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      const add3 = otherUsers[0]
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))

      expect(await instance.slotFT(add1.address)).to.equal(0n);
      expect(await instance.slotFT(add2.address)).to.equal(1n);

      await instance.openFT()
      await instance.connect(add2).transfer(add3.address, 1000n)
      expect(await instance.slotFT(add3.address)).to.equal(2n);
      expect(await instance.balanceOf(add3.address)).to.equal(1000n);
    });
  });

  describe("Test transferFrom and safeTransferFrom", function () {
    it("Tansfer nft need enough allowance", async function () {
      const { instance, tree } = await loadFixture(deployFixture)
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))

      const signature = "safeTransferFrom(address,address,uint256,bytes)";
      await expect(instance.connect(add2)[signature](add1.address, add2.address, 0, "0x"))
        .to.revertedWithCustomError(instance, "ERC721InsufficientApproval")
      await instance.approve(add2.address, 0)
      await expect(instance.connect(add2)[signature](add1.address, add2.address, 0, "0x"))
        .to.emit(instance, "Inscribe")
        .withArgs(0n, "0x" + convertUint8ToHexStr(ethers.toUtf8Bytes(transferString)))
      await expect(instance.connect(add2)[signature](add1.address, add2.address, 0, "0x"))
        .to.revertedWith("Slot can only be transferred at the end")
    });

    it("Transfer nft by function TransferFrom", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))

      await expect(instance.transferFrom(add1.address, add2.address, 0))
        .to.emit(instance, "Inscribe")
        .withArgs(0n, "0x" + convertUint8ToHexStr(ethers.toUtf8Bytes(transferString)))
      expect(await instance.slotFT(add2.address)).to.equal(1n);
      expect(await instance.balanceOf(add2.address)).to.equal(2n);
      await expect(instance.transferFrom(add1.address, add2.address, 0))
        .to.revertedWith("Slot can only be transferred at the end")
      const add3 = otherUsers[0]
      await expect(instance.connect(add2).transferFrom(add2.address, add3.address, 1))
        .to.revertedWith("Slot can only be transferred at the end")

      await instance.connect(add2).transferFrom(add2.address, add1.address, 0)
      expect(await instance.balanceOf(add2.address)).to.equal(1n);
      await instance.connect(add2).transferFrom(add2.address, add3.address, 1)
      expect(await instance.balanceOf(add2.address)).to.equal(0n);
      expect(await instance.slotFT(add2.address)).to.equal(0n);
      expect(await instance.slotFT(add3.address)).to.equal(1n);

      await expect(instance.transferFrom(add3.address, add1.address, 1))
        .to.revertedWithCustomError(instance, "ERC721InsufficientApproval")
    });

    it("Tansfer from or to zero address will fail", async function () {
      const { instance, tree } = await loadFixture(deployFixture)
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      expect(await instance.balanceOf(add1.address)).to.equal(1n);
      await expect(instance.transferFrom(ethers.ZeroAddress, add1.address, 0))
        .to.revertedWithCustomError(instance, "ERC721IncorrectOwner");
      await expect(instance.transferFrom(add1.address, ethers.ZeroAddress, 0))
        .to.revertedWithCustomError(instance, "ERC721InvalidReceiver");
      expect(await instance.balanceOf(add1.address)).to.equal(1n);
    });
  });

  describe("Test allowance", function () {
    it("Only owner of the nft can approve", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))

      await expect(instance.connect(add2).approve(add2.address, 0n))
        .to.revertedWithCustomError(instance, "ERC721InvalidApprover")

      expect(await instance.getApproved(1n)).to.equal(ethers.ZeroAddress);
      await instance.connect(add2).approve(add1.address, 1n)
      expect(await instance.allowance(add2.address, add1.address)).to.equal(0n);
      expect(await instance.getApproved(1n)).to.equal(add1.address);
    });

    it("Allowance are different after openFT", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))

      expect(await instance.getApproved(1n)).to.equal(ethers.ZeroAddress);
      await instance.connect(add2).approve(add1.address, 1n)
      expect(await instance.allowance(add2.address, add1.address)).to.equal(0n);
      expect(await instance.getApproved(1n)).to.equal(add1.address);

      await instance.openFT()
      await expect(instance.transferFrom(add2.address, add1.address, 1000n))
        .to.revertedWith("ERC20: insufficient allowance")
      await instance.connect(add2).approve(add1.address, 2000n)
      await instance.transferFrom(add2.address, add1.address, 1000n)
      expect(await instance.allowance(add2.address, add1.address)).to.equal(1000n);
    });
  });

  describe("Test onlyOwner functions", function () {
    it("Test setRoyaltyRecipient", async function () {
      const { instance } = await loadFixture(deployFixture)

      await expect(instance.connect(add2).setRoyaltyRecipient(add2.address))
        .to.be.revertedWithCustomError(instance, "OwnableUnauthorizedAccount");

      [receiver,] = await instance.royaltyInfo(1, 100);
      expect(receiver).to.equal(ethers.ZeroAddress);

      await instance.setRoyaltyRecipient(add2.address);
      [receiver, amount] = await instance.royaltyInfo(1, 1000);
      expect(receiver).to.equal(add2.address);
      expect(amount).to.equal(5);
    });

    it("Test openFT", async function () {
      maxSupply = 2000n
      const { instance, tree } = await deployFixture()
      await instance.openInscribe()

      await instance.inscribe(...getProof(tree, add1.address, 0))
      await expect(instance.openFT())
        .to.revertedWith("Must reach the upper limit before it can be opened");
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      expect(await instance.totalSupply()).to.equal(2000n);
      await instance.openFT()
    });
  });

  describe("Test waterToWine", function () {
    it("Only the owner of the slots can call waterToWine", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))

      await expect(instance.waterToWine(typedUint256(0n), typedUint256(1n), typedUint256(1000n)))
        .to.revertedWith("The ability of FT has not been granted");
      await instance.openFT()
      await expect(instance.waterToWine(typedUint256(0n), typedUint256(1n), typedUint256(1000n)))
        .to.revertedWith("Is not yours");
      await instance.connect(add2).transfer(add1.address, 1000n)
      await instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(1000n))
    });

    it("Should have enough balance", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      // prepare
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      await instance.openFT()
      await instance.connect(add2).transfer(add1.address, 1000n)

      expect(await instance.balanceOf(add1.address)).to.equal(1000n);
      await expect(instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(2000n)))
        .to.revertedWith("Insufficient balance");
      await instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(1000n))
      await expect(instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(1000n)))
        .to.revertedWith("Insufficient balance");
    });

    it("Should increase and decrease a correct balance and emit event", async function () {
      const { instance, tree } = await loadFixture(deployFixture)

      // prepare
      await instance.openInscribe()
      await instance.inscribe(...getProof(tree, add1.address, 0))
      await instance.connect(add2).inscribe(...getProof(tree, add2.address, 1))
      await instance.openFT()
      await instance.connect(add2).transfer(add1.address, 1000n)

      expect(await instance.balanceOf(add1.address)).to.equal(1000n);
      await expect(instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(2000n)))
        .to.revertedWith("Insufficient balance");

      await expect(instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(1000n)))
        .to.emit(instance, "Inscribe")
        .withArgs(0n, getInscribeBytes("0"))
        .and.to.emit(instance, "Inscribe")
        .withArgs(2n, getInscribeBytes("2000"))

      expect(await instance.balanceOf(add1.address)).to.equal(2000n);
      expect(await instance.balanceOf(add2.address)).to.equal(0n);

      await expect(instance.waterToWine(typedUint256(2n), typedUint256(0n), typedUint256(1000n)))
        .to.emit(instance, "Inscribe")
        .withArgs(2n, getInscribeBytes("1000"))
        .and.to.emit(instance, "Inscribe")
        .withArgs(0n, getInscribeBytes("1000"))

      expect(await instance.balanceOf(add1.address)).to.equal(1000n);

      await expect(instance.waterToWine(typedUint256(0n), typedUint256(2n), typedUint256(1000n)))
        .to.emit(instance, "Inscribe")
        .withArgs(0n, getInscribeBytes("0"))
        .and.to.emit(instance, "Inscribe")
        .withArgs(2n, getInscribeBytes("2000"))

      expect(await instance.balanceOf(add1.address)).to.equal(2000n);

      await expect(instance.waterToWine(typedUint256(2n), typedUint256(0n), typedUint256(0n)))
        .to.emit(instance, "Inscribe")
        .withArgs(2n, getInscribeBytes("2000"))
        .and.to.emit(instance, "Inscribe")
        .withArgs(0n, getInscribeBytes("0"))

      expect(await instance.balanceOf(add1.address)).to.equal(2000n);
    });

    async function buildNewTree() {
      const { instance } = await loadFixture(deployFixture)
      const arr = Array(500).fill(add2.address).concat(Array(500).fill(add1.address))
      const leaves = arr.map((x, i) => keccak256(keccak256(abiCoder.encode(["address", "uint256"], [x, i]))));
      const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
      const root = tree.getRoot().toString('hex');
      await instance.setMerkleRoot("0x" + root)
      await instance.openInscribe()
      for (let i = 0; i < 500; i++) {
        await expect(instance.connect(add2).inscribe(...getProof(tree, add2.address, i)))
          .to.emit(instance, "Inscribe")
          .withArgs(i, getInscribeBytes("1000", "mint"))
      }
      for (let i = 500; i < 505; i++) {
        await expect(instance.inscribe(...getProof(tree, add1.address, i)))
          .to.emit(instance, "Inscribe")
          .withArgs(i, getInscribeBytes("1000", "mint"))
      }
      return { instance, arr }
    }

    it("Test required condition", async function () {
      const { instance, arr } = await buildNewTree()

      const wtw = arr.map((_, index) => ({ insId: index, amount: 1000n }))
      await expect(instance.connect(add2).waterToWine([], 0)).to.revertedWith("The ability of FT has not been granted");
      await instance.openFT()
      await expect(instance.connect(add2).waterToWine([], 500)).to.revertedWith("Is not yours");
      await expect(instance.connect(add2).waterToWine(wtw, 0)).to.revertedWith("You drink too much!");
      await expect(instance.connect(add2).waterToWine(wtw.slice(1, 501), 0)).to.revertedWith("Is not yours");
    });

    it("Process waterToWine in batches will succeed and emit event", async function () {
      const { instance, arr } = await buildNewTree()

      const wtw = arr.map((_, index) => ({ insId: index, amount: 1000n }))
      await instance.openFT()
      const amount = 1000 * 500
      expect(await instance.balanceOf(add2.address)).to.equal(1000);
      expect(await instance.slotFT(add2.address)).to.equal(1);
      await expect(instance.connect(add2).waterToWine(wtw.slice(0, 500), 1))
        .to.emit(instance, "Inscribe")
        .withArgs(1, getInscribeBytes(String(amount)))
      expect(await instance.balanceOf(add2.address)).to.equal(amount);
      expect(await instance.slotFT(add2.address)).to.equal(1);

      await expect(instance.waterToWine(wtw.slice(500, 505), 500))
        .to.emit(instance, "Inscribe")
        .withArgs(500, getInscribeBytes("5000"))
      expect(await instance.balanceOf(add1.address)).to.equal(5000);
    });
  });
});
