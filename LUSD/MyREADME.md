> - Doc: https://docs.liquity.org/v/cn/
> - Contract Code: https://github.com/liquity/beta
> - Defillama: https://defillama.com/protocol/liquity
> - DevUI: https://eth.liquity.fi/

## Introduction

- 概述

  - Liquity是什么？

    Liquity是一种去中心化的借贷协议，允许您用以太币作[抵押](https://docs.liquity.org/faq/borrowing#what-do-you-mean-by-collateral)提取[无息贷款](https://docs.liquity.org/faq/borrowing)。 贷款以LUSD（一种与美元挂钩的稳定币）的形式支付，并要求110%的[最低抵押率](https://docs.liquity.org/faq/borrowing#what-is-the-minimum-collateral-ratio-mcr-and-the-recommended-collateral-ratio)。

    除了用户的抵押外，Liquity的贷款还由一个LUSD的[稳定池](https://docs.liquity.org/faq/stability-pool-and-liquidations#what-is-the-stability-pool)和所有借款人集体作为最后担保人提供担保。

    > Liquity 协议属于 CDP（Collateralized Debt Position）
    >
    > 在CDP中，用户可以将自己的数字资产作为抵押物，借出相应的稳定币（如DAI）。用户需要将抵押物锁定在智能合约中，同时设定一定的抵押率，例如150%。这意味着如果用户想要借出100个DAI，他需要抵押价值至少为150个DAI的数字资产。

  - Liquity的动机

    当前，稳定币市场中绝大部分的资产都是以法币作抵押的中心化稳定币，去中心化稳定币如DAI和sUSD仅占总供应量的一小部分。通过提供一种更加高效和易于使用的借入稳定币的方式，使得去中心化稳定币的使用更加普及和便捷，并且保持协议的去中心化特性。

  - Liquity的优势

    - 0%利率
    - 100%的最低抵押率
    - 无治理——所有的操作都基于算法，在协议部署时就已经设置好了协议参数。不可升级/更改，Liquity没有管理员密钥。没有人可以以任何方式更改系统规则。 智能合约的代码是完全不变的。
    - 可以直接赎回——LUSD可以随时按面值赎回相关抵押品。
    - 完全去中心化——Liquity协议没有管理密钥，并且可以通过由不同前端运营商提供的多个接口进行访问，从而使其不受审查。

  - 如何使用

    需要选择一个Web界面（又名[前端](https://docs.liquity.org/faq/frontend-operators)）来访问系统。 构建该协议的核心团队将不会运行前端。 但是您可以通过第三方前端应用程序和集成服务来访问Liquity。

    > 使用liquity的前端列表：https://www.liquity.org/frontend#frontends
    >
    > 前端运营商为终端用户提供了一个网页界面，使他们能够与Liquity协议进行交互。
    >
    > 他们将获得由用户产生的LQTY代币的一部分作为此项服务的奖励。
    >
    > LQTY奖励发放给稳定池的存款人，然后在用户自己和前端运营商之间按比例分配。双方各自获得多少由前端操作员设置的回扣率决定，范围在 0% 到 100% 之间，如果前端将回扣率设置为 60%，他们的用户将获得 60% 的奖励，而前端将获得剩余的 40%。（一旦一个地址在稳定池中注册为前端并具有指定的回扣率，就无法再更改了，如果前端运营商希望更改其回扣率，他们必须使用新的回扣率注册新的前端地址。）

  - 如何借款

    要借入LUSD，您所需要的只是一个钱包（如MetaMask）和足够的以太币以开设[金库](https://docs.liquity.org/faq/borrowing#what-is-a-trove)并支付交易费。

    1. 开设一个金库（Trove）并向其中存入一定数量的抵押品（ETH）
    2. 提取一定数量的LUSD保证您的抵押率不高于110%

- LUSD 和 LQTY

  - LUSD

    LUSD是与美元挂钩的稳定币，可以用于偿还Liquity协议里的贷款。您在任何时候都可以按面值赎回[抵押品](https://docs.liquity.org/faq/borrowing#what-do-you-mean-by-collateral)。

    > 抵押品是任何借款人为提取贷款而提供的资产，以作为债务的担保。目前，Liquity仅支持ETH作为抵押。

  - LQTY

    LQTY是Liquity发行的辅助令牌。它捕获了系统产生的费用收入，并激励早期用户和前端开发商。LQTY奖励只会累积发放给稳定提供者，即将LUSD存入稳定池的用户、促成这些存款的前端以及LUSD:ETH Uniswap池的流动性提供者。LQTY的总供应量上限为100,000,000个代币。

    > 要想稳定池中存款或者质押LQTY，您需要拥有LUSD和/或LQTY代币。
    >
    > 您可以通过开设金库借入LUSD，而LQTY可以通过在稳定池中存款来赚取。
    >
    > 您还可以使用Uniswap或其他（去中心化）交易所在公开市场上购买代币。
    >
    > LQTY 可以通过三种方式获得：
    >
    > - 将LUSD存入[稳定池](https://docs.liquity.org/faq/stability-pool-and-liquidations#what-is-the-stability-pool)。
    > - 通过您的[前端](https://docs.liquity.org/faq/frontend-operators)促成稳定池存款。
    > - 为LUSD:ETH Uniswap池提供流动性

- 借贷

  - 为什么使用 Liquity 进行借贷

    该协议提供无息贷款，并比其他借贷系统具有更高的资本效率。用户可以将自己的以太坊作为抵押品借入LUSD（一种稳定币），然后在未来偿还贷款。这样，用户无需出售以太坊以获取流动资金。此外，如果用户认为以太币价格未来会上涨，可以使用该协议将其以太币头寸提高至多11倍，并不断借入LUSD购买更多的以太币，从而获得更高的收益。

  - 抵押品

    Liquity仅支持ETH作为抵押

  - 抵押率

    > 一般来说抵押率指的是贷款金额与抵押物价值之间的比率，一般用于衡量贷款风险。例如，如果一笔贷款的金额为10万美元，抵押物的价值为15万美元，则抵押率为10万/15万=0.67，即抵押率为67%。抵押率越低，表示借款人的风险越小，因为抵押物的价值可以更好地保障贷款本金的安全。而高抵押率可能意味着借款人的风险较高，因为抵押物价值的下降可能会导致无法完全偿还贷款。

    在 Liquity 的借贷协议中抵押率是指金库中抵押品的美元价值与其以LUSD为单位的债务之间的比率。随着以太币价格的变化，金库的抵押率会随时间波动。您可以通过调整Trove的抵押品和/或债务数量（即增加更多的ETH抵押品或还清部分债务）来影响抵押率。

    例如：假设以太坊的当前价格为$ 3,000，而您决定存入10 ETH。如果您借入10,000 LUSD，那么Trove的抵押物比率将为300％。如果您借入25,000 LUSD，则您的比率为120％。

    - 最低抵押率 MCR

      最小抵押率（或简称MCR）是在正常操作（即正常模式）下不会触发清算的债务与抵押物的最低比率。这是设置为110％的协议参数。因此，如果您的金库中有10,000 LUSD的负债，则您需要至少价值$ 11,000的以太币作为抵押，以避免被清算。

    - 推荐抵押率

      为避免在[恢复模式](https://docs.liquity.org/faq/recovery-mode)期间清算，建议将比率保持在150％以上（例如200％或更安全的250％）

  - 如何实现免息借贷

    该协议收取一次性借入和赎回费用。这一费用会根据最近的赎回时间在算法上进行调整。例如：如果近期发生更多的赎回（这意味着LUSD的交易价格可能低于1美元），则借贷费用将增加，从而阻碍借贷。

  - 金库 Trove

    金库是您获取和维护贷款的地方。每个金库都链接到一个以太坊地址，而每个地址只能拥有一个金库。

    金库记录两项账户余额：一项是作为抵押的资产（ETH），另一项是以LUSD计价的债务。您可以通过添加抵押品或偿还债务来更改每一项账户的金额。当您更改这些余额时，您的金库的抵押率也会相应更改。

    您可以随时清偿债务以关闭Trove。

  - 还款时间

    协议发行的贷款没有还款时间表。只要您保持至少110％的抵押比率，您就可以保持金库运行并在任何时间偿还债务。

- 赎回

  - 
    赎回是将 LUSD 以面值兑换 ETH 的过程，就好像 1 LUSD 正好值 1 美元。也就是说，如果您支付x LUSD，您将获得价值 x 美元的 ETH 作为回报。

    用户可以随时自由地将 LUSD 兑换为 ETH。但是，Liquity可能会对赎回的金额收取赎回费。

    例如，如果当前赎回费为 1%，ETH 的价格为 500 美元，您赎回 100 LUSD，则您将获得 0.198 ETH（0.2 ETH 减去 0.002 ETH 的赎回费）。

> Liquify 借贷协议的特点：
>
> - 0⃣️利率
>
> - Low collateralization ratio 低担保率 —— 110%
>
>   也就是说存100可以借90（借出来的是LUSD——在它的系统中永远可以以1U的价格来赎回ETH）
>
> - 只提供后台的智能合约、SDK、协议等核心部分，而前端提供给第三方开发商，通过LQTY奖励的方式激励 (前端自定义交易抽成)。

## Core System Architectrue

1. 核心 Liquity 系统由多个智能合约组成，可部署到以太坊区块链。所有应用程序逻辑和数据都包含在这些合约中——不需要在 Web 服务器上运行单独的数据库或后端逻辑。实际上，以太坊网络本身就是 Liquity 后端。因此，所有余额和合约数据都是公开的。
2. 该系统没有管理密钥或人工治理。一旦部署，它是完全自动化的、去中心化的，并且没有用户在系统中拥有任何特殊权限或控制权。
3. 三个主要合约——BorrowerOperations.sol、TroveManager.sol 和 StabilityPool.sol——拥有面向用户的公共功能，并包含大部分内部系统逻辑。他们一起控制 Trove 状态更新以及 Ether 和 LUSD 代币在系统中的移动。

### 核心合约介绍

##### `BorrowerOperations.sol` 

包含借款人与其 Trove 交互的基本操作：Trove 创建、ETH 充值/取款、稳定币发行和还款。它还将发行费用发送到 LQTYStaking 合约。 BorrowerOperations 函数调用 TroveManager，告诉它在必要时更新 Trove 状态。 BorrowerOperations 函数还调用各种池，告诉他们在必要时在池之间或池 <> 用户之间移动以太币/代币。

> https://github.com/liquity/dev#launch-sequence-and-vesting-process
>
> 等待后续总结补充

| Function                     | ETH quantity                        | Path                                       |
| ---------------------------- | ----------------------------------- | ------------------------------------------ |
| openTrove                    | msg.value                           | msg.sender->BorrowerOperations->ActivePool |
| addColl                      | msg.value                           | msg.sender->BorrowerOperations->ActivePool |
| withdrawColl                 | _collWithdrawal parameter           | ActivePool->msg.sender                     |
| adjustTrove: adding ETH      | msg.value                           | msg.sender->BorrowerOperations->ActivePool |
| adjustTrove: withdrawing ETH | _collWithdrawal parameter           | ActivePool->msg.sender                     |
| closeTrove                   | All remaining                       | ActivePool->msg.sender                     |
| claimCollateral              | CollSurplusPool.balance[msg.sender] | CollSurplusPool->msg.sender                |

## Operation

> https://eth.liquity.fi/
>
> 可以自行到网站上尝试操作

**添加一个 Trove**

<img src="https://cdn.jsdelivr.net/gh/lxiiiixi/Image-Hosting/Markdown/image-20230411162001236.png" alt="image-20230411162001236" style="zoom: 50%;" />



**Stability Pool**

通过质押 LUSD 可以获得 ETH 和 LQTY 作为奖励，会给出下一年存入稳定池的 LUSD 的 LQTY 回报率预估。

<img src="https://cdn.jsdelivr.net/gh/lxiiiixi/Image-Hosting/Markdown/image-20230411162205426.png" alt="image-20230411162205426" style="zoom:50%;" />

**Staking**

LQTY 并不是一个治理代币，根据 Liquity 的经济模型，除了卖掉以外可以将 LQTY 去质押，质押了 LQTY 的用户，可以按比例获得每次新开的 Trove 所支付给平台的 Borrowing Fee，另外当用户使用 Redemption 功能时（用户想要用 LUSD 换回 ETH）也会需要支付一定的 Borrowing Fee，这个费用同样是会支付给平台再又平平台分发给 LQTY 的持有者

> 清算规则：
>
> 当出现抵押物价值下降这样的情况使得 Collateral ratio 低于 110% 时，用户手上持有的 LUSD 可以自由支配，也可以在平台换回 ETH，但是在平台抵押的 ETH 会被清算，清算过程会经历几个步骤：
>
> 1. EHT 的价值下降导致 CR 低于 110%
> 2. 接下来所有人都有资格成为清算人，这 10% 的超额抵押部分差价将被分给 Stability Pool 中的人（质押了 LUSD 的人）从而获得这 10% 的清算资金，从 Stability Pool 中的 LUSD burn 掉取弥补这个亏损的价值，如果此时 Stability Pool 中的 LUSD 不够了（Total Collateral Ratio 跌倒了 150%），会启动一个 Recovery Mode ，这时候所有人的 Trove 都会贡献进行清算

## Contract

- [ERC2612][https://eips.ethereum.org/EIPS/eip-2612]

  ERC2612是一种基于以太坊的代币标准，也被称为EIP2612。它是在以太坊社区中广泛使用的ERC20代币标准的基础上，为代币和NFTs（非同质化代币）的安全转移和授权提供了更加安全和高效的方法。ERC2612标准规定了一个新的接口，称为"permit"，该接口允许代币所有者授权第三方在其代币余额上执行特定的操作，而无需在区块链上进行额外的交互。

  ERC2612标准的核心思想是将代币授权的签名过程从交易执行期间转移到授权期间，从而减少交易的复杂性和成本，并提高代币交易的安全性。代币所有者可以通过签署一个包含授权信息的消息（如金额、接收者、截止时间等）来授权第三方代表其执行特定操作，而无需在区块链上执行交易。这些授权消息可以通过任何传输方式（如电子邮件、短信等）发送给第三方，从而实现更灵活和高效的代币授权。

  ERC2612标准同时也规定了一个新的域分隔符（domain separator）的计算方法，用于确保授权签名的唯一性和不可重用性，以避免代币所有者的授权被恶意重放或篡改。

  - permit() 函数

    ERC2612的permit函数是一种新的代币授权方法，旨在提高代币转移的安全性、效率和灵活性。相比于传统的代币授权方法，如approve和transferFrom函数，permit函数具有以下优点：

    1. 更高的安全性：permit函数采用了基于EIP712的签名方式，将签名和授权分离，从而避免了交易执行过程中被中间人攻击的风险。
    2. 更高的效率：permit函数不需要发送交易，只需要通过对授权信息进行签名，就可以将代币授权给第三方，从而减少了交易的复杂性和成本。
    3. 更高的灵活性：permit函数可以通过任何传输方式将授权信息发送给第三方，如电子邮件、短信等，从而实现更灵活和高效的代币授权。

  - domainSeparator 变量

    在ERC2612中，domainSeparator是一个哈希值，用于标识EIP-712域分隔符。域分隔符是一个结构体，用于指定消息的接收者、消息发送者、消息的链ID和合约地址等信息，用于确保消息的唯一性和完整性。

    作用是确保消息的唯一性和完整性，避免了恶意攻击和重放攻击等安全问题。在使用ERC2612的permit函数进行代币授权时，需要使用domainSeparator来计算签名，确保签名的正确性和唯一性。在计算签名时，需要将domainSeparator、授权类型哈希和其他参数一起进行哈希，以确保签名的唯一性和完整性。

- BigNumber

  在 JavaScript 中，由于浮点数精度的限制，当数字超过 `Number.MAX_SAFE_INTEGER`（即 2^53 - 1）时，可能会丢失精度。因此，在处理大型数字时，我们通常使用 `BigNumber` 库来确保精度和正确性。

  ```js
  const { BigNumber } = require("ethers");
  
  // 创建两个 BigNumber 对象
  const num1 = BigNumber.from("12345678901234567890");
  const num2 = BigNumber.from("98765432109876543210");
  
  // 加法
  const sum = num1.add(num2);
  console.log(sum.toString()); // "111111111111111111100"
  
  // 减法
  const difference = num2.sub(num1);
  console.log(difference.toString()); // "86419753208641975320"
  
  // 乘法
  const product = num1.mul(num2);
  console.log(product.toString()); // "121932631137021795660634145237702268900"
  
  // 除法
  const quotient = num2.div(num1);
  console.log(quotient.toString()); // "8000000000"
  ```

  



## Github Doc

> https://github.com/liquity/dev README.md

- Overview

  Liquity是一个抵押债务平台。用户可以锁定以太坊，发行稳定币代币（LUSD）到自己的以太坊地址，然后将这些代币转移到任何其他以太坊地址。个人抵押债务头寸称为Trove。

  稳定币代币的经济性质旨在维持1 LUSD = 1美元的价值，原因如下：

  1. 系统旨在始终过度抵押——锁定的以太坊价值超过发行的稳定币的美元价值。
  2. 稳定币是完全可兑换的——用户可以通过系统直接交换 \$x 的LUSD以获得\$x美元的ETH（减去费用）。
  3. 系统通过可变的发行费用算法控制 LUSD 的生成。

  在用一些以太坊开设Trove之后，用户可以发行（“借入”）代币，以使其Trove的抵押比率保持在110%以上。拥有$1000的以太坊抵押头寸的用户可以发行高达909.09 LUSD。

  代币可以自由交换——任何拥有以太坊地址的人都可以发送或接收LUSD代币，无论他们是否拥有开放的Trove。在偿还Trove的债务后，代币将被销毁。

  Liquity系统定期通过去中心化数据源更新ETH：USD价格。当Trove低于110％的最低抵押比率（MCR）时，它被认为是不足抵押，并容易被清算。

- Liquidation and the Stability Pool

   Liquity 按以下优先顺序使用两步清算机制：

  1. 抵消包含 LUSD 代币的稳定池中抵押不足的 Troves
  2. 如果稳定池清空，将抵押不足的 Troves 重新分配给其他借款人

  Liquity 主要使用其稳定池中的 LUSD 代币来吸收抵押不足的债务，即偿还清算借款人的债务。

  任何用户都可以将 LUSD 代币存入稳定池。这使他们能够从清算的 Trove 中获得抵押品。当发生清算时，清算的债务将被池中相同数量的 LUSD 取消（结果被销毁），并且清算的 Ether 按比例分配给存款人。

  稳定池存款人可以期望从清算中获得净收益，因为在大多数情况下，清算的 Ether 的价值将大于取消的债务的价值（因为清算的 Trove 的 ICR 可能略低于 110%）。

  任何人都可以调用 public liquidateTroves() 函数，该函数将检查抵押不足的 Troves，并将其清算。或者，他们可以使用自定义的 Trove 地址列表调用 batchLiquidateTroves() 以尝试清算。

  - Liquidation gas costs

    目前，通过上述功能进行的大规模清算每 trove 花费 60-65k gas。因此，系统可以在单笔交易中清算最多 95-105 个宝库。

  - Liquidation Logic

    清算的精确行为取决于被清算的 Trove 的 ICR 和全球系统条件：系统的总抵押率（TCR）、稳定池的大小等。

    下面是单个 Trove 在正常模式和恢复模式下的清算逻辑。SP.LUSD 代表稳定池中的 LUSD。

    > - ICR（Initial Collateral Ratio - 初始保证金比率）
    >
    >   加密货币借贷中的ICR指的是抵押品的价值占借款金额的比率，即最初提供的抵押品价值相对于所借款项的比率。
    >
    > - MCR（Minimum Collateralization Ratio - 抵押品最低抵押比率）
    >
    >   它是指保障抵押品价值的最低要求，以确保抵押品的价值不会低于贷款金额，从而保护借款人和投资者的利益
    >
    >   例如，在一个抵押债务平台上，MCR设定为110%，这意味着借款人需要提供抵押品，其价值至少为贷款金额的110%。如果抵押品的价值下降到低于MCR，则该债务头寸就会被自动清算，以保护借款人和投资者的利益。
    >   
    > - CCR （Critical system collateral ratio - 系统关键抵押率）
    >
    >   150%（如果系统的总抵押率低于 CCR，将会触发恢复模式）
    
    #### Liquidations in Normal Mode: TCR >= 150%
    
    | Condition                         | Liquidation behavior                                         |
    | --------------------------------- | ------------------------------------------------------------ |
    | ICR < MCR & SP.LUSD >= trove.debt | StabilityPool 中等于 Trove 债务的 LUSD 被 Trove 债务抵消。 Trove 的 ETH 抵押品由储户共享。 |
    | ICR < MCR & SP.LUSD < trove.debt  | StabilityPool 的 LUSD 总额被来自 Trove 的等量债务所抵消。储户共享 Trove 抵押品的一小部分（等于其抵消债务与其全部债务的比率）。剩余的债务和抵押品（减去 ETH gas 补偿）被重新分配给活跃的 Troves |
    | ICR < MCR & SP.LUSD = 0           | 将所有债务和抵押品（减去 ETH 气体补偿）重新分配给活跃的 Troves。 |
    | ICR >= MCR                        | Do nothing.                                                  |
    
    #### Liquidations in Recovery Mode: TCR < 150%
    
    | Condition                                | Liquidation behavior                                         |
    | ---------------------------------------- | ------------------------------------------------------------ |
    | ICR <=100%                               | 将所有债务和抵押品（减去 ETH 气体补偿）重新分配给活跃的 Troves。 |
    | 100% < ICR < MCR & SP.LUSD > trove.debt  | StabilityPool 中等于 Trove 债务的 LUSD 被 Trove 债务抵消。储户之间共享 Trove 的 ETH 抵押品（减去 ETH 气体补偿）。 |
    | 100% < ICR < MCR & SP.LUSD < trove.debt  | StabilityPool 的 LUSD 总额被来自 Trove 的等量债务所抵消。储户共享 Trove 抵押品的一小部分（等于其抵消债务与其全部债务的比率）。剩余的债务和抵押品（减去 ETH 气体补偿）被重新分配给活跃的宝库 |
    | MCR <= ICR < TCR & SP.LUSD >= trove.debt | LUSD 池被来自 Trove 的等量债务抵消。美元价值等于 1.1 * 债务的一小部分 ETH 抵押品由储户共享。没有任何东西被重新分配给其他活跃的 Troves。由于它的 ICR > 1.1，因此 Trove 有剩余的抵押品，它被发送到 CollSurplusPool 并由借款人索取。宝库已关闭。 |
    | MCR <= ICR < TCR & SP.LUSD < trove.debt  | Do nothing.                                                  |
    | ICR >= TCR                               | Do nothing.                                                  |

- Gains From Liquidations

  



























- 稳定池的作用：用户可以通过存入 LUSD 到稳定池中来获取 ETH 和 LQTY















> ##### GTP
>
> LUSD是稳定币吗
>
> > LUSD是一种算法稳定币。算法稳定币是一种使用算法和智能合约来维持价格稳定的数字货币，通常以特定的资产或货币作为基础。LUSD通过使用一种名为“Trove”的智能合约系统，以及与以太坊上的其他协议相结合，来实现价格稳定。
> >
> > LUSD的价格稳定机制是基于“抵押率”的概念。当用户在Liquity协议中借入LUSD时，需要将ETH作为抵押品，保持一定的抵押率。当抵押率低于设定的安全阈值时，系统会自动进行清算，以保护借款人和Liquity协议的稳定性。这种抵押率机制和清算保护措施可以使LUSD保持价格稳定，而不需要像传统的中心化稳定币那样依赖于法定货币的储备金或其他外部因素。
> >
> > 因此，LUSD是一种基于算法和智能合约的算法稳定币。
>
> LUSD与USDT的区别
>
> > LUSD和USDT是两种不同的稳定币，它们有以下几个方面的区别：
> >
> > 1. 抵押物不同：LUSD的抵押物是以太坊（ETH），而USDT的抵押物是美元等法定货币或其他实物资产。
> > 2. 发行机制不同：LUSD是由Liquity协议发行的，而USDT是由Tether公司等中心化机构发行的。
> > 3. 支持的区块链不同：LUSD是基于以太坊区块链发行的，而USDT则支持多个区块链，如以太坊、比特币等。
> > 4. 储备金不同：LUSD的价格稳定机制是基于抵押率的，而USDT则采用了储备金机制，即以等值的法定货币或其他实物资产作为储备金来维持价格稳定。
> > 5. 去中心化程度不同：LUSD是一个去中心化的稳定币协议，无需中心化机构来管理和发行，而USDT则是由中心化机构发行和管理的稳定币。
>
> 清算是什么意思
>
> > 在金融领域，清算是指在交易中完成交付和结算的过程。当债务人无法按时兑付债务时，清算也可以指将债务人的资产出售以偿还债务的过程。在加密货币领域，清算通常指在保证金交易中，当抵押物价值低于借款金额时，清算系统将强制平仓以保护贷方资产的过程。
> >
> > 在DeFi中，清算是指在去中心化借贷协议中，当某个用户的抵押品价值下跌到一定程度，无法维持其贷款的抵押率时，系统将自动强制清算该用户的抵押品，并使用清算所得资金来偿还贷款。这是保护协议稳定性和其他用户资产安全的一种机制。
> >
> > 清算通常会触发一些惩罚措施，例如处罚清算者（通常是协议中的流动性提供者）或收取清算费用等，以鼓励用户维护其抵押品的价值，避免触发清算机制。在去中心化金融中，清算机制是保证协议稳定性和可靠性的重要机制之一。
>
> 









<img src="https://cdn.jsdelivr.net/gh/lxiiiixi/Image-Hosting/Markdown/image-20230411103532091.png" alt="image-20230411103532091" style="zoom: 33%;" />
