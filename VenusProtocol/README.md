> Contract: https://github.com/VenusProtocol/venus-protocol/tree/develop/contracts
> Video introduction: https://www.youtube.com/watch?v=sDwR4cxkh5c

> Core dir: VRTVault Vault XVSVault



## Summary

- 部署
  - 分别部署代理合约和实现合约
  - 传入相关参数
  - 代理合约与实现合约的绑定

- 测试
  - 部署后的初始状态检查
  - 代码规范
    - 对于 public 的变量根据情况检查是不是没有必要又有一个专门的function读取
  - 对于转账交易
    - 先测试完全正常的交易流程（包括是否有onwer/admin权限）
    - 考虑授权和权限额度的问题
    - 考虑转账超出余额的情况等
  - 对于权限的转移
    - 重点关注的情况：比如 admin 设置了 pending admin，紧接着自己丢弃本身的admin 身份，但是日后某一天可以恢复自己的 admin 身份重新拥有权限。
    - 在正常的转移流程中思考，比如完成转移后 pendingadmin 有没有设置为零地址。
  - 质押操作
    - 
- Tips
  - 对于独立的合约可以分开单独来测试功能
  - 在对于某个函数的测试中，重点关注功能是否会出错，是否有漏洞 
  - 整体关注逻辑，细节看重功能
  - 会出现的问题大多数情况不在于功能，如果简单的只是测试功能的话，很多方法肉眼都能看出来是没有错误的根本不需要测试，更重要的是要想象一些额外的可能性，比比如一个操作完整的流程先走了一遍之后，思考一下中间可能会出现什么中断或者别的情况，说白了就是多考虑一些“就不走寻常路”的情况。







