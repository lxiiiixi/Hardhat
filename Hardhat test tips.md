## 比较数值的小于、等于、大于

expect(A).to.gt(B) // A > B
expect(A).to.equal(B) // A = B
expect(A).to.lte(B) // A < B

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
