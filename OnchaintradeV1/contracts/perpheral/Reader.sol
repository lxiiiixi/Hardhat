// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

interface ISwap {
    function getPoolState(address token)
        external
        view
        returns (
            uint256 reserve,
            uint256 lastRatioToken,
            uint256 lastRatioOsd,
            uint256 osd_
        );

    function getPoolInfo(address token)
        external
        view
        returns (
            address liquidity,
            uint256 createdAt,
            bool rebalancible,
            bool usePriceFeed
        );

    function getPoolFeePolicy(address token)
        external
        view
        returns (
            uint8 feeType,
            uint16 feeRate0,
            uint16 feeRate1,
            uint16 feeRate2,
            uint8 revenueRate,
            uint256 revenueOsd
        );

    function getPriceRatio(address token)
        external
        view
        returns (uint256 tokenRatio, uint256 osdRatio);
}

interface IBorrowPrice {
    function getPrice(address token) external view returns (uint256);
}

interface IBorrow {
    function getPositionsView(address _asset, address _account)
        external
        view
        returns (
            uint256 debt,
            uint256 r0,
            address[] memory collateralTokens,
            uint256[] memory collateralAmounts
        );

    function getAssetsView(address _asset)
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
        );

    function getAccountDebt(address _asset, address _account, uint256 delaySeconds) external view returns (uint256);

    function getDebt(address _asset)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function liquidatable(address _asset, address _account) external view returns (bool);
}

interface IStake {
    function pending(address _lpToken, address _user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            address
        );
}

contract Reader {
    address public swap;
    address public borrow;
    address public borrowPrice;

    constructor(
        address _swap,
        address _borrow,
        address _borrowPrice
    ) {
        swap = _swap;
        borrow = _borrow;
        borrowPrice = _borrowPrice;
    }

    function bulkToken(address account, address[] memory tokens)
        public
        view
        returns (
            uint256[] memory balances,
            uint256[] memory totalSupplys,
            uint8[] memory decimals,
            string[] memory names,
            string[] memory symbols
        )
    {
        balances = new uint256[](tokens.length);
        totalSupplys = new uint256[](tokens.length);
        decimals = new uint8[](tokens.length);
        names = new string[](tokens.length);
        symbols = new string[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(account);
            totalSupplys[i] = IERC20(tokens[i]).totalSupply();
            decimals[i] = IERC20(tokens[i]).decimals();
            names[i] = IERC20(tokens[i]).name();
            symbols[i] = IERC20(tokens[i]).symbol();
        }
        return (balances, totalSupplys, decimals, names, symbols);
    }

    function bulkSwapPoolInfo(address[] memory tokens)
        public
        view
        returns (
            uint256[] memory reserveTokens,
            uint256[] memory reserveOsds,
            bool[] memory isUsePriceFeeds,
            bool[] memory isRebalancible,
            address[] memory liquidityList
        )
    {
        reserveTokens = new uint256[](tokens.length);
        reserveOsds = new uint256[](tokens.length);
        isUsePriceFeeds = new bool[](tokens.length);
        isRebalancible = new bool[](tokens.length);
        liquidityList = new address[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenAddress = tokens[i];

            (uint256 reserveToken, , , uint256 reserveOsd) = ISwap(swap).getPoolState(tokenAddress);
            (address liquidity, , bool rebalancible, bool usePriceFeed) = ISwap(swap).getPoolInfo(
                tokenAddress
            );

            reserveTokens[i] = reserveToken;
            reserveOsds[i] = reserveOsd;
            isUsePriceFeeds[i] = usePriceFeed;
            isRebalancible[i] = rebalancible;
            liquidityList[i] = liquidity;
        }
    }

    function bulkSwapRatio(address[] memory tokens)
        public
        view
        returns (uint256[] memory ratioTokens, uint256[] memory ratioOsds)
    {
        ratioTokens = new uint256[](tokens.length);
        ratioOsds = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenAddress = tokens[i];
            (uint256 ratioToken, uint256 ratioOsd) = ISwap(swap).getPriceRatio(tokenAddress);
            ratioTokens[i] = ratioToken;
            ratioOsds[i] = ratioOsd;
        }
    }

    function bulkAccountBorrowPosition(address account, address[] memory tokens)
        public
        view
        returns (
            uint256[] memory debtList,
            uint256[] memory r0List,
            uint256[] memory collateralNum,
            address[] memory collateralTokenList,
            uint256[] memory collateralAmountList
        )
    {
        uint256 sumCollateral = 0;

        debtList = new uint256[](tokens.length);
        r0List = new uint256[](tokens.length);
        collateralNum = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            (, uint256 r0, address[] memory collateralTokens, ) = IBorrow(borrow).getPositionsView(
                tokens[i],
                account
            );
            debtList[i] = IBorrow(borrow).getAccountDebt(tokens[i], account, 3600);
            r0List[i] = r0;
            collateralNum[i] = collateralTokens.length;
            sumCollateral += collateralTokens.length;
        }

        collateralTokenList = new address[](sumCollateral);
        collateralAmountList = new uint256[](sumCollateral);

        uint256 offset = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            (, , address[] memory collateralTokens, uint256[] memory collateralAmounts) = IBorrow(
                borrow
            ).getPositionsView(tokens[i], account);

            for (uint256 j = 0; j < collateralTokens.length; j++) {
                collateralTokenList[offset] = collateralTokens[j];
                collateralAmountList[offset] = collateralAmounts[j];
                offset++;
            }
        }
    }

    function bulkBorrowAssetInfoPart(address[] memory tokens)
        public
        view
        returns (
            uint8[] memory borrowCreditList,
            uint8[] memory collateralCreditList,
            uint8[] memory penaltyRateList
        )
    {
        borrowCreditList = new uint8[](tokens.length);
        collateralCreditList = new uint8[](tokens.length);
        penaltyRateList = new uint8[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            {
                address token = tokens[i];
                (
                    ,
                    ,
                    ,
                    ,
                    ,
                    ,
                    ,
                    ,
                    ,
                    uint8 borrowCredit,
                    uint8 collateralCredit,
                    uint8 penaltyRate
                ) = IBorrow(borrow).getAssetsView(token);
                borrowCreditList[i] = borrowCredit;
                collateralCreditList[i] = collateralCredit;
                penaltyRateList[i] = penaltyRate;
            }
        }
    }

    function bulkBorrowAssetInfo(address[] memory tokens)
        public
        view
        returns (
            uint16[] memory interestRateList,
            uint16[] memory baseList,
            uint16[] memory optimalList,
            uint16[] memory slope1List,
            uint16[] memory slope2List,
            uint8[] memory borrowCreditList,
            uint8[] memory collateralCreditList,
            uint8[] memory penaltyRateList
        )
    {
        interestRateList = new uint16[](tokens.length);
        baseList = new uint16[](tokens.length);
        optimalList = new uint16[](tokens.length);
        slope1List = new uint16[](tokens.length);
        slope2List = new uint16[](tokens.length);

        (borrowCreditList, collateralCreditList, penaltyRateList) = bulkBorrowAssetInfoPart(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            {
                address token = tokens[i];
                (
                    ,
                    ,
                    ,
                    ,
                    uint16 interestRate,
                    uint16 base,
                    uint16 optimal,
                    uint16 slope1,
                    uint16 slope2,
                    ,
                    ,

                ) = IBorrow(borrow).getAssetsView(token);
                interestRateList[i] = interestRate;
                baseList[i] = base;
                optimalList[i] = optimal;
                slope1List[i] = slope1;
                slope2List[i] = slope2;
            }
        }
    }

    function bulkBorrowAssetState(address[] memory tokens)
        public
        view
        returns (
            uint256[] memory debtList,
            uint256[] memory r0List,
            uint256[] memory relativeInterestList,
            uint256[] memory updatedAtList
        )
    {
        debtList = new uint256[](tokens.length);
        r0List = new uint256[](tokens.length);
        relativeInterestList = new uint256[](tokens.length);
        updatedAtList = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            {
                address token = tokens[i];
                (
                    uint256 debt,
                    uint256 r0,
                    uint256 relativeInterest,
                    uint256 updatedAt,
                    ,
                    ,
                    ,
                    ,
                    ,
                    ,
                    ,

                ) = IBorrow(borrow).getAssetsView(token);
                debtList[i] = uint256(debt);
                r0List[i] = uint256(r0);
                relativeInterestList[i] = uint256(relativeInterest);
                updatedAtList[i] = uint256(updatedAt);
            }
        }
    }

    function bulkBorrowPrice(address[] memory tokens)
        public
        view
        returns (uint256[] memory priceList)
    {
        priceList = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 price = IBorrowPrice(borrowPrice).getPrice(tokens[i]);
            priceList[i] = price;
        }
    }


    function bulkLpPrices(address[] memory tokens) public view returns (
        uint256[] memory lpPrices
    ) {
        lpPrices = new uint256[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            (address liquidity,,,) = ISwap(swap).getPoolInfo(tokens[i]);
            (uint256 tokenRatio, uint256 osdRatio) = ISwap(swap).getPriceRatio(tokens[i]);
            (uint256 reserveToken, , , uint256 reserveOsd) = ISwap(swap).getPoolState(tokens[i]);
            uint256 price = osdRatio * 1e10 / tokenRatio;
            // total value
            uint256 totalValue = (reserveToken * price / 1e10 + reserveOsd);
            uint256 lpBalance = IERC20(liquidity).totalSupply();
            uint8 decimal = IERC20(liquidity).decimals();
            lpPrices[i] = totalValue * (10**(30 - decimal - 4)) / lpBalance;
        }
    }

    function bulkStakeInfo(
        address stake,
        address account,
        address[] memory tokens
    )
        public
        view
        returns (
            uint256[] memory accountYeilds,
            uint256[] memory totalYeilds,
            uint256[] memory dayStaked,
            uint256[] memory accountStakeds,
            uint256[] memory totalStakeds,
            address[] memory rewardTokens,
            uint8[] memory rewardTokensDecimal,
            uint256[] memory rewardTokenPrices
        )
    {
        accountYeilds = new uint256[](tokens.length);
        totalYeilds = new uint256[](tokens.length);
        dayStaked = new uint256[](tokens.length);
        accountStakeds = new uint256[](tokens.length);
        totalStakeds = new uint256[](tokens.length);
        rewardTokens = new address[](tokens.length);
        rewardTokensDecimal = new uint8[](tokens.length);
        rewardTokenPrices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            (accountYeilds[i], totalYeilds[i], dayStaked[i], accountStakeds[i], rewardTokens[i]) = IStake(stake)
                .pending(tokens[i], account);
            totalStakeds[i] = IERC20(tokens[i]).balanceOf(stake);
            if (rewardTokens[i] != address(0)) {
                rewardTokensDecimal[i] = IERC20(rewardTokens[i]).decimals();
                rewardTokenPrices[i] = IBorrowPrice(borrowPrice).getPrice(rewardTokens[i]);
            }
        }
    }

    function bulkBorrowLiquidatable(address[] memory assets, address[] memory accounts)
        public
        view
        returns (bool[] memory shouldLiquidates)
    {
        require(assets.length == accounts.length, "invalid_length");

        shouldLiquidates = new bool[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            shouldLiquidates[i] = IBorrow(borrow).liquidatable(assets[i], accounts[i]);
        }
    }

    function bulkBorrowDebt(address[] memory assets, address[] memory accounts)
        public
        view
        returns (uint256[] memory debts)
    {
        require(assets.length == accounts.length, "invalid_length");

        debts = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            debts[i] = IBorrow(borrow).getAccountDebt(assets[i], accounts[i], 3600);
        }
    }
}
