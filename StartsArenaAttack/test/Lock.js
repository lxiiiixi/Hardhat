const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { formatEther } = require("ethers");
const { ethers } = require("hardhat");

describe("Attack", function () {
  let attacker;
  const proxyContractAddress = "0xA481B139a1A654cA19d2074F174f17D7534e8CeC"

  async function deploy() {
    // const proxyInstance = await ethers.getContractAt("TransparentUpgradeableProxy", proxyContractAddress);
    [attacker] = await ethers.getSigners()
    const Attacker = await ethers.getContractFactory("AttackerMain")
    const amount = ethers.parseEther("1"); // 1 AVAX
    console.log(formatEther(await ethers.provider.getBalance(attacker.address)));
    const attackerInstance = await Attacker.deploy(proxyContractAddress, attacker.address, { value: amount })
    console.log(formatEther(await ethers.provider.getBalance(attacker.address)));
    return { attackerInstance };
  }

  describe("Deployment", function () {
    it("Attack", async function () {
      const { attackerInstance } = await loadFixture(deploy);
      // const amount = ethers.parseEther("1"); // 1 AVAX
      // const attackerAddress = attackerInstance.target
      // console.log(await ethers.provider.getBalance(attackerAddress));
      // await attackerInstance.attack({ value: amount })
      // await attackerInstance.sellShares()
      // console.log(await ethers.provider.getBalance(attackerAddress));
    });
  });
});
