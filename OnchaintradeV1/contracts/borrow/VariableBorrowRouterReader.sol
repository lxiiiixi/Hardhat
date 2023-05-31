// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

interface IOracle {
    function getPrice(address token) external view returns (uint256);
}

interface IBorrowRouter {
    function oracle() external view returns (address);
    function getReward(address token, address account) external view returns (uint256, uint256, address);
}

contract VariableBorrowRouterReader {

    function bulkBorrowStakeInfo(address borrowStake, address account, address[] memory tokens) public view returns (
        uint256[] memory accountYeilds,
        uint256[] memory dayStaked,
        address[] memory rewardTokens,
        uint8[] memory rewardTokensDecimal,
        uint256[] memory rewardTokenPrices
    ) {
        accountYeilds = new uint256[](tokens.length);
        dayStaked = new uint256[](tokens.length);
        rewardTokens = new address[](tokens.length);
        rewardTokensDecimal = new uint8[](tokens.length);
        rewardTokenPrices = new uint256[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            (accountYeilds[i], dayStaked[i], rewardTokens[i]) = IBorrowRouter(borrowStake).getReward(tokens[i], account);
            if (rewardTokens[i] != address(0))  {
                rewardTokensDecimal[i] = IERC20(rewardTokens[i]).decimals();
                rewardTokenPrices[i] = IOracle(IBorrowRouter(borrowStake).oracle()).getPrice(rewardTokens[i]);
            }
        }
    }

}
