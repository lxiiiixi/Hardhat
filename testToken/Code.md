# 11. Appendices

## 11.1 Unit Test

### 1. testToken.t.js

```js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("testToken", function () {
  let owner, addr1;
  const totalSupply = ethers.utils.parseUnits("350000000", 18);

  async function deployToken() {
    [owner, addr1] = await ethers.getSigners();
    const TestToken = await ethers.getContractFactory("testToken");
    const instance = await TestToken.deploy(350000000);
    return { instance };
  }

  describe("Deployment test", function () {
    it("Should set the correct metadata", async function () {
      const { instance } = await deployToken();

      expect(await instance.totalSupply()).equal(totalSupply);
      expect(await instance.balanceOf(owner.address)).equal(totalSupply);
      expect(await instance.name()).equal("token");
      expect(await instance.symbol()).equal("TK");
      expect(await instance.decimals()).equal(18);
    });
  });

  describe("Transactions test", function () {
    it("Should transfer tokens between accounts", async function () {
      const { instance } = await deployToken();
      const transferAmount = "5000";

      expect(await instance.transfer(addr1.address, transferAmount))
        .be.emit(instance, "Transfer").withArgs(owner.address, addr1.address, transferAmount);
      expect(await instance.balanceOf(addr1.address)).to.equal(transferAmount);
    });

    it("Should fail if sender doesn’t have enough tokens", async function () {
      const { instance } = await deployToken();
      const initialOwnerBalance = await instance.balanceOf(owner.address);
      await expect(instance.connect(addr1).transfer(owner.address, 1)).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      expect(await instance.balanceOf(owner.address)).to.equal(initialOwnerBalance);
    });
  });

  describe("Allowance test", function () {
    it("Should update the allowance when approving", async function () {
      const { instance } = await deployToken();
      const approveAmount = "1000"

      expect(await instance.approve(addr1.address, approveAmount))
        .to.be.emit(instance, "Approval").withArgs(owner.address, addr1.address, approveAmount);
      const allowance = await instance.allowance(owner.address, addr1.address);
      expect(allowance).to.equal(approveAmount);
      // increse allowance again
      expect(await instance.increaseAllowance(addr1.address, approveAmount))
        .to.be.emit(instance, "Approval").withArgs(owner.address, addr1.address, allowance.add(approveAmount));
      expect(await instance.allowance(owner.address, addr1.address)).to.equal(allowance.add(approveAmount));
    });
  });

  describe("Burn test", function () {
    it("Should burn tokens correctly", async function () {
      const { instance } = await deployToken();
      const initialSupply = await instance.totalSupply();
      const burnAmount = "1000";

      await instance.burn(burnAmount);
      expect(await instance.totalSupply()).to.equal(initialSupply.sub(burnAmount));
      expect(await instance.balanceOf(owner.address)).to.equal(initialSupply.sub(burnAmount));
    });

    it("Should burn tokens by anyone himself", async function () {
      const { instance } = await deployToken();
      const initialSupply = await instance.totalSupply();
      const burnAmount = "1000";

      await instance.transfer(addr1.address, burnAmount)
      expect(await instance.balanceOf(addr1.address)).to.equal(burnAmount);
      await instance.connect(addr1).burn(burnAmount);
      expect(await instance.totalSupply()).to.equal(initialSupply.sub(burnAmount));
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
    });

    it("Should burnFrom tokens correctly", async function () {
      const { instance } = await deployToken();
      const initialSupply = await instance.totalSupply();
      const burnAmount = "1000";

      await instance.transfer(addr1.address, burnAmount)
      await instance.connect(addr1).approve(owner.address, burnAmount);
      await instance.burnFrom(addr1.address, burnAmount);
      expect(await instance.totalSupply()).to.equal(initialSupply.sub(burnAmount));
      expect(await instance.balanceOf(addr1.address)).to.equal(0);
    });
  });

  describe("Ownership test", function () {
    it("Should transfer and renounce ownership correctly", async function () {
      const { instance } = await deployToken();

      expect(await instance.owner()).to.equal(owner.address);
      await instance.transferOwnership(addr1.address);
      expect(await instance.owner()).to.equal(addr1.address);

      await instance.connect(addr1).renounceOwnership();
      expect(await instance.owner()).to.equal(ethers.constants.AddressZero);
    });
  });

  describe("claimStuckedER20 test", function () {
    it("Should allow the owner to claim stuck tokens", async function () {
      const { instance } = await deployToken();
      const StuckToken = await ethers.getContractFactory("testToken");
      const stuckTokenInstance = await StuckToken.deploy("1000000");
      await stuckTokenInstance.deployed();

      const ownerBalance = await stuckTokenInstance.balanceOf(owner.address);
      expect(ownerBalance).to.equal(ethers.utils.parseUnits("1000000", 18));
      // Send stuck tokens to the testToken contract
      await stuckTokenInstance.transfer(instance.address, "5000");
      expect(await stuckTokenInstance.balanceOf(owner.address)).to.equal(ownerBalance.sub("5000"));
      expect(await stuckTokenInstance.balanceOf(instance.address)).to.equal("5000");
      // Claim stuck tokens
      await instance.claimStuckedER20(stuckTokenInstance.address);
      expect(await stuckTokenInstance.balanceOf(instance.address)).to.equal("0");
      // Check the owner's balance after claiming
      expect(await stuckTokenInstance.balanceOf(owner.address)).to.equal(ethers.utils.parseUnits("1000000", 18));
    });

    it("Should only owner can claim stuck tokens", async function () {
      const { instance } = await deployToken();
      const StuckToken = await ethers.getContractFactory("testToken");
      const stuckTokenInstance = await StuckToken.deploy("1000000");
      await stuckTokenInstance.deployed();

      await stuckTokenInstance.transfer(instance.address, "5000")
      await expect(instance.connect(addr1).claimStuckedER20(stuckTokenInstance.address)).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
});
```

### 2. UnitTestOutput

```bash
  testToken
    Deployment test
      ✔ Should set the correct metadata (266ms)
    Transactions test
      ✔ Should transfer tokens between accounts (53ms)
      ✔ Should fail if sender doesn’t have enough tokens (67ms)
    Allowance test
      ✔ Should update the allowance when approving (49ms)
    Burn test
      ✔ Should burn tokens correctly (45ms)
      ✔ Should burn tokens by anyone himself (47ms)
      ✔ Should burnFrom tokens correctly (50ms)
    Ownership test
      ✔ Should transfer and renounce ownership correctly (41ms)
    claimStuckedER20 test
      ✔ Should allow the owner to claim stuck tokens (68ms)
      ✔ Should only owner can claim stuck tokens (57ms)
```

## 11.2 External Functions Check Points

### 1. File: contracts/testToken.sol

(Empty elements in the table represent things that are not required or relevant)

contract: testToken is ERC20, ERC20Burnable, Ownable

| Index | Function                              | Visibility | Permission Check | Re-entrancy Check | Injection Check | Unit Test | Notes |
| :---: | :------------------------------------ | :--------- | :--------------- | :---------------- | :-------------- | :-------- | :---- |
|   1   | claimStuckedER20(address)             | external   | onlyOwner        |                   |                 | Passed    |       |
|   2   | owner()                               | public     |                  |                   |                 | Passed    | view  |
|   3   | renounceOwnership()                   | public     | onlyOwner        |                   |                 | Passed    |       |
|   4   | transferOwnership(address)            | public     | onlyOwner        |                   |                 | Passed    |       |
|   5   | burn(uint256)                         | public     |                  |                   |                 | Passed    |       |
|   6   | burnFrom(address,uint256)             | public     |                  |                   |                 | Passed    |       |
|   7   | name()                                | public     |                  |                   |                 | Passed    | view  |
|   8   | symbol()                              | public     |                  |                   |                 | Passed    | view  |
|   9   | decimals()                            | public     |                  |                   |                 | Passed    | view  |
|  10   | totalSupply()                         | public     |                  |                   |                 | Passed    | view  |
|  11   | balanceOf(address)                    | public     |                  |                   |                 | Passed    | view  |
|  12   | transfer(address,uint256)             | public     |                  |                   |                 | Passed    |       |
|  13   | allowance(address,address)            | public     |                  |                   |                 | Passed    | view  |
|  14   | approve(address,uint256)              | public     |                  |                   |                 | Passed    |       |
|  15   | transferFrom(address,address,uint256) | public     |                  |                   |                 | Passed    |       |
|  16   | increaseAllowance(address,uint256)    | public     |                  |                   |                 | Passed    |       |
|  17   | decreaseAllowance(address,uint256)    | public     |                  |                   |                 | Passed    |       |