// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ITroveManager.sol";
import "./Interfaces/ILUSDToken.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedTroves.sol";
import "./Interfaces/ILQTYStaking.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";

/*
 * 包含借款人与其 Trove 交互的基本操作：Trove 创建、ETH 充值/取款、稳定币发行和还款。
 * 它还将发行费用发送到 LQTYStaking 合约。
 * BorrowerOperations 函数调用 TroveManager，告诉它在必要时更新 Trove 状态。
 * BorrowerOperations 函数还调用各种池，告诉他们在必要时在池之间或池 <> 用户之间移动以太币/代币。
 */

contract BorrowerOperations is
    LiquityBase,
    Ownable,
    CheckContract,
    IBorrowerOperations
{
    string public constant NAME = "BorrowerOperations";

    // --- Connected contract declarations ---

    ITroveManager public troveManager;

    address stabilityPoolAddress;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    ILQTYStaking public lqtyStaking;
    address public lqtyStakingAddress;

    ILUSDToken public lusdToken;

    // A doubly linked list of Troves, sorted by their collateral ratios
    ISortedTroves public sortedTroves;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

    struct LocalVariables_adjustTrove {
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint newTCR;
        uint LUSDFee;
        uint newDebt;
        uint newColl;
        uint stake;
    }

    struct LocalVariables_openTrove {
        uint price; // ETH:USD 价格
        uint LUSDFee; // (如果不恢复模式)通过 troveManager.getBorrowingFee(_LUSDAmount) 计算得到的 LUSD 借款费用
        uint netDebt; // (如果不恢复模式)netDebt = _LUSDAmount + LUSDFee,(如果是恢复模式)netDebt = _LUSDAmount
        uint compositeDebt; // netDebt + LUSD_GAS_COMPENSATION(200e18)
        uint ICR; // (compositeDebt>0)ICR = msg.value * price
        uint NICR; // msg.value * 1e20 / compositeDebt
        uint stake; // 当前调用者在 troveManager 中创建的 Trove 的 stake 数量
        uint arrayIndex; // 当前 Trove 在 troveManager 中存储的所有 Troves 中的索引
    }

    struct ContractsCache {
        ITroveManager troveManager;
        IActivePool activePool;
        ILUSDToken lusdToken;
    }

    enum BorrowerOperation {
        openTrove,
        closeTrove,
        adjustTrove
    }

    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event StabilityPoolAddressChanged(address _stabilityPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event LUSDTokenAddressChanged(address _lusdTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);

    event TroveCreated(address indexed _borrower, uint arrayIndex);
    event TroveUpdated(
        address indexed _borrower,
        uint _debt,
        uint _coll,
        uint stake,
        BorrowerOperation operation
    );
    event LUSDBorrowingFeePaid(address indexed _borrower, uint _LUSDFee);

    // --- Dependency setters ---

    function setAddresses(
        address _troveManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedTrovesAddress,
        address _lusdTokenAddress,
        address _lqtyStakingAddress
    ) external override onlyOwner {
        // This makes impossible to open a trove with zero withdrawn LUSD
        assert(MIN_NET_DEBT > 0);

        checkContract(_troveManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_sortedTrovesAddress);
        checkContract(_lusdTokenAddress);
        checkContract(_lqtyStakingAddress);

        troveManager = ITroveManager(_troveManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        stabilityPoolAddress = _stabilityPoolAddress;
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        sortedTroves = ISortedTroves(_sortedTrovesAddress);
        lusdToken = ILUSDToken(_lusdTokenAddress);
        lqtyStakingAddress = _lqtyStakingAddress;
        lqtyStaking = ILQTYStaking(_lqtyStakingAddress);

        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit SortedTrovesAddressChanged(_sortedTrovesAddress);
        emit LUSDTokenAddressChanged(_lusdTokenAddress);
        emit LQTYStakingAddressChanged(_lqtyStakingAddress);

        _renounceOwnership();
    }

    // --- Borrower Trove Operations ---
    /**
     * @dev 支付函数，为调用者创建一个 Trove，请求债务，接收的 Ether 作为抵押品。
     * @param _maxFeePercentage 最大费用百分比，以 1e18 为单位。如果借款费用超过此值，则交易将失败。
     * @param _LUSDAmount 借款的 LUSD 数量，以 1e18 为单位。
     * @param _upperHint 上一个 Trove 的地址，用于计算新 Trove 的位置。
     * @param _lowerHint 下一个 Trove 的地址，用于计算新 Trove 的位置。
     *
     * 成功执行的条件主要取决于产生的抵押率，该比率必须超过最小值（正常模式下为 110%，恢复模式下为 150%）。
     * 除了要求的债务外，还会发行额外的债务来支付发行费，并支付 gas 补偿。
     * 借款人必须提供他/她愿意接受的 _maxFeePercentage，以防出现费用滑点，即首先处理赎回交易，从而推高发行费用。
     */
    function openTrove(
        uint _maxFeePercentage,
        uint _LUSDAmount,
        address _upperHint,
        address _lowerHint
    ) external payable override {
        ContractsCache memory contractsCache = ContractsCache(
            troveManager, // 当前 trove 的管理合约
            activePool,
            lusdToken
        );
        LocalVariables_openTrove memory vars; // 专门用于存储 openTove 临时变量的结构体变量

        vars.price = priceFeed.fetchPrice(); // ETH:USD 价格
        bool isRecoveryMode = _checkRecoveryMode(vars.price); // LiquityBase 合约中的方法，检查是否处于恢复模式(当 Total Collateral Ratio < 150% 时，进入恢复模式)
        console.log("vars.price:", vars.price);

        _requireValidMaxFeePercentage(_maxFeePercentage, isRecoveryMode); // 检查最大费用百分比是否合法
        _requireTroveisNotActive(contractsCache.troveManager, msg.sender); // 检查当前调用者是否已经有 trove

        vars.LUSDFee;
        vars.netDebt = _LUSDAmount;

        if (!isRecoveryMode) {
            // 如果不是恢复模式，计算 LUSD 借款费用并mint这个数量的 LUSD 给 LQTY staking 合约
            // what _triggerBorrowingFee do: (根据计算得到的 LUSD, _maxFeePercentage 和 _LUSDAmount 确保用户可以接受多余的费用 )
            // 1. calculate the LUSD fee
            // 2. send fee to LQTY staking contract
            // 3. mint LUSD to the LQTY staking contract()
            vars.LUSDFee = _triggerBorrowingFee(
                contractsCache.troveManager,
                contractsCache.lusdToken,
                _LUSDAmount,
                _maxFeePercentage
            );
            vars.netDebt = vars.netDebt.add(vars.LUSDFee); // 借款费用 + 借款金额
            console.log(isRecoveryMode, vars.LUSDFee, vars.netDebt);
        }
        _requireAtLeastMinNetDebt(vars.netDebt); // 检查借款金额是否大于最小借款金额

        // ICR is based on the composite debt, i.e. the requested LUSD amount + LUSD borrowing fee + LUSD gas comp.
        // ICR（Initial Collateral Ratio - 初始保证金比率）基于组合债务，即请求的LUSD金额+LUSD借款费用+LUSD燃气补偿。
        vars.compositeDebt = _getCompositeDebt(vars.netDebt); // vars.netDebt +  LUSD_GAS_COMPENSATION
        assert(vars.compositeDebt > 0);

        vars.ICR = LiquityMath._computeCR(
            msg.value,
            vars.compositeDebt,
            vars.price
        );
        vars.NICR = LiquityMath._computeNominalCR(
            msg.value,
            vars.compositeDebt
        );

        if (isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR);
        } else {
            _requireICRisAboveMCR(vars.ICR);
            // 计算系统的总抵押率 TCR，确保 TCR < 系统关键抵押率 CCR(150%)
            uint newTCR = _getNewTCRFromTroveChange(
                msg.value,
                true,
                vars.compositeDebt,
                true,
                vars.price
            ); // bools: coll increase, debt increase
            _requireNewTCRisAboveCCR(newTCR);
        }

        // 上面都是对于 var 结构体变量的一些计算和赋值操作
        // 下面开始对于合约的一些操作
        /**
         * troveManager：
         * 1. setTroveStatus：记录当前 Trove 的状态为 Active
         * 2. increaseTroveColl：记录当前 Trove 的抵押物数量
         * 3. increaseTroveDebt：记录当前 Trove 的债务数量
         * 4. updateTroveRewardSnapshots：更新当前 Trove 在 TroveRewardSnapshots 中的快照
         * 5. updateStakeAndTotalStakes：更新并记录当前 Trove 的抵押物价值 stake
         * 6. addTroveOwnerToArray：将当前 Trove 的地址添加到 Trove 所有者列表中
         *
         * sortedTroves：
         * 1. insert：将当前 Trove 插入到 sortedTroves 中
         */

        // Set the trove struct's properties
        contractsCache.troveManager.setTroveStatus(msg.sender, 1); // 记录当前 Trove 的状态为 Active
        contractsCache.troveManager.increaseTroveColl(msg.sender, msg.value); // 记录当前 Trove 的抵押物数量
        contractsCache.troveManager.increaseTroveDebt( // 记录当前 Trove 的混合债务数量
            msg.sender,
            vars.compositeDebt
        );

        contractsCache.troveManager.updateTroveRewardSnapshots(msg.sender); // 更新当前 Trove 在 TroveRewardSnapshots 中的快照
        // 根据msg.value计算当前Trove新的抵押物价值
        vars.stake = contractsCache.troveManager.updateStakeAndTotalStakes(
            msg.sender // emit TotalStakesUpdated(totalStakes);
        );

        sortedTroves.insert(msg.sender, vars.NICR, _upperHint, _lowerHint); // 将当前 Trove 插入到 Trove 双向链表中
        vars.arrayIndex = contractsCache.troveManager.addTroveOwnerToArray( // 将当前 Trove 的地址添加到 Trove 所有者列表中，记录并返回当前 Trove 的索引
            msg.sender
        );
        emit TroveCreated(msg.sender, vars.arrayIndex);

        // Move the ether to the Active Pool, and mint the LUSDAmount to the borrower
        // 将以太币转移到 Active Pool
        _activePoolAddColl(contractsCache.activePool, msg.value);
        // 增加 Active Pool 中记录的LUSD借款数量（vars.netDebt），并 mint LUSDAmount 数量的 LUSD 给借款人
        _withdrawLUSD(
            contractsCache.activePool,
            contractsCache.lusdToken,
            msg.sender,
            _LUSDAmount,
            vars.netDebt
        );
        // Move the LUSD gas compensation to the Gas Pool
        // 和上述同理，只不过是将 LUSD_GAS_COMPENSATION 数量的 LUSD 给 Gas Pool
        _withdrawLUSD(
            contractsCache.activePool,
            contractsCache.lusdToken,
            gasPoolAddress,
            LUSD_GAS_COMPENSATION,
            LUSD_GAS_COMPENSATION
        );

        // Active Pool 中增加了两次 LUSD 的借款数量，分别是 vars.netDebt 和 LUSD_GAS_COMPENSATION

        emit TroveUpdated(
            msg.sender,
            vars.compositeDebt,
            msg.value,
            vars.stake,
            BorrowerOperation.openTrove
        );
        emit LUSDBorrowingFeePaid(msg.sender, vars.LUSDFee);
    }

    // Send ETH as collateral to a trove
    function addColl(
        address _upperHint,
        address _lowerHint
    ) external payable override {
        _adjustTrove(msg.sender, 0, 0, false, _upperHint, _lowerHint, 0);
    }

    // Send ETH as collateral to a trove. Called by only the Stability Pool.
    function moveETHGainToTrove(
        address _borrower,
        address _upperHint,
        address _lowerHint
    ) external payable override {
        _requireCallerIsStabilityPool();
        _adjustTrove(_borrower, 0, 0, false, _upperHint, _lowerHint, 0);
    }

    // Withdraw ETH collateral from a trove
    function withdrawColl(
        uint _collWithdrawal,
        address _upperHint,
        address _lowerHint
    ) external override {
        _adjustTrove(
            msg.sender,
            _collWithdrawal,
            0,
            false,
            _upperHint,
            _lowerHint,
            0
        );
    }

    // Withdraw LUSD tokens from a trove: mint new LUSD tokens to the owner, and increase the trove's debt accordingly
    function withdrawLUSD(
        uint _maxFeePercentage,
        uint _LUSDAmount,
        address _upperHint,
        address _lowerHint
    ) external override {
        _adjustTrove(
            msg.sender,
            0,
            _LUSDAmount,
            true,
            _upperHint,
            _lowerHint,
            _maxFeePercentage
        );
    }

    // Repay LUSD tokens to a Trove: Burn the repaid LUSD tokens, and reduce the trove's debt accordingly
    function repayLUSD(
        uint _LUSDAmount,
        address _upperHint,
        address _lowerHint
    ) external override {
        _adjustTrove(
            msg.sender,
            0,
            _LUSDAmount,
            false,
            _upperHint,
            _lowerHint,
            0
        );
    }

    function adjustTrove(
        uint _maxFeePercentage,
        uint _collWithdrawal,
        uint _LUSDChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable override {
        _adjustTrove(
            msg.sender,
            _collWithdrawal,
            _LUSDChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _maxFeePercentage
        );
    }

    /*
     * _adjustTrove(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal.
     * It therefore expects either a positive msg.value, or a positive _collWithdrawal argument.
     * If both are positive, it will revert.
     *
     * 除了债务变化外，此函数还可以执行抵押品的补充或提取。
     * 因此，它期望正的 msg.value 或正的 _collWithdrawal 参数。如果两者都是正数，它将会回滚。
     *
     */
    function _adjustTrove(
        address _borrower, // 借款人地址
        uint _collWithdrawal, // 抵押物提取/存入数量
        uint _LUSDChange, // 借入/偿还的 LUSD 数量
        bool _isDebtIncrease, // 是否继续借入 LUSD（债务是否增加）
        address _upperHint, // 上一个 Trove 的地址
        address _lowerHint, // 下一个 Trove 的地址
        uint _maxFeePercentage
    ) internal {
        // 这里声明了一个名为 contractsCache 的 ContractsCache 结构体变量，并将其初始化为一个新的 ContractsCache 对象。
        ContractsCache memory contractsCache = ContractsCache(
            troveManager,
            activePool,
            lusdToken
        );
        LocalVariables_adjustTrove memory vars;

        vars.price = priceFeed.fetchPrice(); // 获取当前的 ETH:USD 价格
        bool isRecoveryMode = _checkRecoveryMode(vars.price); // 检查是否处于 Recovery Mode

        if (_isDebtIncrease) {
            _requireValidMaxFeePercentage(_maxFeePercentage, isRecoveryMode);
            _requireNonZeroDebtChange(_LUSDChange);
        }
        _requireSingularCollChange(_collWithdrawal); // 保证用户是抵押（抵押物提取的数量_collWithdrawal为0）
        _requireNonZeroAdjustment(_collWithdrawal, _LUSDChange);
        _requireTroveisActive(contractsCache.troveManager, _borrower);

        // Confirm the operation is either a borrower adjusting their own trove, or a pure ETH transfer from the Stability Pool to a trove
        assert(
            msg.sender == _borrower ||
                (msg.sender == stabilityPoolAddress &&
                    msg.value > 0 &&
                    _LUSDChange == 0)
        );

        contractsCache.troveManager.applyPendingRewards(_borrower);

        // Get the collChange based on whether or not ETH was sent in the transaction
        // 根据是否在交易中发送了 ETH 来获判断本次操作是抵押还是提取
        (vars.collChange, vars.isCollIncrease) = _getCollChange(
            msg.value, // 如果是抵押，msg.value 为抵押物
            _collWithdrawal // 如果是提取，_collWithdrawal 为提取的抵押物数量
        );

        vars.netDebtChange = _LUSDChange;

        // If the adjustment incorporates a debt increase and system is in Normal Mode, then trigger a borrowing fee
        if (_isDebtIncrease && !isRecoveryMode) {
            // 计算本次借入的 LUSD 的手续费并增加债务
            vars.LUSDFee = _triggerBorrowingFee(
                contractsCache.troveManager,
                contractsCache.lusdToken,
                _LUSDChange,
                _maxFeePercentage
            );
            vars.netDebtChange = vars.netDebtChange.add(vars.LUSDFee); // The raw debt change includes the fee
        }

        vars.debt = contractsCache.troveManager.getTroveDebt(_borrower);
        vars.coll = contractsCache.troveManager.getTroveColl(_borrower);

        // Get the trove's old ICR before the adjustment, and what its new ICR will be after the adjustment
        vars.oldICR = LiquityMath._computeCR(vars.coll, vars.debt, vars.price);
        vars.newICR = _getNewICRFromTroveChange(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease,
            vars.price
        );
        assert(_collWithdrawal <= vars.coll);

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(
            isRecoveryMode,
            _collWithdrawal,
            _isDebtIncrease,
            vars
        );

        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough LUSD
        if (!_isDebtIncrease && _LUSDChange > 0) {
            _requireAtLeastMinNetDebt(
                _getNetDebt(vars.debt).sub(vars.netDebtChange)
            );
            _requireValidLUSDRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientLUSDBalance(
                contractsCache.lusdToken,
                _borrower,
                vars.netDebtChange
            );
        }

        (vars.newColl, vars.newDebt) = _updateTroveFromAdjustment(
            contractsCache.troveManager,
            _borrower,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );
        vars.stake = contractsCache.troveManager.updateStakeAndTotalStakes(
            _borrower
        );

        // Re-insert trove in to the sorted list
        uint newNICR = _getNewNominalICRFromTroveChange(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            _isDebtIncrease
        );
        sortedTroves.reInsert(_borrower, newNICR, _upperHint, _lowerHint);

        emit TroveUpdated(
            _borrower,
            vars.newDebt,
            vars.newColl,
            vars.stake,
            BorrowerOperation.adjustTrove
        );
        emit LUSDBorrowingFeePaid(msg.sender, vars.LUSDFee);

        // Use the unmodified _LUSDChange here, as we don't send the fee to the user
        _moveTokensAndETHfromAdjustment(
            contractsCache.activePool,
            contractsCache.lusdToken,
            msg.sender,
            vars.collChange,
            vars.isCollIncrease,
            _LUSDChange,
            _isDebtIncrease,
            vars.netDebtChange
        );
    }

    // send all remaining eth from ActivePool to msg.sender
    function closeTrove() external override {
        ITroveManager troveManagerCached = troveManager;
        IActivePool activePoolCached = activePool;
        ILUSDToken lusdTokenCached = lusdToken;

        _requireTroveisActive(troveManagerCached, msg.sender); // 确保用户的 Trove 是 active 状态
        uint price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(price);

        // 查询当前用户是否有待领取的 LQTY 奖励，如果有，则先领取
        troveManagerCached.applyPendingRewards(msg.sender);

        // 分别查询当前用户的 Trove 的抵押物和债务
        uint coll = troveManagerCached.getTroveColl(msg.sender);
        uint debt = troveManagerCached.getTroveDebt(msg.sender);

        // 需要保证用户的 LUSD 余额 >= 用户减去了存在gaspool中的的混合债务（借款数量+需要支付的借款费）
        _requireSufficientLUSDBalance(
            lusdTokenCached,
            msg.sender,
            debt.sub(LUSD_GAS_COMPENSATION)
        );

        // 计算系统新的总抵押率并确保高于系统关键抵押率CCR（触发恢复模式）
        uint newTCR = _getNewTCRFromTroveChange(
            coll,
            false,
            debt,
            false,
            price
        );
        _requireNewTCRisAboveCCR(newTCR);

        troveManagerCached.removeStake(msg.sender); // 将用户的 stake 记录修改为 0
        troveManagerCached.closeTrove(msg.sender); // 修改 Troves mapping 中当前用户的数据和状态

        emit TroveUpdated(msg.sender, 0, 0, 0, BorrowerOperation.closeTrove);

        // Burn the repaid LUSD from the user's balance and the gas compensation from the Gas Pool
        _repayLUSD(
            activePoolCached,
            lusdTokenCached,
            msg.sender,
            debt.sub(LUSD_GAS_COMPENSATION)
        );
        _repayLUSD(
            activePoolCached,
            lusdTokenCached,
            gasPoolAddress,
            LUSD_GAS_COMPENSATION
        );

        // Send the collateral back to the user
        activePoolCached.sendETH(msg.sender, coll);
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
     * 在 Recovery 模式下，通过赎回或清算中的 ICR > MCR 来索取剩余抵押物。
     */
    function claimCollateral() external override {
        // send ETH from CollSurplus Pool to owner
        collSurplusPool.claimColl(msg.sender);
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(
        ITroveManager _troveManager,
        ILUSDToken _lusdToken,
        uint _LUSDAmount,
        uint _maxFeePercentage
    ) internal returns (uint) {
        _troveManager.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        uint LUSDFee = _troveManager.getBorrowingFee(_LUSDAmount); // 获取LUSD借款费用

        _requireUserAcceptsFee(LUSDFee, _LUSDAmount, _maxFeePercentage); // 确保该用户接受该费用

        // Send fee to LQTY staking contract
        lqtyStaking.increaseF_LUSD(LUSDFee); // 将LUSD借款费用增加到LQTY质押合约中
        console.log("123123", LUSDFee);
        _lusdToken.mint(lqtyStakingAddress, LUSDFee); // 将LUSD借款费用增加到LQTY质押合约中

        return LUSDFee;
    }

    function _getUSDValue(
        uint _coll,
        uint _price
    ) internal pure returns (uint) {
        uint usdValue = _price.mul(_coll).div(DECIMAL_PRECISION);

        return usdValue;
    }

    function _getCollChange(
        uint _collReceived,
        uint _requestedCollWithdrawal
    ) internal pure returns (uint collChange, bool isCollIncrease) {
        if (_collReceived != 0) {
            collChange = _collReceived;
            isCollIncrease = true;
        } else {
            collChange = _requestedCollWithdrawal;
        }
    }

    // Update trove's coll and debt based on whether they increase or decrease
    function _updateTroveFromAdjustment(
        ITroveManager _troveManager,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    ) internal returns (uint, uint) {
        uint newColl = (_isCollIncrease)
            ? _troveManager.increaseTroveColl(_borrower, _collChange)
            : _troveManager.decreaseTroveColl(_borrower, _collChange);
        uint newDebt = (_isDebtIncrease)
            ? _troveManager.increaseTroveDebt(_borrower, _debtChange)
            : _troveManager.decreaseTroveDebt(_borrower, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndETHfromAdjustment(
        IActivePool _activePool,
        ILUSDToken _lusdToken,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _LUSDChange,
        bool _isDebtIncrease,
        uint _netDebtChange
    ) internal {
        if (_isDebtIncrease) {
            _withdrawLUSD(
                _activePool,
                _lusdToken,
                _borrower,
                _LUSDChange,
                _netDebtChange
            );
        } else {
            _repayLUSD(_activePool, _lusdToken, _borrower, _LUSDChange);
        }

        if (_isCollIncrease) {
            _activePoolAddColl(_activePool, _collChange);
        } else {
            _activePool.sendETH(_borrower, _collChange);
        }
    }

    // Send ETH to Active Pool and increase its recorded ETH balance
    function _activePoolAddColl(
        IActivePool _activePool,
        uint _amount
    ) internal {
        (bool success, ) = address(_activePool).call{value: _amount}("");
        require(success, "BorrowerOps: Sending ETH to ActivePool failed");
    }

    // Issue the specified amount of LUSD to _account and increases the total active debt (_netDebtIncrease potentially includes a LUSDFee)
    // 向_account发行指定数量的LUSD，并增加总活跃债务（_netDebtIncrease可能包括LUSDFee）。
    function _withdrawLUSD(
        IActivePool _activePool,
        ILUSDToken _lusdToken,
        address _account,
        uint _LUSDAmount,
        uint _netDebtIncrease
    ) internal {
        _activePool.increaseLUSDDebt(_netDebtIncrease); // 增加 ActivePool 中记录的LUSD借款数量
        _lusdToken.mint(_account, _LUSDAmount); // mint _LUSDAmount 数量的 LUSD 给 _account
    }

    // Burn the specified amount of LUSD from _account and decreases the total active debt
    function _repayLUSD(
        IActivePool _activePool,
        ILUSDToken _lusdToken,
        address _account,
        uint _LUSD
    ) internal {
        _activePool.decreaseLUSDDebt(_LUSD);
        _lusdToken.burn(_account, _LUSD);
    }

    // --- 'Require' wrapper functions ---

    function _requireSingularCollChange(uint _collWithdrawal) internal view {
        require(
            msg.value == 0 || _collWithdrawal == 0,
            "BorrowerOperations: Cannot withdraw and add coll"
        );
    }

    function _requireCallerIsBorrower(address _borrower) internal view {
        require(
            msg.sender == _borrower,
            "BorrowerOps: Caller must be the borrower for a withdrawal"
        );
    }

    function _requireNonZeroAdjustment(
        uint _collWithdrawal,
        uint _LUSDChange
    ) internal view {
        require(
            msg.value != 0 || _collWithdrawal != 0 || _LUSDChange != 0,
            "BorrowerOps: There must be either a collateral change or a debt change"
        );
    }

    function _requireTroveisActive(
        ITroveManager _troveManager,
        address _borrower
    ) internal view {
        uint status = _troveManager.getTroveStatus(_borrower);
        require(status == 1, "BorrowerOps: Trove does not exist or is closed");
    }

    function _requireTroveisNotActive(
        ITroveManager _troveManager,
        address _borrower
    ) internal view {
        uint status = _troveManager.getTroveStatus(_borrower);
        require(status != 1, "BorrowerOps: Trove is active");
    }

    function _requireNonZeroDebtChange(uint _LUSDChange) internal pure {
        require(
            _LUSDChange > 0,
            "BorrowerOps: Debt increase requires non-zero debtChange"
        );
    }

    function _requireNotInRecoveryMode(uint _price) internal view {
        require(
            !_checkRecoveryMode(_price),
            "BorrowerOps: Operation not permitted during Recovery Mode"
        );
    }

    function _requireNoCollWithdrawal(uint _collWithdrawal) internal pure {
        require(
            _collWithdrawal == 0,
            "BorrowerOps: Collateral withdrawal not permitted Recovery Mode"
        );
    }

    function _requireValidAdjustmentInCurrentMode(
        bool _isRecoveryMode,
        uint _collWithdrawal,
        bool _isDebtIncrease,
        LocalVariables_adjustTrove memory _vars
    ) internal view {
        /*
         *In Recovery Mode, only allow:
         *
         * - Pure collateral top-up
         * - Pure debt repayment
         * - Collateral top-up with debt repayment
         * - A debt increase combined with a collateral top-up which makes the ICR >= 150% and improves the ICR (and by extension improves the TCR).
         *
         * In Normal Mode, ensure:
         *
         * - The new ICR is above MCR
         * - The adjustment won't pull the TCR below CCR
         */
        if (_isRecoveryMode) {
            _requireNoCollWithdrawal(_collWithdrawal);
            if (_isDebtIncrease) {
                _requireICRisAboveCCR(_vars.newICR);
                _requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
            }
        } else {
            // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR);
            _vars.newTCR = _getNewTCRFromTroveChange(
                _vars.collChange,
                _vars.isCollIncrease,
                _vars.netDebtChange,
                _isDebtIncrease,
                _vars.price
            );
            _requireNewTCRisAboveCCR(_vars.newTCR);
        }
    }

    function _requireICRisAboveMCR(uint _newICR) internal pure {
        require(
            _newICR >= MCR,
            "BorrowerOps: An operation that would result in ICR < MCR is not permitted"
        );
    }

    function _requireICRisAboveCCR(uint _newICR) internal pure {
        require(
            _newICR >= CCR,
            "BorrowerOps: Operation must leave trove with ICR >= CCR"
        );
    }

    function _requireNewICRisAboveOldICR(
        uint _newICR,
        uint _oldICR
    ) internal pure {
        require(
            _newICR >= _oldICR,
            "BorrowerOps: Cannot decrease your Trove's ICR in Recovery Mode"
        );
    }

    // 确保 系统的总抵押率 TCR < 系统关键抵押率 CCR(150%)
    function _requireNewTCRisAboveCCR(uint _newTCR) internal pure {
        require(
            _newTCR >= CCR,
            "BorrowerOps: An operation that would result in TCR < CCR is not permitted"
        );
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require(
            _netDebt >= MIN_NET_DEBT,
            "BorrowerOps: Trove's net debt must be greater than minimum"
        );
    }

    function _requireValidLUSDRepayment(
        uint _currentDebt,
        uint _debtRepayment
    ) internal pure {
        require(
            _debtRepayment <= _currentDebt.sub(LUSD_GAS_COMPENSATION),
            "BorrowerOps: Amount repaid must not be larger than the Trove's debt"
        );
    }

    function _requireCallerIsStabilityPool() internal view {
        require(
            msg.sender == stabilityPoolAddress,
            "BorrowerOps: Caller is not Stability Pool"
        );
    }

    function _requireSufficientLUSDBalance(
        ILUSDToken _lusdToken,
        address _borrower,
        uint _debtRepayment
    ) internal view {
        require(
            _lusdToken.balanceOf(_borrower) >= _debtRepayment,
            "BorrowerOps: Caller doesnt have enough LUSD to make repayment"
        );
    }

    function _requireValidMaxFeePercentage(
        uint _maxFeePercentage,
        bool _isRecoveryMode
    ) internal pure {
        if (_isRecoveryMode) {
            require(
                _maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must less than or equal to 100%"
            );
        } else {
            require(
                _maxFeePercentage >= BORROWING_FEE_FLOOR &&
                    _maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must be between 0.5% and 100%"
            );
        }
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromTroveChange(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    ) internal pure returns (uint) {
        (uint newColl, uint newDebt) = _getNewTroveAmounts(
            _coll,
            _debt,
            _collChange,
            _isCollIncrease,
            _debtChange,
            _isDebtIncrease
        );

        uint newNICR = LiquityMath._computeNominalCR(newColl, newDebt);
        return newNICR;
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromTroveChange(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    ) internal pure returns (uint) {
        (uint newColl, uint newDebt) = _getNewTroveAmounts(
            _coll,
            _debt,
            _collChange,
            _isCollIncrease,
            _debtChange,
            _isDebtIncrease
        );

        uint newICR = LiquityMath._computeCR(newColl, newDebt, _price);
        return newICR;
    }

    function _getNewTroveAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    ) internal pure returns (uint, uint) {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease
            ? _coll.add(_collChange)
            : _coll.sub(_collChange);
        newDebt = _isDebtIncrease
            ? _debt.add(_debtChange)
            : _debt.sub(_debtChange);

        return (newColl, newDebt);
    }

    function _getNewTCRFromTroveChange(
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    ) internal view returns (uint) {
        uint totalColl = getEntireSystemColl();
        uint totalDebt = getEntireSystemDebt();

        totalColl = _isCollIncrease
            ? totalColl.add(_collChange)
            : totalColl.sub(_collChange);
        totalDebt = _isDebtIncrease
            ? totalDebt.add(_debtChange)
            : totalDebt.sub(_debtChange);

        uint newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price);
        return newTCR;
    }

    function getCompositeDebt(
        uint _debt
    ) external pure override returns (uint) {
        return _getCompositeDebt(_debt);
    }
}
