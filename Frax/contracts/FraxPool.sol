// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./FXS.sol";
import "./Frax.sol";
import "./ERC20.sol";
// import '../../Uniswap/TransferHelper.sol';
import "./UniswapPairOracle.sol";
import "./AccessControl.sol";
// import "../../Utils/StringHelpers.sol";
import "./FraxPoolLibrary.sol";

import "hardhat/console.sol";

/*
   Same as FraxPool.sol, but has some gas optimizations

   - 用于铸造和赎回FRAX，以及回购多余抵押品的合约
   - Frax池合约是由治理系统部署和批准的，这意味着在治理提案成功执行后，可以随时添加新的抵押品类型
   - Frax池是一种智能合约，为用户存入抵押品来铸造Frax代币，或通过赎回发送到合约中的Frax来取回抵押品。每个Frax池都有不同类型的可接受抵押品。Frax 池可以支持任何类型的加密货币，但稳定币由于其价格的小波动，是最容易实现的。Frax的设计初衷是接受任何类型的加密货币作为抵押品，但低波动性池在一开始是首选，因为它们不会不规则地改变抵押品比率。
     每个池合约都有一个池上限(可存储用于铸造FRAX的最大允许抵押品)和资产的价格信息流。
     这些池通过对 FRAX 和 FRAXShare 合约的授权调用来创建和赎回协议代币。
   - 滑点：每个铸造和赎回函数都有一个AMOUNT_out_min参数，该参数指定交易者预期的最小代币单元。这作为提交交易时滑点范围的限制，因为从交易创建时到区块打包期间价格可能会发生变化。
*/

contract FraxPool is AccessControl {
    using SafeMath for uint256;

    // using FraxPoolLibrary for FraxPoolLibrary.MintFF_Params;
    // using FraxPoolLibrary for FraxPoolLibrary.BuybackFXS_Params;

    /* ========== STATE VARIABLES ========== */

    ERC20 private collateral_token; // 池子中抵押贷币的实例
    address private collateral_address; // 抵押贷币的地址
    address private owner_address; // 池子的所有者地址
    // address private oracle_address;
    address private frax_contract_address; // FRAX 合约地址
    address private fxs_contract_address; // FXS 合约地址
    address private timelock_address; // Timelock address for the governance contract
    FRAXShares private FXS; // FXS 合约实例
    FRAXStablecoin private FRAX; // FRAX 合约实例
    // UniswapPairOracle private oracle;
    UniswapPairOracle private collatEthOracle; // 抵押品和ETH的价格信息流
    address private collat_eth_oracle_address; // 抵押品和ETH的价格信息流的合约地址
    address private weth_address;

    uint256 private minting_fee;
    uint256 private redemption_fee; // 抵押费

    mapping(address => uint256) public redeemFXSBalances; // 跟踪给定地址的赎回余额。赎回者不能在同一个区块中同时请求赎回和实际赎回他们的 FRAX。这是为了防止可能导致 FRAX 和/或 FXS 价格崩溃的闪电贷漏洞利用。他们必须等到下一个区块。此特定变量用于赎回抵押中的 FXS 部分。
    mapping(address => uint256) public redeemCollateralBalances; // 同上，但是用于赎回抵押中抵押品的部分。

    uint256 public unclaimedPoolCollateral; // 抵押品余额的总额
    uint256 public unclaimedPoolFXS; // FXS余额的总额

    mapping(address => uint256) public lastRedeemed; // 用于记录给定地址赎回的最后一个区块

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant COLLATERAL_RATIO_PRECISION = 1e6;
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;

    // Number of decimals needed to get to 18
    uint256 private missing_decimals;

    // Pool_ceiling is the total units of collateral that a pool contract can hold
    uint256 public pool_ceiling = 0; // 池子可以接受的最大抵押品数量

    // Stores price of the collateral, if price is paused
    // 如果抵押品价格暂停，则存储抵押品价格。
    uint256 public pausedPrice = 0;

    // Bonus rate on FXS minted during recollateralizeFRAX(); 6 decimals of precision, set to 0.75% on genesis
    // 在recollateralizeFRAX()期间铸造的FXS奖励率
    uint256 public bonus_rate = 7500;

    // Number of blocks to wait before being able to collectRedemption()
    uint256 public redemption_delay = 1;

    // AccessControl Roles
    bytes32 private constant MINT_PAUSER = keccak256("MINT_PAUSER"); // 铸币暂停者
    bytes32 private constant REDEEM_PAUSER = keccak256("REDEEM_PAUSER"); // 赎回暂停者
    bytes32 private constant BUYBACK_PAUSER = keccak256("BUYBACK_PAUSER"); // 回购暂停者
    bytes32 private constant RECOLLATERALIZE_PAUSER =
        keccak256("RECOLLATERALIZE_PAUSER"); // 重新抵押暂停者
    bytes32 private constant COLLATERAL_PRICE_PAUSER =
        keccak256("COLLATERAL_PRICE_PAUSER"); // 抵押品价格暂停者

    // AccessControl state variables
    bool private mintPaused = false; // 记录是否暂停铸币功能
    bool private redeemPaused = false; // 记录是否暂停赎回功能
    bool private recollateralizePaused = false;
    bool private buyBackPaused = false;
    bool private collateralPricePaused = false;

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == timelock_address || msg.sender == owner_address,
            "You are not the owner or the governance timelock"
        );
        _;
    }

    modifier notRedeemPaused() {
        require(redeemPaused == false, "Redeeming is paused");
        _;
    }

    modifier notMintPaused() {
        require(mintPaused == false, "Minting is paused");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _frax_contract_address,
        address _fxs_contract_address,
        address _collateral_address,
        address _creator_address,
        address _timelock_address,
        uint256 _pool_ceiling
    ) public {
        FRAX = FRAXStablecoin(_frax_contract_address);
        FXS = FRAXShares(_fxs_contract_address);
        frax_contract_address = _frax_contract_address;
        fxs_contract_address = _fxs_contract_address;
        collateral_address = _collateral_address;
        timelock_address = _timelock_address;
        owner_address = _creator_address;
        collateral_token = ERC20(_collateral_address);
        pool_ceiling = _pool_ceiling;
        missing_decimals = uint(18).sub(collateral_token.decimals());

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        grantRole(MINT_PAUSER, timelock_address);
        grantRole(REDEEM_PAUSER, timelock_address);
        grantRole(RECOLLATERALIZE_PAUSER, timelock_address);
        grantRole(BUYBACK_PAUSER, timelock_address);
        grantRole(COLLATERAL_PRICE_PAUSER, timelock_address);
    }

    /* ========== VIEWS ========== */

    // Returns dollar value of collateral held in this Frax pool
    // 返回此 Frax 池中持有的抵押品 collateral_token 价值（以美元计）
    function collatDollarBalance() public view returns (uint256) {
        uint256 eth_usd_price = FRAX.eth_usd_price(); // 获取当前 ETH/USD 价格
        // 查询 weth 在交易对中的价格
        uint256 eth_collat_price = collatEthOracle.consult(
            weth_address,
            (PRICE_PRECISION * (10 ** missing_decimals))
        );

        // 计算 WETH/USD 价格：ETH/USD 价格乘以 PRICE_PRECISION 精度，再除以 WETH/ETH 的价格得到
        uint256 collat_usd_price = eth_usd_price.mul(PRICE_PRECISION).div(
            eth_collat_price
        );

        // 获取合约当前持有的 collateral_token 数量，减去未领取的 unclaimedPoolCollateral 数量
        return
            (
                collateral_token.balanceOf(address(this)).sub(
                    unclaimedPoolCollateral
                )
            ).mul(10 ** missing_decimals).mul(collat_usd_price).div(
                    PRICE_PRECISION
                ); //.mul(getCollateralPrice()).div(1e6);
    }

    // Returns the value of excess collateral held in this Frax pool, compared to what is needed to maintain the global collateral ratio
    // 返回此 Frax 池中持有的超额抵押品价值（超过抵押率要求的余额）
    // 超额抵押品是指合约中持有的抵押品价值超过了发行的 FRAX 的总价值，因此这个函数的结果表示，如果合约需要赎回所有 FRAX 并销毁它们，那么还剩下多少抵押品可以被赎回。
    function availableExcessCollatDV() public view returns (uint256) {
        uint256 total_supply = FRAX.totalSupply(); // 当前 FRAX 的总供应量
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio(); // 获取当前的全局抵押率
        uint256 global_collat_value = FRAX.globalCollateralValue(); // 获取当前的全局抵押品价值

        if (global_collateral_ratio > COLLATERAL_RATIO_PRECISION)
            // 如果超过了最大抵押率精度
            global_collateral_ratio = COLLATERAL_RATIO_PRECISION; // Handles an overcollateralized contract with CR > 1

        // 计算当前需要的抵押品价值，即每 1 个 FRAX 需要多少抵押品以当前抵押率的比例
        uint256 required_collat_dollar_value_d18 = (
            total_supply.mul(global_collateral_ratio)
        ).div(COLLATERAL_RATIO_PRECISION); // Calculates collateral needed to back each 1 FRAX with $1 of collateral at current collat ratio

        // 如果当前的全局抵押品价值超过了需要的抵押品价值，则返回两者之间的差值，即可用的超额抵押品价值。否则返回 0，表示没有可用的超额抵押品价值。
        if (global_collat_value > required_collat_dollar_value_d18)
            return global_collat_value.sub(required_collat_dollar_value_d18);
        else return 0;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    // Returns the price of the pool collateral in USD
    // 返回当前池子中 collateral_token 的价格（以美元计）
    function getCollateralPrice() public view returns (uint256) {
        if (collateralPricePaused == true) {
            // 处理特殊情况，例如抵押品价格暂停更新或者预言机出现故障的情况 => 返回预设的价格pausedPrice
            return pausedPrice;
        } else {
            uint256 eth_usd_price = FRAX.eth_usd_price();

            console.log(
                ">>>>>",
                address(FRAX),
                collatEthOracle.consult(
                    weth_address,
                    PRICE_PRECISION * (10 ** missing_decimals)
                )
            );
            return
                eth_usd_price.mul(PRICE_PRECISION).div(
                    // WETH 在交易对中的价格
                    collatEthOracle.consult(
                        weth_address,
                        PRICE_PRECISION * (10 ** missing_decimals)
                    )
                );
        }
    }

    function setCollatETHOracle(
        address _collateral_weth_oracle_address,
        address _weth_address
    ) external onlyByOwnerOrGovernance {
        collat_eth_oracle_address = _collateral_weth_oracle_address;
        collatEthOracle = UniswapPairOracle(_collateral_weth_oracle_address);
        weth_address = _weth_address;
    }

    /******************************************** Mint ******************************************/

    // We separate out the 1t1, fractional and algorithmic minting functions for gas efficiency
    // 1比1的铸币和赎回功能，从抵押品中铸造 FRAX（不需要FXS），只有在抵押率为100%时才可用。
    function mint1t1FRAX(
        uint256 collateral_amount,
        uint256 FRAX_out_min
    ) external notMintPaused {
        uint256 collateral_amount_d18 = collateral_amount *
            (10 ** missing_decimals);
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio();

        require(
            global_collateral_ratio >= COLLATERAL_RATIO_MAX,
            "Collateral ratio must be >= 1"
        );
        require(
            (collateral_token.balanceOf(address(this)))
                .sub(unclaimedPoolCollateral)
                .add(collateral_amount) <= pool_ceiling,
            "[Pool's Closed]: Ceiling reached"
        );

        uint256 frax_amount_d18 = FraxPoolLibrary.calcMint1t1FRAX(
            getCollateralPrice(),
            minting_fee,
            collateral_amount_d18
        ); //1 FRAX for each $1 worth of collateral

        require(FRAX_out_min <= frax_amount_d18, "Slippage limit reached");
        collateral_token.transferFrom(
            msg.sender,
            address(this),
            collateral_amount
        );
        FRAX.pool_mint(msg.sender, frax_amount_d18);
    }

    // 0% collateral-backed
    // 纯算法铸造和赎回函数，从抵押品和 FXS 中铸造 FRAX，只能在0%的比例可用。
    function mintAlgorithmicFRAX(
        uint256 fxs_amount_d18,
        uint256 FRAX_out_min
    ) external notMintPaused {
        uint256 fxs_price = FRAX.fxs_price();
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio();
        require(global_collateral_ratio == 0, "Collateral ratio must be 0");

        uint256 frax_amount_d18 = FraxPoolLibrary.calcMintAlgorithmicFRAX(
            minting_fee,
            fxs_price, // X FXS / 1 USD
            fxs_amount_d18
        );

        // libary 合约调用的两种调用有什么区别  （using）

        require(FRAX_out_min <= frax_amount_d18, "Slippage limit reached");
        FXS.pool_burn_from(msg.sender, fxs_amount_d18);
        FRAX.pool_mint(msg.sender, frax_amount_d18);
    }

    // Will fail if fully collateralized or fully algorithmic
    // > 0% and < 100% collateral-backed
    // 部分抵押铸造和赎回函数，从 FXS 中铸造 FRAX，仅在担保比率为99.99%和0.01%之间可用。
    function mintFractionalFRAX(
        uint256 collateral_amount,
        uint256 fxs_amount,
        uint256 FRAX_out_min
    ) external notMintPaused {
        uint256 frax_price = FRAX.frax_price();
        uint256 fxs_price = FRAX.fxs_price();
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio();

        require(
            global_collateral_ratio < COLLATERAL_RATIO_MAX &&
                global_collateral_ratio > 0,
            "Collateral ratio needs to be between .000001 and .999999"
        );
        require(
            collateral_token
                .balanceOf(address(this))
                .sub(unclaimedPoolCollateral)
                .add(collateral_amount) <= pool_ceiling,
            "Pool ceiling reached, no more FRAX can be minted with this collateral"
        );

        uint256 collateral_amount_d18 = collateral_amount *
            (10 ** missing_decimals);
        FraxPoolLibrary.MintFF_Params memory input_params = FraxPoolLibrary
            .MintFF_Params(
                minting_fee,
                fxs_price,
                frax_price,
                getCollateralPrice(),
                fxs_amount,
                collateral_amount_d18,
                (
                    collateral_token.balanceOf(address(this)).sub(
                        unclaimedPoolCollateral
                    )
                ),
                pool_ceiling,
                global_collateral_ratio
            );

        (uint256 mint_amount, uint256 fxs_needed) = FraxPoolLibrary
            .calcMintFractionalFRAX(input_params);

        require(FRAX_out_min <= mint_amount, "Slippage limit reached");
        require(fxs_needed <= fxs_amount, "Not enough FXS inputted");
        FXS.pool_burn_from(msg.sender, fxs_needed);
        collateral_token.transferFrom(
            msg.sender,
            address(this),
            collateral_amount
        );
        FRAX.pool_mint(msg.sender, mint_amount);
    }

    /******************************************** Redeem ******************************************/

    // Redeem collateral. 100% collateral-backed
    function redeem1t1FRAX(
        uint256 FRAX_amount,
        uint256 COLLATERAL_out_min
    ) external notRedeemPaused {
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio();
        require(
            global_collateral_ratio == COLLATERAL_RATIO_MAX,
            "Collateral ratio must be == 1"
        );

        // Need to adjust for decimals of collateral
        uint256 FRAX_amount_precision = FRAX_amount.div(10 ** missing_decimals);
        uint256 collateral_needed = FraxPoolLibrary.calcRedeem1t1FRAX(
            getCollateralPrice(),
            FRAX_amount_precision,
            redemption_fee
        );

        require(
            collateral_needed <=
                collateral_token.balanceOf(address(this)).sub(
                    unclaimedPoolCollateral
                ),
            "Not enough collateral in pool"
        );

        redeemCollateralBalances[msg.sender] = redeemCollateralBalances[
            msg.sender
        ].add(collateral_needed);
        unclaimedPoolCollateral = unclaimedPoolCollateral.add(
            collateral_needed
        );
        lastRedeemed[msg.sender] = block.number;

        require(
            COLLATERAL_out_min <= collateral_needed,
            "Slippage limit reached"
        );

        // Move all external functions to the end
        FRAX.pool_burn_from(msg.sender, FRAX_amount);
    }

    // Will fail if fully collateralized or algorithmic
    // Redeem FRAX for collateral and FXS. > 0% and < 100% collateral-backed
    function redeemFractionalFRAX(
        uint256 FRAX_amount,
        uint256 FXS_out_min,
        uint256 COLLATERAL_out_min
    ) external notRedeemPaused {
        uint256 fxs_price = FRAX.fxs_price();
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio();

        require(
            global_collateral_ratio < COLLATERAL_RATIO_MAX &&
                global_collateral_ratio > 0,
            "Collateral ratio needs to be between .000001 and .999999"
        );
        uint256 col_price_usd = getCollateralPrice();

        uint256 FRAX_amount_post_fee = FRAX_amount.sub(
            (FRAX_amount.mul(redemption_fee)).div(PRICE_PRECISION)
        );
        uint256 fxs_dollar_value_d18 = FRAX_amount_post_fee.sub(
            FRAX_amount_post_fee.mul(global_collateral_ratio).div(
                PRICE_PRECISION
            )
        );
        uint256 fxs_amount = fxs_dollar_value_d18.mul(PRICE_PRECISION).div(
            fxs_price
        );

        // Need to adjust for decimals of collateral
        uint256 FRAX_amount_precision = FRAX_amount_post_fee.div(
            10 ** missing_decimals
        );
        uint256 collateral_dollar_value = FRAX_amount_precision
            .mul(global_collateral_ratio)
            .div(PRICE_PRECISION);
        uint256 collateral_amount = collateral_dollar_value
            .mul(PRICE_PRECISION)
            .div(col_price_usd);

        redeemCollateralBalances[msg.sender] = redeemCollateralBalances[
            msg.sender
        ].add(collateral_amount);
        unclaimedPoolCollateral = unclaimedPoolCollateral.add(
            collateral_amount
        );

        redeemFXSBalances[msg.sender] = redeemFXSBalances[msg.sender].add(
            fxs_amount
        );
        unclaimedPoolFXS = unclaimedPoolFXS.add(fxs_amount);

        lastRedeemed[msg.sender] = block.number;

        require(
            collateral_amount <=
                collateral_token.balanceOf(address(this)).sub(
                    unclaimedPoolCollateral
                ),
            "Not enough collateral in pool"
        );
        require(
            COLLATERAL_out_min <= collateral_amount,
            "Slippage limit reached [collateral]"
        );
        require(FXS_out_min <= fxs_amount, "Slippage limit reached [FXS]");

        // Move all external functions to the end
        FRAX.pool_burn_from(msg.sender, FRAX_amount);
        FXS.pool_mint(address(this), fxs_amount);
    }

    // Redeem FRAX for FXS. 0% collateral-backed
    function redeemAlgorithmicFRAX(
        uint256 FRAX_amount,
        uint256 FXS_out_min
    ) external notRedeemPaused {
        uint256 fxs_price = FRAX.fxs_price();
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio();

        require(global_collateral_ratio == 0, "Collateral ratio must be 0");
        uint256 fxs_dollar_value_d18 = FRAX_amount;
        fxs_dollar_value_d18 = fxs_dollar_value_d18.sub(
            (fxs_dollar_value_d18.mul(redemption_fee)).div(PRICE_PRECISION)
        ); //apply redemption fee

        uint256 fxs_amount = fxs_dollar_value_d18.mul(PRICE_PRECISION).div(
            fxs_price
        );

        redeemFXSBalances[msg.sender] = redeemFXSBalances[msg.sender].add(
            fxs_amount
        );
        unclaimedPoolFXS = unclaimedPoolFXS.add(fxs_amount);

        lastRedeemed[msg.sender] = block.number;

        require(FXS_out_min <= fxs_amount, "Slippage limit reached");
        // Move all external functions to the end
        FRAX.pool_burn_from(msg.sender, FRAX_amount);
        FXS.pool_mint(address(this), fxs_amount);
    }

    /******************************************** Redeem ******************************************/

    // After a redemption happens, transfer the newly minted FXS and owed collateral from this pool
    // contract to the user. Redemption is split into two functions to prevent flash loans from being able
    // to take out FRAX/collateral from the system, use an AMM to trade the new price, and then mint back into the system.
    // 赎回发生后，将新铸造的 FXS 和所欠抵押品从该矿池合约转移给用户。
    // 赎回分为两个功能，以防止闪电贷能够从系统中取出 FRAX / 抵押品，使用 AMM 交易新价格，然后再铸币回系统
    function collectRedemption() external {
        require(
            (lastRedeemed[msg.sender].add(redemption_delay)) <= block.number,
            "Must wait for redemption_delay blocks before collecting redemption"
        );
        bool sendFXS = false;
        bool sendCollateral = false;
        uint FXSAmount;
        uint CollateralAmount;

        // Use Checks-Effects-Interactions pattern
        if (redeemFXSBalances[msg.sender] > 0) {
            FXSAmount = redeemFXSBalances[msg.sender];
            redeemFXSBalances[msg.sender] = 0;
            unclaimedPoolFXS = unclaimedPoolFXS.sub(FXSAmount);

            sendFXS = true;
        }

        if (redeemCollateralBalances[msg.sender] > 0) {
            CollateralAmount = redeemCollateralBalances[msg.sender];
            redeemCollateralBalances[msg.sender] = 0;
            unclaimedPoolCollateral = unclaimedPoolCollateral.sub(
                CollateralAmount
            );

            sendCollateral = true;
        }

        if (sendFXS == true) {
            FXS.transfer(msg.sender, FXSAmount);
        }
        if (sendCollateral == true) {
            collateral_token.transfer(msg.sender, CollateralAmount);
        }
    }

    // When the protocol is recollateralizing, we need to give a discount of FXS to hit the new CR target
    // Thus, if the target collateral ratio is higher than the actual value of collateral, minters get FXS for adding collateral
    // This function simply rewards anyone that sends collateral to a pool with the same amount of FXS + the bonus rate
    // Anyone can call this function to recollateralize the protocol and take the extra FXS value from the bonus rate as an arb opportunity
    function recollateralizeFRAX(
        uint256 collateral_amount,
        uint256 FXS_out_min
    ) external {
        require(recollateralizePaused == false, "Recollateralize is paused");
        uint256 collateral_amount_d18 = collateral_amount *
            (10 ** missing_decimals);
        uint256 fxs_price = FRAX.fxs_price();
        uint256 frax_total_supply = FRAX.totalSupply();
        uint256 global_collateral_ratio = FRAX.global_collateral_ratio();
        uint256 global_collat_value = FRAX.globalCollateralValue();

        (uint256 collateral_units, uint256 amount_to_recollat) = FraxPoolLibrary
            .calcRecollateralizeFRAXInner(
                collateral_amount_d18,
                getCollateralPrice(),
                global_collat_value,
                frax_total_supply,
                global_collateral_ratio
            );

        uint256 collateral_units_precision = collateral_units.div(
            10 ** missing_decimals
        );

        uint256 fxs_paid_back = amount_to_recollat
            .mul(uint(1e6).add(bonus_rate))
            .div(fxs_price);

        require(FXS_out_min <= fxs_paid_back, "Slippage limit reached");
        collateral_token.transferFrom(
            msg.sender,
            address(this),
            collateral_units_precision
        );
        FXS.pool_mint(msg.sender, fxs_paid_back);
    }

    // Function can be called by an FXS holder to have the protocol buy back FXS with excess collateral value from a desired collateral pool
    // This can also happen if the collateral ratio > 1
    // 让 FXS 持有者从指定的抵押池中以过剩抵押价值的价格回购 FXS
    function buyBackFXS(
        uint256 FXS_amount, // 回购的FAS数量
        uint256 COLLATERAL_out_min // 最少应该获得的抵押品数量
    ) external {
        require(buyBackPaused == false, "Buyback is paused");
        uint256 fxs_price = FRAX.fxs_price();

        FraxPoolLibrary.BuybackFXS_Params memory input_params = FraxPoolLibrary
            .BuybackFXS_Params(
                availableExcessCollatDV(),
                fxs_price,
                getCollateralPrice(),
                FXS_amount
            );

        uint256 collateral_equivalent_d18 = FraxPoolLibrary.calcBuyBackFXS(
            input_params
        );
        uint256 collateral_precision = collateral_equivalent_d18.div(
            10 ** missing_decimals
        );
        // 根据当前 FXS 价格和抵押品价格计算出回购 FXS 所需要的抵押品数量。如果回购价格低于 COLLATERAL_out_min 则会失败，因为这意味着回购价格低于用户的期望值，存在滑点风险。
        require(
            COLLATERAL_out_min <= collateral_precision,
            "Slippage limit reached"
        );
        // Give the sender their desired collateral and burn the FXS
        // 从调用者地址中销毁 FXS 并将对应数量的抵押品转移给调用者
        FXS.pool_burn_from(msg.sender, FXS_amount);
        collateral_token.transfer(msg.sender, collateral_precision);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function toggleMinting() external {
        require(hasRole(MINT_PAUSER, msg.sender));
        mintPaused = !mintPaused;
    }

    function toggleRedeeming() external {
        require(hasRole(REDEEM_PAUSER, msg.sender));
        redeemPaused = !redeemPaused;
    }

    function toggleRecollateralize() external {
        require(hasRole(RECOLLATERALIZE_PAUSER, msg.sender));
        recollateralizePaused = !recollateralizePaused;
    }

    function toggleBuyBack() external {
        require(hasRole(BUYBACK_PAUSER, msg.sender));
        buyBackPaused = !buyBackPaused;
    }

    function toggleCollateralPrice() external {
        require(hasRole(COLLATERAL_PRICE_PAUSER, msg.sender));
        // If pausing, set paused price; else if unpausing, clear pausedPrice
        if (collateralPricePaused == false) {
            pausedPrice = getCollateralPrice();
        } else {
            pausedPrice = 0;
        }
        collateralPricePaused = !collateralPricePaused;
    }

    // Combined into one function due to 24KiB contract memory limit
    function setPoolParameters(
        uint256 new_ceiling,
        uint256 new_bonus_rate,
        uint256 new_redemption_delay
    ) external onlyByOwnerOrGovernance {
        pool_ceiling = new_ceiling;
        bonus_rate = new_bonus_rate;
        redemption_delay = new_redemption_delay;
        minting_fee = FRAX.minting_fee();
        redemption_fee = FRAX.redemption_fee();
    }

    function setTimelock(
        address new_timelock
    ) external onlyByOwnerOrGovernance {
        timelock_address = new_timelock;
    }

    function setOwner(address _owner_address) external onlyByOwnerOrGovernance {
        owner_address = _owner_address;
    }

    /* ========== EVENTS ========== */
}
