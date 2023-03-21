const { expect } = require("chai");
const { ethers } = require("hardhat");

// DOGECEO
describe("DogeCeo", function () {
  async function deployTokens(ARGS) {
    const DogeCeoToken = await ethers.getContractFactory("DOGECEO");
    TokenInstance = await DogeCeoToken.deploy("0x10ED43C718714eb63d5aA57B78B54704E256024E")
  }

  beforeEach(async () => {
    await deployTokens();
  })

  describe("Deployment", function () {
    it("Should set the right unlockTime", async function () {

    });
  });
});
