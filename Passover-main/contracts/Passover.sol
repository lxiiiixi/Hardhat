// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "contracts/ERC7583/IERC7583.sol";
import "hardhat/console.sol";

contract Passover is ERC20, IERC7583, Ownable, Pausable {
    using Strings for address;
    using Strings for uint256;

    address public vault;
    bytes32 public rootClaimLossesDirect;
    bytes32 public rootRefund;
    bytes32 public rootClaimLossesAfterRefund;

    mapping(bytes32 => bool) public leafStatus;

    constructor(
        string memory name,
        string memory symbol,
        address vault_,
        address owner_
    ) ERC20(name, symbol) Ownable(owner_) {
        vault = vault_;
    }

    event ClaimLosses(
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes32 txHash
    );

    /// @notice This function is for compensating transactions for TokenIDs that were stolen from the beginning, because the owner in the snapshot will directly receive the INSC+ claim eligibility.
    /// @dev Before claiming, you need to obtain the correct Merkle proofs.
    /// @param tokenId The TokenID corresponding to the transaction trail
    /// @param amount The quantity eligible for compensation
    /// @param txHash The tx hash corresponding to your compensation
    /// @param nonce The nonce is used as a random number to increase the entropy source.
    /// @param proofs Merkle proof from backend
    function claimLossesDirect(
        uint256 tokenId,
        uint256 amount,
        bytes32 txHash,
        uint256 nonce,
        bytes32[] calldata proofs
    ) public whenNotPaused {
        // merkle verify
        bytes32 leaf = keccak256(
            abi.encode(tokenId, msg.sender, amount, txHash, nonce)
        );
        require(!leafStatus[leaf], "This leaf has been used");
        require(
            MerkleProof.verify(proofs, rootClaimLossesDirect, leaf),
            "Merkle verification failed"
        );

        leafStatus[leaf] = true;
        _mint(msg.sender, amount);
        emit ClaimLosses(tokenId, msg.sender, amount, txHash);
    }

    /// @notice This function is the entry point for refunds. Users who choose to refund will gain the eligibility to receive INSC+.
    /// @dev The deadline for each level in the transaction trail to make a choice is determined by the owner through setting the time of rootRefund.
    /// @param tokenId The TokenID corresponding to the transaction trail
    /// @param amount The quantity eligible for compensation
    /// @param txHash The tx hash corresponding to your compensation
    /// @param nonce The nonce is used as a random number to increase the entropy source.
    /// @param proofs Merkle proof from backend
    function refund(
        uint256 tokenId,
        uint256 amount,
        bytes32 txHash,
        uint256 nonce,
        bytes32[] calldata proofs
    ) public payable whenNotPaused {
        require(msg.value == amount, "The refund amount is incorrect");
        // merkle verify
        bytes32 leaf = keccak256(
            abi.encode(tokenId, msg.sender, amount, txHash, nonce)
        );
        require(!leafStatus[leaf], "This leaf has been used");
        require(
            MerkleProof.verify(proofs, rootRefund, leaf),
            "Merkle verification failed"
        );
        leafStatus[leaf] = true;
        payable(vault).transfer(msg.value);

        emit Inscribe(
            tokenId,
            bytes(
                string.concat(
                    "data:text/plain;charset=utf-8,",
                    msg.sender.toHexString(),
                    "has already refunded the sales proceeds of INSC",
                    tokenId.toString(),
                    ", and he will receive the corresponding INSC+"
                )
            )
        );
    }

    /// @notice This function is for compensating the transactions of TokenIDs after a Refund. After confirming the final receiving address for INSC+ based on user choices, the remaining users in the transaction trail will be compensated through this function.
    /// @dev Before claiming, you need to obtain the correct Merkle proofs.
    /// @param tokenId The TokenID corresponding to the transaction trail
    /// @param amount The quantity eligible for compensation
    /// @param txHash The tx hash corresponding to your compensation
    /// @param nonce The nonce is used as a random number to increase the entropy source.
    /// @param proofs Merkle proof from backend
    function claimLossesAfterRefund(
        uint256 tokenId,
        uint256 amount,
        bytes32 txHash,
        uint256 nonce,
        bytes32[] calldata proofs
    ) public whenNotPaused {
        // merkle verify
        bytes32 leaf = keccak256(
            abi.encode(tokenId, msg.sender, amount, txHash, nonce)
        );
        require(!leafStatus[leaf], "This leaf has been used");
        require(
            MerkleProof.verify(proofs, rootClaimLossesAfterRefund, leaf),
            "Merkle verification failed"
        );

        leafStatus[leaf] = true;
        _mint(msg.sender, amount);
        emit ClaimLosses(tokenId, msg.sender, amount, txHash);
    }

    // ---------- owner access ----------

    function setClaimLossesDirectRoot(bytes32 root_) public onlyOwner {
        rootClaimLossesDirect = root_;
    }

    function setRefundRoot(bytes32 root_) public onlyOwner {
        rootRefund = root_;
    }

    function setClaimLossesAfterRefundRoot(bytes32 root_) public onlyOwner {
        rootClaimLossesAfterRefund = root_;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
