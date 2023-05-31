// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFuture.sol";
import "hardhat/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

// future reader contract for front end
contract FutureReader is Ownable {
    address[] public collateralTokens;
    address[] public indexTokens;
    uint256 public pairCount;

    address public future;

    struct VirtualTokenInfo {
        uint8 decimal;
        string name;
        string symbol;
    }

    mapping(address => VirtualTokenInfo) public virtualTokenList;

    constructor(address _future) {
        future = _future;

        virtualTokenList[address(0)].decimal = 18;
        virtualTokenList[address(0)].name = "USD";
        virtualTokenList[address(0)].symbol = "USD";
    }

    function setPairs(address[] memory _collateralTokens, address[] memory _indexTokens)
        external
        onlyOwner
    {
        require(_collateralTokens.length == _indexTokens.length, "invalid_length");
        pairCount = _indexTokens.length;
        collateralTokens = new address[](pairCount);
        indexTokens = new address[](pairCount);
        for (uint256 i = 0; i < pairCount; i++) {
            collateralTokens[i] = _collateralTokens[i];
            indexTokens[i] = _indexTokens[i];
        }
    }

    function setVirtualTokens() external onlyOwner {}

    function getPairs()
        external
        view
        returns (
            address[] memory collTokens,
            address[] memory idxTokens,
            uint256[] memory tradingFeeRates,
            uint256[] memory maxLeverages,
            int256[] memory longFundingRates,
            int256[] memory shortFundingRates,
            int256[] memory cumulativeLongFundingRates,
            int256[] memory cumulativeShortFundingRates
        )
    {
        collTokens = new address[](pairCount);
        idxTokens = new address[](pairCount);

        tradingFeeRates = new uint256[](pairCount);
        maxLeverages = new uint256[](pairCount);
        longFundingRates = new int256[](pairCount);
        shortFundingRates = new int256[](pairCount);
        cumulativeLongFundingRates = new int256[](pairCount);
        cumulativeShortFundingRates = new int256[](pairCount);

        for (uint256 i = 0; i < pairCount; i++) {
            collTokens[i] = collateralTokens[i];
            idxTokens[i] = indexTokens[i];

            bytes32 pairKey = IFuture(future).getPairKey(collTokens[i], idxTokens[i]);
            tradingFeeRates[i] = IFuture(future).tradingFeeRates(pairKey);
            maxLeverages[i] = IFuture(future).maxLeverages(pairKey);
            longFundingRates[i] = IFuture(future).longFundingRates(pairKey);
            shortFundingRates[i] = IFuture(future).shortFundingRates(pairKey);
            cumulativeLongFundingRates[i] = IFuture(future).cumulativeLongFundingRates(pairKey);
            cumulativeShortFundingRates[i] = IFuture(future).cumulativeShortFundingRates(pairKey);
        }
    }

    function getPairs2()
        external
        view
        returns (
            address[] memory collTokens,
            address[] memory idxTokens,
            int256[] memory dataList
        )
    {
        collTokens = new address[](pairCount);
        idxTokens = new address[](pairCount);
        dataList = new int256[](pairCount * 18);
        /**
        0 tradingFeeRate, 

        1 maxMmr, 
        2 minMmr, 
        3 maxLeverage, 

        4 maxTotalLongSize, 
        5 maxTotalShortSize, 

        6 cumulativeLongFundingRate, 
        7 cumulativeShortFundingRate, 
        8 longFundingRate, 
        9 shortFundingRate, 
        10 lastFundingTimestamp, 

        11 collateralInsuranceFund, 
        12 totalShortSize, 
        13 totalLongSize

        14 collateralTokenDecimals
        15 indexTokenDecimals

        16 collateralPrice
        17 indexPrice
         */

        for (uint256 i = 0; i < pairCount; i++) {
            collTokens[i] = collateralTokens[i];
            idxTokens[i] = indexTokens[i];

            bytes32 key = IFuture(future).getPairKey(collateralTokens[i], indexTokens[i]);

            uint256 startIndex = i * 18;

            dataList[startIndex + 0] = int256(IFuture(future).tradingFeeRates(key));

            dataList[startIndex + 1] = int256(IFuture(future).maxMaintanenceMarginRatios(key));
            dataList[startIndex + 2] = int256(IFuture(future).minMaintanenceMarginRatios(key));
            dataList[startIndex + 3] = int256(IFuture(future).maxLeverages(key));

            dataList[startIndex + 4] = int256(IFuture(future).maxTotalLongSizes(key));
            dataList[startIndex + 5] = int256(IFuture(future).maxTotalShortSizes(key));

            dataList[startIndex + 6] = IFuture(future).cumulativeLongFundingRates(key);
            dataList[startIndex + 7] = IFuture(future).cumulativeShortFundingRates(key);
            dataList[startIndex + 8] = IFuture(future).longFundingRates(key);
            dataList[startIndex + 9] = IFuture(future).shortFundingRates(key);
            dataList[startIndex + 10] = int256(IFuture(future).lastFundingTimestamps(key));

            dataList[startIndex + 11] = int256(
                IFuture(future).collateralInsuranceFunds(collateralTokens[i])
            );
            dataList[startIndex + 12] = int256(IFuture(future).totalLongSizes(key));
            dataList[startIndex + 13] = int256(IFuture(future).totalShortSizes(key));

            dataList[startIndex + 14] = int256(
                uint256(IFuture(future).tokenDecimals(collateralTokens[i]))
            );
            dataList[startIndex + 15] = int256(
                uint256(IFuture(future).tokenDecimals(indexTokens[i]))
            );
            dataList[startIndex + 16] = int256(
                uint256(IFuture(future).getPrice(collateralTokens[i]))
            );
            dataList[startIndex + 17] = int256(uint256(IFuture(future).getPrice(indexTokens[i])));
        }
    }

    function getPositionList(address _account)
        external
        view
        returns (
            address[] memory collateralTokenList,
            address[] memory indexTokenList,
            bool[] memory isLongList,
            uint256[] memory marginList,
            uint256[] memory openNotionalList,
            uint256[] memory sizeList,
            int256[] memory entryFundingRateList
        )
    {
        collateralTokenList = new address[](pairCount * 2);
        indexTokenList = new address[](pairCount * 2);
        isLongList = new bool[](pairCount * 2);
        marginList = new uint256[](pairCount * 2);
        openNotionalList = new uint256[](pairCount * 2);
        sizeList = new uint256[](pairCount * 2);
        entryFundingRateList = new int256[](pairCount * 2);

        for (uint256 i = 0; i < pairCount; i++) {
            collateralTokenList[i * 2] = collateralTokens[i];
            collateralTokenList[i * 2 + 1] = collateralTokens[i];
            indexTokenList[i * 2] = indexTokens[i];
            indexTokenList[i * 2 + 1] = indexTokens[i];
            isLongList[i * 2] = true;
            isLongList[i * 2 + 1] = false;
        }
        address account = _account; // avoid stack too deap
        for (uint256 i = 0; i < pairCount * 2; i++) {
            (uint256 margin, uint256 openNotional, uint256 size, int256 entryFundingRate) = IFuture(
                future
            ).getPosition(collateralTokenList[i], indexTokenList[i], account, isLongList[i]);

            marginList[i] = margin;
            openNotionalList[i] = openNotional;
            sizeList[i] = size;
            entryFundingRateList[i] = entryFundingRate;
        }
    }

    function getPositionList2(address account)
        external
        view
        returns (
            address[] memory collateralTokenList,
            address[] memory indexTokenList,
            bool[] memory isLongList,
            int256[] memory dataList
        )
    {
        collateralTokenList = new address[](pairCount * 2);
        indexTokenList = new address[](pairCount * 2);
        isLongList = new bool[](pairCount * 2);
        dataList = new int256[](pairCount * 2 * 7); // margin, openNotional, size, entryFundingRate, entryCollateralPrice, entryIndexPrice, mmr

        for (uint256 i = 0; i < pairCount; i++) {
            collateralTokenList[i * 2] = collateralTokens[i];
            collateralTokenList[i * 2 + 1] = collateralTokens[i];
            indexTokenList[i * 2] = indexTokens[i];
            indexTokenList[i * 2 + 1] = indexTokens[i];
            isLongList[i * 2] = true;
            isLongList[i * 2 + 1] = false;
        }

        for (uint256 i = 0; i < pairCount * 2; i++) {
            uint256 startIndex = i * 7;
            {
                (
                    uint256 margin,
                    uint256 openNotional,
                    uint256 size,
                    int256 entryFundingRate
                ) = IFuture(future).getPosition(
                        collateralTokenList[i],
                        indexTokenList[i],
                        account,
                        isLongList[i]
                    );

                dataList[startIndex + 0] = int256(margin);
                dataList[startIndex + 1] = int256(openNotional);
                dataList[startIndex + 2] = int256(size);
                dataList[startIndex + 3] = entryFundingRate;
            }
            {
                (uint256 entryCollateralPrice, uint256 entryIndexPrice) = IFuture(future)
                    .getPositionEntryPrice(
                        collateralTokenList[i],
                        indexTokenList[i],
                        account,
                        isLongList[i]
                    );
                dataList[startIndex + 4] = int256(entryCollateralPrice);
                dataList[startIndex + 5] = int256(entryIndexPrice);
            }
            {
                uint256 mmr = IFuture(future).getMaintanenceMarginRatio(
                    collateralTokenList[i],
                    indexTokenList[i],
                    account,
                    isLongList[i]
                );
                dataList[startIndex + 6] = int256(mmr);
            }
        }
    }

    function bulkTokenInfo(address[] memory tokens)
        public
        view
        returns (
            uint8[] memory decimals,
            string[] memory names,
            string[] memory symbols
        )
    {
        decimals = new uint8[](tokens.length);
        names = new string[](tokens.length);
        symbols = new string[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (virtualTokenList[tokens[i]].decimal > 0) {
                decimals[i] = virtualTokenList[tokens[i]].decimal;
                names[i] = virtualTokenList[tokens[i]].name;
                symbols[i] = virtualTokenList[tokens[i]].symbol;
            } else {
                decimals[i] = IERC20(tokens[i]).decimals();
                names[i] = IERC20(tokens[i]).name();
                symbols[i] = IERC20(tokens[i]).symbol();
            }
        }
    }

    function bulkValidateLiquidate(
        address[] memory _collTokens,
        address[] memory _indexTokens,
        address[] memory _accounts,
        bool[] memory _isLongs
    ) public view returns (bool[] memory shouldLiquidates) {
        shouldLiquidates = new bool[](_collTokens.length);

        require(_collTokens.length == _indexTokens.length, "invalid_length");
        require(_collTokens.length == _accounts.length, "invalid_length");
        require(_collTokens.length == _isLongs.length, "invalid_length");

        for (uint256 i = 0; i < _collTokens.length; i++) {
            shouldLiquidates[i] = IFuture(future).validateLiquidate(
                _collTokens[i],
                _indexTokens[i],
                _accounts[i],
                _isLongs[i],
                false
            );
        }
    }
}
