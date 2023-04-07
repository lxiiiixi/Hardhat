const { ethers } = require("hardhat");
async function start() {
    const frax = "0x853d955aCEf822Db058eb8505911ED77F175b99e";
    const FRAXStablecoin = await ethers.getContractFactory("FRAXStablecoin");
    const url = "https://eth-mainnet.g.alchemy.com/v2/Z2xliWVjYToNgU62-55w8-UuY28l79Zq"

    const provider = new ethers.providers.JsonRpcProvider(url)
    const instance = FRAXStablecoin.attach(frax).connect(provider)
    const fxs_price = await instance.fxs_price();
    console.log(fxs_price);
}
start()