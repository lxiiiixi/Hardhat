const {
  time,
  loadFixture, // 可以让我们在测试中都使用相同的配置
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

// 在测试类里会定义一个部署合约的方法，然后在需要使用合约对象的地方，通过loadFixture(function) 获取部署合约的快照对象
// expect方法: 断言测试

// 标识测试的开始，其中第一个参数为测试标题，可以随便定义，第二个参数为要执行的函数体
// describe是可以嵌套使用的 一般测试会在第一个describe里定义一个合约部署方法，然后在describe里嵌套 describe，通过loadFixture(function) 获取相同合约部署快照
describe("Lock", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  // 定义了一个合约部署方法
  async function deployOneYearLockFixture() {
    const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    const ONE_GWEI = 1_000_000_000;

    const lockedAmount = ONE_GWEI;
    const unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount] = await ethers.getSigners();

    const Lock = await ethers.getContractFactory("Lock"); // 创建一个合约对象 Lock（对应了contracts目录下的合约名）
    const lock = await Lock.deploy(unlockTime, { value: lockedAmount }); // deploy方法进行合约部署，括号内为合约部署时所需的初始化值，如果合约不需要可以不填写

    return { lock, unlockTime, lockedAmount, owner, otherAccount };
  }

  // 测试方法
  describe("Deployment", function () {
    // 使用 it 进行测试 第一个参数为测试描述 第二个参数为具体方法实现
    it("Should set the right unlockTime", async function () {
      // 获取合约创建快照对象，从对象中获取到合约对象以及合约部署方法里定义的解锁时间
      const { lock, unlockTime } = await loadFixture(deployOneYearLockFixture);
      // 使用expect进行断言，判断合约对象里面存储的解锁时间是否与合约部署方法里定义的解锁时间相等
      expect(await lock.unlockTime()).to.equal(unlockTime);
      expect(await lock.testConsole()).to.be.equal(true);
    });

    it("Should set the right owner", async function () {
      const { lock, owner } = await loadFixture(deployOneYearLockFixture);

      expect(await lock.owner()).to.equal(owner.address);
    });

    it("Should receive and store the funds to lock", async function () {
      const { lock, lockedAmount } = await loadFixture(
        deployOneYearLockFixture
      );

      expect(await ethers.provider.getBalance(lock.address)).to.equal(
        lockedAmount
      );
    });

    it("Should fail if the unlockTime is not in the future", async function () {
      // We don't use the fixture here because we want a different deployment
      const latestTime = await time.latest();
      const Lock = await ethers.getContractFactory("Lock");
      await expect(Lock.deploy(latestTime, { value: 1 })).to.be.revertedWith(
        "Unlock time should be in the future"
      );
    });
  });

  describe("Withdrawals", function () {
    describe("Validations", function () {
      it("Should revert with the right error if called too soon", async function () {
        const { lock } = await loadFixture(deployOneYearLockFixture);

        await expect(lock.withdraw()).to.be.revertedWith(
          "You can't withdraw yet"
        );
      });

      it("Should revert with the right error if called from another account", async function () {
        const { lock, unlockTime, otherAccount } = await loadFixture(
          deployOneYearLockFixture
        );

        // We can increase the time in Hardhat Network
        await time.increaseTo(unlockTime);

        // We use lock.connect() to send a transaction from another account
        await expect(lock.connect(otherAccount).withdraw()).to.be.revertedWith(
          "You aren't the owner"
        );
      });

      it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
        const { lock, unlockTime } = await loadFixture(
          deployOneYearLockFixture
        );

        // Transactions are sent using the first signer by default
        await time.increaseTo(unlockTime);

        await expect(lock.withdraw()).not.to.be.reverted;
      });
    });

    describe("Events", function () {
      it("Should emit an event on withdrawals", async function () {
        const { lock, unlockTime, lockedAmount } = await loadFixture(
          deployOneYearLockFixture
        );

        await time.increaseTo(unlockTime);

        await expect(lock.withdraw())
          .to.emit(lock, "Withdrawal")
          .withArgs(lockedAmount, anyValue); // We accept any value as `when` arg
      });
    });

    describe("Transfers", function () {
      it("Should transfer the funds to the owner", async function () {
        const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
          deployOneYearLockFixture
        );

        await time.increaseTo(unlockTime);

        await expect(lock.withdraw()).to.changeEtherBalances(
          [owner, lock],
          [lockedAmount, -lockedAmount]
        );
      });
    });
  });
});


// 编译：npx hardhat compile
// 测试：npx hardhat test