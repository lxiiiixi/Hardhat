> 合约地址：https://bscscan.com/address/0xf5bde7eb378661f04c841b22ba057326b0370153#code

`````solidity
    function claimOwnership() public {
        require(msg.sender == _NEW_OWNER_, "INVALID_CLAIM");
        emit OwnershipTransferred(_OWNER_, _NEW_OWNER_);
        _OWNER_ = _NEW_OWNER_;
        _NEW_OWNER_ = address(0);
    }
    // 这个方法是需要被声明过的新的owner调用的
    // address(0)/address(0x0) 表示一个null/undefined的地址
`````

> - 流通燃烧率
>
>   流通燃烧率是指加密货币交易时产生的燃烧费用占交易额的比例。在某些加密货币的交易过程中，会收取一定的燃烧费用，这些费用会被销毁，不再进入任何人的钱包，从而减少了货币的总供应量，从而有助于抑制通货膨胀。交易燃烧率可以作为衡量加密货币交易活跃度的指标，因为交易量越大，产生的燃烧费用也会相应增加，从而提高交易燃烧率。
>
> - 流通费用率
>
>   区块链中的流通费用率（Transaction Fee Rate）是指在进行交易时，交易所需支付的费用与交易金额的比率。通常情况下，区块链上的交易需要得到矿工的验证和打包，以便被确认并记录在区块链上。为了鼓励矿工完成这一工作，交易发起人需要支付一定的费用，这个费用就是流通费用率。
>
>   在比特币等公链上，流通费用率通常是根据当前网络的交易量和矿工的工作量来决定的，当交易量增加时，矿工的工作量也会相应增加，因此流通费用率也会随之上升。而当交易量减少时，流通费用率也会下降。
>
>   流通费用率的高低直接影响到交易的速度和可靠性，如果流通费用率较低，交易可能会需要很长时间才能被确认，甚至被遗弃；而如果流通费用率较高，交易的速度会更快，但同时也需要支付更高的费用。因此，流通费用率的合理设置是区块链系统中重要的问题之一。

核心合约理解

```solidity
contract CustomERC20 is InitializableOwnable {
    using SafeMath for uint256; // 使用上面定义的 SafeMath library

    string public name; // 代币名称
    uint8 public decimals; // 代币精度
    string public symbol; // 符号
    uint256 public totalSupply; // 总发行量

    uint256 public tradeBurnRatio; // 交易燃烧率
    uint256 public tradeFeeRatio; // 交易
    address public team; // 团队地址

    mapping(address => uint256) balances; // 映射：地址 => 余额
    mapping(address => mapping(address => uint256)) internal allowed; 
    // 映射：地址 => （地址 => 许可的代币量）
    // 理解为：键是一个包含两个账户地址的数组，值是一个代币数量

    event Transfer(address indexed from, address indexed to, uint256 amount); // 代币转移事件
    event Approval(address indexed owner, address indexed spender, uint256 amount); // 授权许可事件

    event ChangeTeam(address oldTeam, address newTeam); // 团队改变事件


    function init( // 初始化的函数
        address _creator,
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _tradeBurnRatio,
        uint256 _tradeFeeRatio,
        address _team
    ) public {
        initOwner(_creator); // 初始化owner
        name = _name; 
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply;
        balances[_creator] = _totalSupply; // 给owner发送全部发行的代币
        require(_tradeBurnRatio >= 0 && _tradeBurnRatio <= 5000, "TRADE_BURN_RATIO_INVALID");
        require(_tradeFeeRatio >= 0 && _tradeFeeRatio <= 5000, "TRADE_FEE_RATIO_INVALID");
        tradeBurnRatio = _tradeBurnRatio;
        tradeFeeRatio = _tradeFeeRatio;
        team = _team;
        emit Transfer(address(0), _creator, _totalSupply);
    }
    
    // 合约发起者msg.sender调用，传入to和amount，触发交易事件
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender,to,amount);
        return true;
    }

		// 获取owner的余额
    function balanceOf(address owner) public view returns (uint256 balance) {
        return balances[owner];
    }
    
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        require(amount <= allowed[from][msg.sender], "ALLOWANCE_NOT_ENOUGH"); // 要求from账户需要有大于等于amount的转移许可量
        _transfer(from,to,amount);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowed[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

		// 获取owner给spender授权的许可数量
    function allowance(address owner, address spender) public view returns (uint256) {
        return allowed[owner][spender];
    }


    function _transfer( // 代币转移的具体实现
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address"); // sender和recipient都需要是有效地址
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(balances[sender] >= amount, "ERC20: transfer amount exceeds balance"); // sender的余额要大于amount

        balances[sender] = balances[sender].sub(amount); // 从sender的余额中减去amount数量

        uint256 burnAmount; // 定义燃烧代币数量
        uint256 feeAmount; // 费用数量
        if(tradeBurnRatio > 0) {
            burnAmount = amount.mul(tradeBurnRatio).div(10000);
            balances[address(0)] = balances[address(0)].add(burnAmount); // 销毁通过tradeBurnRatio计算得来的burnAmount的代币
            emit Transfer(sender, address(0), burnAmount);
        }

        if(tradeFeeRatio > 0) {
            feeAmount = amount.mul(tradeFeeRatio).div(10000);
            balances[team] = balances[team].add(feeAmount); // 给整个团队feeAmount数量的代币
            emit Transfer(sender, team, feeAmount);
        }
        
        uint256 receiveAmount = amount.sub(burnAmount).sub(feeAmount); // 最终接收者recipient接收的代币要减去burnAmount和feeAmount
        balances[recipient] = balances[recipient].add(receiveAmount);

        emit Transfer(sender, recipient, receiveAmount);
    }


    //=================== Ownable ======================
    // 修改team的账户
    function changeTeamAccount(address newTeam) external onlyOwner {
        require(tradeFeeRatio > 0, "NOT_TRADE_FEE_TOKEN"); 
        emit ChangeTeam(team,newTeam);
        team = newTeam;
    }

		// 禁止当前owner的权限 是只有owner才能执行的操作
    function abandonOwnership(address zeroAddress) external onlyOwner {
        require(zeroAddress == address(0), "NOT_ZERO_ADDRESS");
        emit OwnershipTransferred(_OWNER_, address(0));
        _OWNER_ = address(0);
    }
}
```





























