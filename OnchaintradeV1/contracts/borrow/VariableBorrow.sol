// SPDX-License-Identifiera: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

import "../interfaces/ISwapForBorrow.sol";
import "../interfaces/IBorrowForSwap.sol";
import "../interfaces/IOracle.sol";

import "./FlashLoan.sol";

import "hardhat/console.sol";

contract VariableBorrow is Ownable, IBorrowForSwap, FlashLoan {
    using SafeERC20 for IERC20;
    using PRBMathUD60x18 for uint256;

    struct Collateral {
        address token;
        uint256 amount;
    }
    struct Position {
        uint256 debt; // individual interest/borrow?
        uint256 r0; // r=asset.relativeInterest, interest = r/r0*debt
        Collateral[] collaterals;
    }
    struct Asset {
        uint256 debt;
        uint256 protocolRevenueAmount;
        uint256 protocolRevenueAmountExtract;
        uint256 r0;
        uint256 relativeInterest;
        uint256 updatedAt;
        // max 65536 => 655.36%
        uint16 interestRate; // year
        uint16 base;
        uint16 optimal;
        uint16 slope1;
        uint16 slope2;
        uint8 borrowCredit;
        uint8 collateralCredit;
        uint8 penaltyRate;
    }

    event Borrow(
        address indexed asset,
        address indexed account,
        uint256 amount
    );
    event Repay(address indexed asset, address indexed account, uint256 amount);

    event CollateralAdd(
        address indexed asset,
        address indexed account,
        address indexed colAsset,
        uint256 amount
    );

    event CollateralRemove(
        address indexed asset,
        address indexed account,
        address indexed colAsset,
        uint256 amount
    );

    event Liquidate(
        address indexed asset,
        address indexed account,
        uint256 amount
    );

    event UpdateDebtPosition(
        address indexed asset,
        address indexed account,
        uint256 debt
    );

    mapping(address => Asset) public assets;
    address[] public assetList;
    // asset => account => position
    mapping(address => mapping(address => Position)) public positions;

    address private protocolRevenueAddress = address(0);
    address private router = address(0);
    uint8 private protocolRevenueRate = 50;
    uint8 private protocolRevenueFlashRate = 50;
    uint16 private flashLoanFeeRate = 9;
    ISwapForBorrow public swap;
    IOracle public oracle;

    constructor(address _swap, address _oracle) {
        // check swap oracle
        swap = ISwapForBorrow(_swap);
        oracle = IOracle(_oracle);
    }

    function borrow(
        address _asset, // 资产地址
        uint256 amount, // 用户想要借贷的数量
        Collateral[] calldata collaterals, // 抵押品信息
        address to // 贷款接收者
    ) external {
        Asset storage asset = assets[_asset];
        require(asset.updatedAt > 0, "ASSET_NOT_EXIST");
        require(to == msg.sender || router == msg.sender, "PERMISSION DENY");

        Position storage position = positions[_asset][to]; // 当前借款者的持仓信息

        // deposit
        for (uint256 i = 0; i < collaterals.length; i++) {
            Collateral calldata c = collaterals[i];
            // 每次抵押品传入的顺序必须按照新增时存储的保持一致（可以传入amount为0）
            if (i < position.collaterals.length) {
                if (c.amount > 0) {
                    // 该抵押品已经存在的情况
                    require(
                        c.token == position.collaterals[i].token,
                        "INVALID_COLLATERAL"
                    );
                    IERC20(c.token).safeTransferFrom(
                        msg.sender,
                        address(this),
                        c.amount
                    );
                    position.collaterals[i].amount += c.amount;
                }
            } else {
                IERC20(c.token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    c.amount
                );
                position.collaterals.push(c);
            }
        }

        // 处理借款
        if (amount > 0) {
            uint256 r1 = _currentRelativeInterest(asset, 0); // TODO no repeat calc?
            uint256 newDebt = position.debt > 0
                ? r1.div(position.r0).mul(position.debt) + amount // 资产相对利率/头寸的相对利率 * 头寸之前的债务 + 新的债务
                : amount; // 如果是第一次借款，则之前没有债务

            // 资产的协议收益金额 = ((资产相对利率/头寸的相对利率 * 资产的总债务 - 资产的总债务) * 协议的收益税率)/100
            asset.protocolRevenueAmount +=
                ((r1.div(asset.r0).mul(asset.debt) - asset.debt) *
                    protocolRevenueRate) /
                100;
            asset.debt = r1.div(asset.r0).mul(asset.debt) + amount;
            asset.r0 = r1;

            // 检查新增债务和抵押之后是否会导致被清算
            require(
                !_liquidatable(position.collaterals, _asset, newDebt),
                "INSUFF_COLLATERAL"
            );

            position.r0 = r1;
            position.debt = newDebt;
            _updateInterest(_asset, swap.borrow(_asset, amount, msg.sender));
        }

        emit Borrow(_asset, to, amount);
        emit UpdateDebtPosition(_asset, to, position.debt);
        for (uint i = 0; i < collaterals.length; i++) {
            Collateral calldata c = collaterals[i];
            emit CollateralAdd(_asset, to, c.token, c.amount);
        }
    }

    function repay(
        address _asset,
        uint256 amountMax,
        Collateral[] calldata collaterals,
        address to
    ) external returns (uint256) {
        Asset storage asset = assets[_asset];
        require(asset.updatedAt > 0, "ASSET_NOT_EXIST");
        require(to == msg.sender || router == msg.sender, "PERMISSION DENY");

        Position storage position = positions[_asset][to];
        // require(position.debt > 0, "ACCOUNT_NO_DEBT");

        uint256 amount; // 计算实际还款金额
        if (amountMax > 0 && position.debt > 0) {
            // 如果 amountMax>0 且账户存在债务
            uint256 r1 = _currentRelativeInterest(asset, 0);
            uint256 debt = r1.div(position.r0).mul(position.debt);
            // 如果债务小于传入的amountMax则还款所有债务即可，如果大于传入的则只还款amountMax
            amount = Math.min(debt, amountMax);

            asset.protocolRevenueAmount +=
                ((r1.div(asset.r0).mul(asset.debt) - asset.debt) *
                    protocolRevenueRate) /
                100;
            asset.debt = r1.div(asset.r0).mul(asset.debt) - amount; // 更新资产记录的债务
            asset.r0 = r1; // 更新资产的相对利率

            // 更新用户资产头寸的信息
            position.r0 = r1;
            position.debt = debt - amount;

            // 将目标资产从用户地址赚到swap合约地址 => 更新利率(使用swap合约转移资金后更新的余额计算)
            _updateInterest(_asset, swap.repay(_asset, amount, msg.sender));
        }

        // withdraw：依次将抵押品中的目标数量的代币从合约转移给用户
        for (uint256 i = 0; i < collaterals.length; i++) {
            Collateral calldata c = collaterals[i];
            if (c.amount > 0) {
                require(
                    c.token == position.collaterals[i].token,
                    "INVALID_COLLATERAL"
                );
                require(
                    position.collaterals[i].amount >= c.amount,
                    "INVALID_COLLATERAL"
                );

                IERC20(c.token).safeTransfer(msg.sender, c.amount);
                position.collaterals[i].amount -= c.amount;
            }
        }

        // valid
        (uint256 credit0, , ) = _creditOfDebt(_asset, position.debt);
        (uint256 credit1, ) = _creditOfCollaterals(position.collaterals);
        // collateral should > debt
        require(credit1 >= credit0, "COLLATERALs_INSUFF"); // 保证剩下的抵押品足够
        emit Repay(_asset, to, amount);
        emit UpdateDebtPosition(_asset, to, position.debt);
        for (uint i = 0; i < collaterals.length; i++) {
            Collateral calldata c = collaterals[i];
            emit CollateralRemove(_asset, to, c.token, c.amount);
        }
        return amount;
    }

    function liquidate(
        address _asset, // 指定要清算债务的资产
        address account, // 指定要清算债务的借款人
        uint256 amount, // 限制清算的最大金额
        address to // 清算资产的接收方
    ) external {
        // 1. 获取资产和借款人的头寸信息
        Asset storage asset = assets[_asset];
        require(asset.updatedAt > 0, "ASSET_NOT_EXIST");
        Position storage position = positions[_asset][account];
        require(position.debt > 0, "NO_DEBT");

        // 2. 计算清算金额和比例
        uint256 r1 = _currentRelativeInterest(asset, 0);
        uint256 debt = r1.div(position.r0).mul(position.debt);
        amount = Math.min(debt, amount); // 取较小值来限制清算最大金额，确保清算金额不超过借款人的实际债务金额
        uint256 percent = _liquidatePercent( // 得到抵押品对应的清算比例
            position.collaterals,
            _asset,
            debt,
            amount
        );

        // 3. 更新资产信息
        asset.protocolRevenueAmount +=
            ((r1.div(asset.r0).mul(asset.debt) - asset.debt) *
                protocolRevenueRate) /
            100;
        asset.debt = r1.div(asset.r0).mul(asset.debt) - amount;
        asset.r0 = r1;

        // 4. 更新借款人头寸信息
        position.r0 = r1;
        position.debt = debt - amount;

        // 5. 更新资产的利息，并调用swap.repay函数还款给swap合约
        _updateInterest(_asset, swap.repay(_asset, amount, msg.sender));

        // 6. 清算抵押品
        for (uint256 i = 0; i < position.collaterals.length; i++) {
            Collateral storage c = position.collaterals[i];
            if (c.amount > 0) {
                uint256 liquidateAmount = c.amount.mul(percent);
                IERC20(c.token).safeTransfer(to, liquidateAmount);
                c.amount -= liquidateAmount;
            }
        }

        emit Liquidate(_asset, account, amount);
        emit UpdateDebtPosition(_asset, to, position.debt);
    }

    function _updateInterest(
        address _asset,
        uint256 availability
    ) internal returns (bool) {
        // swap.pools[asset]
        Asset storage asset = assets[_asset];
        if (asset.updatedAt == 0) {
            return false;
        }
        console.log(
            "_updateInterest: asset.debt and availability",
            asset.debt,
            availability
        );
        uint256 u = ((asset.debt * 10000) / (asset.debt + availability));
        // 当前资产债务 * 10000 / (当前资产债务 + 可用资产)

        console.log("_updateInterest: u, asset.optimal", u, asset.optimal);

        uint16 newRate = u < asset.optimal
            ? uint16(10000 + asset.base + (u * asset.slope1) / asset.optimal)
            : uint16(
                10000 +
                    asset.base +
                    asset.slope1 +
                    ((u - asset.optimal) * asset.slope2) /
                    (10000 - asset.optimal)
            );
        // newRate：新的借款利率
        // 如果上面计算的比例小于最优比例：

        if (newRate != asset.interestRate) {
            asset.relativeInterest = _currentRelativeInterest(asset, 0);
            asset.interestRate = newRate;
            // solhint-disable-next-line not-rely-on-time
            asset.updatedAt = block.timestamp;
        }

        console.log(
            "_updateInterest: newRate relativeInterest",
            newRate,
            asset.relativeInterest
        );

        return true;
    }

    function _currentRelativeInterest(
        Asset storage asset,
        uint256 delaySeconds
    ) internal view returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        uint256 time = block.timestamp;

        uint256 delta = time + delaySeconds - asset.updatedAt;
        // 添加某个资产第一次调用 updateAsset 时调用 _updateInterest 计算相对利率时 delta 为0（如果delaySeconds为0）

        // 1.1 = 1.1e18 = 11000*1e14
        console.log(
            "_currentRelativeInterest: asset.interestRate",
            asset.interestRate,
            delta,
            asset.relativeInterest
        );

        return
            uint256(asset.interestRate)
                .div(10000)
                .pow((delta * 1e18) / 365 days)
                .mul(asset.relativeInterest);
        // delta * 1e18 / 365 days： 表示当前到上次更新这段时间在365天中的占比 （365 days 表示一年的秒数）
        //      假设 delta 等于 86400（即一天的秒数），则 (delta * 1e18) / 365 days 的结果将是 1e18，即以 1e18 为基础单位的一年。
        // uint256(x).pow(y)： 这是 Solidity 中的一种整数幂运算，将 x 的 y 次方作为结果返回。
        //      例如 uint256(5).pow(2)=25
    }

    function _creditOfDebt(
        address _asset,
        uint256 amount
    ) internal view returns (uint256 credit, uint256 rate, uint256 price) {
        uint8 borrowCredit = assets[_asset].borrowCredit;
        price = oracle.getPrice(_asset);
        credit = amount * price * borrowCredit;
        rate = uint256(borrowCredit) * 1e18;
    }

    function _creditOfCollaterals(
        Collateral[] memory collaterals
    ) internal view returns (uint256, uint256) {
        uint256 valueSum; // 抵押品总价值
        uint256 creditSum; // 总信用
        uint256 rateSum;
        for (uint256 i = 0; i < collaterals.length; i++) {
            Collateral memory collateral = collaterals[i];
            Asset storage asset = assets[collateral.token];

            uint256 valueRat = collateral.amount *
                oracle.getPrice(collateral.token);
            // 当前抵押品价值 = 抵押品数量*抵押品价格
            uint256 creditRat = asset.collateralCredit * valueRat;
            // 当前抵押品的信用 = 该资产作为抵押品对应的信用*价值
            console.log(
                "valueRat creditRat-----------------",
                valueRat,
                creditRat
            );
            uint256 rateRat = creditRat * (asset.penaltyRate + 100);
            valueSum += valueRat;
            creditSum += creditRat;
            rateSum += rateRat;
        }
        return (creditSum, valueSum == 0 ? 0 : rateSum.div(100 * valueSum));
    }

    function _liquidatePercent(
        Collateral[] memory collaterals,
        address _asset,
        uint256 debt,
        uint256 amount
    ) internal view returns (uint256) {
        (uint256 credit0, uint256 rate0, uint256 price0) = _creditOfDebt(
            _asset,
            debt
        );
        (uint256 credit1, uint256 rate1) = _creditOfCollaterals(collaterals);
        // 1.1*credit0=credit1
        // 1.1*(credit0-v*rate0)=credit1-v*rate1
        // v=(1.1*credit0-credit1)/(1.1*rate0-rate1)
        // amount=v/price
        uint256 maxAmount = (credit0.mul(1.1e18) - credit1).div(
            (rate0.mul(1.1e18) - rate1) * price0
        );

        require(credit0 >= credit1, "NOT_LIQUIDATABLE");
        require(maxAmount >= amount, "AMOUNT_EXCEED");

        uint256 dCredit = (amount * price0).mul(rate1);
        if (dCredit > credit1 || credit1 == 0) {
            return 1e18;
        } else {
            return dCredit.div(credit1);
        }
    }

    function _liquidatable(
        Collateral[] memory collaterals,
        address _asset,
        uint256 debt
    ) internal view returns (bool) {
        (uint256 credit0, , ) = _creditOfDebt(_asset, debt);
        (uint256 credit1, ) = _creditOfCollaterals(collaterals);
        console.log(
            "_creditOfDebt _creditOfCollaterals +++++++++++++++++++",
            credit0,
            credit1
        );
        return credit0 >= credit1;
    }

    function liquidatable(
        address _asset,
        address _account
    ) public view returns (bool) {
        Asset storage asset = assets[_asset];
        if (asset.updatedAt == 0) {
            return false;
        }
        Position storage position = positions[_asset][_account];
        if (position.debt == 0) {
            return false;
        }
        uint256 r1 = _currentRelativeInterest(asset, 0);
        uint256 debt = r1.div(position.r0).mul(position.debt);
        return _liquidatable(position.collaterals, _asset, debt);
    }

    // viewers
    function liquidatableAmount(
        address _asset,
        address account
    ) external view returns (uint256) {
        // TODO DRY
        Asset storage asset = assets[_asset];
        Position storage position = positions[_asset][account];

        uint256 r1 = _currentRelativeInterest(asset, 0);
        console.log("+++++++++++++++r1", r1);

        uint256 debt = r1.div(position.r0).mul(position.debt);

        (uint256 credit0, uint256 rate0, uint256 price0) = _creditOfDebt(
            _asset,
            debt
        );
        (uint256 credit1, uint256 rate1) = _creditOfCollaterals(
            position.collaterals
        );
        if (credit0 < credit1) {
            return 0; // 说明不可清算
        }

        console.log("credit1 credit1", credit0, credit1);
        console.log("credit1 credit1", credit0.mul(1.1e18), credit1);
        console.log("rate0", rate0, rate0.mul(1.1e18), rate1);

        uint256 maxAmount = (credit0.mul(1.1e18) - credit1).div(
            (rate0.mul(1.1e18) - rate1) * price0
        );

        return maxAmount;
    }

    function getMaxAmountOfBorrow(
        address _asset,
        Collateral[] calldata collaterals,
        address to
    ) external view returns (uint256) {
        (uint256 credit0, , ) = _creditOfDebt(_asset, 1);
        (uint256 credit1, ) = _creditOfCollaterals(
            positions[_asset][to].collaterals
        );
        (uint256 credit2, ) = _creditOfCollaterals(collaterals);
        uint256 availability = swap.getAvailability(_asset);
        uint256 maxUserAmount = (credit1 + credit2) / credit0;
        if (availability > maxUserAmount) {
            return maxUserAmount;
        } else {
            return availability;
        }
    }

    function getMaxAmountOfRepay(
        address _asset,
        Collateral[] calldata collaterals
    ) external view returns (uint256) {
        (uint256 credit0, , ) = _creditOfDebt(_asset, 1);
        (uint256 credit1, ) = _creditOfCollaterals(
            positions[_asset][msg.sender].collaterals
        );
        (uint256 credit2, ) = _creditOfCollaterals(collaterals);

        return (credit1 - credit2) / credit0;
    }

    function getAccountDebt(
        address _asset,
        address _account,
        uint256 delaySeconds
    ) external view returns (uint256) {
        Asset storage asset = assets[_asset];
        Position storage position = positions[_asset][_account];
        uint256 r1 = _currentRelativeInterest(asset, delaySeconds);
        if (position.r0 > 0) {
            uint256 debt = r1.div(position.r0).mul(position.debt);
            return debt;
        } else {
            return 0;
        }
    }

    function getCollaterals(
        address _asset,
        address _account
    ) external view returns (Collateral[] memory) {
        Position memory p = positions[_asset][_account];
        return p.collaterals;
    }

    function getPositionsView(
        address _asset,
        address _account
    )
        external
        view
        returns (
            uint256 debt,
            uint256 r0,
            address[] memory collateralTokens,
            uint256[] memory collateralAmounts
        )
    {
        Position memory p = positions[_asset][_account];
        debt = p.debt;
        r0 = p.r0;
        collateralTokens = new address[](p.collaterals.length);
        collateralAmounts = new uint256[](p.collaterals.length);
        for (uint256 index = 0; index < p.collaterals.length; index++) {
            collateralTokens[index] = p.collaterals[index].token;
            collateralAmounts[index] = p.collaterals[index].amount;
        }
    }

    function getAssetsView(
        address _asset
    )
        external
        view
        returns (
            uint256 debt,
            uint256 r0,
            uint256 relativeInterest,
            uint256 updatedAt,
            uint16 interestRate,
            uint16 base,
            uint16 optimal,
            uint16 slope1,
            uint16 slope2,
            uint8 borrowCredit,
            uint8 collateralCredit,
            uint8 penaltyRate
        )
    {
        Asset memory asset = assets[_asset];
        debt = asset.debt;
        r0 = asset.r0;
        relativeInterest = asset.relativeInterest;
        updatedAt = asset.updatedAt;
        interestRate = asset.interestRate;
        base = asset.base;
        optimal = asset.optimal;
        slope1 = asset.slope1;
        slope2 = asset.slope2;
        borrowCredit = asset.borrowCredit;
        collateralCredit = asset.collateralCredit;
        penaltyRate = asset.penaltyRate;
    }

    // admin
    function updateAsset(
        address _asset,
        uint16 base,
        uint16 optimal,
        uint16 slope1,
        uint16 slope2,
        uint8 borrowCredit,
        uint8 collateralCredit,
        uint8 penaltyRate
    ) external onlyOwner {
        Asset storage asset = assets[_asset];
        if (asset.updatedAt == 0) {
            assetList.push(_asset);
        }
        asset.base = base;
        asset.optimal = optimal;
        asset.slope1 = slope1;
        asset.slope2 = slope2;

        if (asset.relativeInterest == 0) {
            // init
            asset.r0 = 1e18;
            asset.relativeInterest = 1e18;
            // solhint-disable-next-line not-rely-on-time
            asset.updatedAt = block.timestamp;
        }
        _updateInterest(_asset, swap.getAvailability(_asset));

        asset.borrowCredit = borrowCredit;
        asset.collateralCredit = collateralCredit;
        asset.penaltyRate = penaltyRate;
    }

    function updateProtocolRevenue(
        address _protocolRevenueAddress,
        uint8 _protocolRevenueRate,
        uint8 _protocolRevenueFlashRate,
        uint16 _flashLoanFeeRate
    ) external onlyOwner {
        require(
            _protocolRevenueAddress != address(0),
            "CANNOT BE THE ZERO ADDRESS"
        );
        require(_protocolRevenueRate <= 100, "RATE BETWEEN 0-100");
        require(_protocolRevenueFlashRate <= 100, "RATE BETWEEN 0-100");
        require(_flashLoanFeeRate <= 10000, "FEE RATE BETWEEN 0-10000");
        protocolRevenueAddress = _protocolRevenueAddress;
        protocolRevenueRate = _protocolRevenueRate;
        protocolRevenueFlashRate = _protocolRevenueFlashRate;
        flashLoanFeeRate = _flashLoanFeeRate;
    }

    function extractProtocolRevenue(address _asset) external {
        (, , uint256 canExtractAmount) = _getDebtAndRevenue(_asset);
        require(canExtractAmount > 0, "PROTOCOL_AMOUNT_INSUFF");
        swap.protocolRevenueExtract(
            _asset,
            canExtractAmount,
            protocolRevenueAddress
        );
        Asset storage asset = assets[_asset];
        asset.protocolRevenueAmountExtract += canExtractAmount;
    }

    function setOracle(address _oracle) external onlyOwner {
        // not check
        oracle = IOracle(_oracle);
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    // swap
    function updateInterest(
        address asset,
        uint256 availability
    ) external override returns (bool) {
        require(msg.sender == address(swap), "NOT_SWAP");
        return _updateInterest(asset, availability);
    }

    function _getDebtAndRevenue(
        address _asset
    ) internal view returns (uint256, uint256, uint256) {
        Asset storage asset = assets[_asset];
        if (asset.updatedAt == 0) {
            return (0, 0, 0);
        }
        uint256 r1 = _currentRelativeInterest(asset, 0);
        uint256 newDebt = r1.div(asset.r0).mul(asset.debt);
        uint256 newProtocolRevenue = ((newDebt - asset.debt) *
            protocolRevenueRate) / 100;
        uint256 currentProtocolRevenue = asset.protocolRevenueAmount +
            newProtocolRevenue -
            asset.protocolRevenueAmountExtract;
        return (
            newDebt,
            asset.protocolRevenueAmount + newProtocolRevenue,
            currentProtocolRevenue
        );
    }

    function getDebt(
        address _asset
    ) external view override returns (uint256, uint256, uint256) {
        (
            uint256 newDebt,
            uint256 totalProtocolRevenue,
            uint256 currentProtocolRevenue
        ) = _getDebtAndRevenue(_asset);
        return (newDebt, totalProtocolRevenue, currentProtocolRevenue);
    }

    function getAssetList() external view returns (address[] memory) {
        uint256 assetListLen = assetList.length;
        address[] memory _assetList = new address[](assetListLen);
        for (uint i = 0; i < assetListLen; i++) {
            _assetList[i] = assetList[i];
        }
        return _assetList;
    }

    function flashFee(
        address /* token */,
        uint256 amount
    ) public view override returns (uint256) {
        // 0.1%
        return (amount * flashLoanFeeRate) / 10000;
    }

    // FlashLoan
    function maxFlashLoan(
        address token
    ) public view virtual override returns (uint256) {
        return swap.getAvailability(token);
    }

    function flashLoanBorrow(
        address token,
        uint256 amount,
        address to
    ) internal override {
        swap.borrow(token, amount, to);
    }

    function flashLoanRepay(
        address token,
        uint256 amount,
        uint256 amountFee,
        address from
    ) internal override {
        Asset storage asset = assets[token];
        asset.protocolRevenueAmount +=
            (amountFee * protocolRevenueFlashRate) /
            100;
        swap.repay(token, amount + amountFee, from);
    }
}
