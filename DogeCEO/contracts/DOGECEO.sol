/**

    ██████╗░░█████╗░░██████╗░███████╗  ░█████╗░███████╗░█████╗░
    ██╔══██╗██╔══██╗██╔════╝░██╔════╝  ██╔══██╗██╔════╝██╔══██╗
    ██║░░██║██║░░██║██║░░██╗░█████╗░░  ██║░░╚═╝█████╗░░██║░░██║
    ██║░░██║██║░░██║██║░░╚██╗██╔══╝░░  ██║░░██╗██╔══╝░░██║░░██║
    ██████╔╝╚█████╔╝╚██████╔╝███████╗  ╚█████╔╝███████╗╚█████╔╝
    ╚═════╝░░╚════╝░░╚═════╝░╚══════╝  ░╚════╝░╚══════╝░╚════╝░
    ✅website https://DOGE.CEO

*/

// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.17;

// https://github.com/bnb-chain/BEPs/blob/master/BEP20.md
interface IBEP20 {
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

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _setOwner(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    // 放弃所有权：实现去中心化
    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

// https://docs.uniswap.org/contracts/v2/reference/smart-contracts/router-02
interface IRouter {
    function factory() external pure returns (address); // 返回工厂合约地址，用于创建新的交易对和流动性池

    function WETH() external pure returns (address); // 返回WETH地址

    function addLiquidityETH(
        // 添加ETH与其他代币的流动性
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

    // ETH 自动计算代币交换路径和价格，并将指定代币转换为 ETH，然后将 ETH 转入指定地址。
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path, // [tokenA, tokenB, WETH] 表示先将 tokenA 兑换为 tokenB，再将 tokenB 兑换为 WETH
        address to,
        uint256 deadline
    ) external;
}

library Address {
    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }
}

// 5% Reflections for Hodlers: Helping to fill your bag with DOGE
// 5% Marketing & Development: Giving us the immediate resources we need to promote and actively drive new investors to purchase.
contract DOGECEO is Context, IBEP20, Ownable {
    using Address for address payable; // 为 address payable 类型添加一些额外的函数

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances; // 存储每个地址的所有授权
    mapping(address => bool) private _isExcludedFromFee; // 存储每个地址的是否被排除在交易手续费中
    mapping(address => bool) private _isExcluded; // 存储每个地址的是否被排除在交易中

    address[] private _excluded;

    bool private swapping;

    IRouter public router;
    address public pair;

    uint8 private constant _decimals = 9;
    uint256 private constant MAX = ~uint256(0); // 2^256 - 1 最大的256位无符号整数

    uint256 private _tTotal = 420 * 10 ** 15 * 10 ** _decimals; // 代币总供应量
    uint256 private _rTotal = (MAX - (MAX % _tTotal)); // 代币的实际供应量（去除一些奖励代币）

    uint256 public swapTokensAtAmount = 1e14 * 10 ** _decimals; // 表示最小交换量（防止恶意用户进行小额攻击）

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;
    address public marketingWallet = 0xaa313121bd678d01880dad8Aa68E9B4fa8848DFD;

    string private constant _name = "Doge CEO";
    string private constant _symbol = "DOGECEO";

    struct Taxes {
        uint256 rfi;
        uint256 marketing;
    }

    Taxes public taxes = Taxes(5, 5);

    struct TotFeesPaidStruct {
        uint256 rfi;
        uint256 marketing;
    }

    TotFeesPaidStruct public totFeesPaid;

    struct valuesFromGetValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rRfi;
        uint256 rMarketing;
        uint256 tTransferAmount;
        uint256 tRfi;
        uint256 tMarketing;
    }

    modifier lockTheSwap() {
        // 防止重入攻击 确保同一时间内只有一个交换操作在进行
        swapping = true;
        _;
        swapping = false;
    }

    constructor(address routerAddress) {
        IRouter _router = IRouter(routerAddress);
        address _pair = IFactory(_router.factory()).createPair(
            address(this),
            _router.WETH()
        );

        router = _router;
        pair = _pair;

        excludeFromReward(pair);
        excludeFromReward(deadWallet);

        _rOwned[owner()] = _rTotal;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[marketingWallet] = true;
        _isExcludedFromFee[deadWallet] = true;
        emit Transfer(address(0), owner(), _tTotal);
    }

    //std BEP20:
    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    //override BEP20:
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
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

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "BEP20: transfer amount exceeds allowance"
        );
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "BEP20: decreased allowance below zero"
        );
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    // 查询某地址是否被排除在奖励外
    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    //
    function reflectionFromToken(
        uint256 tAmount,
        bool deductTransferRfi
    ) public view returns (uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferRfi) {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rAmount;
        } else {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rTransferAmount;
        }
    }

    function tokenFromReflection(
        uint256 rAmount
    ) public view returns (uint256) {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    //@dev kept original RFI naming -> "reward" as in reflection
    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is not excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function _reflectRfi(uint256 rRfi, uint256 tRfi) private {
        _rTotal -= rRfi;
        totFeesPaid.rfi += tRfi;
    }

    function _takeMarketing(uint256 rMarketing, uint256 tMarketing) private {
        totFeesPaid.marketing += tMarketing;

        if (_isExcluded[address(this)]) {
            _tOwned[address(this)] += tMarketing;
        }
        _rOwned[address(this)] += rMarketing;
    }

    function _getValues(
        uint256 tAmount,
        bool takeFee
    ) private view returns (valuesFromGetValues memory to_return) {
        to_return = _getTValues(tAmount, takeFee);
        (
            to_return.rAmount,
            to_return.rTransferAmount,
            to_return.rRfi,
            to_return.rMarketing
        ) = _getRValues(to_return, tAmount, takeFee, _getRate());

        return to_return;
    }

    // 根据tAmount和takeFee计算代币转移值
    function _getTValues(
        uint256 tAmount,
        bool takeFee
    ) private view returns (valuesFromGetValues memory s) {
        if (!takeFee) {
            // takeFee 为 false（标记为不收税）
            s.tTransferAmount = tAmount;
            return s;
        }

        s.tRfi = (tAmount * taxes.rfi) / 100; // 根据tAmount计算rfi
        s.tMarketing = (tAmount * taxes.marketing) / 100; // 根据tAmount计算marketing
        s.tTransferAmount = tAmount - s.tRfi - s.tMarketing; // 计算s的tTransferAmount
        return s;
    }

    function _getRValues(
        valuesFromGetValues memory s,
        uint256 tAmount,
        bool takeFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rRfi,
            uint256 rMarketing
        )
    {
        rAmount = tAmount * currentRate;

        if (!takeFee) {
            // takeFee 为 false（标记为不收税）
            return (rAmount, rAmount, 0, 0);
        }

        rRfi = s.tRfi * currentRate;
        rMarketing = s.tMarketing * currentRate;
        rTransferAmount = rAmount - rRfi - rMarketing;
        return (rAmount, rTransferAmount, rRfi, rMarketing);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply - _rOwned[_excluded[i]];
            tSupply = tSupply - _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(
            amount <= balanceOf(from),
            "You are trying to transfer more than your balance"
        );

        bool canSwap = balanceOf(address(this)) >= swapTokensAtAmount; // 交换量大于等于 swapTokensAtAmount 才能被正常处理 防止小额攻击
        if (
            !swapping &&
            canSwap &&
            from != pair &&
            !_isExcludedFromFee[from] &&
            !_isExcludedFromFee[to]
        ) {
            swapAndLiquify();
        }
        bool takeFee = true;
        if (swapping || _isExcludedFromFee[from] || _isExcludedFromFee[to])
            takeFee = false;

        _tokenTransfer(from, to, amount, takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        bool takeFee
    ) private {
        valuesFromGetValues memory s = _getValues(tAmount, takeFee);

        if (_isExcluded[sender]) {
            //from excluded
            _tOwned[sender] = _tOwned[sender] - tAmount;
        }
        if (_isExcluded[recipient]) {
            //to excluded
            _tOwned[recipient] = _tOwned[recipient] + s.tTransferAmount;
        }

        _rOwned[sender] = _rOwned[sender] - s.rAmount;
        _rOwned[recipient] = _rOwned[recipient] + s.rTransferAmount;

        if (s.rRfi > 0 || s.tRfi > 0) _reflectRfi(s.rRfi, s.tRfi);
        if (s.rMarketing > 0 || s.tMarketing > 0)
            _takeMarketing(s.rMarketing, s.tMarketing);
        emit Transfer(sender, recipient, s.tTransferAmount);
    }

    function swapAndLiquify() private lockTheSwap {
        uint256 contractBalance = balanceOf(address(this)); // 当前合约中的代币
        swapTokensForBNB(contractBalance); // 将当前合约中的代币换算成BNB
        uint256 deltaBalance = address(this).balance; // 当前合约地址中的 BNB 余额

        if (deltaBalance > 0) {
            // 将剩余的 BNB 转移到一个指定的地址中
            payable(marketingWallet).sendValue(deltaBalance);
        }
    }

    function swapTokensForBNB(uint256 tokenAmount) private {
        // generate the pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this); // 当前合约地址
        path[1] = router.WETH(); // WETH 地址

        _approve(address(this), address(router), tokenAmount); // 为 router 节点从当前合约地址中转移 tokenAmount 个代币

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function bulkExcludeFee(
        address[] memory accounts,
        bool state
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = state;
        }
    }

    receive() external payable {}
}
