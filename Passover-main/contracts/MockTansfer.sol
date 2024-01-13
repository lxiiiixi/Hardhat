// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IINS20 {
    function safeTransferFrom0(
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external returns (bool);
}

contract MockTransfer is IERC721Receiver {
    IINS20 public ins20Contract;
    address public target;
    bool public reenter = false;

    constructor(address _ins20Address) {
        ins20Contract = IINS20(_ins20Address);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        if (reenter) {
            // ins20Contract.safeTransferFrom0(
            //     address(this),
            //     target,
            //     tokenId,
            //     data
            // );
            address(ins20Contract).call(
                abi.encodeWithSignature(
                    "safeTransferFrom(address,address,uint256,bytes)",
                    address(this),
                    target,
                    1,
                    "0x"
                )
            );
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    function triggerReentrancy(uint256 tokenId, address to) public {
        target = to;
        reenter = true;
        address(ins20Contract).call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                msg.sender,
                address(this),
                tokenId,
                "0x"
            )
        );
        // ins20Contract.safeTransferFrom0(
        //     msg.sender,
        //     address(this),
        //     tokenId,
        //     "0x"
        // );
        reenter = false;
    }
}
