## 学习记录

userInfo{
amount // 当前用户质押的代币总量
rewardDebt  
}

PoolInfo{
lpToken
allocPoint
lastRewardBlock
accSushiPerShare
}

constructor 中传入的几个参数：

-   startBlock：当时 sushi 开始被 mine 的区块 sushiPerBlock：sushi 代币每个区块被创建的数量
-   devaddr：开发者地址
-   sushi：sushi 代币地址
-   bonusEndBlock：
-   sushiPerBlock：sushi 在每个区块被 create 的数量

function add（添加池子）

1. 更新所有的池子（调用 massUpdatePools）
2. 增加记录的总权重 totalAllocPoint
3. 将当前添加的池子 push 到 poolInfo 中，初始时池子中的 accSushiPerShare 变量默认为 0

function set（更新池子的权重-allocPoint）

1. 根据池子的 pid 更新池子的 allocPoint 变量信息
2. 更新总权重 totalAllocPoint

function deposit（用户质押）

1. 更新用户当前质押的池子 updatePool(\_pid)

2. 根据记录用户信息中的 amount 变量计算本次本次质押之前用户的奖励

    pending = user.amount \* pool.accSushiPerShare / 1e12 - user.rewardDebt

    - user.amount：本次质押之前用户的质押数量，如果是第一质押则为 0

    - pool.accSushiPerShare：

        在更新池子的时候这个变量会更新，第一次 updatePool 中 pool.accSushiPerShare = sushiReward.mul(1e12).div(lpSupply)

        其中 sushiReward = multiplier.mul(sushiPerBlock).mul(pool.allocPoint).div(totalAllocPoint)

        ​ lpSupply 是当前池子质押代币的总量

        也就是：上次的发奖励到这次的区块数量 _ 每个区块的 sushiPerBlock 数量 _ 当前池子在所有的池子中分配权重的占比

        总结来说就是：

        - sushiReward 是上次更新到这次更新这段时间内积累的 sushi 奖励总量
        - pool.accSushiPerShare 是这个池子中每一个单位的质押代币可以分配到多少 sushi 奖励（从上次发奖励到这次更新奖励之间的积累 sushi 奖励总量/总的质押代币数量）

    - user.rewardDebt 是记录的当前用户在从上一次到当前这个时间段中间应该领取的 sushi 奖励

3. 计算出 pending 的奖励后将奖励发送给用户

4. 用户质押：将指定数量的质押代币转移到当前合约中

5. 更新用户记录的 amount 和 rewardDebt

function updatePool（更新池子 --> 主要是根据当前现有的数据计算出最新的，并且 mint 出需要发放的奖励代币）

1. 获取当前合约中目标质押代币的总量，如果还没有人质押，就不需要后续的操作，记录 pool.lastRewardBlock 变量后直接返回。
2. 计算出 sushiReward，也就是上次更新到这次更新这段时间内积累的 sushi 奖励总量
3. 直接 mint 出计算数量的 sushi 代币
4. 更新 pool.accSushiPerShare 变量： pool.accSushiPerShare.add( sushiReward.mul(1e12).div(lpSupply) );
5. 更新 pool.lastRewardBlock 变量，记录为本次更新的区块

function withdraw（提取质押代币）

1. 如果当前用户的 user.amount 小于提取目标数量的代币则直接返回
2. 更新池子 updatePool(\_pid)
3. 计算 pendingReward 并且将这个数量的奖励代币发给用户
4. 分别更新 user.amount，user.rewardDebt
5. 将目标数量的质押代币返还给用户

function emergencyWithdraw（紧急提币函数-一般都需要有一个）

1. 直接将调用者在指定池子中所有的质押代币都转移给用户
2. 将当前用户记录的两个变量设置为 0

## MasterChef 代码重点

1. 奖励更新，任何用户每操作一次，都要更新池子的奖励以便发放给用户，所以都会调用`updatePool`函数。

2. 奖励计算精度放大，

    ```solidity
    pool.accSushiPerShare = pool.accSushiPerShare.add(
        sushiReward.mul(1e12).div(lpSupply)
    );
    ```

    这里将精度放大了 1e12 倍，如果不放大，由于除法是地板除，当`sushiReward`较小时，这里始终为 0 值。注意，部分代币可能要放大 1e18 倍（因为有的代币精度为 6，所以导致 sushiReward 较小）。

3. 逻辑顺序，先更新用户奖励，再更新用户数量，最后更新用户债务。

4. 这里质押时未判断资产质押前后合约内代币余额差是否和质押数量相同，如果有通缩性代币，例如质押 5 个，转进来后只有 4 个，那么第一是数量不对，第二奖励计算分母为`lpSupply = pool.lpToken.balanceOf(address(this))`，会导致其变得很小，形成攻击（真实案例）

5. 用户本金 100%安全，因为在`updatePool`里会进行`sushi.mint`操作，假定其调用失败了，则用户无法进行任何操作（任何操作都会调用 updatePool 函数，本金无法取出。因此，Sushi 增加了一个紧急提币函数，`emergencyWithdraw`，用来在这种情况下用户放弃奖励，提取本金。

6. 重入攻击，在`emergencyWithdraw`函数和`withdraw`等函数中，假定相关代币为具有回调功能的 ERC677 代币，则可形成重入攻击。解决方案是将状态更新放在代币发送之前。

7. 危险函数`migrate`，虽然是管理员可以设置，但万一管理员权限丢了，则可以直接将所有资金全部偷走
