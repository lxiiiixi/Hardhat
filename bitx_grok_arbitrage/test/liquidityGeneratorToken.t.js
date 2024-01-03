const {
    loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Liquidity Generator Token Unit Test", function () {
    const config = {
        Mintable: false,
        Burnable: true,
        BurnFrom: false,
        Pausable: false,
        Ownable: true
    }

    const meta = {
        contractName: "PuppyLove",
        tokenName: "PuppyLoveCoin",
        tokenSymbol: "PLC",
        TokenDecimals: 18,
        initSupply: ethers.parseEther("1000000000000"),
        maxTxAmount: ethers.parseEther("10000000000"),
        maxWalletSize: ethers.parseEther("10000000000"),
        swapTokensAtAmount: ethers.parseEther("10000000000"),
    }

    async function deployTokenFixture() {
        const [owner, alice, bob, ...users] = await ethers.getSigners();
        const StandardToken = await ethers.getContractFactory(meta.contractName);
        const instance = await StandardToken.deploy();
        check_config(instance);
        return {
            singers: { owner, alice, bob, users },
            instance
        };
    }

    function check_config(instance) {
        let functions = instance.interface.fragments
            .filter(item => item.type === "function")
            .map(item => item.name);

        let mint_flag = functions.includes("mint");
        if (config.Mintable !== mint_flag) {
            throw ("Invalid Mintable config");
        }

        let burn_flag = functions.includes("burn");
        if (config.Burnable !== burn_flag) {
            throw ("Invalid Burnable config");
        }

        let burn_from_flag = functions.includes("burnFrom");
        if (config.BurnFrom !== burn_from_flag) {
            throw ("Invalid BurnFrom config");
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

    describe("OnlyOwner functions unit Test", function () {
        it("Test setFee", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice } = singers;
            await expect(instance.connect(alice).setFee(4, 4, 10, 10)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
            await expect(instance.setFee(5, 10, 4, 10)).to.be.revertedWith("Buy rewards must be between 0% and 4%");
            await expect(instance.setFee(4, 5, 4, 10)).to.be.revertedWith("Sell rewards must be between 0% and 4%");
            await expect(instance.setFee(4, 10, 30, 10)).to.be.revertedWith("Buy tax must be between 0% and 25%");
            await expect(instance.setFee(4, 4, 10, 30)).to.be.revertedWith("Sell tax must be between 0% and 25%");
            await expect(instance.setFee(4, 4, 10, 10)).to.be.emit(
                instance, "SetFee"
            ).withArgs(4, 4, 10, 10);
        })

        it("Test setMinSwapTokensThreshold", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;
            const amount = ethers.parseEther("100")
            await expect(instance.connect(alice).setMinSwapTokensThreshold(amount)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
            await expect(instance.setMinSwapTokensThreshold(amount)).to.be.emit(
                instance, "setMinSwapThreshold"
            ).withArgs(amount);
        })

        it("Test toggleSwap", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice } = singers;
            await expect(instance.connect(alice).toggleSwap(true)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
            await expect(instance.toggleSwap(true)).to.be.emit(
                instance, "swapToggle"
            ).withArgs(true);
        })

        it("Test setMaxTxnAmount", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;
            const amount = ethers.parseEther("100")
            await expect(instance.connect(alice).setMaxTxnAmount(amount)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
            await expect(instance.setMaxTxnAmount(amount)).to.be.emit(
                instance, "maxTxUpdate"
            ).withArgs(amount);

            // test state change
            await instance.transfer(alice.address, meta.maxTxAmount)
            await expect(instance.connect(alice).transfer(bob.address, amount + convert(1))).to.be.revertedWith(
                "TOKEN: Max Transaction Limit"
            );
        })

        it("Test setMaxWalletSize", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;
            const amount = ethers.parseEther("10")
            await expect(instance.connect(alice).setMaxWalletSize(amount)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
            await expect(instance.setMaxWalletSize(amount)).to.be.emit(
                instance, "updateMaxwalletSize"
            ).withArgs(amount);

            await instance.transfer(alice.address, amount + 1n)
            await expect(instance.connect(alice).transfer(bob.address, amount + 1n))
                .to.be.revertedWith("TOKEN: Balance exceeds wallet size!");
        })

        it("Test excludeMultipleAccountsFromFees", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;
            await expect(instance.connect(alice).excludeMultipleAccountsFromFees([alice.address, bob.address], true))
                .to.be.revertedWith("Ownable: caller is not the owner");

            // add liquidity
            const liquidityAmount = meta.initSupply / convert(2)
            const UniswapV2Router = await ethers.getContractFactory(`UniswapV2Router02`);
            const uniswapV2Router = await UniswapV2Router.attach(await instance.uniswapV2Router())
            await instance.approve(uniswapV2Router.target, ethers.MaxUint256);
            await uniswapV2Router.addLiquidityETH(instance.target, liquidityAmount, 0, 0, alice.address, 9876543210, { value: ethers.parseEther("10") });

            // will take fee between alice and bob
            const transferAmount = ethers.parseEther("1")
            await instance.transfer(alice.address, transferAmount);
            await instance.connect(alice).approve(uniswapV2Router.target, ethers.MaxUint256);
            await uniswapV2Router.connect(alice).swapETHForExactTokens(transferAmount, [await uniswapV2Router.WETH(), instance.target], bob.address, 9876543210, { value: ethers.parseEther("1") })
            const buyFee = transferAmount * 5n / 100n
            expect(await instance.balanceOf(instance.target)).eq(buyFee);
            expect(await instance.balanceOf(bob.address)).eq(transferAmount - buyFee);

            await instance.excludeMultipleAccountsFromFees([alice.address, bob.address], true)

            // will not take fee between alice and bob
            await instance.transfer(alice.address, transferAmount);
            await instance.connect(alice).approve(uniswapV2Router.target, ethers.MaxUint256);
            await uniswapV2Router.connect(alice).swapETHForExactTokens(transferAmount, [await uniswapV2Router.WETH(), instance.target], bob.address, 9876543210, { value: ethers.parseEther("1") })
            expect(await instance.balanceOf(instance.target)).eq(buyFee);
            expect(await instance.balanceOf(bob.address)).eq(transferAmount * 2n - buyFee);
        })
    });

    describe("Manual functions unit Test", function () {
        it("Test manualswap and manualsend", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, owner } = singers;

            // add liquidity
            const liquidityAmount = meta.initSupply / convert(2)
            const UniswapV2Router = await ethers.getContractFactory(`UniswapV2Router02`);
            const uniswapV2Router = await UniswapV2Router.attach(await instance.uniswapV2Router())
            await instance.approve(uniswapV2Router.target, ethers.MaxUint256);
            await uniswapV2Router.addLiquidityETH(instance.target, liquidityAmount, 0, 0, alice.address, 9876543210, { value: ethers.parseEther("10") });

            const path = [await uniswapV2Router.WETH(), instance.target]
            const amountOut = ethers.parseEther("10")
            const feeOnBuy = amountOut * 5n / 100n
            await expect(uniswapV2Router.swapETHForExactTokens(amountOut, path, alice.address, 9876543210, { value: ethers.parseEther("1") }))
                .to.be.emit(instance, "Transfer")
                .withArgs(await instance.uniswapV2Pair(), alice.address, amountOut - feeOnBuy);
            expect(await instance.balanceOf(instance.target)).eq(feeOnBuy);
            expect(await instance.balanceOf(alice.address)).eq(amountOut - feeOnBuy);
            console.log(await instance.balanceOf(owner.address));

            // 	manualswap
            expect(await ethers.provider.getBalance(instance.target)).eq(0);
            const ethAmountOut = (await uniswapV2Router.getAmountsOut(feeOnBuy, [instance.target, await uniswapV2Router.WETH()]))[1]
            await instance.manualswap()
            expect(await instance.balanceOf(instance.target)).eq(0);
            expect(await ethers.provider.getBalance(instance.target)).eq(ethAmountOut);

            // manualsend
            await instance.manualsend()
            expect(await ethers.provider.getBalance(instance.target)).eq(0);
            expect(await ethers.provider.getBalance("0x273AfFd240228c0C6FEC0E8ca55106CCe4eb08a3")).eq(ethAmountOut);
        });
    });

    // Here are the basic ERC20 token function tests below

    describe("Metadata unit Test", function () {
        it("Metadata should be the same as expected", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner } = singers;
            expect(await instance.name()).eq(meta.tokenName, "TokenName does not match");
            expect(await instance.symbol()).eq(meta.tokenSymbol, "TokenSymbol does not match");
            expect(await instance.decimals()).eq(meta.TokenDecimals, "TokenDecimals does not match");
            expect(await instance.balanceOf(owner.address)).eq(meta.initSupply, "InitSupply does not match");
            expect(await instance.totalSupply()).eq(meta.initSupply, "InitSupply does not match");
        });
    });

    describe("Transfer unit test", function () {
        it("Token transfer param check", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice } = singers;

            await expect(instance.transfer(ethers.ZeroAddress, 10000)).to.be.
                revertedWith("ERC20: transfer to the zero address");
            await expect(instance.transferFrom(ethers.ZeroAddress, alice.address, 10000)).to.be.
                revertedWith("ERC20: transfer from the zero address");
            await expect(instance.transfer(alice.address, 0)).to.be.
                revertedWith("Transfer amount must be greater than zero");
        });

        it("Transfer between accounts will not take fee", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;

            // will not take fee between alice and bob
            expect(await instance.balanceOf(instance.target)).eq(0);
            const transferAmount = ethers.parseEther("1")
            await instance.transfer(alice.address, transferAmount);
            await instance.connect(alice).transfer(bob.address, transferAmount);
            expect(await instance.balanceOf(instance.target)).eq(0);
        })

        it("Token transfer should emit event and change balance", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner, alice, bob } = singers;
            await expect(instance.transfer(alice.address, meta.initSupply + convert(1))).to.be.reverted;
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

        it("Test transfer between users who are not owner or router", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;

            // const amount = ethers.parseEther("100")
            await instance.transfer(alice.address, meta.maxTxAmount + convert(1))
            await expect(instance.connect(alice).transfer(bob.address, meta.maxTxAmount + convert(1))).to.be.
                revertedWith("TOKEN: Max Transaction Limit");
            await instance.connect(alice).transfer(bob.address, meta.maxTxAmount - convert(1))
            await expect(instance.connect(alice).transfer(bob.address, convert(1))).to.be.
                revertedWith("TOKEN: Balance exceeds wallet size!");
            await instance.transfer(instance.target, meta.swapTokensAtAmount)

            // add liquidity
            const liquidityAmount = meta.initSupply / convert(2)
            const UniswapV2Router = await ethers.getContractFactory(`UniswapV2Router02`);
            const uniswapV2Router = await UniswapV2Router.attach(await instance.uniswapV2Router())
            await instance.approve(uniswapV2Router.target, ethers.MaxUint256);
            await uniswapV2Router.addLiquidityETH(instance.target, liquidityAmount, 0, 0, alice.address, 9876543210, { value: ethers.parseEther("10") });

            const taxesAddress = "0x273AfFd240228c0C6FEC0E8ca55106CCe4eb08a3"
            const uniswapV2Pair = await instance.uniswapV2Pair()
            expect(await instance.balanceOf(uniswapV2Pair)).eq(liquidityAmount);
            expect(await ethers.provider.getBalance(taxesAddress)).eq(0);
            await instance.connect(bob).transfer(alice.address, convert(1))
            expect(await instance.balanceOf(uniswapV2Pair)).eq(liquidityAmount + meta.maxWalletSize);
            expect(await ethers.provider.getBalance(taxesAddress)).gt(0);
        });

        it("Test transfer between user will not take fee", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;

            expect(await instance.balanceOf(instance.target)).eq(0);
            await instance.transfer(alice.address, ethers.parseEther("100"))
            await instance.connect(alice).transfer(bob.address, ethers.parseEther("100"))
            expect(await instance.balanceOf(instance.target)).eq(0);
        });


        it("Test swap exact tokens by router", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice } = singers;

            // add liquidity
            const liquidityAmount = meta.initSupply / convert(2)
            const UniswapV2Router = await ethers.getContractFactory(`UniswapV2Router02`);
            const uniswapV2Router = await UniswapV2Router.attach(await instance.uniswapV2Router())
            await instance.approve(uniswapV2Router.target, ethers.MaxUint256);
            await uniswapV2Router.addLiquidityETH(instance.target, liquidityAmount, 0, 0, alice.address, 9876543210, { value: ethers.parseEther("10") });

            expect(await instance.balanceOf(instance.target)).eq(0);
            //  token: from(uniswapV2Pair) -> alice
            const path = [await uniswapV2Router.WETH(), instance.target]
            const amountOut = ethers.parseEther("10")
            const feeOnBuy = amountOut * 5n / 100n
            await expect(uniswapV2Router.swapETHForExactTokens(amountOut, path, alice.address, 9876543210, { value: ethers.parseEther("1") }))
                .to.be.emit(instance, "Transfer")
                .withArgs(await instance.uniswapV2Pair(), alice.address, amountOut - feeOnBuy);
            expect(await instance.balanceOf(instance.target)).eq(feeOnBuy);
            expect(await instance.balanceOf(alice.address)).eq(amountOut - feeOnBuy);
        });

        it("Test swap in exact tokens by router", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice } = singers;

            // add liquidity
            const liquidityAmount = meta.initSupply / convert(2)
            const UniswapV2Router = await ethers.getContractFactory(`UniswapV2Router02`);
            const uniswapV2Router = await UniswapV2Router.attach(await instance.uniswapV2Router())
            await instance.approve(uniswapV2Router.target, ethers.MaxUint256);
            await uniswapV2Router.addLiquidityETH(instance.target, liquidityAmount, 0, 0, alice.address, 9876543210, { value: ethers.parseEther("10") });
            const pairAddress = await instance.uniswapV2Pair()

            // swapExactTokensForETH: token in -> eth out
            const path = [instance.target, await uniswapV2Router.WETH()]
            const amountIn = ethers.parseEther("1")
            const feeOnSell = amountIn * 5n / 100n
            await instance.transfer(alice.address, amountIn)
            expect(await instance.balanceOf(alice.address)).eq(amountIn);
            expect(await instance.balanceOf(pairAddress)).eq(meta.initSupply / 2n);
            await instance.connect(alice).approve(uniswapV2Router.target, ethers.MaxUint256);
            await expect(uniswapV2Router.connect(alice).swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, alice.address, 9876543210))
                .to.be.emit(instance, "Transfer")
                .withArgs(alice.address, pairAddress, amountIn - feeOnSell);
            expect(await instance.balanceOf(alice.address)).eq(0);
            expect(await instance.balanceOf(pairAddress)).eq(meta.initSupply / 2n + amountIn - feeOnSell);
            expect(await instance.balanceOf(instance.target)).eq(feeOnSell);
        });
    });

    describe("Approve unit test", function () {
        it("Approve should change state and emit event", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers
            expect(await instance.allowance(alice.address, bob.address)).eq(0, "Allowance0 does not match");

            await expect(instance.connect(alice).approve(bob.address, 10000)).to.be.emit(
                instance, "Approval"
            ).withArgs(alice.address, bob.address, 10000);
            expect(await instance.allowance(alice.address, bob.address)).eq(10000, "Allowance1 does not match");
        });
    });

    describe("TransferFrom unit test", function () {
        it("Token transferFrom should emit event and change state", async function () {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner, alice } = singers
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

        it("Should be failed if sender doesn’t have enough approval", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner, alice } = singers
            const amount = 1000;
            await instance.approve(alice.address, amount - 1);
            await expect(instance.connect(alice).transferFrom(owner.address, alice.address, amount)).to.be.reverted;
        });
    });

    describe("Burnable unit test", function () {
        if (!config.Burnable) {
            return;
        }

        it("Only owner can burn", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice } = singers
            await expect(instance.connect(alice).burn(4000)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });

        it("Burn should change state and emit event", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner } = singers

            expect(await instance.totalSupply()).eq(meta.initSupply, "InitSupply does not match");
            expect(await instance.balanceOf(owner)).eq(meta.initSupply, "Owner balance does not match");
            await expect(instance.burn(4000)).to.emit(
                instance, "Transfer"
            ).withArgs(owner.address, ethers.ZeroAddress, 4000);
            expect(await instance.totalSupply()).eq(meta.initSupply - convert(4000), "InitSupply does not match");
            expect(await instance.balanceOf(owner)).eq(meta.initSupply - convert(4000), "Owner balance does not match");
        });

        if (!config.BurnFrom) {
            return;
        }

        it("BurnFrom should change allowance", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner, alice } = singers
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
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner, alice } = singers
            const amount = 1000;
            await instance.approve(alice.address, amount - 1);
            await expect(instance.connect(alice).burnFrom(owner.address, amount)).to.be.revertedWith(
                "ERC20: insufficient allowance"
            );
        });

        it("Maximum approval should not change while BurnFrom", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner, alice } = singers
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
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner } = singers
            expect(await instance.owner()).eq(owner.address, "initial owner does not match");

            await expect(instance.renounceOwnership()).to.be.emit(
                instance, "OwnershipTransferred"
            ).withArgs(owner.address, ethers.ZeroAddress);

            expect(await instance.owner()).eq(ethers.ZeroAddress, "owner should be zero");
        });

        it("Change owner should change state and emit event", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { owner, alice } = singers;
            expect(await instance.owner()).eq(owner.address, "initial owner does not match");

            await expect(instance.transferOwnership(alice.address)).to.be.emit(
                instance, "OwnershipTransferred"
            ).withArgs(owner.address, alice.address);

            expect(await instance.owner()).eq(alice.address, "owner does not match");
        });

        it("only old owner can change or renounce owner", async () => {
            const { instance, singers } = await loadFixture(deployTokenFixture);
            const { alice, bob } = singers;
            await expect(instance.connect(alice).transferOwnership(bob.address)).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
            await expect(instance.connect(alice).renounceOwnership()).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });
    });

    // describe("Mintable unit test", function () {
    //     if (!config.Mintable) {
    //         return;
    //     }

    //     it("Only owner can mint token", async () => {
    //         const { instance, singers } = await loadFixture(deployTokenFixture);
    //         const { bob, alice } = singers
    //         await expect(instance.connect(alice).mint(bob.address, 10000)).to.be.revertedWith(
    //             "Ownable: caller is not the owner"
    //         );
    //     });

    //     it("mint token can change supply and balance", async () => {
    //         const { instance, singers } = await loadFixture(deployTokenFixture);
    //         const { alice } = singers
    //         await expect(instance.mint(alice.address, 10000)).to.be.emit(
    //             instance, "Transfer"
    //         ).withArgs(ethers.ZeroAddress, alice.address, 10000);
    //         expect(await instance.balanceOf(alice.address)).eq(10000, "Balance of alice does not match");
    //         expect(await instance.totalSupply()).eq(meta.initSupply + convert(10000), "TotalSupply does not match");
    //     });
    // });

    // describe("Pausable unit test", function () {
    //     if (!config.Pausable) {
    //         return;
    //     }

    //     it("Only owner can pause transfer", async () => {
    //         const { instance, alice } = await loadFixture(deployTokenFixture);
    //         await expect(instance.connect(alice).pause()).to.be.revertedWith(
    //             "Ownable: caller is not the owner"
    //         );

    //         await expect(instance.connect(alice).unpause()).to.be.revertedWith(
    //             "Ownable: caller is not the owner"
    //         );
    //     });

    //     it("Pause and unpause should change state and emit event", async () => {
    //         const { instance, owner } = await loadFixture(deployTokenFixture);
    //         expect(await instance.paused()).to.be.false;

    //         await expect(instance.pause()).to.be.emit(
    //             instance, "Paused"
    //         ).withArgs(owner.address);

    //         expect(await instance.paused()).to.be.true;
    //         await expect(instance.pause()).to.be.revertedWith("Pausable: paused");

    //         await expect(instance.unpause()).to.be.emit(
    //             instance, "Unpaused"
    //         ).withArgs(owner.address);

    //         expect(await instance.paused()).to.be.false;
    //         await expect(instance.unpause()).to.be.revertedWith("Pausable: not paused");
    //     });

    //     it("TokenTransfer should be failed while paused", async () => {
    //         const { instance, owner, alice } = await loadFixture(deployTokenFixture);
    //         await instance.pause();

    //         await expect(instance.transfer(alice.address, 10000)).to.be.revertedWith(
    //             "ERC20Pausable: token transfer while paused"
    //         );

    //         await instance.approve(alice.address, 100000);
    //         await expect(instance.connect(alice).transferFrom(owner.address, alice.address, 1000))
    //             .to.be.revertedWith("ERC20Pausable: token transfer while paused");
    //     });
    // });
});
