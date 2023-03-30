const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

// const hardhat = require("hardhat")
// for (let i in hardhat) {
//   console.log(i);
// }

// DOGECEO
// uniswapV2中交易是先发送给路由合约，再由路由合约调用factory合约或者pair合约
describe("DogeCeo", function () {
  const DEAD_ADDRESS = "0x000000000000000000000000000000000000dEaD";
  const MARKET_ADDRESS = "0xaa313121bd678d01880dad8Aa68E9B4fa8848DFD";
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";


  async function deployUniswapAndDogoCeo() {
    const [owner, Alice, Bob] = await ethers.getSigners();
    // 1. 部署 ETH 合约
    const WETH9 = await ethers.getContractFactory("WETH9");
    const weth = await WETH9.deploy();
    // 2. 部署 UniswapV2Factory
    const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factory = await UniswapV2Factory.deploy(owner.address);
    // 3. 部署 UniswapV2Router
    const UniswapV2Router = await ethers.getContractFactory("UniswapV2Router02");
    const router = await UniswapV2Router.deploy(factory.address, weth.address);
    // 计算得到hex值 log出来在Router中替换掉
    // const UniswapV2Pair = await ethers.getContractFactory("UniswapV2Pair");
    // let initCode = ethers.utils.keccak256(UniswapV2Pair.bytecode);
    // console.log(initCode);

    // 4. 部署 DogeCeo
    const DogeCeo = await ethers.getContractFactory("DOGECEO");
    const instance = await DogeCeo.deploy(router.address);

    // 5. 添加流动性
    let balance = await instance.balanceOf(owner.address);
    let amount = balance.div(2); // 代币总量的一半
    await instance.approve(router.address, ethers.constants.MaxInt256);
    await router.addLiquidityETH(instance.address, amount, 1, 1, owner.address, 9876543210, { value: ethers.utils.parseEther("100") }); // 100 ETH 对应的 wei 数量即 100 * 10^18 wei

    // 6. 获得交易对地址
    const pair = await factory.getPair(instance.address, weth.address);

    // ethers.utils.parseUnits(value, decimals)
    // 将以太单位转换为指定精度的最小单位,或者将其他数字转换为指定精度的最小单位,通常用于将以太单位转换为 wei 单位
    let supply = ethers.utils.parseUnits("420", 15);
    let unit = ethers.utils.parseUnits("1.0", 9);
    supply = supply.mul(unit);

    return { router, pair, owner, Alice, Bob, instance, supply };
  }

  describe("Deployment", function () {
    it("Owner should be the deployer", async function () {
      const { owner, instance } = await loadFixture(deployUniswapAndDogoCeo);
      expect(await instance.owner()).to.equal(owner.address);
    })

    it("Checke the meta data and initial supply", async function () {
      const { owner, supply, instance, pair } = await loadFixture(deployUniswapAndDogoCeo);
      expect(await instance.name()).to.equal("Doge CEO");
      expect(await instance.symbol()).to.equal("DOGECEO");
      expect(await instance.decimals()).to.equal(9);
      expect(await instance.totalSupply()).to.equal(supply);
      expect(await instance.balanceOf(owner.address)).to.equal(supply.div(2));
      expect(await instance.balanceOf(pair)).to.equal(supply.div(2));
    })

    it("Exclude should be set", async function () {
      const { owner, supply, instance, pair } = await loadFixture(deployUniswapAndDogoCeo);
      expect(await instance.isExcludedFromReward(pair)).to.true;
      expect(await instance.isExcludedFromReward(DEAD_ADDRESS)).to.true;
      expect(await instance.isExcludedFromFee(instance.address)).to.true;
      expect(await instance.isExcludedFromFee(owner.address)).to.true;
      expect(await instance.isExcludedFromFee(MARKET_ADDRESS)).to.true;
      expect(await instance.isExcludedFromFee(DEAD_ADDRESS)).to.true;
    })
  })

  describe("RenounceOwnerShip can be successful", async function () {
    it("Only owner can renounceOwnership", async function () {
      const { instance, Alice } = await loadFixture(deployUniswapAndDogoCeo);
      await expect(instance.connect(Alice).renounceOwnership()).to.revertedWith("Ownable: caller is not the owner")
    })

    it("Should emit the event", async function () {
      const { instance, owner } = await loadFixture(deployUniswapAndDogoCeo);
      await expect(instance.renounceOwnership()).to.emit(instance, "OwnershipTransferred").withArgs(owner.address, ZERO_ADDRESS);
    })
  })

  describe("OnlyOwner test", async function () {
    it("Test excludeFromReward and includeInReward", async function () {
      const { instance, Alice } = await loadFixture(deployUniswapAndDogoCeo);
      // 将 Alice 的地址添加到 _excluded 列表中
      expect(await instance.isExcludedFromReward(Alice.address)).to.false;
      await instance.excludeFromReward(Alice.address);
      expect(await instance.isExcludedFromReward(Alice.address)).to.true;
      expect(await instance.isExcludedFromReward(Alice.address)).to.revertedWith("Account is already excluded");
      // 执行 includeInReward 后，Alice 的地址会从 _excluded 列表中移除
      await instance.includeInReward(Alice.address);
      expect(await instance.isExcludedFromReward(Alice.address)).to.false;
      expect(await instance.isExcludedFromReward(Alice.address)).to.revertedWith("Account is not excluded");
    })

    it("Test excludeFromFee and includeInFee", async function () {
      const { instance, Alice } = await loadFixture(deployUniswapAndDogoCeo);
      // test excludeFromFee
      expect(await instance.isExcludedFromFee(Alice.address)).to.false;
      await instance.excludeFromFee(Alice.address);
      expect(await instance.isExcludedFromFee(Alice.address)).to.true;
      // test excludeFromFee twice 
      await instance.excludeFromFee(Alice.address);
      expect(await instance.isExcludedFromFee(Alice.address)).to.true;

      // test includeInFee
      await instance.includeInFee(Alice.address);
      expect(await instance.isExcludedFromFee(Alice.address)).to.false;
    })

    it("Test bulkExcludeFee", async function () {
      const { instance, Alice, Bob } = await loadFixture(deployUniswapAndDogoCeo);
      let accounts = [Alice.address, Bob.address];
      // add
      await instance.bulkExcludeFee(accounts, true);
      expect(await instance.isExcludedFromFee(Alice.address)).to.true;
      expect(await instance.isExcludedFromFee(Bob.address)).to.true;
      // remove
      await instance.bulkExcludeFee(accounts, false);
      expect(await instance.isExcludedFromFee(Alice.address)).to.false;
      expect(await instance.isExcludedFromFee(Bob.address)).to.false;
    })
  })

  describe("Approve test", async function () {
    it("Approve should emit event", async function () {
      const { instance, Alice, Bob } = await loadFixture(deployUniswapAndDogoCeo);
      // 授权后allowance会增加
      await expect(instance.connect(Alice).approve(Bob.address, 100000)).to.emit(instance, "Approval").withArgs(Alice.address, Bob.address, 100000);
      expect(await instance.allowance(Alice.address, Bob.address)).to.equal(100000);
      // increaseAllowance test
      await expect(instance.connect(Alice).increaseAllowance(Bob.address, 200000)).to.emit(instance, "Approval").withArgs(Alice.address, Bob.address, 300000);
      expect(await instance.allowance(Alice.address, Bob.address)).to.equal(300000);
      // decreaseAllowance test
      await expect(instance.connect(Alice).decreaseAllowance(Bob.address, 300000)).to.emit(instance, "Approval").withArgs(Alice.address, Bob.address, 0);
      expect(await instance.allowance(Alice.address, Bob.address)).to.equal(0);
    })
  })

  // ??????????
  describe("Reflection test", async function () {
    it("Test reflectionFromToken and tokenFromReflection", async function () {
      const { instance, supply } = await loadFixture(deployUniswapAndDogoCeo);
      const max = ethers.constants.MaxUint256;
      const rTotal = max.sub(max.mod(supply));
      const rate = rTotal.div(supply);
      // console.log(rTotal, rate, supply, max);
      for (let i = 0; i < 10; i++) {
        let tAmount = parseInt(Math.random() * 10000 + 10000)
        tAmount = ethers.BigNumber.from("" + tAmount)
        let rAmount = rate.mul(tAmount)
        let fee = tAmount.mul(5).div(100).mul(rate).mul(2);
        let rTransferAmount = rAmount.sub(fee);
        let v1 = await instance.reflectionFromToken(tAmount, false);
        let v2 = await instance.reflectionFromToken(tAmount, true);
        let v3 = await instance.tokenFromReflection(rAmount);
        expect(v1).to.equal(rAmount)
        expect(v2).to.equal(rTransferAmount)
        expect(v3).to.equal(tAmount)
      }
    })
  })

  describe("Test transferFrom", async function () {
    it("TransferFrom should decrease approval", async function () {
      const { instance, Alice, Bob, owner, supply } = await loadFixture(deployUniswapAndDogoCeo);
      const value = ethers.utils.parseUnits("10000", 9);
      await instance.approve(Alice.address, value);
      await expect(instance.connect(Alice).transferFrom(owner.address, Bob.address, ethers.utils.parseUnits("9000", 9))).to.emit(instance, "Transfer").withArgs(owner.address, Bob.address, ethers.utils.parseUnits("9000", 9));
      expect(await instance.allowance(owner.address, Alice.address)).to.equal(ethers.utils.parseUnits("1000", 9));
      expect(await instance.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits("9000", 9));
      expect(await instance.balanceOf(owner.address)).to.equal(supply.div(2).sub(ethers.utils.parseUnits("9000", 9)), 9);
    })
  })

  describe("Test transfer", async function () {
    it("Transfer from address of excludeFee", async function () {
      const { instance, Alice, Bob } = await loadFixture(deployUniswapAndDogoCeo);
      // test transfer
      expect(await instance.balanceOf(Alice.address)).to.equal(0);
      let value = ethers.utils.parseUnits("10000", 9);
      await instance.transfer(Alice.address, value);
      expect(await instance.balanceOf(Alice.address)).to.equal(value);

      // 需要收税
      expect(await instance.balanceOf(Bob.address)).to.equal(0);
      await instance.connect(Alice).transfer(Bob.address, value.div(2));
      expect(await instance.balanceOf(Bob.address)).to.equal(value.div(2).mul(9).div(10));

      // 不收税
      await instance.excludeFromFee(Alice.address);
      await expect(instance.connect(Alice).transfer(Bob.address, value.div(2))).to.be.emit(instance, "Transfer").withArgs(Alice.address, Bob.address, value.div(2));
    });

    it("Transfer without reward", async function () {
      const { instance, Alice, Bob } = await loadFixture(deployUniswapAndDogoCeo);
      let value = ethers.utils.parseUnits("10000", 9);
      await instance.transfer(Alice.address, value);
      await expect(instance.connect(Alice).transfer(Bob.address, value)).to.be.emit(instance, "Transfer").withArgs(Alice.address, Bob.address, value.mul(9).div(10));
      expect(await instance.balanceOf(Bob.address)).to.equal(value.mul(9).div(10));
      expect(await instance.balanceOf(instance.address)).to.equal(value.mul(5).div(100));
      // 计算reward
      let { rfi, marketing } = await instance.totFeesPaid()
      expect(rfi).to.equal(value.mul(5).div(100));
      expect(marketing).to.equal(value.mul(5).div(100));
    })

    // ？？？？？？
    it("Transfer with reward", async function () {
      const { instance, owner, Alice, Bob } = await loadFixture(deployUniswapAndDogoCeo);
      let balance = await instance.balanceOf(owner.address);
      await instance.transfer(Alice.address, balance);
      await instance.connect(Alice).transfer(Bob.address, balance);
      expect(await instance.balanceOf(Bob.address)).to.gt(balance.mul(9).div(10));
      // gt():大于  lt():小于
      // 每次交易的过程中都会有 10% 的手续费，其中 5% 用于奖励持币者，5% 用于奖励开发者
    })

    // ??????????
    it("Transfer with swap", async function () {
      const { instance, Alice, Bob, supply, pair, router } = await loadFixture(deployUniswapAndDogoCeo);
      let swapTokensAtAmount = await instance.swapTokensAtAmount();
      await instance.transfer(Alice.address, supply.div(2));
      await instance.connect(Alice).transfer(Bob.address, supply.div(2));
      let bobBalance = await instance.balanceOf(Bob.address);
      let instanceBalance = await instance.balanceOf(instance.address);
      expect(instanceBalance).gt(swapTokensAtAmount); // canSwap = true

      let pairBalance = await instance.balanceOf(pair);
      const UniswapV2Pair = await ethers.getContractFactory("UniswapV2Pair");
      const pairContract = UniswapV2Pair.attach(pair);

      let token0 = await pairContract.token0();
      let isToken0 = token0 == instance.address;

      let amount0In = isToken0 ? instanceBalance : 0;
      let amount1In = isToken0 ? 0 : instanceBalance;
      let amount0Out = isToken0 ? 0 : anyValue;
      let amount1Out = isToken0 ? anyValue : 0;
      await expect(instance.connect(Bob).transfer(Alice.address, 1)).to.be.emit(pairContract, "Swap").withArgs(router.address, amount0In, amount1In, amount0Out, amount1Out, router.address);
      expect(await instance.balanceOf(pair)).to.equal(instanceBalance.add(pairBalance));
      expect(await instance.balanceOf(Bob.address)).to.equal(bobBalance.sub(1));
      expect(await instance.totalSupply()).equal(supply);
    })
  });
});
