const { expect } = require("chai");
const { ethers } = require("hardhat");


describe("TeamToken", function () {
    let owner, user1, user2, users;
    let TokenInstance;
    const init_supply = ethers.utils.parseEther("10000")
    const ZERO_ADDRESS = ethers.constants.AddressZero;
    let args = {};

    async function deployTokens(ARGS) {
        const TeamToken = await ethers.getContractFactory("TeamToken");
        let theArgs = []
        for (const i in ARGS) {
            theArgs.push(ARGS[i])
        }
        // console.log(theArgs);
        TokenInstance = await TeamToken.deploy(...theArgs)
    }

    beforeEach(async () => {
        [owner, user1, user2, ...users] = await ethers.getSigners();
        args = { name: "Zedxion", symbol: "ZEDXION", decimals: 18, supply: init_supply, owner: owner.address, feeWallet: user1.address }
    })


    describe("Initial state uint test", async () => {
        it(("Initial state should equal with the params of constructor"), async () => {
            await deployTokens(args);
            expect(await TokenInstance.name()).to.be.equal("Zedxion");
            expect(await TokenInstance.symbol()).to.be.equal("ZEDXION");
            expect(await TokenInstance.decimals()).to.be.equal(18);
            expect(await TokenInstance.totalSupply()).to.be.equal(init_supply);
            expect(await TokenInstance.balanceOf(owner.address)).to.be.equal(init_supply)
            // expect(await TokenInstance.owner()).to.be.equal(owner);
            // expect(await TokenInstance.feeWallet()).to.be.equal(user1);
        });

        it(("Set up decimals can be seccessful"), async () => {
            args.decimals = 10
            await deployTokens(args);
            expect(await TokenInstance.decimals()).to.be.equal(10);
        });

        it(("Set the owner and feeWallet to zero address will fail"), async () => {
            args.owner = ZERO_ADDRESS
            await expect(deployTokens(args)).to.be.revertedWith("[Validation] invalid address");
            args.owner = owner.address
            args.feeWallet = ZERO_ADDRESS
            await expect(deployTokens(args)).to.be.revertedWith("[Validation] invalid address");
        });
    })

    describe("Mint test", async () => {
        it(("Mint will emit Transfer event"), async () => {
            expect(await deployTokens(args)).to.be.emit(TokenInstance, "Transfer").withArgs(ZERO_ADDRESS, owner.address, init_supply);
        })

        it(("TotalSupply and owner balance will add after being mint"), async () => {
            const new_supply = ethers.utils.parseEther("100000")
            args.supply = new_supply
            await deployTokens(args);
            expect(await TokenInstance.totalSupply()).to.be.equal(new_supply);
            expect(await TokenInstance.balanceOf(owner.address)).to.be.equal(new_supply);
        })
    })

    describe("Transfer test", async () => {
        it("Tansfer to and from zero address should be failed", async () => {
            await deployTokens(args);
            await expect(TokenInstance.transfer(ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: transfer to the zero address")
            // await expect(TokenInstance.connect(ZERO_ADDRESS).transfer(user1.address, 100)).to.be.revertedWith("ERC20: transfer to the zero address")
        })

        it("Tansfer zero value should always be successful", async () => {
            await deployTokens(args);
            await TokenInstance.connect(user1).transfer(user2.address, 0);
        });

        it("Tansfer will fail if sender don't have enough balance", async () => {
            await deployTokens(args);
            expect(await TokenInstance.balanceOf(user1.address)).to.be.equal(0);
            await expect(TokenInstance.connect(user1).transfer(user2.address, 100)).to.be.revertedWith("ERC20: transfer amount exceeds balance")
            expect(await TokenInstance.balanceOf(user2.address)).to.be.equal(0);
        });

        it("Balance will be changed successfully and totol supply will not change", async () => {
            await deployTokens(args);
            await expect(TokenInstance.transfer(user2.address, 100)).to.be.emit(
                TokenInstance, "Transfer"
            ).withArgs(owner.address, user2.address, 100);
            expect(await TokenInstance.totalSupply()).to.be.equal(init_supply);
            expect(await TokenInstance.balanceOf(user2.address)).to.be.equal(100);
            expect(await TokenInstance.balanceOf(owner.address)).to.be.equal(init_supply.sub(100));
        });
    })

    describe("TransferFrom test", async () => {
        it("Tansfer to and from zero address should be failed", async () => {
            await deployTokens(args);
            await expect(TokenInstance.transferFrom(owner.address, ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: transfer to the zero address")
            await expect(TokenInstance.transferFrom(ZERO_ADDRESS, ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: transfer from the zero address")
        })

        it("Sender must have a balance of at least amount", async () => {
            await deployTokens(args);
            expect(await TokenInstance.balanceOf(user2.address)).to.be.equal(0);
            await expect(TokenInstance.transferFrom(user2.address, user1.address, 100)).to.be.revertedWith("ERC20: transfer amount exceeds balance")
            expect(await TokenInstance.transferFrom(user2.address, user1.address, 0))

        })
        it("Tranfer from self will be successfull and totol supply will not change", async () => {
            await deployTokens(args);
            await TokenInstance.approve(owner.address, 1000);
            expect(await TokenInstance.transferFrom(owner.address, owner.address, 100))
            expect(await TokenInstance.totalSupply()).to.be.equal(init_supply);
            expect(await TokenInstance.balanceOf(owner.address)).to.be.equal(init_supply)
        })

        it("Approval of sender will change after transfer", async () => {
            await deployTokens(args);
            // user1 给 owner 授权可以转user1的钱
            await TokenInstance.connect(user1).approve(owner.address, 1000);
            expect(await TokenInstance.allowance(user1.address, owner.address)).to.be.equal(1000);
            await expect(TokenInstance.transferFrom(user1.address, user2.address, 100)).to.be.revertedWith("ERC20: transfer amount exceeds balance")
            await TokenInstance.transfer(user1.address, 100)
            expect(await TokenInstance.balanceOf(user1.address)).to.be.equal(100)
            // owner 去执行将user1的代币转给user2
            await expect(TokenInstance.transferFrom(user1.address, user2.address, 100)).to.be.emit(
                TokenInstance, "Transfer"
            ).withArgs(user1.address, user2.address, 100);
            expect(await TokenInstance.balanceOf(user2.address)).to.be.equal(100)
            expect(await TokenInstance.balanceOf(user1.address)).to.be.equal(0)
            expect(await TokenInstance.allowance(user1.address, owner.address)).to.be.equal(900);
            expect(await TokenInstance.totalSupply()).to.be.equal(init_supply);
        })

    })

    describe("Approve test", async () => {
        it("Spender cannot be the zero address", async () => {
            await deployTokens(args);
            await expect(TokenInstance.approve(ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: approve to the zero address")
        })
        it("Approve should change state and emit event", async () => {
            await expect(TokenInstance.connect(user1).approve(user2.address, 100)).to.be.emit(
                TokenInstance, "Approval"
            ).withArgs(user1.address, user2.address, 100);
            expect(await TokenInstance.allowance(user1.address, user2.address)).to.be.equal(100);
        });
    })


    describe("Change allowance test", async () => {
        it("Spender cannot be the zero address", async () => {
            await deployTokens(args);
            await expect(TokenInstance.increaseAllowance(ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: approve to the zero address")
            await expect(TokenInstance.decreaseAllowance(ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: decreased allowance below zero")
        })

        it("Allowance should be added after increaseAllowance", async () => {
            await deployTokens(args);
            // 合约调用
            await TokenInstance.approve(user1.address, 100);
            await expect(TokenInstance.increaseAllowance(user1.address, 100)).to.be.emit(
                TokenInstance, "Approval"
            ).withArgs(owner.address, user1.address, 200);
            expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(200);
        })

        it("Allowance should be decreased after decreaseAllowance", async () => {
            await deployTokens(args);
            await expect(TokenInstance.decreaseAllowance(user1.address, 100)).to.be.revertedWith("ERC20: decreased allowance below zero")
            await TokenInstance.approve(user1.address, 100);
            await expect(TokenInstance.decreaseAllowance(user1.address, 100)).to.be.emit(
                TokenInstance, "Approval"
            ).withArgs(owner.address, user1.address, 0);
            expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(0);
        })

    })
})