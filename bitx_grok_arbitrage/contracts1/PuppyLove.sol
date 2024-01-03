/**
 *Submitted for verification at Etherscan.io on 2023-12-07
 */

/**
 *Submitted for verification at Etherscan.io on 2023-12-05
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.22;
import "hardhat/console.sol";

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function burn(uint256 amount) external returns (bool); // Add burn function

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Burn(address indexed from, uint256 value);
}

contract Ownable is Context {
    address private _owner;
    address private _previousOwner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

contract PuppyLove is Context, IERC20, Ownable {
    string private constant _name = "PuppyLoveCoin";
    string private constant _symbol = "PLC";
    uint8 private constant _decimals = 18;

    // t —— Transaction 实际的交易金额或在交易中涉及的金额
    // r —— Reflection 经过“反射”机制计算后的值
    mapping(address => uint256) private _rOwned; // 映射拥有
    mapping(address => uint256) private _tOwned; // 实际拥有
    mapping(address => mapping(address => uint256)) private _allowances; // 代币转账许可
    mapping(address => bool) private _isExcludedFromFee;
    uint256 private constant MAX = ~uint256(0); // (2^256 - 1)
    uint256 public _tTotal = 1000000000000 * 10 ** 18;
    uint256 public _rTotal = (MAX - (MAX % _tTotal)); // MAX 减去 _tTotal 这么多位数的余数
    uint256 private _tFeeTotal;
    uint256 private _redisFeeOnBuy = 0; // 重分配费用 —— 从交易所的 pair 合约转出的情况也就是 buy 的情况
    uint256 private _taxFeeOnBuy = 5; //
    uint256 private _redisFeeOnSell = 0;
    uint256 private _taxFeeOnSell = 5;

    //Original Fee
    uint256 private _redisFee = _redisFeeOnSell;
    uint256 private _taxFee = _taxFeeOnSell;

    uint256 private _previousredisFee = _redisFee;
    uint256 private _previoustaxFee = _taxFee;

    mapping(address => uint256) public _buyMap;
    address payable private _ownerAddress;
    address payable private _taxes =
        payable(0x273AfFd240228c0C6FEC0E8ca55106CCe4eb08a3);
    // address payable private _ownerAddress =
    //     payable(0xA958d20a63097f0ebadAF7580B450e60AEB377B9);

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    // bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = true;

    uint256 public _maxTxAmount = 10000000000 * 10 ** 18;
    uint256 public _maxWalletSize = 10000000000 * 10 ** 18;
    uint256 public _swapTokensAtAmount = 10000000000 * 10 ** 18;

    event MaxTxAmountUpdated(uint256 _maxTxAmount);
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }
    //events

    event SetFee(
        uint redisFeeBuy,
        uint redisFeeSell,
        uint taxFeeBuy,
        uint taxFeeSell
    );
    event updateMaxwalletSize(uint);
    event maxTxUpdate(uint);
    event swapToggle(bool);
    event setMinSwapThreshold(uint);

    constructor() {
        _ownerAddress = payable(owner());
        _rOwned[_ownerAddress] = _rTotal;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_ownerAddress] = true;
        _isExcludedFromFee[_taxes] = true;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    function burn(uint256 amount) public override onlyOwner returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

    function tokenFromReflection(
        uint256 rAmount
    ) private view returns (uint256) {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    // 对于不收费的情况，暂时用一个中间变量 _previousredisFee 和 _previoustaxFee 保存费用
    function removeAllFee() private {
        if (_redisFee == 0 && _taxFee == 0) return;

        _previousredisFee = _redisFee;
        _previoustaxFee = _taxFee;

        _redisFee = 0;
        _taxFee = 0;
    }

    // 恢复费用相关的变量
    function restoreAllFee() private {
        _redisFee = _previousredisFee;
        _taxFee = _previoustaxFee;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _rOwned[account] = _rOwned[account] - amount;
        _tTotal = _tTotal - amount;
        emit Transfer(account, address(0), amount);
        emit Burn(account, amount); // Emit the Burn event
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (from != owner() && to != owner()) {
            require(amount <= _maxTxAmount, "TOKEN: Max Transaction Limit");

            if (to != uniswapV2Pair) {
                require(
                    balanceOf(to) + amount < _maxWalletSize,
                    "TOKEN: Balance exceeds wallet size!"
                );
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            bool canSwap = contractTokenBalance >= _swapTokensAtAmount;

            if (contractTokenBalance >= _maxTxAmount) {
                contractTokenBalance = _maxTxAmount;
            }

            if (
                canSwap &&
                !inSwap &&
                from != uniswapV2Pair &&
                swapEnabled &&
                !_isExcludedFromFee[from] &&
                !_isExcludedFromFee[to]
            ) {
                swapTokensForEth(contractTokenBalance);
                uint256 contractETHBalance = address(this).balance;
                console.log("contractETHBalance", contractETHBalance);
                if (contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        bool takeFee = true;

        //Transfer Tokens
        if (
            (_isExcludedFromFee[from] || _isExcludedFromFee[to]) ||
            (from != uniswapV2Pair && to != uniswapV2Pair)
        ) {
            takeFee = false;
        } else {
            //Set Fee for Buys
            if (from == uniswapV2Pair && to != address(uniswapV2Router)) {
                _redisFee = _redisFeeOnBuy;
                _taxFee = _taxFeeOnBuy;
            }

            //Set Fee for Sells
            if (to == uniswapV2Pair && from != address(uniswapV2Router)) {
                _redisFee = _redisFeeOnSell;
                _taxFee = _taxFeeOnSell;
            }
        }

        _tokenTransfer(from, to, amount, takeFee);
    }

    // 使用当前合约中的代币去交易所中换取 WETH
    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        _taxes.transfer(amount);
    }

    function manualswap() external {
        require(_msgSender() == _ownerAddress);
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance);
    }

    function manualsend() external {
        require(_msgSender() == _ownerAddress);
        uint256 contractETHBalance = address(this).balance;
        sendETHToFee(contractETHBalance);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();
        _transferStandard(sender, recipient, amount);
        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tTeam
        ) = _getValues(tAmount);
        // 修改映射的数据
        _rOwned[sender] = _rOwned[sender] - rAmount;
        _rOwned[recipient] = _rOwned[recipient] + rTransferAmount;
        _takeTeam(tTeam); // 记录映射的团队收益
        _reflectFee(rFee, tFee);
        console.log("tTransferAmount", tFee, tTeam, tTransferAmount);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _takeTeam(uint256 tTeam) private {
        uint256 currentRate = _getRate();
        uint256 rTeam = tTeam * currentRate;
        _rOwned[address(this)] = _rOwned[address(this)] + rTeam;
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }

    receive() external payable {}

    function _getValues(
        uint256 tAmount
    )
        private
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        (uint256 tTransferAmount, uint256 tFee, uint256 tTeam) = _getTValues(
            tAmount,
            _redisFee,
            _taxFee
        );
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            tTeam,
            currentRate
        );
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tTeam);
    }

    // 计算交易中涉及的不同类型的“实际”值（T值，Transaction Values），
    // 包括实际转移的代币数量、重分配费用（redisFee），和税费（taxFee）。
    function _getTValues(
        uint256 tAmount,
        uint256 redisFee,
        uint256 taxFee
    ) private pure returns (uint256, uint256, uint256) {
        uint256 tFee = (tAmount * redisFee) / 100;
        uint256 tTeam = (tAmount * taxFee) / 100;
        uint256 tTransferAmount = (tAmount - tFee) - tTeam;
        return (tTransferAmount, tFee, tTeam);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tTeam,
        uint256 currentRate
    ) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount * currentRate;
        uint256 rFee = tFee * currentRate;
        uint256 rTeam = tTeam * currentRate;
        uint256 rTransferAmount = rAmount - rFee - rTeam;
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function setFee(
        uint256 redisFeeOnBuy,
        uint256 redisFeeOnSell,
        uint256 taxFeeOnBuy,
        uint256 taxFeeOnSell
    ) public onlyOwner {
        require(
            redisFeeOnBuy >= 0 && redisFeeOnBuy <= 4,
            "Buy rewards must be between 0% and 4%"
        );
        require(
            taxFeeOnBuy >= 0 && taxFeeOnBuy < 25,
            "Buy tax must be between 0% and 25%"
        );
        require(
            redisFeeOnSell >= 0 && redisFeeOnSell <= 4,
            "Sell rewards must be between 0% and 4%"
        );
        require(
            taxFeeOnSell >= 0 && taxFeeOnSell < 25,
            "Sell tax must be between 0% and 25%"
        );

        _redisFeeOnBuy = redisFeeOnBuy;
        _redisFeeOnSell = redisFeeOnSell;
        _taxFeeOnBuy = taxFeeOnBuy;
        _taxFeeOnSell = taxFeeOnSell;
        emit SetFee({
            redisFeeBuy: _redisFeeOnBuy,
            redisFeeSell: redisFeeOnSell,
            taxFeeBuy: taxFeeOnBuy,
            taxFeeSell: taxFeeOnSell
        });
    }

    //Set minimum tokens required to swap.
    function setMinSwapTokensThreshold(
        uint256 swapTokensAtAmount
    ) public onlyOwner {
        _swapTokensAtAmount = swapTokensAtAmount;
        emit setMinSwapThreshold(swapTokensAtAmount);
    }

    //Set minimum tokens required to swap.
    function toggleSwap(bool _swapEnabled) public onlyOwner {
        swapEnabled = _swapEnabled;
        emit swapToggle(_swapEnabled);
    }

    //Set maximum transaction
    function setMaxTxnAmount(uint256 maxTxAmount) public onlyOwner {
        _maxTxAmount = maxTxAmount;
        emit maxTxUpdate(maxTxAmount);
    }

    function setMaxWalletSize(uint256 maxWalletSize) public onlyOwner {
        _maxWalletSize = maxWalletSize;
        emit updateMaxwalletSize(_maxWalletSize);
    }

    function excludeMultipleAccountsFromFees(
        address[] calldata accounts,
        bool excluded
    ) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = excluded;
        }
    }
}
