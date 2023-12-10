const {
  loadFixture,
  impersonateAccount
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { upgrades } = require("hardhat")

async function deployContract(name, args, options) {
  const contractFactory = await ethers.getContractFactory(name, options)
  return await contractFactory.deploy(...args)
}

async function contractAt(name, address) {
  const contractFactory = await ethers.getContractFactory(name)
  return await contractFactory.attach(address)
}

async function prepareLenderPool(wbnb) {
  const wbnb_user = "0x98cF4F4B03a4e967D54a3d0aeC9fCA90851f2Cca"
  await impersonateAccount(wbnb_user);
  const user_signer = await ethers.getSigner(wbnb_user)
  const MockLenderPool = await ethers.getContractFactory("MockLenderPool")
  const lenderPool = await MockLenderPool.deploy(wbnb_user)
  const depositAmount = ethers.parseEther("100")
  await wbnb.connect(user_signer).approve(lenderPool.target, depositAmount)
  await lenderPool.connect(user_signer).deposit(wbnb.target, depositAmount)
  return lenderPool;
}

describe("Lock", function () {
  let add1, add2;
  async function deployOneYearLockFixture() {
    [add1, add2] = await ethers.getSigners();
    const wbnb = await contractAt("WBNB", "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c")
    const bitx = await contractAt("BITX", "0x668935b74cd1683c44dc3e5dfa61a6e0b219b913")
    const grok = await contractAt("GROKXAI", "0xf875aF40467Bd46Bb78df8dc9BF805E04e6C11B3")
    // token0:bitx - token1:wbnb
    const bitx_wbnb_pair = await contractAt("PancakePair", "0x65B823d83710f816B60Be9129b16937c3587e257") // https://coinmarketcap.com/dexscan/bsc/0x65b823d83710f816b60be9129b16937c3587e257/
    // token0:wbnb - token1:grok
    const grok_wbnb_pair = await contractAt("PancakePair", "0xcA5c44DFef71975dC92CCa1216CfA97EE9815955")
    // token0:bitx - token1:grok
    const bitx_grok_pair = await contractAt("PancakePair", "0x813fdd385d1bf97F4CBa7c18689135baa419A391")

    // const wbnb_decimals = await wbnb.decimals() // 18
    // const bitx_decimals = await bitx.decimals() // 9 
    // const grok_decimals = await grok.decimals() // 9
    // const bitx_wbnb_reserves = await bitx_wbnb_pair.getReserves()
    // const wbnb_per_bitx = bitx_wbnb_reserves[1] / (bitx_wbnb_reserves[0])
    // const bitx_per_wbnb = bitx_wbnb_reserves[0] / bitx_wbnb_reserves[1]
    // const grok_wbnb_reserves = await grok_wbnb_pair.getReserves()
    // const wbnb_per_grok = grok_wbnb_reserves[0] / (grok_wbnb_reserves[1])
    // const grok_per_wbnb = (grok_wbnb_reserves[1]) / grok_wbnb_reserves[0]
    // const bitx_grok_reserves = await bitx_grok_pair.getReserves()
    // const bitx_per_grok = bitx_grok_reserves[0] / bitx_grok_reserves[1]
    // const grok_per_bitx = bitx_grok_reserves[1] / bitx_grok_reserves[0]
    // const arbitrager = await deployContract("Arbitrager", [lenderPool.target, wbnb.target, bitx.target, grok.target, bitx_wbnb_pair.target, bitx_grok_pair.target, grok_wbnb_pair.target])

    // const panCakeSwap = await deployContract("PanCakeSwap", [])
    const PancakeSwap = await ethers.getContractFactory("PanCakeSwap")
    const panCakeSwap = await upgrades.deployProxy(PancakeSwap, [])
    await panCakeSwap.waitForDeployment()

    const base_load = ethers.parseEther("0.1")
    const swapParamsWithoutPay = {
      base_token: wbnb.target,
      pair0: bitx_wbnb_pair.target,
      tax_rate0: 5,
      middle_pair: bitx_grok_pair.target,
      pair1: grok_wbnb_pair.target,
      tax_rate1: 5,
      base_load
    }

    const rewards = await panCakeSwap.cal_three_pair_reward(swapParamsWithoutPay)

    console.log(rewards);
    console.log(ethers.formatEther(rewards[0]));

    const swapParams = {
      base_token: wbnb.target,
      pair0: bitx_wbnb_pair.target,
      middle_pair: bitx_grok_pair.target,
      pair1: grok_wbnb_pair.target,
      base_load,
      base_pay: rewards[1],
      tokenA_pay: rewards[2],
      tokenB_pay: rewards[3]
    }

    console.log(await wbnb.balanceOf(add1.address));
    await panCakeSwap.swap(swapParams)
    console.log(await wbnb.balanceOf(add1.address));

    // 0.1  168955795171966n
    // 0.09 170196401251203n
    // 0.08 167400236975765n


    return { wbnb, bitx, grok, bitx_wbnb_pair, grok_wbnb_pair, bitx_grok_pair };
  }

  describe("Deployment", function () {
    it("Should set the right unlockTime", async function () {
      const { wbnb, bitx, grok, bitx_wbnb_pair, grok_wbnb_pair, bitx_grok_pair } = await loadFixture(deployOneYearLockFixture);
      // console.log(await bitx_wbnb_pair.getReserves());
      // console.log(await grok_wbnb_pair.getReserves());
      // console.log(await bitx_grok_pair.getReserves());
    });
  });
});
