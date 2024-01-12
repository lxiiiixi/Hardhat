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
    const vaultAddress = ethers.Wallet.createRandom().address;

    async function deployFixture() {
        [add1, add2, ...otherUsers] = await ethers.getSigners();
        const instance = await deployContract("Passover", ["Passover Token", "PT", vaultAddress, add1.address]);

        const fixedHash = ethers.keccak256(ethers.toUtf8Bytes("Passover"));
        const leaves = [add1.address, add2.address, ...otherUsers.map(u => u.address)]
            .map((x, i) => keccak256(abiCoder.encode(["uint256", "address", "uint256", "bytes32", "uint256"], [i, x, 1000n, fixedHash, i])));
        // tokenId, msg.sender, amount, txHash, nonce
        const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
        const root = '0x' + tree.getRoot().toString('hex');
        await instance.setClaimLossesDirectRoot(root)
        await instance.setRefundRoot(root)
        await instance.setClaimLossesAfterRefundRoot(root)

        return { instance, leaves, fixedHash, tree, root };
    }

    function getProof(tree, address, tokenId, txHash) {
        const leaf = keccak256(abiCoder.encode(["uint256", "address", "uint256", "bytes32", "uint256"], [tokenId, address, 1000n, txHash, tokenId]));
        const proof = tree.getProof(leaf).map(x => x.data);
        return [tokenId, 1000n, txHash, tokenId, proof]
    }

    describe("Test metadata", function () {
        it("Should set the correct data", async function () {
            const { instance, root } = await loadFixture(deployFixture)

            expect(await instance.name()).to.equal("Passover Token");
            expect(await instance.symbol()).to.equal("PT");
            expect(await instance.totalSupply()).to.equal(0n);
            expect(await instance.balanceOf(add1.address)).to.equal(0n);

            expect(await instance.owner()).to.equal(add1.address);
            expect(await instance.paused()).to.equal(false);

            expect(await instance.vault()).to.equal(vaultAddress);
            expect(await instance.rootClaimLossesDirect()).to.equal(root);
            expect(await instance.rootRefund()).to.equal(root);
            expect(await instance.rootClaimLossesAfterRefund()).to.equal(root);
        });
    });

    describe("Test ownable and pausable functions", function () {
        it("Some functions can only be called by the owner", async function () {
            const { instance } = await loadFixture(deployFixture)

            const testBytes = ethers.keccak256(ethers.toUtf8Bytes("Test"))
            await expect(instance.connect(add2).setClaimLossesDirectRoot(testBytes))
                .to.revertedWithCustomError(instance, "OwnableUnauthorizedAccount")
            await expect(instance.connect(add2).setRefundRoot(testBytes))
                .to.revertedWithCustomError(instance, "OwnableUnauthorizedAccount")
            await expect(instance.connect(add2).setClaimLossesAfterRefundRoot(testBytes))
                .to.revertedWithCustomError(instance, "OwnableUnauthorizedAccount")
            await expect(instance.connect(add2).pause())
                .to.revertedWithCustomError(instance, "OwnableUnauthorizedAccount")
            await expect(instance.connect(add2).unpause())
                .to.revertedWithCustomError(instance, "OwnableUnauthorizedAccount")
        });

        it("Some functions can only be called when not paused", async function () {
            const { instance, fixedHash, tree } = await loadFixture(deployFixture)

            await instance.pause()
            await expect(instance.claimLossesDirect(...getProof(tree, add1.address, 0, fixedHash)))
                .to.revertedWithCustomError(instance, "EnforcedPause")
            await expect(instance.refund(...getProof(tree, add1.address, 0, fixedHash)))
                .to.revertedWithCustomError(instance, "EnforcedPause")
            await expect(instance.claimLossesAfterRefund(...getProof(tree, add1.address, 0, fixedHash)))
                .to.revertedWithCustomError(instance, "EnforcedPause")
            await instance.unpause()
            await instance.claimLossesDirect(...getProof(tree, add1.address, 0, fixedHash))
        });
    });

    describe("Test claim functions", function () {
        it("Test claimLossesDirect", async function () {
            const { instance, leaves, fixedHash, tree } = await loadFixture(deployFixture)

            await expect(instance.claimLossesDirect(...getProof(tree, add1.address, 1, fixedHash)))
                .to.revertedWith("Merkle verification failed")
            await expect(instance.connect(add2).claimLossesDirect(...getProof(tree, add1.address, 1, fixedHash)))
                .to.revertedWith("Merkle verification failed")
            expect(await instance.leafStatus(leaves[0])).to.equal(false);
            expect(await instance.balanceOf(add1.address)).to.equal(0n);
            expect(await instance.totalSupply()).to.equal(0n);
            await expect(instance.claimLossesDirect(...getProof(tree, add1.address, 0, fixedHash)))
                .to.emit(instance, "ClaimLosses")
                .withArgs(0n, add1.address, 1000n, fixedHash);
            expect(await instance.leafStatus(leaves[0])).to.equal(true);
            expect(await instance.balanceOf(add1.address)).to.equal(1000n);
            expect(await instance.totalSupply()).to.equal(1000n);

            // claim again will fail
            await expect(instance.claimLossesDirect(...getProof(tree, add1.address, 0, fixedHash)))
                .to.revertedWith("This leaf has been used")
        });

        it("Test refund", async function () {
            const { instance, leaves, fixedHash, tree } = await loadFixture(deployFixture)

            // refund: caller -> vault
            await expect(instance.refund(...getProof(tree, add1.address, 0, fixedHash, { value: 100n })))
                .to.revertedWith("The refund amount is incorrect")
            await expect(instance.refund(...getProof(tree, add1.address, 1, fixedHash, { value: 1000n })))
                .to.revertedWith("The refund amount is incorrect")

            expect(await ethers.provider.getBalance(vaultAddress)).to.equal(0);
            await expect(instance.refund(...getProof(tree, add1.address, 0, fixedHash), { value: 1000n }))
                .to.emit(instance, "Inscribe")
                .withArgs(0n, "data:text/plain;charset=utf-8," + ethers.toBeHex(add1.address) + "has already refunded the sales proceeds of INSC" + "0" + ", and he will receive the corresponding INSC+");
            expect(await ethers.provider.getBalance(vaultAddress)).to.equal(1000n);



            // await expect(instance.refund(...getProof(tree, add1.address, 1, fixedHash, { value: 1000n })))
            //     .to.revertedWith("The refund amount is incorrect")

        });
    });
});