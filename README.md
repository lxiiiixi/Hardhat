## Get Start

```bash
$ mkdir Greeting
$ cd Greeting
$ yarn init  # 包管理
$ yarn add --dev hardhat
$ npx hardhat # 初始化项目
$ npx hardhat compile  # 编译
$ yarn add @openzeppelin/contracts@3.0.x # 安装OpenZeppelin(指定版本)
```

## [Command-line replace and completion](https://hardhat.org/hardhat-runner/docs/guides/command-line-completion#command-line-completion)

After doing this running `hh` will be equivalent to running `npx hardhat`. For example, instead of running `npx hardhat compile` you can run `hh compile`.

```bash
$ npx hardhat test
# equivalent to
$ hh test
```

## list_function 外部检查函数生成

在项目的根目录下复制工具文件 `list_functions` ，然后在根目录下执行 `./list_functions  合约存放地址`

```sh
$ ./list_functions -h   # help
```

例如：

```sh
liuxi@liuxideMacBook-Pro PNB % ./list_functions contracts/PinkBNB.sol
zsh: permission denied: ./list_functions
# 解决权限问题
liuxi@liuxideMacBook-Pro PNB % chmod +x ./list_functions
liuxi@liuxideMacBook-Pro PNB % ./list_functions contracts/PinkBNB.sol
Success! The result is written to PinkBNB.sol.md
# 被写入到根目录下了
```

## Hardhat 常用功能命令

```bash
npx hardhat flatten contracts/Foo.sol > Flattened.sol # 导出单一文件命令
```

## OpenZeppelin - Solidity 版本对应关系

> OpenZeppelin Doc: https://docs.openzeppelin.com/contracts/4.x/

| Solidity | OpenZeppelin         |
| -------- | -------------------- |
| 0.5.x    | 2.3.x - 2.5.x        |
| 0.6.x    | 3.0.x - 3.1.x 或 3.4 |
| 0.7.x    | 3.2.x - 3.3.x 或 3.4 |
| 0.8.x    | 4.0.x - 4.5.x        |

> OpenZeppelin v3.4 兼容 sol v0.6 和 sol v0.7

