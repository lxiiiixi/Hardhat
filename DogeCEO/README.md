# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a script that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat run scripts/deploy.js
```

# knowledge point

## abstract contract

[抽象合约](https://docs.soliditylang.org/en/v0.8.19/contracts.html#abstract-contracts)

抽象合约是指一种不能独立实例化的合约类型，它作为其他合约继承的蓝图。它包含一个或多个未定义的方法或函数，必须由继承它的合约来实现。

## Interface

https://docs.soliditylang.org/en/v0.8.19/contracts.html#interfaces

接口是 Solidity 中的一种抽象类型，它只定义了函数的签名和返回类型，而不包含函数的实现。因此，接口本身不能被实例化或调用，而是需要通过其他合约实现接口中定义的函数，以实现接口与合约之间的交互。

具体来说，如果一个合约想要实现某个接口，那么它需要实现接口中定义的所有函数，并保证这些函数的签名和返回类型与接口中定义的一致。这样，其他合约就可以通过接口调用这些函数，与该合约进行交互。

在 Solidity 中，**可以通过将接口的地址作为参数传递给其他合约，来实现接口与合约之间的交互**。例如，如果一个合约需要与一个实现了某个接口的合约进行交互，它可以将接口的地址作为参数传递给自己的函数，然后通过接口调用对应的函数。

以下是一个简单的示例，展示了如何使用接口与另一个合约进行交互：

```
pragma solidity ^0.8.0;

interface IMyContract {
    function myFunction() external returns (uint);
}

contract MyContract {
    IMyContract public otherContract;

    constructor(address _otherContract) {
        otherContract = IMyContract(_otherContract);
    }

    function callOtherContract() public returns (uint) {
        return otherContract.myFunction();
    }
}
```

在上面的代码中，`MyContract` 合约实现了一个 `IMyContract` 接口，并将另一个实现了该接口的合约的地址作为构造函数参数传入。然后，`MyContract` 合约中的 `callOtherContract` 函数可以通过接口调用对应的函数，与另一个合约进行交互。

## msg.data

`msg.data` 是 Solidity 中的一个全局变量，它包含了调用当前合约的函数时传递的所有数据。

在 Solidity 中，函数调用可以传递参数，这些参数可以是各种类型的数据。当函数被调用时，这些参数会被编码成字节数组并作为函数调用的一部分传递到合约中。`msg.data` 就是包含这些字节数组的变量。

在合约中，可以使用 `msg.data` 变量来访问传递给当前函数调用的数据。例如，可以使用 `msg.data.length` 获取传递数据的字节数，或者使用 `msg.data[0]` 获取传递数据的第一个字节。

需要注意的是，`msg.data` 变量是不可修改的，也就是说，不能在合约中修改它的值。此外，`msg.data` 只能在函数调用时使用，不能在合约的其他地方使用

## RIF

RFI 税率是一种针对去中心化交易所（DEX）或代币的税率，它的全称是 Reflective Finance Charge（反射性金融费用），也称为反射性机制（reflection mechanism）。

RFI 税率的基本原理是将每次代币交易中的一定比例（通常为交易金额的一定百分比）作为税收，然后将这个税收重新分配给所有持有该代币的人。这种机制类似于股息（dividend）或利息（interest），但与传统股票或债券不同的是，RFI 税率是实现在区块链上的自动化分配，而不需要中心化的金融机构或信托人来进行分配。

RFI 税率的实现一般需要使用智能合约技术，例如 Solidity 语言，来编写一个合约来实现自动化分配机制。在代币交易中，每次交易都会触发智能合约中的代码，从而收取一定比例的税收，并将其重新分配给所有持有该代币的人。这种机制可以促进代币的流通和交易，同时为持有者提供了一定的经济利益。

需要注意的是，RFI 税率是一种相对较新的机制，其具体实现方式和效果可能因不同的代币和智能合约而有所不同。在参与代币交易时，需要仔细了解和评估代币的税率机制和风险，并进行充分的研究和风险评估。

## Router











## 映射币的审计











分红

映射

交易对

土狗币的分红原理









































