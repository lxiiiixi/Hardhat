const { ethers } = require("ethers");

const bsc_rpc_url = "https://autumn-dawn-arm.bsc.discover.quiknode.pro/7091c37d7b6798e83e23207a78ee6e8d9ad0624d/"
const provider = new ethers.JsonRpcProvider(bsc_rpc_url)
const proxy_address = "0xba2ae424d960c26247dd6c32edc70b295c744c43"
const admin_slot = BigInt("0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103")
const impl_slot = BigInt("0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc")

const abi = [
    "function admin() view returns(address)",
    "function implementation() view returns(address)"
]
const proxy_contract = new ethers.Contract(proxy_address, abi, provider)

async function checkResult(admin_address, impl_address) {
    try {
        let admin = await proxy_contract.admin({
            "from": admin_address
        })
        console.log("check admin_address:", admin === admin_address)
        let impl = await proxy_contract.implementation({
            "from": admin_address
        })
        console.log("check impl_address:", impl === impl_address)
    } catch (e) {
        console.log(e)
    }
}

async function start() {
    const admin_info = await provider.getStorage(proxy_address, admin_slot)
    console.log("admin_info:", admin_info)
    const admin_address = ethers.getAddress("0x" + admin_info.substring(26))
    console.log("admin_address:", admin_address)
    console.log()

    const impl_info = await provider.getStorage(proxy_address, impl_slot)
    console.log("impl_info:", impl_info)
    const impl_address = ethers.getAddress("0x" + impl_info.substring(26))
    console.log("impl_address:", impl_address)
    console.log()
    checkResult(admin_address, impl_address)
}

start()

/**
 * admin_info: 0x000000000000000000000000d2f93484f2d319194cba95c5171b18c1d8cfd6c4
admin_address: 0xD2f93484f2D319194cBa95C5171B18C1d8cfD6C4

impl_info: 0x000000000000000000000000ba5fe23f8a3a24bed3236f05f2fcf35fd0bf0b5c
impl_address: 0xBA5Fe23f8a3a24BEd3236F05F2FcF35fd0BF0B5C

check admin_address: true
check impl_address: true
 */