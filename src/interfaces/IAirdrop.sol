// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAirdrop
 * @author BinnaDev (Obinna Franklin Duru)
 * @notice The central interface for the BinnaDev Advanced Airdrop System.
 * @dev Defines shared events and custom errors for all airdrop modules
 * to ensure a consistent, reliable, and easily indexable system.
 */
interface IAirdrop {
    // --- Events ---

    /**
     * @notice Emitted when a user successfully claims an airdrop.
     * @param module The type of airdrop module that processed the claim (e.g., "Merkle", "Signature").
     * @param claimIndex A unique identifier for the claim (e.g., Merkle tree index or signature nonce).
     * @param claimant The user who received the tokens.
     * @param tokenContract The address of the token contract (ERC20 or ERC721).
     * @param tokenId The ID of the token (0 for ERC20, >0 for ERC721).
     * @param amount The amount of tokens (for ERC20, 0 for ERC721).
     */
    event Claimed(
        string module,
        uint256 indexed claimIndex,
        address indexed claimant,
        address indexed tokenContract,
        uint256 tokenId,
        uint256 amount
    );

    // --- Errors ---

    /**
     * @notice Reverts when the token transfer (ERC20 or ERC721) fails.
     */
    error Airdrop_TransferFailed();

    /**
     * @notice Reverts when the provided token ID or amount is zero.
     */
    error Airdrop_InvalidAllocation();

    // --- MerkleAirdrop Errors ---

    /**
     * @notice Reverts when a Merkle proof is invalid or does not match the root.
     */
    error MerkleAirdrop_InvalidProof();

    /**
     * @notice Reverts when the `_msgSender()` (via ERC-2771) does not
     * match the `claimant` address in the Merkle leaf.
     * @param sender The address of the `_msgSender()`.
     * @param claimant The address specified in the claim data.
     */
    error MerkleAirdrop_NotClaimant(address sender, address claimant);

    /**
     * @notice Reverts when the bitmap index for a claim has already been set.
     * @param index The Merkle tree index that was already claimed.
     */
    error MerkleAirdrop_AlreadyClaimed(uint256 index);

    /**
     * @notice Reverts if the provided Merkle proof is longer than the allowed maximum depth.
     * @param proofLength The length of the proof provided.
     * @param maxDepth The maximum allowed length.
     */
    error MerkleAirdrop_ProofTooLong(uint256 proofLength, uint256 maxDepth);

    // --- SignatureAirdrop Errors ---

    /**
     * @notice Reverts when the provided nonce does not match the claimant's current nonce.
     * @param expected The on-chain nonce required for the claim.
     * @param provided The nonce that was included in the signed payload.
     */
    error SignatureAirdrop_InvalidNonce(uint256 expected, uint256 provided);

    /**
     * @notice Reverts when the recovered signer does not match the expected claimant.
     * @param expected The claimant address from the payload.
     * @param recovered The address recovered from the signature.
     */
    error SignatureAirdrop_InvalidSignature(address expected, address recovered);
}
