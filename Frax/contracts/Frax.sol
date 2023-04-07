// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2; // 允许 Solidity 合约在函数参数和返回值中使用任意类型的动态数组和结构体，以及通过引用传递和返回结构体、数组等复杂类型。

import "hardhat/console.sol";

/*
Frax协议是一个双代币系统，包括
        稳定代币Frax (Frax) ———— Frax代币是Frax稳定币的主要代币，用于支付和储存价值，它是一种固定价值的代币，其价格与美元挂钩。（铸造FRAX需要将适当的抵押品和FXS代币放入Frax协议中）
        治理代币Frax Shares (FXS) ———— Frax协议的治理代币，用于参与协议的治理和决策。持有FXS代币的用户可以参与提案、投票和决策，从而影响协议的发展和运营。同时，FXS代币还可以用于支付Frax协议的各种手续费和奖励。

在95%的抵押率下，铸造1 FRAX将需要0.95美元的抵押品并burn掉价值0.05美元的FXS

该协议还拥有抵押品的合约池(创世阶段为USDT和USDC)。池子可以通过治理方式添加或删除。
FRAX、FXS和抵押品的价格都是根据Uniswap交易对价格和 Chainlink oracle预言机对ETH/USD价格的时间加权平均值计算出来的。
算法控制器使用这些数据来调整 Frax的供应量和价格，以保持 Frax 的价格在 $1.00 附近。
Frax 还采用了一种“弹性供应”机制，使得 Frax 的供应量能够根据市场需求自动调整。具体来说，当 Frax 的价格高于 1 美元时，Frax 的供应量会增加，当 Frax 的价格低于 1 美元时，Frax 的供应量会减少，以保持 Frax 的价格稳定在 1 美元左右。
Frax 还具有一种通缩机制，使得 Frax 的供应量能够逐渐减少。具体来说，当 Frax 的价格高于 1 美元时，Frax 的供应量会减少，以保持 Frax 的价格稳定在 1 美元左右。这种通缩机制可以帮助 Frax 稳定币更好地保持其稳定性和价值。
相关分享：https://illustrious-soup-aa9.notion.site/Frax-664105031f1b4347a3f927922b11f467

Oracle：Frax系统从两个外部系统获取价格信息: Chainlink 和Uniswap。系统记录来自Chainlink的ETH-USD价格，并将其应用于来自Uniswap的FRAX-wETH和FXS-wETH池余额，以获得准确的FRAX-USD和FXS-USD价格。这使得FRAX可以跟踪美元的真实价格，而不是一篮子链上稳定币的价格(这可能会显著偏离)。
Chainlink 预言机是ETH-USD价格的时间加权平均值，每小时更新一次。

*/

// import "./Context.sol";
// import "./IERC20.sol";
// import "./ERC20.sol";
import "./ERC20Custom.sol";
import "./SafeMath.sol";
import "./FXS.sol";
import "./FraxPool.sol";
import "./UniswapPairOracle.sol";
import "./ChainlinkETHUSDPriceConsumer.sol";
import "./AccessControl.sol";

// 如果是使用了标准模版库中的合约就不需要测试

contract FRAXStablecoin is ERC20Custom, AccessControl {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    enum PriceChoice {
        FRAX,
        FXS
    }

    ChainlinkETHUSDPriceConsumer private eth_usd_pricer;
    // ChainlinkETHUSDPriceConsumer 包含获取 ETH/USD 价格数据的功能。

    uint8 private eth_usd_pricer_decimals; // 由 eth_usd_pricer.decimals() 返回的小数位数

    // 由 UniswapPairOracle 合约实例化的两个变量
    UniswapPairOracle private fraxEthOracle; // FRAX / WETH 在Uniswap上的价格预言机实例。
    UniswapPairOracle private fxsEthOracle; // FXS / WETH 在Uniswap上的价格预言机实例。

    string public symbol;
    string public name;
    uint8 public constant decimals = 18;

    address public owner_address; // 拥有特权操作的所有者地址数组
    address public creator_address; // 合约创造者地址
    address public timelock_address; // 时间锁合约的地址
    address public controller_address; // 治理合约的地址
    address public fxs_address; // FXS 合约地址
    address public frax_eth_oracle_address; // fraxEthOracle地址
    address public fxs_eth_oracle_address; // fxsEthOracle 地址
    address public weth_address; // 标准Wrapped-Ethereum（WETH）合约地址
    address public eth_usd_consumer_address; // ChainlinkETHUSDPriceConsumer 地址

    uint256 public constant genesis_supply = 2000000e18; // 2M FRAX (only for testing, genesis supply will be 5k on Mainnet). This is to help with establishing the Uniswap pools, as they need liquidity
    // FRAX创世供应。应该为一个小的非零数量。大部分FRAX供应来自铸币，但一开始需要少量，以防止各种功能中的零除错误。

    // The addresses in this array are added by the oracle and these contracts are able to mint frax
    // 这个数组中的地址是由Oracle添加的，这些合约能够铸造Frax。
    address[] public frax_pools_array; // 所有 FraxPool 合约地址

    // Mapping is also used for faster verification
    mapping(address => bool) public frax_pools;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;

    uint256 public global_collateral_ratio; // 6 decimals of precision, e.g. 924102 = 0.924102
    // 在所有FraxPool中，当前FRAX与抵押品的比率。

    uint256 public redemption_fee; // 将FRAX兑换成FXS和或抵押品的费用。以及用FXS回购多余抵押品的费用。参见FraxPool合约用例。
    uint256 public minting_fee; // 用FXS和或其他抵押物铸造FRAX的费用。参见 FraxPool 合约用例。

    uint256 public frax_step; // Amount to change the collateralization ratio by upon refreshCollateralRatio()
    // 在刷新抵押率时，每次调整的抵押率量

    uint256 public refresh_cooldown; // Seconds to wait before being able to run refreshCollateralRatio() again
    // 再次运行refreshCollateralRatio()之前等待的秒数

    uint256 public price_target; // The price of FRAX at which the collateral ratio will respond to; this value is only used for the collateral ratio mechanism and not for minting and redeeming which are hardcoded at $1
    // 一个价格目标：$1，当价格低于这个价格目标时，会增加抵押率，当价格高于这个价格目标时，会降低抵押率。

    uint256 public price_band; // The bound above and below the price target at which the refreshCollateralRatio() will not change the collateral ratio
    // 价格波动范围 动态调整全局的抵押率时使用 想要修改的话onlyByOwnerOrGovernance
    // refreshCollateralRatio() 不会改变抵押率的价格目标上下限

    address public DEFAULT_ADMIN_ADDRESS;
    // bytes32 是一个固定长度为 32 字节的字节数组，可以用于存储哈希值、密钥、标识符等。
    // 作为一个标识符用于标记在合约中存储的某个状态变量或映射是否被授权暂停抵押率（collateral ratio）的编辑
    bytes32 public constant COLLATERAL_RATIO_PAUSER =
        keccak256("COLLATERAL_RATIO_PAUSER");
    bool public collateral_ratio_paused = false; // 抵押品比率是否暂停。

    /* ========== MODIFIERS ========== */

    // 限定只有被授权暂停抵押率（collateral ratio）的编辑的地址才能调用该函数，针对指定抵押品比率的限制操作。
    modifier onlyCollateralRatioPauser() {
        // hasRole是内置函数，用于检查某个地址是否被授权某个角色，这里就是检查 msg.sender
        require(hasRole(COLLATERAL_RATIO_PAUSER, msg.sender));
        _;
    }

    // 限定只有Frax池的合约才能调用该函数，比如铸造新的Frax
    modifier onlyPools() {
        require(
            frax_pools[msg.sender] == true,
            "Only frax pools can call this function"
        );
        _;
    }

    // 限定只有合约的owner、控制器、或者治理时间锁的地址才能调用该函数
    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == owner_address ||
                msg.sender == timelock_address ||
                msg.sender == controller_address,
            "You are not the owner, controller, or the governance timelock"
        );
        _;
    }

    // 限定只有合约的owner、或者治理时间锁、frax_pools中存在的地址才能调用该函数
    modifier onlyByOwnerGovernanceOrPool() {
        require(
            msg.sender == owner_address ||
                msg.sender == timelock_address ||
                frax_pools[msg.sender] == true,
            "You are not the owner, the governance timelock, or a pool"
        );
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        string memory _name,
        string memory _symbol,
        address _creator_address,
        address _timelock_address
    ) public {
        name = _name;
        symbol = _symbol;
        creator_address = _creator_address;
        timelock_address = _timelock_address;

        // _setupRole 是 Solidity 的一个内置函数，它用于在合约中为某个角色授予访问权限。
        // 这里是将当前执行函数的调用者授予默认管理员角色的访问权限
        // Grant the contract deployer the default admin role: it will be able to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        DEFAULT_ADMIN_ADDRESS = _msgSender();
        owner_address = _creator_address;
        _mint(creator_address, genesis_supply); // ERC20Custom
        grantRole(COLLATERAL_RATIO_PAUSER, creator_address);
        grantRole(COLLATERAL_RATIO_PAUSER, timelock_address);
        frax_step = 2500; // 6 decimals of precision, equal to 0.25%
        global_collateral_ratio = 1000000; // Frax system starts off fully collateralized (6 decimals of precision)
        refresh_cooldown = 3600; // Refresh cooldown period is set to 1 hour (3600 seconds) at genesis
        price_target = 1000000; // Collateral ratio will adjust according to the $1 price target at genesis
        price_band = 5000; // Collateral ratio will not adjust if between $0.995 and $1.005 at genesis
    }

    /* ========== VIEWS ========== */

    // 查询FRAX或FXS相对于USD的价格
    /**
     * 例如此时:
     * eth_usd_price 为 1876776959，也就是 1ETH = 1876.776959 USD
     * 通过 Uniswap Oracle 查询到: Frax/ETH 的价格为 1088301226（1088.301226 USD） ｜ FXS/ETH 的价格为 165958731（165.958731 USD）
     * frax_price 为 1724501 1ETH = 1.724501 USD
     * fxs_price 为 11308696，也就是 1ETH = 11.308696 USD
     */
    function oracle_price(PriceChoice choice) internal view returns (uint256) {
        // 计算过程：最新ETH/USD的价格 * 1e6 / (10 ** 18)
        uint256 eth_usd_price = uint256(eth_usd_pricer.getLatestPrice())
            .mul(PRICE_PRECISION)
            .div(uint256(10) ** eth_usd_pricer_decimals);
        uint256 price_vs_eth;

        // 查询 FRAX/ETH 或 FXS/ETH 的价格
        // 这一步得到的 price_vs_eth 表示将 PRICE_PRECISION 个 WETH 存入系统后，会获得多少个 FRAX 或 FXS（相对于 ETH）
        if (choice == PriceChoice.FRAX) {
            price_vs_eth = uint256(
                fraxEthOracle.consult(weth_address, PRICE_PRECISION)
            ); // How much FRAX if you put in PRICE_PRECISION WETH
        } else if (choice == PriceChoice.FXS) {
            price_vs_eth = uint256(
                fxsEthOracle.consult(weth_address, PRICE_PRECISION)
            ); // How much FXS if you put in PRICE_PRECISION WETH
        } else
            revert(
                "INVALID PRICE CHOICE. Needs to be either 0 (FRAX) or 1 (FXS)"
            );

        console.log("price_vs_eth: %s", price_vs_eth);

        // Will be in 1e6 format
        // 将 ETH/USD 价格和 FRAX/ETH 或 FXS/ETH 价格相除，得到 FRAX/USD 或 FXS/USD 的价格
        return eth_usd_price.mul(PRICE_PRECISION).div(price_vs_eth);
    }

    // Returns X FRAX = 1 USD（1usd可以换取多少个FRAX）
    function frax_price() public view returns (uint256) {
        return oracle_price(PriceChoice.FRAX);
    }

    // Returns X FXS = 1 USD（1usd可以换取多少个FXS）
    function fxs_price() public view returns (uint256) {
        return oracle_price(PriceChoice.FXS);
    }

    // 获取最新的 ETH/USD 的价格
    function eth_usd_price() public view returns (uint256) {
        return
            uint256(eth_usd_pricer.getLatestPrice()).mul(PRICE_PRECISION).div(
                uint256(10) ** eth_usd_pricer_decimals
            );
    }

    // This is needed to avoid costly repeat calls to different getter functions
    // It is cheaper gas-wise to just dump everything and only use some of the info
    // 一次性获取所有需要的信息，避免对不同的getter函数的昂贵重复调用
    function frax_info()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            oracle_price(PriceChoice.FRAX), // frax_price()
            oracle_price(PriceChoice.FXS), // fxs_price()
            totalSupply(), // totalSupply()
            global_collateral_ratio, // global_collateral_ratio()
            globalCollateralValue(), // globalCollateralValue
            minting_fee, // minting_fee()
            redemption_fee, // redemption_fee()
            uint256(eth_usd_pricer.getLatestPrice()).mul(PRICE_PRECISION).div(
                uint256(10) ** eth_usd_pricer_decimals
            ) //eth_usd_price
        );
    }

    // Iterate through all frax pools and calculate all value of collateral in all pools globally
    // 遍历所有的frax池并计算全局所有池中抵押品的总价值，这里采用了每个抵押品的预言机价格。
    function globalCollateralValue() public view returns (uint256) {
        uint256 total_collateral_value_d18 = 0;

        for (uint i = 0; i < frax_pools_array.length; i++) {
            // Exclude null addresses
            if (frax_pools_array[i] != address(0)) {
                total_collateral_value_d18 = total_collateral_value_d18.add(
                    // 得到每个池的抵押品 collateral_token 的价值
                    FraxPool(frax_pools_array[i]).collatDollarBalance()
                );
            }
        }
        return total_collateral_value_d18;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    // There needs to be a time interval that this can be called. Otherwise it can be called multiple times per expansion.
    // 必须设置一个时间间隔来调用此操作，否则可能会在扩展期间被多次调用。
    uint256 public last_call_time; // Last time the refreshCollateralRatio function was called

    // 根据当前的 FRAX/USD 价格动态刷新调整全局的抵押率 global_collateral_ratio  =>  系统可以控制抵押品与发行的稳定币的比例
    // 如果价格高于1美元，则比率降低 frax_step。如果价格低于1美元，则比率增加 frax_step。任何人都可以点击这个函数来改变比率。这个函数每小时只能调用一次。
    function refreshCollateralRatio() public {
        require(
            collateral_ratio_paused == false,
            "Collateral Ratio has been paused"
        );
        uint256 frax_price_cur = frax_price(); // FRAX/USD当前价格

        require( // 保证当前时间大于上次调用时间加上冷却时间（refresh_cooldown 初始时为1h，确保这个函数每小时之内调用一次）
            block.timestamp - last_call_time >= refresh_cooldown,
            "Must wait for the refresh cooldown since last refresh"
        );

        // Step increments are 0.25% (upon genesis, changable by setFraxStep())

        if (frax_price_cur > price_target.add(price_band)) {
            // 如果当前价格 frax_price_cur > 目标价格 price_target + 波动范围 price_band  =>   减少 global_collateral_ratio 并使其不低于 0
            if (global_collateral_ratio <= frax_step) {
                // if within a step of 0, go to 0
                global_collateral_ratio = 0;
            } else {
                global_collateral_ratio = global_collateral_ratio.sub(
                    frax_step
                );
            }
        } else if (frax_price_cur < price_target.sub(price_band)) {
            // 如果当前价格 frax_price_cur > 目标价格 price_target + 波动范围 price_band   =>   增加 global_collateral_ratio 并使其不超过 1000000
            if (global_collateral_ratio.add(frax_step) >= 1000000) {
                global_collateral_ratio = 1000000; // cap collateral ratio at 1.000000
            } else {
                global_collateral_ratio = global_collateral_ratio.add(
                    frax_step
                );
            }
        }

        last_call_time = block.timestamp; // Set the time of the last expansion
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Used by pools when user redeems  当用户赎回时由池子使用
    // 从指定的池子地址 b_address 中销毁一定数量的 FRAX（只有池子管理员可以调用）
    function pool_burn_from(
        address b_address,
        uint256 b_amount
    ) public onlyPools {
        // 调用父合约 ERC20Custom 中的 _burnFrom 函数
        super._burnFrom(b_address, b_amount);
        emit FRAXBurned(b_address, msg.sender, b_amount);
    }

    // This function is what other frax pools will call to mint new FRAX
    // 其他的 frax 池子会调用此函数来发行新的 FRAX（发新的新币会给 m_address）,在 FraxPool.sol 中被调用
    function pool_mint(address m_address, uint256 m_amount) public onlyPools {
        // 调用父合约 ERC20Custom 中的 _mint 函数
        super._mint(m_address, m_amount);
        emit FRAXMinted(msg.sender, m_address, m_amount);
    }

    // Adds collateral addresses supported, such as tether and busd, must be ERC20
    // 添加支持的抵押品地址，例如tether和busd，必须是ERC20
    // 用于向 frax_pools 添加新的池子地址，以便该合约能够与其他池子合约进行交互。例如，如果该合约需要从其他池子合约中购买或者销售资产，那么就需要将这些池子合约的地址添加到 frax_pools 中，以便能够在代码中直接引用这些池子合约的地址。
    function addPool(address pool_address) public onlyByOwnerOrGovernance {
        require(frax_pools[pool_address] == false, "address already exists"); // 不允许添加重复的池子地址
        frax_pools[pool_address] = true;
        frax_pools_array.push(pool_address);
    }

    // Remove a pool
    function removePool(address pool_address) public onlyByOwnerOrGovernance {
        require(
            frax_pools[pool_address] == true,
            "address doesn't exist already"
        );

        // Delete from the mapping
        delete frax_pools[pool_address];

        // 'Delete' from the array by setting the address to 0x0
        for (uint i = 0; i < frax_pools_array.length; i++) {
            if (frax_pools_array[i] == pool_address) {
                frax_pools_array[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }
    }

    function setOwner(address _owner_address) external onlyByOwnerOrGovernance {
        owner_address = _owner_address; // 重置合约管理员
    }

    function setRedemptionFee(uint256 red_fee) public onlyByOwnerOrGovernance {
        redemption_fee = red_fee;
    }

    function setMintingFee(uint256 min_fee) public onlyByOwnerOrGovernance {
        minting_fee = min_fee;
    }

    function setFraxStep(uint256 _new_step) public onlyByOwnerOrGovernance {
        frax_step = _new_step; // 设置抵押品比率在执行 refreshCollateralRatio() 时改变的数量
    }

    function setPriceTarget(
        uint256 _new_price_target
    ) public onlyByOwnerOrGovernance {
        price_target = _new_price_target; // 设置用于刷新抵押品比率()的价格目标(不影响铸造/赎回)
    }

    // 设置refresh_cooldown，用控制抵每次押率刷新的时间间隔（初始时设置的为1h）
    function setRefreshCooldown(
        uint256 _new_cooldown
    ) public onlyByOwnerOrGovernance {
        refresh_cooldown = _new_cooldown;
    }

    function setFXSAddress(
        address _fxs_address
    ) public onlyByOwnerOrGovernance {
        fxs_address = _fxs_address;
    }

    function setETHUSDOracle(
        address _eth_usd_consumer_address
    ) public onlyByOwnerOrGovernance {
        eth_usd_consumer_address = _eth_usd_consumer_address;
        eth_usd_pricer = ChainlinkETHUSDPriceConsumer(eth_usd_consumer_address);
        eth_usd_pricer_decimals = eth_usd_pricer.getDecimals();
    }

    function setTimelock(
        address new_timelock
    ) external onlyByOwnerOrGovernance {
        timelock_address = new_timelock;
    }

    function setController(
        address _controller_address
    ) external onlyByOwnerOrGovernance {
        controller_address = _controller_address;
    }

    function setPriceBand(
        uint256 _price_band
    ) external onlyByOwnerOrGovernance {
        price_band = _price_band;
    }

    // Sets the FRAX_ETH Uniswap oracle address
    function setFRAXEthOracle(
        address _frax_oracle_addr,
        address _weth_address
    ) public onlyByOwnerOrGovernance {
        frax_eth_oracle_address = _frax_oracle_addr;
        fraxEthOracle = UniswapPairOracle(_frax_oracle_addr);
        weth_address = _weth_address;
    }

    // Sets the FXS_ETH Uniswap oracle address
    // 设置 FXS/ETH 价格预言机合约的地址和 WETH 合约的地址
    function setFXSEthOracle(
        address _fxs_oracle_addr,
        address _weth_address
    ) public onlyByOwnerOrGovernance {
        fxs_eth_oracle_address = _fxs_oracle_addr;
        fxsEthOracle = UniswapPairOracle(_fxs_oracle_addr);
        weth_address = _weth_address;
    }

    function toggleCollateralRatio() public onlyCollateralRatioPauser {
        collateral_ratio_paused = !collateral_ratio_paused; // 切换抵押品比率的暂停/取消暂停功能
    }

    /* ========== EVENTS ========== */

    // Track FRAX burned
    // 通常是来自一笔池子的赎回
    event FRAXBurned(address indexed from, address indexed to, uint256 amount);

    // Track FRAX minted
    event FRAXMinted(address indexed from, address indexed to, uint256 amount);
}
