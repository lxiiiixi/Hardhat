// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenIcon is Ownable {
    
    mapping(address => string) private tokenIconMapper;

    function getTokenIcon(address _asset) external view returns (string memory) {
        return tokenIconMapper[_asset];
    }

    function bulkTokenIcon(address[] memory _assetList) external view returns(string[] memory) {
        string[] memory urls = new string[](_assetList.length);
        for (uint256 index = 0; index < _assetList.length; index++) {
            string memory url = tokenIconMapper[_assetList[index]];
            urls[index] = url;
        }
        return urls;
    }

    function setTokenIcon(address _asset, string memory _iconUrl) external onlyOwner {
        tokenIconMapper[_asset] = _iconUrl;
    }

}
