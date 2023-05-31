# Compound 操作详细流程

## 一、合约关系及部署

一个最小运行的Compound需要部署如下合约，其中部分合约是代理实现之间的关系。

- 部署预言机合约，这里demo可以采用`SimplePriceOracle` 合约
- 部署 COMP 代币，用来在用户操作时发奖励使用，直接将Comp代币转入相关合约
- 部署Comptroller 与 Unitroller，注意修改Comptroller合约中Comp代币的地址，Unitroller实质上是代理合约，Comptroller实际上是实现合约。两者部署完成后要进行相互设置。
- unitroller 设置预言机
- 部署利息模块`WhitePaperInterestRateModel`
- 部署市场合约（实现合约，`CErc20Delegate`）
- 欲添加的代币部署市场合约（代理合约，`CErc20Delegator`)
- 管理员添加市场，调用`_supportMarket`函数。
- 可以还要设计清算激励系数及其它参数。测试时再设置。



## 二、用户质押 mint

用户质押相对比较简单，具体操作为先授权欲质押的代币（underlying)，调用相应市场的`mint`函数，得到质押凭证（未必是1:1的关系）。

1. 用户授权

2. 用户调用`CErc20Delegator`合约中的mint函数，参数是欲质押的数量

3. CErc20Delegator委托调用`CErc20Delegate`中的`mint`函数（实际是继承自CErc20的mint函数），然后又调用继承自`CToken`合约中的`mintInternal`函数，该函数返回错误代码及实际得到的质押凭证。

4. mintInternal 函数先进行利息更新操作（所有用户操作时都会先进行此操作，该函数解读见后面部分）

5. 如果更新利息成功，则调用`mintFresh`来进行一个新的`mint`。

6. 在`mintFresh`函数之前定义了一个`MintLocalVars`结构体，方便计算（避免堆栈过深）。很多操作都有这种设计。

7. mintFresh 函数 会调用 comptroller的 mintAllowed 函数来检查是否可以质押（mint凭证）

8. mintAllowed 函数中首先判断是否暂停，然后判断质押的市场是否已经被管理员添加是（因为在此之前并没有调用市场合约，调用了也无法验证真伪，所以判断管理员是否添加了）。

9. 调用 `updateCompSupplyIndex` 函数，注释为保持飞轮移至下一个位置。注意这里是计算提供者奖励。

10. updateCompSupplyIndex 函数详情，此时有一个结构体`CompMarketState`需要注意。记录了最后更新的索引（数量）和区块，分别为uint224及uint32类型，方便放在一个插槽中

11. updateCompSupplyIndex 中，先获取该市场的状态，及当前转速（compSpeeds)及当前区块。计算区块差。

12. 如果区块差和转速均大于0，则要移动飞轮。先获取质押凭证(CToken)的发行总量，计算新增的`compAccrued = 转速 * 区块差 ` 这时转速应该是每个区块产生多少代币，很形象。转速越快产生越快。

13. 这里会计算一个比例，涉及到一个`Double`操作，看名字是双精度数，其实是将`a`扩大`10**36`再除以b，得到一个比率。如果已经有`supply`了，则是 compAccrued /supplyTokens，如果原来为0，则是初始值0. 

14. 拿上面计算得到的`rate`会更新原来的`CompMarketState`中的`index`（累积， 增加操作）

15. 更新当前市场的`CompMarketState`  区块更新到当前区块，`index`加上累积的`rate`。

16. 如果区块差大于0，而转速不为0，则飞轮不动，只是更新当前市场`CompMarketState`中的区块（说明没有累加rate)

17. 上面 `updateCompSupplyIndex`还是很好理解的。

18. mintAllowed 函数接下来调用`distributeSupplierComp`函数，其参数分别为市场合约及质押者

19. distributeSupplierComp 函数用来计算用户累积的`Comp`。

20. 获取更新后的市场状态`CompMarketState`，记录市场当前的`supplyState.index`和提供者自己的`supplierIndex`（compSupplierIndex[cToken][supplier]） 。更新用户的 supplierIndex 为当前市场的`index`。这里也没有问题。记录的临时变量是在接下来的语句中使用的。

21. 如果临时变量中用户的mantissa为0而市场的mantissa不为0，则将临时变量中用户的mantissa更新为一个初始值（保证初始值不会为0）

22. 计算 市场 index和临时变量中的Index差，就是用户获取奖励的index差（第一次会扣除初始值，类似UniswapV2中扣除初始流动性一样）。

23. 查询用户的CToken数量，supplierTokens,并计算`supplierDelta` ，注意虽然这里除了`10**18`，但由于双精度乘上了`10**36`所以这里的结果还是扩大了`10**18`.然后更新用户累积获取的`compAccrued`。从这里可以看出，飞轮转速就是各个市场产生Comp的不同速度，用户在各市场的凭证数量*`compAccrued`就是新获取的`Comp`代币的数量，和Sushi的质押挖矿类似。这里也可以解释为什么`updateCompSupplyIndex`函数中也是操作的`CToken`的数量。

24. 结合`updateCompSupplyIndex`函数来看，虽然在`updateCompSupplyIndex`中计算了`compAccrued`，但并没有更新对应的值，而是根据`compAccrued` 更新了当前市场状态，相当于质押挖矿中根据出块奖励更新每份质押的奖励，然后每个用户再根据更新的市场状态和自己的份额来更新自己的Comp奖励。总体看这个设计和Sushi的质押挖矿很像，不过更复杂。

25. mintAllowed 返回没有错误，通过，回到CToken的`mintFresh`函数。从这里可以看出，`mintAllowed`不仅判断是否可以质押，同时还更新了市场的奖励及用户的奖励。

26. 再次验证市场合约的区块高度为当前区块（如果不相等，会在更新利息时更新）

27. 通过`exchangeRateStoredInternal`函数获取本市场的兑换率（这里采用的余额相比，容易被操纵）

28. exchangeRateStoredInternal 函数详细情况，如果没有质押过，则是初始兑换比例（创建池子时设置的）如果质押过，则进行如下计算 `exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply`  (当前余额 + 所有借出的 - 所有利息) / 凭证总数量 。注意这里exchangeRate可以通过外部直接向合约中转入代币而改变。注意交换率是放大了`10**18倍的`

29. 调用`doTransferIn`来转入质押的代币，这个函数比较简单，但是比较了转入前后的代币余额，返回的是余额差，因此支持收税的代币。

30. 接下来计算增发的凭证数量，公式为`mintTokens = actualMintAmount / exchangeRate` 注意这里有精度转换

31. 接下来更新用户余额和总余额，最后触发相应事件。

32. 这里不存在重入问题，虽然转移代币发生在状态改变之前（必须通过实际代币转移得到实际质押数量），但是相关的交换率计算发生在代币转移之前并保存。因此并不能直接影响增发的凭证。假定重入后再进行质押操作，重入时因为`totalSupply`并无变更，因此会导致兑换率并不准确。这里可以验证一下。这里看了ERC777的代码，发送前有个hook函数_callTokensToSend,如果攻击者使用重入的话，兑换率不变的，并不会有影响。

    假定当前余额为 10，错出为0 ，利息为0， 凭证数量为20，则兑换率为1：2

    用户如果一次性操作，质押10，应该兑换的作证数量为20

    用户重入操作：先质押5，此时兑换率为1：2， 然后在转移之前重入再质押5，此时兑换率仍然为1：2（因为没有发生任何变化），

    质押后变成了余额15，凭证数量为30，然后继续第一次的质押，此时兑换率为临时的1：2(仍然相同，兑换率在转移之前计算好了)

    然后仍然会兑换10个凭证。

33. 从质押可以看到，用户可以不需要进入市场操作。但是如果不进入市场，会导致后面的借贷无法使用该市场的CToken.



## 三、用户借款 borrow

1. 用户在A市场有质押（同时需要进入市场），调用相应市场A合约（CErc20Delegator）的 `mint` 函数。具体流程上

2. 用户进入市场B（可以自动进入），其实就是代表我在哪个市场有质押，不然得遍历所有市场，调用 Comptroller.sol中的`enterMarkets` 函数，其循环体内调用了`addToMarketInternal`函数。
3. 调用 B 市场的 borrow 函数，会委托调用其实现合约`CErc20`的borrow 函数，然后再调用CToken.sol中的`borrowInternal`函数。

4. 在`borrowInternal`函数中，先进行利息结算`accrueInterest`。具体流程见下。

5. `CToken.sol`中的`accrueInterest`函数代码解读如下：

   - 记录下当前区块高度和上一次记录的区块高度，如果两者相同，直接返回

   - 获取当前市场underlying(质押的代币，不是质押凭证代币)的数量 `getCashPrior`

   - 使用三个临时变量保存, `totalBorrows` 借出的总量，`totalReserves`合约保留的总量（平台保留的）, `borrowIndex` 累积利息率
     - 调用利率模块的`getBorrowRate` 函数来计借贷利率`borrowRateMantissa`，这个值的留底为每个区块产生的利息率（不是利息数值），并要小于最大值。
       - utilizationRate 计算的是利用率， 从该函数的计算公式可以得出,`reserves`为保留的数量。
       - 利用率 * 系数 + 基准利率 为借贷利率，也就是 getBorrowRate 的返回结果。

   - 计算区块差

   - 计算 simpleInterestFactor 顾名思义，简单利息因数， borrowRateMantissa * 区块差 得到这在段时间内的利息率。

   - 计算累积利息 interestAccumulated ，就是 simpleInterestFactor * 所有借款 ，得到所有借款的利息

   - 计算并更新 totalBorrowsNew 与 totalReservesNew 与 borrowIndexNew ，注意： totalBorrowsNew与borrowIndexNew 是指数更新的， totalReservesNew 稍微有些差别，totalReservesNew 为 借款利息 * 保留因子。borrowIndexNew 为累积利息率。因为Compound是复利，指数操作。

6. 接下来调用`borrowFresh`，看名字就知道是新的借款（此时利息已经更新过了）

7. 调用comptroller的borrowAllowed函数来看是否能借这么多，此函数需要详细解析（风险点）

8. borrowAllowed 函数的详细解读为：

   - 检查是否暂停了及市场是否开放了（不是进入，是管理员supportMarket）

   - 检查用户是否进入了该市场，如果没有，则验证调用者必须为`CToken`，当然你也可以这里伪造一个cToken来调用，但没有什么意义，因为伪造的cToken无法进入listed，所以在前面会验证失败。

   - 如果没有进入市场，则自动进入该市场，同样调用了`addToMarketInternal`函数

   - 检查借款市场的预言机价格，如果为0，则没有预言机，返回错误代码。

   - 检查借款市场的借款上限，一般不会有上限。

   - 调用`getHypotheticalAccountLiquidityInternal`函数检查是否能借及余额是否足够。

   - 转动飞轮，这里注意调用的是`updateCompBorrowIndex`与`distributeBorrowerComp`。意思是和借相关的奖励。

9. `getHypotheticalAccountLiquidityInternal`为一`internal`的`view`函数用来计算用户贷款或者redeemed时需要提供的流动性，它返回错误代码，用户剩余的价值或者用户流动性不足时的价值差。其参数分别为：`account` 用户 ，`cTokenModify` 欲操作的市场，redeemTokens 赎回的代币数量，borrowAmount 借的代币数量。注意`cTokenModify`为零地址时代表不进行任何操作，如果为某个市场地址时，需要对该市场的值进行修正。

   它主要用在如下几个地方:

   - 同名公共函数调用
   - getAccountLiquidity （用来查询用户所有的流动性）
   - 判断出借时流动性是否足够
   - 判断赎回时流动性是否足够

   具体解读为：

   - 定义了一个临时结构体：`AccountLiquidityLocalVars` ,它的字段有很多。使用结构体是为了防止Solidity中堆栈过深（变量过多）的问题。

   - 遍历用户所有进入的市场

   - 获取用户在该市场的快照(`getAccountSnapshot`)

   - `getAccountSnapshot`函数用来获取用户在某市场的凭证余额，借款数量（`recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex` ，接下来调用 `exchangeRateStoredInternal`函数来获取兑换率

   - 获取该市场的最大抵押率，获取预言机价格。

   - 这里根据价格，最大抵押率，交换率三者相乘计算了一个`tokensToDenom`，未完全理解其含义

   - 累积抵押`sumCollateral += tokensToDenom * cTokenBalance`  ，相当于所有抵押物的价值

   - 累积`sumBorrowPlusEffects` 计算公式为`sumBorrowPlusEffects += oraclePrice * borrowBalance`  相当于所有借款的价值

   - 如果市场为操作市场，则额外进行borrow 与 redeem处理。（也就加上本次borrow 与 redeem的资产价值）。因为借款时会自动进入市场，所以这里必然会遍历到操作的市场。

     ```javascript
     sumBorrowPlusEffects += tokensToDenom * redeemTokens
     sumBorrowPlusEffects += oraclePrice * borrowAmount
     ```

     

   - 如果抵押物 大于所有借款价值，则返回其价值差作为剩余的价值，如果抵押物 小于借款价值，则返回错误代码及差额。

   - 从上面的计算可以看出，借出的价值是用预言机价格*借出数量计算的，抵押物的价值是使用的`凭证数量 * 交换率 * 最大抵押率  *  `   `预言机价格` 。这个公式的前一部分是相当于将凭证重新转化为`underlying`，后面再乘上价格就和借出价值计算相同了。

   - 从这里可以看出，借出时，并不需要消耗CToken，而只是根据CToken的数量进行价值计算并比较。其中交换率及预言机价格是瞬时的，是随时变化的，而最大质押率是由项目方设计 的。由于价格及交换率的变化，用户的抵押有可能不够借款的价值，从而会形成爆仓。

   - 接下来根据  getHypotheticalAccountLiquidityInternal 的返回值来进行相应的操作及提示。

   - 如果用户可以借款的话。接下来移到飞轮计算用户的Comp奖励，这一点在`Mint`操作时已经解读了。

   - 同`Mint`一样，Comp的奖励计算是放在相应操作的`Allowed`中操作的。

   - Comptroller合约的`borrowAllowed`执行完毕，返回`CToken.sol`中的`borrowFresh`函数。

   - 和`mint`一样，再次进行区块验证。

   - 验证当前借的数量必须小于市场中代币余额（只是为什么放在这里验证，感觉放在borrowAllowed中也行的）

   - 新建一个`BorrowLocalVars`局部变量`var`记录相应的值

   - 调用`borrowBalanceStoredInternal`来获取用户已经借出的数量，加上本次借出的数量并更新。

   - `borrowBalanceStoredInternal`函数内部也是使用`getAccountSnapshot`函数中相同的方式来计算，因为`getAccountSnapshot`也是调用的本函数。

   - 更新全部借出的数量

   - 转出出借代币（重入风险点，因为前面更新的值保存在临时变量`var`中，如果重入此时该变量未更新）。

   - 更新临时变量中的值到存储中，更新用户的interestIndex。

   - 触发Borrow事件，返回出错误代码。

   - 这里的重入和退出市场结合起来就可以形成攻击，已经实施了多次。主要原因是涉及到了ERC777代币，在转出代币后重入退出市场，由于此时用户的借款数量及利率未更新，退出市场时不会检查新的借款。此时用户发起赎回操作，由于已经退出市场，该市场的借款情况不会被检查。详情见 https://learnblockchain.cn/article/3724

   - 需要注意的是，如果不是借ERC777，是借ETH，也是有可能重入的。解决办法，将`doTransferOut`放在`return`语句前面。

   

## 四、赎回操作 redeem   

赎回操作是用户在某个市场使用CToken换回抵押的资产，具体操作为：

1. 用户调用CErc20Delegator中的redeem函数，会调用实现合约的`redeem`或者`redeemUnderlying`函数。接下来会调用`CToken.sol`中的`redeemInternal`或者`redeemUnderlyingInternal`函数
2. 更新利息。用户操作前都要更新利息 操作。
3. 调用`redeemFresh`，此时传递了`msg.sender`作为操作者
4. `redeemFresh`函数能同时处理传入凭证或者underlying数量两种情况，分别对应第一步中的`redeem`或者`redeemUnderlying`调用。
5. `redeemFresh`函数中首先判断只能处理两者之一，不能同时提两种币。
6. 创建一个临时`RedeemLocalVars`变量`vars`
7. 获取本市场的兑换率`exchangeRateStoredInternal`   `（ 余额 + 借出 - 利息 ）/ CToken数量`  所以CToken * 兑换率就是兑换的代币数量。这就是上面borrow公式时计算抵押价值时是 * 兑换率。
8. 如果是`redeem`操作， 则根据兑换率计算underlying的数量。 如果是redeemUnderlying操作，则刚好相反，并记录在`vars`变量中。
9. 仍然调用`comptroller.redeemAllowed`来判断是否允许赎回操作，注意这里传递的是CToken的数量。（因为要统一计算抵押数量）
10. `redeemAllowed`函数调用了`redeemAllowedInternal`函数来判断。因此退出市场或者转移Token也要用到相同的逻辑，所以写成了一个公共的内部函数。
11. redeemAllowedInternal函数操作并不复杂，如下：
    - 判断市场是否由管理员添加了
    - 判断用户是否进入了，如果未进入，则不能赎回，这里可以看出，如果从别人那获取了CToken,要想赎回，需要先进入。
    - 调用`getHypotheticalAccountLiquidityInternal`函数，注意第二个参数和第三个参数。这里如果是赎回操作，则抵押品价值加上了欲传入的CToken的价值。然后再通过 抵押品价值和借款价值比较判断是否可以赎回。
12. 更新Comp的奖励，然后再返回CToken中的`redeemFresh`函数。注意因为这里是赎回操作，所以更新的是提供者奖励`updateCompSupplyIndex`。
13. 再次验证区块高度。
14. 更新用户的凭证数量及总凭证数量到临时变量中，判断市场内的余额是否大于赎回的underlying的数量。
15. 这里又是先转出了underlying(重入？？？)
16. 更新用户的代币及所有代币的数量
17. 调用`redeemVerify`进行某种情况验证。函数返回。
18. 重点：getHypotheticalAccountLiquidityInternal 函数中的判断。不管是`redeemTokens`还是`borrowAmount`，增加的都是借出资产数量，只是计算的方式不同（对应CToken/underlying)

19 重点：这里赎回按道理可以和借款一样进行重入攻击，需要验证。





## 五、退出市场操作 exitMarket

退出市场操作，就是该市场的抵押资产不参与借款与赎回计算

1. 获取该市场的用户快照，
2. 检查用户在该市场是否有借款，如果有借款，则无法退出
3. 调用 `redeemAllowedInternal` 来进行贷款检查，这里统一把赎回及退出市场操作延申为借款增加。
4. 删除市场中的用户信息。
5. 退出成功。注意退出后用户质押仍然存在。只是该市场的抵押资产不参与借款与赎回计算。



## 六、repayBorrow 与 repayBorrowBehalf

这两个函数类似，都是归还贷款。不过一个是帮别人归还。

1. 调用CErc20Delegator合约中的`repayBorrow`或者`repayBorrowBehalf`函数。
2. 接下来调用`repayBorrowInternal`或者`repayBorrowBehalfInternal` 函数。这两者逻辑其实是一样的。
3. 注意：repayBorrowInternal 或者 repayBorrowBehalfInternal 函数有防重入措施。但是仅这两个函数是不够的。
4. 第一步是例行操作，更新利息，然后调用`repayBorrowFresh` 函数。
5. 第二步照例是调用`comptroller.repayBorrowAllowed` 来判断支付后是否满足质押 > 贷款
6. repayBorrowAllowed 函数相当简单，其实只要是还，都是允许的。这里只是简单的判断了市场是否有效（管理员是否添加）。然后调用同其它操作允许判断一样，转动飞轮，更新`borrower`的奖励（替别人还也是更新别人的`borrow`奖励）。注意这里的飞轮是`updateCompBorrowIndex`。
7. 接下来返回repayBorrowFresh函数，再次判断区块高度。
8. 记录借款者的利率及借款数量，记录归还数量，这里提到记录利率是为了进行验证，但最后将验证代码注释掉了。
9. 还款，记录实际还款数量（防止有收税的）
10. 更新用户的借款数量和全体借款数量
11. 记录用户的借款数量，利率和全体借款数量
12. 触发事件，返回。
13. 从上面可以看到，还款没有任何限制。你也无法多还。
14. borrowBalanceStoredInternal 函数调用时，因为市场利率肯定是高于用户利率的，所以计算的数量其实是要比`principal`要多一点的。



## 七、清算 liquidateBorrow

任何人清算借贷者的抵押物。没收的抵押品给了清算者。

1. 调用`CErc20Delegator`合约的`liquidateBorrow`函数，参数分别为借款人，清算的数量，没收的抵押物所在的市场。

2. 调用CErc20的`liquidateBorrow`及`liquidateBorrowInternal`函数。

3. CToken的`liquidateBorrowInternal`函数，照例先是更新利息（调用本市场的accrueInterest函数），然后是更新目标市场的利息,（调用目标市场`accrueInterest`函数）

4. 调用 `liquidateBorrowFresh` 函数。照例先是调用`comptroller.liquidateBorrowAllowed`来判断能否清算。

5. `liquidateBorrowAllowed`函数中，先是判断源市场和目标市场是否有效。

6. 接下来读取借贷者在源市场中的借款数量。`borrowBalance`

7. 如果市场已经废弃，则清算数量不能超过借款数量。`isDeprecated`

8. `isDeprecated`函数的注释表明，如果市场废弃了，所有的借款可以立即被清算。判断市场废弃的三个条件。抵押系数为0，暂停并且利息系数为1e18。

9. 通常市场不是废弃的，此时获取借贷者的负债情况shortfall，（代表借款价值已经超过了抵押价值）。

10. 如果shortfall为0，说明借款者是健康的，没有债务，不能被清算。

11. 根据`closeFactorMantissa`计算一个`maxClose`，也就是最大清算数量。偿还的数量不能超过这个最大清算数量。其实这里和目标市场基本没有关系，只是验证了是否有效。

12. 返回CToken的`liquidateBorrowFresh`函数并检查两个市场的区块高度。

13. 判断是否自己清算自己和清算数量是否为0及-1.当为`-1`时，其实为最大值,但是这样在`liquidateBorrowAllowed`中是会返回错误代码的，因为肯定超过了贷款数量。这时在`liquidateBorrowAllowed1`时就通不过。因此这里为`-1`的判断有待商榷。

14. 接下来的逻辑和归还贷款相同，都是调用了`liquidateBorrowAllowed`进行还款。

15. 接下来计算没收的资产数量，调用的是`comptroller`的`liquidateCalculateSeizeTokens`函数，该函数需要进一步解析。

16. 如果借款者的抵押品小于没收的数量，则失败。

17. 根据目标市场是否为源市场，分别调用不同的函数来进行没收，需要注意的是`cTokenCollateral.seize`的实现过程，这个比较复杂。

18. 判断没收操作返回操作码正确，返回实际支付的数量。

19. 没收函数`seize`详解，它也调用了`seizeInternal`函数。`seizeInternal`的四个参数分别为：

    - 执行操作的CToken合约。（如果是没收本合约的，则就是address(this)，否则为调用者msg.sender)

    - 调用`comptroller.seizeAllowed`函数进行操作是否允许判断。其详细如下：

      - 参数分别为欲没收资产的市场，（传递过来的address(this)），借贷者贷款合约（别人要替他清算的），清算者，贷款者，没收的数量

      - 需要清算未暂停
      - 需要两个市场有效
      - 需要两个市场的`comptroller`为同一地址，这样估计是为了防止版本问题吧。
      - 转动飞轮，更新欲没收资产的市场的Comp及借款者和清算者的Comp奖励。这里为什么也要更新清算者的奖励，也是一个问题。解释如下：注意这里更新的是Supply奖励。因为这里相当于CToken进行了转移，所以和TransferAllowed一样，并不涉及到借款操作，所以是更新的是发送和接收者的supply奖励。

    - 再次判断借贷者和清算者不能是同一账号（重复了)

    - 注意没收的是CTokens，因此这里分别对清算者及借贷者的CToken余额进行了加减操作。

    - 没收的CToken好像收了一下没收利息，没收的是seizeTokens，清算者增加的是liquidatorSeizeTokens。totalReservesNew 增加的是protocolSeizeAmount（underlying)，totalSupply减去了没收的利息，也就是实际上totalSupply减小了。totalSupply 也会导致兑换率的变化（比初始兑换率要高）

20. 从seizeInternal函数内部退出。我们接下来看`liquidateCalculateSeizeTokens`的计算。

21. liquidateCalculateSeizeTokens 函数三个参数分别为借款的市场，抵押的市场和实际清算的数量。

22. 先获取两个市场的预言机价格。任何一个为0则返回错误代码。

23. 获取抵押市场的交易率，这里的注释清楚的写明了没收数量的计算，其实际是两种代币的价值比较，然后再除以兑换率就得到没收市场应该没收的CToken的数量，只不过多了一个清算激励因数。最终公式如下：

    `seizeTokens = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)`



## 八、Compound 所有外部状态变量和接口一览

用户绝大多数操作都是直接和市场合约`CErc20Delegator`交互，而`Unitroller`主要是项目方的运营合约（用户进入和退出市场也在这里，因为会统一操作多个市场，其记录在Comptroller合约中）

### 8.1 ComptrollerStorage.sol

这个合约内部包含了多个合约，但均为相关状态变量存储合约。分别如下 ：

#### 8.1.1 UnitrollerAdminStorage 

专门用来存储管理员和实现合约（相当于openzepplin中代理合约的管理员及实现插槽），注意Unitroller及Comtroller均在第一顺位继承了该合约，这样相关操作时插槽才不会冲突（插槽位置相同）。

#### 8.1.2 ComptrollerV1Storage

分别为预言机地址，最大清算比例因数，清算激励因数，单个账号能参与的最大市场数量（好像没有用到）， 所有用户参与的市场。

#### 8.1.3 ComptrollerV2Storage

首先定义了一个Market结构体，记录了该市场的相关信息，其四个字段分别为：是否列出（有效），最大借款比例，市场参与者（账号），是否接受Comp。

接下来定义了每个市场对应一个Market的mapping.变量名为`markets`

接下来定义了几个暂停开关，暂停时用户可以提款 ，但不能转移，没收或者清算。

接下来定义了两个暂停的mapping，暂时未知作用。

#### 8.1.4 ComptrollerV3Storage

定义了一个结构体，`CompMarketState`，用于记录最后更新的索引和区块高度（这里索引使用了或者是因为两个不同的变量使用到了，具体数值需要详细了解一下）

allMarkets 记录了所有市场

compRate ，奖励Comp的速度，具体数值为每个区块的奖励数量

compSpeeds 每个市场的飞轮转速，转速不同，奖励的Comp不同。

compSupplyState 与 compBorrowState 每个市场的Supply与Borrow状态

compSupplierIndex 与 compBorrowerIndex 市场中每个用户的状态

compAccrued 每个用户的Comp奖励

#### 8.1.5 ComptrollerV4Storage

borrowCapGuardian 用来设置每个合约的借款上限的合约地址（暂时未看见作用）。

borrowCaps 每个市场的借款上限

#### 8.1.6 ComptrollerV5Storage

compContributorSpeeds 作用未知

lastContributorBlock 作用未知

上述合约后面的继承上一个，所以V5继承了从头开始的所有合约。

因为我们使用的是`Comptroller`合约，它继承的是ComptrollerV5Storage，因此我们这里只看到ComptrollerV5Storage就行了。

#### 8.1.7 Comptroller 

该合约为Unitroller合约的实现合约。主要状态变量有：

compInitialIndex = 1e36  从这里可以看出V3中的index不是索引的意思，其实就是一个值。

closeFactorMinMantissa 与 closeFactorMaxMantissa 清算比例的上下限，这里放大了1e18倍，可以看出最小5%，最大90%

collateralFactorMaxMantissa 借款比例上限,同样放大了1e18。

getAssetsIn() 获取用户进入的市场

checkMembership 检查用户是否进入了某市场

enterMarkets 用户进入某些市场，很简单

exitMarket 用户退出某市场，需要检查在该市场无借款并且退出后贷款<= 抵押。

以`Allowed`结尾的函数，是在CToken里调用用来判定是否可以进行某项目操作。当然用户也可以直接调用，但一般不这么操作。因为它不是一个view函数，这里会更新Comp的奖励，会花费gas。

以`Verify`为结尾的函数也是用来在CToken中回调的。这里用户直接调用没有任何效果，相当于一个pure函数。

以`AllowedInternal`结尾的函数为判断某项目操作是否允许（主要是通过借款和抵押的比较），这是一个view函数。但由于是内部可见性，所以用户无法调用。

getAccountLiquidity这是一个view函数，获取用户在所有进入的市场的流动性或者债务（这里流动性是指抵押品超过借款的数量，债务刚好相反）。

getHypotheticalAccountLiquidity 函数，假定用户要进行借款或者赎回操作，计算其流动性和债务。这里不管是借款还是赎回，都按增加债务统一计算。这是一个view函数。

liquidateCalculateSeizeTokens 计算清算时没收的CToken数量。 通过价值相等来计算（再除于价格和兑换率得到）。注意是一个view函数。

以`_set`开头都是管理员设置函数。

_setPriceOracle 管理员接口，设置预言机。

_setCloseFactor 管理员接口，设置清算比例

_setCollateralFactor 管理员接口，设置借款比例（变量名称叫抵押因数），例如在某个市场的抵押品价值为`cTokenBalance * collateralFactor * exchangeRate * oraclePrice` 其意义为CToken数量 * 借款比例 * 交换率得到能借的underlying的数量，再乘上其价格，得到能借（抵押品）的数量。 

_setLiquidationIncentive 设计清算激励

_supportMarket 管理员接口，管理员添加一个市场。注意管理员添加市场后用户才能会市场进行操作，叫进入市场。不然任意人都可以部署CToken合约并操作了。

_setMarketBorrowCaps 设置市场借款上限，一般不会设置。

接下来设置几个暂停地址。这个一般用不到。

_become 函数，用于最开始和unitroller绑定时使用。

注意：`transferAllowed` 更新的是`updateCompSupplyIndex` 奖励，因为此时不涉及borrow.

updateContributorRewards 更新 contributor 的奖励，其中的`contributor`需要在`_setContributorCompSpeed`函数中设置奖励

claimComp 相关，用户提取Comp奖励，不管是suppy奖励还是borrow奖励

_grantComp 管理员提取多余的Comp代币

_setCompSpeed 设置某市场的Comp产生速度

#### 8.1.8 CErc20Delegator

市场合约用户接口

_setImplementation 部署后绑定实现合约`CErc20Delegate`

mint 用户质押接口

redeem 与 redeemUnderlying用户赎回接口，分别用于输入CToken的数量或者underlying数量

borrow 用户借款

repayBorrow 用户偿还借款

repayBorrowBehalf 替别人偿还借款

liquidateBorrow 清算接口（替别人还款，获得别人的抵押物）

transfer,transferFrom与approve 标准ERC20操作，但是转移之前需要检查债务。

balanceOfUnderlying 查看相应的抵押品数量（随交换率的变化而变化）

getAccountSnapshot 获取用户账号快照，返回值分别为错误代码，cToken数量，借款数量，交换率。

borrowRatePerBlock 每区块借款利息率，放大了`1e18`。

supplyRatePerBlock 每区块存款利息率，放大了`1e18`。

totalBorrowsCurrent 市场合计借款 + 利息，注意不是view函数，因为会更新利息。然后再返回 `totalBorrows`

borrowBalanceCurrent 用户当前借款，注意不是view函数，因为会更新利息及borrowIndex,然后返回更新后的borrowBalance.

borrowBalanceStored 这个函数是view类型的，是未更新利息时的借款数量

exchangeRateCurrent 当前交换率，注意是非view函数，因为会更新利息。

exchangeRateStored 当前交换率，未更新利息的。view函数。

getCash 就是合约内underlying的余额

accrueInterest 累积利息操作。

seize 没收操作，只能为另一个cToken在清算期间使用。

sweepToken 提取合约中额外的ERC20代币

接下来是管理员功能。

重点是Reserve是什么。这个应该是平台方收集的利息 。































