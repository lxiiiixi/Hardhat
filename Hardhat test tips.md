## 比较数值的小于、等于、大于

> https://docs.ethers.org/v5/api/utils/bignumber/#BigNumber--BigNumber--methods--comparison-and-equivalence

expect(A).to.gte(B) // A >= B
expect(A).to.equal(B) // A = B
expect(A).to.lte(B) // A <= B

## 在一次合约方法调用时测试多个事件参数

```js
const txPromise = SwapInstance.connect(user1).addLiquidity(
    PT1Instance.address,
    amount,
    user1.address,
    0
);
// 这里返回的是一个 pending 状态的 Promise 对象
await txPromise; // 为了其他数据的测试，保证等待这里的异步操作结束
// 但是很奇怪的点暂时记录一下：有时候不await等待结果返回，得到的也是更新之后的数据，但是有的时候如果不加这一句，得到的数据就不是更新后的也就是函数还没有执行完，或许是因为函数的复杂程度吗，这里的疑惑还不确定？

// 测试上面函数调用中触发的两个事件
await expect(txPromise)
    .to.emit(SwapInstance, "PoolAmountUpdated")
    .withArgs(PT1Instance.address, amount * 2, 0, amount, amountOsd);
await expect(txPromise)
    .to.emit(SwapInstance, "AddLiquidity")
    .withArgs(PT1Instance.address, amount, liquidityOutAmount, user1.address);
```

## 区块和时间戳

在 solidity 中 block.timestamp 变量获取的时间戳是以秒为单位的整数。这个时间戳代表当前区块的时间戳，也就是当前交易被打包进的区块的时间戳。（也就是说每一个区块中所有交易通过 block.timestamp 获取的时间戳都相同，因为它们都是基于同一个区块的时间戳计算得出的，这些交易都是在同一时刻被矿工打包进区块的。）

> 所以往往函数调用时获取的时间戳是会比合约中通过 block.timestamp 获取到的时间戳小那么几秒（目前的个人理解是这样）
> 所以测试时通过 Date 对象获得和传入的也要是秒级的

```js
function getNowTimeStamp() {
    return Math.floor(new Date().getTime() / 1000);
}
```

## 一些知识点记录

-   `block.timestamp`: 在以太坊智能合约中，block.timestamp 是一个全局变量，用于表示当前区块的时间戳（即区块的创建时间）。当您调用智能合约中的方法时，block.timestamp 的值在整个合约执行过程中是不变的，即在同一个交易中，不管调用了多少次方法，block.timestamp 的值都是相同的。

这是因为在一个区块中，所有的交易被打包在一起，执行同一个区块的代码时，它们共享相同的区块信息，包括 block.timestamp 的值。在一个区块中的所有交易执行过程中，block.timestamp 不会随着方法调用的次数而改变。

## 错误警惕 await 和 expect 的顺序

### 正确写法

```js
// emit
await expect(StakeInstance.deposit(LP1Instance.address, depositAmount))
    .to.emit(StakeInstance, "Deposit")
    .withArgs(admin.address, LP1Instance.address, depositAmount);

// revert
await expect(
    StakeInstance.connect(user1).setPoolInfo(LP1Instance.address, 1000, 100000000)
).to.revertedWith("Ownable: caller is not the owner");

// equal
expect(await Reward2Instance.balanceOf(StakeInstance.address)).to.equal(0);
```

#### 错误写法

```js
// ！！！！这样也会通过的错误写法：
expect(await instance.transfer(owner.address, transferAmount))
    .be.emit(instance, "Transfer1")
    .withArgs(owner.address, owner.address, transferAmount);
```
