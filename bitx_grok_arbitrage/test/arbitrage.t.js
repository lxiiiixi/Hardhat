const { upgrades } = require("hardhat")

async function contractAt(name, address) {
    const contractFactory = await ethers.getContractFactory(name)
    return await contractFactory.attach(address)
}

describe("Arbitrage", function () {
    let add1;
    const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
    // const bitx = "0x668935b74cd1683c44dc3e5dfa61a6e0b219b913"
    // const grok = "0xf875aF40467Bd46Bb78df8dc9BF805E04e6C11B3"

    const bitx_wbnb_pair = "0x65B823d83710f816B60Be9129b16937c3587e257"  // token0:bitx - token1:wbnb
    const grok_wbnb_pair = "0xcA5c44DFef71975dC92CCa1216CfA97EE9815955"  // token0:wbnb - token1:grok
    const bitx_grok_pair = "0x813fdd385d1bf97F4CBa7c18689135baa419A391"

    async function deploy() {
        [add1] = await ethers.getSigners();

        const Arbitrager = await ethers.getContractFactory("Arbitrager")
        const instance = await upgrades.deployProxy(Arbitrager, [])
        const wbnbInstance = await contractAt("WBNB", wbnb)

        const baseAmount = ethers.parseEther("0.09")
        const swapCalculateParams = {
            baseToken: wbnb,
            pair0: bitx_wbnb_pair,
            pair1: bitx_grok_pair,
            pair2: grok_wbnb_pair,
            taxRate0: 5,
            taxRate1: 5,
            baseAmount
        }
        const result = await instance.calculateRewardAndAmountIn(swapCalculateParams)
        console.log(baseAmount, result);
        // 计算结果中需要最了终拿到的 baseAmount 数量是大于 result[1] 也就是要保证更小的 baseTokenShouldPay 数量在最中换到 baseAmount

        const swapParams = {
            baseToken: wbnb,
            pair0: bitx_wbnb_pair,
            pair1: bitx_grok_pair, // pair2 表示除开 baseToken 以外的 tokenA/tokenB
            pair2: grok_wbnb_pair,
            baseAmount,
            baseTokenShouldPay: result[1],
            tokenAShouldPay: result[2],
            tokenBShouldPay: result[3]
        }

        console.log(await wbnbInstance.balanceOf(add1.address));
        await instance.swap(swapParams)
        console.log(await wbnbInstance.balanceOf(add1.address));

        // 三个 token: tokenA tokenB baseToken
        // 1. tokenA in 并且在拿到 baseToken 但是还没有转入 tokenA 的时候利用回调执行下面的操作
        // 2. 转入上面基于 tokenA in 能拿到的最多的 baseToken 数量到另一个与 baseToken 相关联的 pair，并且拿到相应的 tokenB
        // 3. 拿到 tokenB 之后用所有的 tokenB 去转换得到 baseToken
        // 4. 将 baseToken 还给最开始第一步中的 pair

        // 1. baseAmount 个 baseToken Out ==need==> tokenAShouldPay 个 tokenA In
        // 2. tokenBShouldPay 个 tokenB Out ==need==> baseAmount 个 baseToken In
        // 3. tokenBShouldPay 个 tokenB In ==get==> baseTokenShouldPay 个 baseToken Out

        // Q1: 如何确定 bitx 还是 grok 是作为 token0/token1 呢，也就是说 如何确认 pair1 和 pair2 的代币顺序呢？
        // 主要分析哪个代币购买wbnb价格更低，哪个代币的卖出wbnb的价格更高，保证以低价买入后又以高价卖出。
    }

    describe("Deployment", function () {
        it("Should set the right unlockTime", async function () {
            await deploy()
        });
    });
});
