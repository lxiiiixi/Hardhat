const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CustomERC20", function () {
    let owner, user1, user2, users;
    let TokenInstance;
    const init_supply = ethers.utils.parseEther("100000000000000"); // 将以太币（ETH）的值转换为它在Wei单位下的等价值
    // BigNumber { value: "100000000000000000000000000000000" }
    const ZERO_ADDRESS = ethers.constants.AddressZero; // 零地址 0x0000000000000000000000000000000000000000
    const BURN_TAX_RATE = 20;
    const TRADE_TAX_RATE = 80;


    async function deployTokensAndInit() {
        [owner, user1, user2, ...users] = await ethers.getSigners(); // 可以获得20个地址
        const CustomERC20 = await ethers.getContractFactory("CustomERC20");
        TokenInstance = await CustomERC20.deploy();
        let args = [owner.address, init_supply, "Pink BNB", "PNB", 18, BURN_TAX_RATE, TRADE_TAX_RATE, users[0].address];
        await TokenInstance.init(...args);
    }

    beforeEach(async () => {
        await deployTokensAndInit();
    })

    describe("Initial state uint test", () => {
        it("Call init twice should be failed", async () => {
            let args = [owner.address, init_supply, "Pink BNB", "PNB", 18, BURN_TAX_RATE, TRADE_TAX_RATE, users[0].address];
            await expect(TokenInstance.init(...args)).to.be.revertedWith("DODO_INITIALIZED");
            await expect(TokenInstance.initOwner(user1.address)).to.be.revertedWith("DODO_INITIALIZED");
        })

        it(("Initial state should equal with the params of constructor"), async () => {
            expect(await TokenInstance._OWNER_()).to.be.equal(owner.address);
            expect(await TokenInstance._NEW_OWNER_()).to.be.equal(ZERO_ADDRESS);
            expect(await TokenInstance.name()).to.be.equal("Pink BNB");
            expect(await TokenInstance.symbol()).to.be.equal("PNB");
            expect(await TokenInstance.decimals()).to.be.equal(18);
            expect(await TokenInstance.tradeBurnRatio()).to.be.equal(BURN_TAX_RATE);
            expect(await TokenInstance.tradeFeeRatio()).to.be.equal(TRADE_TAX_RATE);
            expect(await TokenInstance.team()).to.be.equal(users[0].address);
            expect(await TokenInstance.balanceOf(owner.address)).to.be.equal(init_supply);
            expect(await TokenInstance.totalSupply()).to.be.equal(init_supply);
        });
    })

    describe("Owner and OnlyOwner unit test", () => {
        it("Only owner can transfer ownership", async () => {
            await expect(TokenInstance.connect(user1).transferOwnership(user1.address)).to.be.revertedWith("NOT_OWNER");
            await expect(TokenInstance.transferOwnership(user1.address)).to.be.emit(TokenInstance, "OwnershipTransferPrepared").withArgs(owner.address, user1.address);
        })

        it("TransferOwnership can reset _NEW_OWNER_", async () => {
            await TokenInstance.transferOwnership(user1.address);
            expect(await TokenInstance._NEW_OWNER_()).to.be.equal(user1.address);
            await TokenInstance.transferOwnership(ZERO_ADDRESS);
            expect(await TokenInstance._NEW_OWNER_()).to.be.equal(ZERO_ADDRESS);
        })

        it("Only _NEW_OWNER_ can claim ownership", async () => {
            await TokenInstance.transferOwnership(user1.address);
            expect(await TokenInstance._NEW_OWNER_()).to.be.equal(user1.address);
            await expect(TokenInstance.connect(user2).claimOwnership()).to.be.revertedWith("INVALID_CLAIM");
            await expect(TokenInstance.connect(user1).claimOwnership()).to.be.emit(TokenInstance, "OwnershipTransferred").withArgs(owner.address, user1.address);
            expect(await TokenInstance._OWNER_()).to.be.equal(user1.address);
            expect(await TokenInstance._NEW_OWNER_()).to.be.equal(ZERO_ADDRESS);
        })

        it("AbandonOwnership should set owner to zero address", async () => {
            await expect(TokenInstance.abandonOwnership(user2.address)).to.be.revertedWith("NOT_ZERO_ADDRESS");
            await expect(TokenInstance.abandonOwnership(ZERO_ADDRESS)).to.be.emit(
                TokenInstance, "OwnershipTransferred"
            ).withArgs(owner.address, ZERO_ADDRESS);
            expect(await TokenInstance._OWNER_()).to.be.equal(ZERO_ADDRESS);
        })

        // bug复现
        it("AbandonOwnership should reset the value of _NEW_OWNER_", async () => {
            // 转移owner权限给user1 => 在user1 acclaim之前abandon自己的权限 => 此时_NEW_OWNER_为user1 => user1 claim 之后就可以获得owner权限  => 原本应该是owner零地址的变成了user1
            await TokenInstance.transferOwnership(user1.address);
            await TokenInstance.abandonOwnership(ZERO_ADDRESS);
            expect(await TokenInstance._OWNER_()).to.be.equal(ZERO_ADDRESS);
            expect(await TokenInstance._NEW_OWNER_()).to.be.equal(user1.address);
            await TokenInstance.connect(user1).claimOwnership();
            expect(await TokenInstance._OWNER_()).to.be.equal(ZERO_ADDRESS);
        });
    })

    describe("changeTeamAccount unit test", () => {
        it("Should change state and emit event", async () => {
            await expect(TokenInstance.changeTeamAccount(users[1].address)).to.be.emit(
                TokenInstance, "ChangeTeam"
            ).withArgs(users[0].address, users[1].address);
            expect(await TokenInstance.team()).to.be.equal(users[1].address);
        });
    });

    describe("Tansfer test", () => {
        it("Tansfer to zero address should be failed", async () => {
            await expect(TokenInstance.transfer(ZERO_ADDRESS, 100)).to.be.revertedWith("ERC20: transfer to the zero address")
        })

        it("Tansfer zero value should always be successful", async () => {
            expect(await TokenInstance.balanceOf(user1.address)).to.be.equal(0);
            await TokenInstance.connect(user1).transfer(user2.address, 0);
        });

        it("Transfer token beyond balance should be failed", async () => {
            await expect(TokenInstance.connect(user1).transfer(user2.address, 10)).to.be.revertedWith("ERC20: transfer amount exceeds balance");
        });

        it("Transfer token should be taxed", async () => {
            let amount = 1000000;
            let burn_fee = 1000000 * BURN_TAX_RATE / 10000;
            let trade_fee = 1000000 * TRADE_TAX_RATE / 10000;
            await expect(TokenInstance.transfer(user1.address, amount)).to.be.emit(
                TokenInstance, "Transfer"
            ).withArgs(owner.address, user1.address, amount - burn_fee - trade_fee);
            expect(await TokenInstance.balanceOf(owner.address)).to.be.equal(init_supply.sub(amount));
            expect(await TokenInstance.balanceOf(user1.address)).to.be.equal(amount -
                burn_fee - trade_fee);
            expect(await TokenInstance.balanceOf(ZERO_ADDRESS)).to.be.equal(burn_fee);
            expect(await
                TokenInstance.balanceOf(users[0].address)).to.be.equal(trade_fee);
        });

        // 这里有疑问
        it("Transfer to self should only be taxed", async () => {
            await TokenInstance.transfer(user1.address, 100000);
            let balance_before = 100000 * 99 / 100;
            expect(await TokenInstance.balanceOf(user1.address)).to.be.equal(balance_before);
            let amount = 1000;
            await TokenInstance.connect(user1).transfer(user1.address, amount);
            let balance_after = await TokenInstance.balanceOf(user1.address);
            expect(balance_after).to.be.equal(balance_before - amount / 100);
        });
    });

    describe("Approve and transferFrom unit test", () => {
        it("Approve should change allowance and change state", async () => {
            expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(0);
            await expect(TokenInstance.approve(user1.address, 1000)).to.be.emit(
                TokenInstance, "Approval"
            ).withArgs(owner.address, user1.address, 1000);
            expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(1000);
        })

        it("Transfer from should change allowance", async () => {
            await expect(TokenInstance.connect(user1).transferFrom(owner.address, user1.address, 1000)).to.be.revertedWith("ALLOWANCE_NOT_ENOUGH");
            await TokenInstance.approve(user1.address, 10000);
            await expect(TokenInstance.connect(user1).transferFrom(owner.address, user1.address, 1000)).to.be.emit(
                TokenInstance, "Transfer"
            ).withArgs(owner.address, user1.address, 1000 * 99 / 100);
            expect(await TokenInstance.allowance(owner.address, user1.address)).to.be.equal(10000 - 1000);
        })
    })
})