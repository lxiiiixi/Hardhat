## Get Start

```bash
$ mkdir Greeting
$ cd Greeting
$ yarn init  # 包管理
$ yarn add --dev hardhat
$ npx hardhat # 初始化项目
$ npx hardhat compile  # 编译
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
