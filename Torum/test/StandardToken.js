const {
    loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Token Unit Test", function () {
    const config = {
        Mintable: false,
        Burnable: false,
        Pausable: false,
        Ownable: true
    }
    const meta = {
        contractName: "Torum",
        tokenName: "Torum",
        tokenSymbol: "XTM",
        TokenDecimals: 18,
        initSupply: ethers.parseEther("800000000")
    }

    async function deployTokenFixture() {
        const [owner, alice, bob, ...users] = await ethers.getSigners();
        const StandardToken = await ethers.getContractFactory(meta.contractName);
        const instance = await StandardToken.deploy();

        check_config(instance);
        return { owner, alice, bob, users, instance };
    }

    function check_config(instance) {
        let functions = instance.interface.fragments
            .filter(item => item.type === "function")
            .map(item => item.name);

        let mint_flag = functions.includes("mint");
        if (config.Mintable !== mint_flag) {
            throw ("Invalid Mintable config");
        }

        let burn_flag = functions.includes("burn") && functions.includes("burnFrom");
        if (config.Burnable !== burn_flag) {
            throw ("Invalid Burnable config");
        }

        let owner_flag = functions.includes("owner")
            && functions.includes("renounceOwnership")
            && functions.includes("transferOwnership");

        if (config.Ownable !== owner_flag) {
            throw ("Invalid Ownable config");
        }

        let pause_flag = functions.includes("pause")
            && functions.includes("unpause")
            && functions.includes("paused");
        if (config.Pausable !== pause_flag) {
            throw ("Invalid Pausable config");
        }

        if (config.Pausable && !config.Ownable) {
            throw ("Please check the calling permission of Pausable");
        }

        if (config.Mintable && !config.Ownable) {
            throw ("Please check the calling permission of Mintable");
        }
    }

    function convert(num) {
        return ethers.getBigInt(num);
    }

    describe("Metadata unit Test", function () {
        it("Metadata should be the same as expected", async function () {
            const { instance, owner } = await loadFixture(deployTokenFixture);
            expect(await instance.name()).eq(meta.tokenName, "TokenName does not match");
            expect(await instance.symbol()).eq(meta.tokenSymbol, "TokenSymbol does not match");
            expect(await instance.decimals()).eq(meta.TokenDecimals, "TokenDecimals does not match");
            expect(await instance.balanceOf(owner.address)).eq(meta.initSupply, "InitSupply does not match");
            expect(await instance.totalSupply()).eq(meta.initSupply, "InitSupply does not match");
        });
    });

    describe("Transfer unit test", function () {
        it("Token transfer should emit event and change balance", async function () {
            const { instance, owner, alice, bob } = await loadFixture(deployTokenFixture);
            await expect(instance.transfer(alice.address, 1000)).to.be.emit(
                instance, "Transfer"
            ).withArgs(owner.address, alice.address, 1000);
            expect(await instance.balanceOf(alice.address)).eq(1000, "Balance of alice does not match");
            expect(await instance.balanceOf(owner.address)).eq(meta.initSupply - convert(1000), "Balance of owner does not match");
            expect(await instance.totalSupply()).eq(meta.initSupply, "InitSupply does not match");
            await instance.connect(alice).transfer(bob.address, 400);
            expect(await instance.balanceOf(alice.address)).eq(600, "Balance of alice does not match while transferring to bob");
            expect(await instance.balanceOf(bob.address)).eq(400, "Balance of bob does not match");
        });

        it("Should be failed if sender doesn’t have enough tokens", async () => {
            const { instance, alice } = await loadFixture(deployTokenFixture);
            await expect(instance.transfer(alice.address, meta.initSupply + convert(1))).to.be.revertedWith(
                "ERC20: transfer amount exceeds balance"
            );
        });

        it("Should be failed if sender transfer to or from zero address", async function () {
            const { instance, alice } = await loadFixture(deployTokenFixture);
            const transferAmount = convert(5000);
            const AddressZero = ethers.ZeroAddress;
            await expect(instance.transfer(AddressZero, transferAmount)).to.revertedWith("ERC20: transfer to the zero address");
            await instance.approve(alice.address, transferAmount);
            await expect(instance.transferFrom(alice.address, AddressZero, transferAmount)).to.revertedWith("ERC20: transfer to the zero address");
        });
    });

    describe("Approve unit test", function () {
        it("Approve should change state and emit event", async () => {
            const { instance, alice, bob } = await loadFixture(deployTokenFixture);
            expect(await instance.allowance(alice.address, bob.address)).eq(0, "Allowance0 does not match");

            await expect(instance.connect(alice).approve(bob.address, 10000)).to.be.emit(
                instance, "Approval"
            ).withArgs(alice.address, bob.address, 10000);
            expect(await instance.allowance(alice.address, bob.address)).eq(10000, "Allowance1 does not match");

            await expect(instance.connect(alice).increaseAllowance(bob.address, 2000)).to.be.emit(
                instance, "Approval"
            ).withArgs(alice.address, bob.address, 12000);
            expect(await instance.allowance(alice.address, bob.address)).eq(12000, "Allowance2 does not match");

            await expect(instance.connect(alice).decreaseAllowance(bob.address, 3000)).to.be.emit(
                instance, "Approval"
            ).withArgs(alice.address, bob.address, 9000);
            expect(await instance.allowance(alice.address, bob.address)).eq(9000, "Allowance3 does not match");

        });
    });

    describe("TransferFrom unit test", function () {
        it("Token transferFrom should emit event and change state", async function () {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            const amount = 1000;
            await instance.approve(alice.address, amount * 10);
            await expect(instance.connect(alice).transferFrom(owner.address, alice.address, amount)).to.be.emit(
                instance, "Transfer"
            ).withArgs(owner.address, alice.address, amount);

            expect(await instance.balanceOf(alice.address)).eq(amount, "Balance of alice does not match");
            expect(await instance.balanceOf(owner.address)).eq(meta.initSupply - convert(amount), "Balance of owner does not match");
            expect(await instance.totalSupply()).eq(meta.initSupply, "InitSupply does not match");
            expect(await instance.allowance(owner.address, alice.address)).eq(amount * 9, "Allowance does not match");
        });

        it("Maximum approval should not change while transferFrom", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            const amount = 1000;
            await instance.approve(alice.address, ethers.MaxUint256);
            await instance.connect(alice).transferFrom(owner.address, alice.address, amount);
            expect(await instance.allowance(owner.address, alice.address)).eq(ethers.MaxUint256, "Allowance does not match");
        });

        it("Should be failed if sender doesn’t have enough approval", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            const amount = 1000;
            await instance.approve(alice.address, amount - 1);
            await expect(instance.connect(alice).transferFrom(owner.address, alice.address, amount)).to.be.revertedWith(
                "ERC20: insufficient allowance"
            );
        });
    });

    describe("Burnable unit test", function () {
        if (!config.Burnable) {
            return;
        }

        it("Burn should change state and emit event", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            await instance.transfer(alice.address, 10000);

            await expect(instance.connect(alice).burn(4000)).to.emit(
                instance, "Transfer"
            ).withArgs(alice.address, ethers.ZeroAddress, 4000);
            expect(await instance.balanceOf(alice.address)).eq(6000, "Balance of alice does not match");
            expect(await instance.totalSupply()).eq(meta.initSupply - convert(4000), "InitSupply does not match");
        });

        it("BurnFrom should change allowance", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            const amount = 1000;
            await instance.approve(alice.address, amount * 10);
            await expect(instance.connect(alice).burnFrom(owner.address, amount)).to.be.emit(
                instance, "Transfer"
            ).withArgs(owner.address, ethers.ZeroAddress, amount);
            expect(await instance.balanceOf(owner.address)).eq(meta.initSupply - convert(amount), "Balance of owner does not match");
            expect(await instance.totalSupply()).eq(meta.initSupply - convert(amount), "InitSupply does not match");
            expect(await instance.allowance(owner.address, alice.address)).eq(amount * 9, "Allowance does not match");
        });

        it("Should be failed if burner doesn’t have enough approval", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            const amount = 1000;
            await instance.approve(alice.address, amount - 1);
            await expect(instance.connect(alice).burnFrom(owner.address, amount)).to.be.revertedWith(
                "ERC20: insufficient allowance"
            );
        });

        it("Maximum approval should not change while BurnFrom", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            const amount = 1000;
            await instance.approve(alice.address, ethers.MaxUint256);
            await instance.connect(alice).burnFrom(owner.address, amount);
            expect(await instance.allowance(owner.address, alice.address)).eq(ethers.MaxUint256, "Allowance does not match");
        });
    });

    describe("Ownable unit test", function () {
        if (!config.Ownable) {
            return;
        }

        it("Renounce owner should change state and emit event", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            expect(await instance.owner()).eq(owner.address, "initial owner does not match");

            await expect(instance.renounceOwnership()).to.be.emit(
                instance, "OwnershipTransferred"
            ).withArgs(owner.address, ethers.ZeroAddress);

            expect(await instance.owner()).eq(ethers.ZeroAddress, "owner should be zero");
        });

        it("Change owner should change state and emit event", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            expect(await instance.owner()).eq(owner.address, "initial owner does not match");

            await expect(instance.transferOwnership(alice.address)).to.be.emit(
                instance, "OwnershipTransferred"
            ).withArgs(owner.address, alice.address);

            expect(await instance.owner()).eq(alice.address, "owner does not match");
        });

        it("only old owner can change or renounce owner", async () => {
            const { instance, bob, alice } = await loadFixture(deployTokenFixture);
            await expect(instance.connect(alice).transferOwnership(bob.address)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
            await expect(instance.connect(alice).renounceOwnership()).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
    });


    describe("Mintable unit test", function () {
        if (!config.Mintable) {
            return;
        }

        it("Only owner can mint token", async () => {
            const { instance, bob, alice } = await loadFixture(deployTokenFixture);
            await expect(instance.connect(alice).mint(bob.address, 10000)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });

        it("mint token can change supply and balance", async () => {
            const { instance, alice } = await loadFixture(deployTokenFixture);
            await expect(instance.mint(alice.address, 10000)).to.be.emit(
                instance, "Transfer"
            ).withArgs(ethers.ZeroAddress, alice.address, 10000);
            expect(await instance.balanceOf(alice.address)).eq(10000, "Balance of alice does not match");
            expect(await instance.totalSupply()).eq(meta.initSupply + convert(10000), "TotalSupply does not match");
        });
    });

    describe("Pausable unit test", function () {
        if (!config.Pausable) {
            return;
        }

        it("Only owner can pause transfer", async () => {
            const { instance, alice } = await loadFixture(deployTokenFixture);
            await expect(instance.connect(alice).pause()).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );

            await expect(instance.connect(alice).unpause()).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });

        it("Pause and unpause should change state and emit event", async () => {
            const { instance, owner } = await loadFixture(deployTokenFixture);
            expect(await instance.paused()).to.be.false;

            await expect(instance.pause()).to.be.emit(
                instance, "Paused"
            ).withArgs(owner.address);

            expect(await instance.paused()).to.be.true;
            await expect(instance.pause()).to.be.revertedWith("Pausable: paused");

            await expect(instance.unpause()).to.be.emit(
                instance, "Unpaused"
            ).withArgs(owner.address);

            expect(await instance.paused()).to.be.false;
            await expect(instance.unpause()).to.be.revertedWith("Pausable: not paused");
        });

        it("TokenTransfer should be failed while paused", async () => {
            const { instance, owner, alice } = await loadFixture(deployTokenFixture);
            await instance.pause();

            await expect(instance.transfer(alice.address, 10000)).to.be.revertedWith(
                "ERC20Pausable: token transfer while paused"
            );

            await instance.approve(alice.address, 100000);
            await expect(instance.connect(alice).transferFrom(owner.address, alice.address, 1000))
                .to.be.revertedWith("ERC20Pausable: token transfer while paused");
        });
    });

});