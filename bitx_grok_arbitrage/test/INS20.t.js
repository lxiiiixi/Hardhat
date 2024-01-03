const {
    loadFixture,
    impersonateAccount
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

async function deployContract(name, args, options) {
    const contractFactory = await ethers.getContractFactory(name, options)
    return await contractFactory.deploy(...args)
}

async function contractAt(name, address) {
    const contractFactory = await ethers.getContractFactory(name)
    return await contractFactory.attach(address)
}

describe("INS20", function () {
    let add1, add2;
    const contractAddress = "0x8c578A6e31Fc94B1Facd58202be53a8385BACbf7"

    async function fork() {
        [add1, add2] = await ethers.getSigners();
        const instance = await contractAt("INS20", contractAddress)
        return { instance }
    }

    async function deploy() {
        [add1, add2] = await ethers.getSigners();
        const instance = await deployContract("INS20", ["INSC", 10000, 10000, add2.address])
        const dataString = `{"p":"ins-20","op":"mint","tick":"INSC","amt":"1000"}`;
        const dataBytes = ethers.toUtf8Bytes(dataString);
        return { instance, dataString, dataBytes }
    }

    describe("Test basic function", function () {
        it("Test metadata", async function () {
            const { instance, dataBytes } = await loadFixture(deploy)
            expect(await instance.symbol()).to.equal("INSC");
            expect(await instance.totalSupply()).to.equal(0);
            expect(await instance.decimals()).to.equal(1);
            expect(await instance.maxSupply()).to.equal(10000);
            expect(await instance.mintLimit()).to.equal(10000);
            expect(await instance.nft2ft()).to.equal(false);

            const hash = ethers.keccak256(dataBytes);
            expect(await instance.hash()).to.equal(hash);
        });
    });

    describe("Test inscribe", function () {
        it("Test first inscribe", async function () {
            const { instance, dataString, dataBytes } = await loadFixture(deploy)
            await expect(instance.inscribe("0x")).to.revertedWith("Inscribe data is wrong.");

            expect(await instance.lastBlock()).to.equal(0);
            expect(await instance.mintedPer()).to.equal(0);
            expect(await instance.totalSupply()).to.equal(0);
            expect(await instance.balanceOf(add1.address)).to.equal(0);

            await expect(instance.inscribe(dataBytes))
                .to.emit(instance, "Inscribe")
                .withArgs(ethers.ZeroAddress, add1.address, "data:text/plain;charset=utf-8" + dataString);

            expect(await instance.lastBlock()).to.gt(0);
            expect(await instance.mintedPer()).to.equal(0);
            expect(await instance.totalSupply()).to.equal(1000);
            expect(await instance.balanceOf(add1.address)).to.equal(1);

            await instance.connect(add2).toFT()
            expect(await instance.balanceOf(add1.address)).to.equal(1000);

            await expect(instance.connect(add2).toFT()).to.revertedWith("Has done");
        });

        it("Test inscribe if exceeded max supply", async function () {
            const { instance, dataBytes } = await loadFixture(deploy)
            await expect(instance.inscribe("0x")).to.revertedWith("Inscribe data is wrong.");

            // max supply: 10000

            // inscribe 9 times
            for (let times = 0; times < 9; times++) {
                await instance.inscribe(dataBytes)
            }
            await expect(instance.inscribe(dataBytes)).to.revertedWith("Exceeded max supply");
        });
    });

    describe("Approve and transfer Test", function () {
        it("Test approve erc721 and transfer", async function () {
            const { instance, dataBytes } = await loadFixture(deploy)
            // allowance

            await instance.inscribe(dataBytes)
            await expect(instance.approve(add2.address, 1)).to.revertedWith("ERC721: invalid token ID");

            // expect(await instance.allowance(add1.address, add2.address)).to.equal(0);
            expect(await instance.balanceOf(add1.address)).to.equal(1);
            await expect(instance.connect(add2).transferFrom(add1.address, add2.address, 0)).to.revertedWith("ERC721: caller is not token owner nor approved");
            await instance.approve(add2.address, 0)
            await instance.connect(add2).transferFrom(add1.address, add2.address, 0)
            expect(await instance.balanceOf(add2.address)).to.equal(1);
            expect(await instance.balanceOf(add1.address)).to.equal(0);
        });

        it("Test approve erc20 and transfer", async function () {
            const { instance, dataBytes } = await loadFixture(deploy)

            await instance.inscribe(dataBytes)
            await instance.connect(add2).toFT()

            expect(await instance.balanceOf(add1.address)).to.equal(1000);
            expect(await instance.allowance(add1.address, add2.address)).to.equal(0);
            await instance.approve(add2.address, 10000)
            expect(await instance.allowance(add1.address, add2.address)).to.equal(10000);

            await instance.connect(add2).transferFrom(add1.address, add2.address, 1000)
            expect(await instance.balanceOf(add1.address)).to.equal(0);
            expect(await instance.balanceOf(add2.address)).to.equal(1000);

            // insufficient allowance
            await expect(instance.connect(add2).transferFrom(add2.address, add1.address, 1000)).to.revertedWith('ERC20: insufficient allowance');
        });

        it("Test transfer function", async function () {
            const { instance, dataBytes } = await loadFixture(deploy)

            await instance.inscribe(dataBytes)
            expect(await instance.balanceOf(add1.address)).to.equal(1);
            expect(await instance.balanceOf(add2.address)).to.equal(0);
            await instance.transfer(add2.address, 1000) // will return false but change nothing
            expect(await instance.balanceOf(add1.address)).to.equal(1);
            expect(await instance.balanceOf(add2.address)).to.equal(0);

            await instance.connect(add2).toFT()
            expect(await instance.balanceOf(add1.address)).to.equal(1000);
            expect(await instance.balanceOf(add2.address)).to.equal(0);
            await expect(instance.transfer(add2.address, 1000)).to.be.emit(
                instance, "Inscribe"
            ).withArgs(add1.address, add2.address, "data:text/plain;charset=utf-8" + '{"p":"ins-20","op":"transfer","tick":"INSC","amt":"1000"}');
            expect(await instance.balanceOf(add2.address)).to.equal(1000);
            expect(await instance.balanceOf(add1.address)).to.equal(0);
        });

        it("Test safeTransferFrom function", async function () {
            const { instance, dataBytes } = await loadFixture(deploy)
            await instance.inscribe(dataBytes)

            await expect(instance.connect(add2).safeTransferFrom(add1.address, add2.address, 0)).to.revertedWith("ERC721: caller is not token owner nor approved");
            expect(await instance.balanceOf(add1.address)).to.equal(1);
            expect(await instance.balanceOf(add2.address)).to.equal(0);
            await instance.safeTransferFrom(add1.address, add2.address, 0)
            expect(await instance.balanceOf(add2.address)).to.equal(1);
            expect(await instance.balanceOf(add1.address)).to.equal(0);

            await instance.connect(add2).toFT()
            await expect(instance.safeTransferFrom(add1.address, add2.address, 0)).to.revertedWith("Not support ERC721 any more.");
        });

        it("Test setApprovalForAll function", async function () {
            const { instance, dataBytes } = await loadFixture(deploy)
            await instance.inscribe(dataBytes)

            expect(await instance.isApprovedForAll(add1.address, add2.address)).to.equal(false);
            await expect(instance.setApprovalForAll(add1.address, true)).to.revertedWith("ERC721: approve to caller");
            await instance.setApprovalForAll(add2.address, true)
            expect(await instance.isApprovedForAll(add1.address, add2.address)).to.equal(true);
        });
    });

    describe("Bug Test", function () {
        it("Test approval bug", async function () {
            const { instance } = await loadFixture(fork)

            expect(await instance.balanceOf(add1.address)).to.equal(0);
            await instance.approve(add1.address, 1000)
            const owner = await instance.ownerOf(1000)
            await instance.transferFrom(owner, add1.address, 1000)
            expect(await instance.ownerOf(1000)).to.equal(add1.address);
            expect(await instance.balanceOf(add1.address)).to.equal(1);
        });

        it("Test change nft2ft state by proxy", async function () {
            const { instance } = await loadFixture(fork)

            const proxyAddress = await instance.proxy()
            impersonateAccount(proxyAddress)
            const proxy_signer = await ethers.getSigner(proxyAddress)
            expect(await instance.nft2ft()).to.equal(false);
            await instance.connect(proxy_signer).toFT()
            expect(await instance.nft2ft()).to.equal(true);

            await expect(instance.approve(add2.address, 1000)).to.be.emit(
                instance, "Approval"
            ).withArgs(add1.address, add2.address, 1000);
        });

        it("Test transfer Erc721", async function () {
            const { instance } = await loadFixture(fork)

            const id = 1000
            await instance.approve(add1.address, id)
            const owner = await instance.ownerOf(id)
            await instance.transferFrom(owner, add1.address, id)
            expect(await instance.ownerOf(id)).to.equal(add1.address);
            expect(await instance.balanceOf(add1.address)).to.equal(1);

            // nft2ft == false: ERC721 _insBalances
            expect(await instance.balanceOf(add1.address)).to.equal(1);
            expect(await instance.balanceOf(add2.address)).to.equal(0);
            await instance.connect(add1).transferFrom(add1.address, add2.address, id)
            expect(await instance.balanceOf(add1.address)).to.equal(0);
            expect(await instance.balanceOf(add2.address)).to.equal(1);
            await instance.connect(add2).transferFrom(add2.address, add1.address, id)

            // change nft2ft
            const proxyAddress = await instance.proxy()
            impersonateAccount(proxyAddress)
            const proxy_signer = await ethers.getSigner(proxyAddress)
            await instance.connect(proxy_signer).toFT()
            expect(await instance.nft2ft()).to.equal(true);
            expect(await instance.balanceOf(add1.address)).to.equal(1000n);
            expect(await instance.balanceOf(add2.address)).to.equal(0);

            // ERC721 _insBalances
            // ERC20 _balances
        });

        it("Test toString", async function () {
            const { instance } = await loadFixture(deploy)

            expect(await instance.getString(0)).to.equal("0");
            expect(await instance.getString(10)).to.equal("10");
            expect(await instance.getString(100000)).to.equal("100000");
        });
    });
});



// toFC 之后如何 mint