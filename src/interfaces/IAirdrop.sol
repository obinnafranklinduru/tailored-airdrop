// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAirdrop
 * @author BinnaDev
 * @notice The central interface for the Advanced Airdrop System.
 * @dev This interface defines the shared events and custom errors used
 * across all airdrop modules (Merkle, Signature) to ensure consistency
 * and provide a clear, auditable "data contract" for the system.
 */
interface IAirdrop {
    /**
     * @notice Emitted when a claim is successfully processed.
     * @param module The specific airdrop module that processed the claim (e.g., "Merkle", "Signature").
     * @param claimIndex The unique claim index (for Merkle) or a sequential nonce (for Signature).
     * @param claimant The user who received the tokens.
     * @param tokenContract The contract address of the token being claimed.
     * @param tokenId The ID of the token (for ERC721); 0 for ERC20.
     * @param amount The amount of tokens (for ERC20); 1 for ERC721.
     */
    event Claimed(
        string indexed module,
        uint256 indexed claimIndex,
        address indexed claimant,
        address tokenContract,
        uint256 tokenId,
        uint256 amount
    );

    // --- Generic Errors ---

    /**
     * @notice Reverts if the token transfer (ERC20 or ERC721) fails.
     */
    error Airdrop_TransferFailed();

    /**
     * @notice Reverts if the allocation is for zero tokens and zero amount.
     */
    error Airdrop_InvalidAllocation();

    // --- MerkleAirdrop Errors ---

    /**
     * @notice Reverts if the provided claim index has already been claimed in the bitmap.
     * @param index The index that was already marked as claimed.
     */
    error MerkleAirdrop_AlreadyClaimed(uint256 index);

    /**
     * @notice Reverts if the Merkle proof verification fails (root mismatch).
     */
    error MerkleAirdrop_InvalidProof();

    /**
     * @notice Reverts if the `claimant` in the Merkle leaf does not match the `_msgSender()`.
     * @param claimant The claimant address specified in the leaf.
     * @param sender The address that initiated the transaction (`_msgSender()`).
     */
    error MerkleAirdrop_NotClaimant(address claimant, address sender);

    /**
     * @notice Reverts if the provided Merkle proof is longer than the allowed maximum depth.
     * @param proofLength The length of the proof provided.
     * @param maxDepth The maximum allowed length.
     */
    error MerkleAirdrop_ProofTooLong(uint256 proofLength, uint256 maxDepth);

    // --- SignatureAirdrop Errors ---

    /**
     * @notice Reverts if the recovered signer from the signature is invalid or does not match the claimant.
     * @param expected The address expected to have signed.
     * @param recovered The address recovered from the signature.
     */
    error SignatureAirdrop_InvalidSignature(address expected, address recovered);

    /**
     * @notice Reverts if the provided nonce does not match the claimant's current nonce.
     * @param expected The expected nonce.
     * @param provided The nonce from the signed message.
     */
    error SignatureAirdrop_InvalidNonce(uint256 expected, uint256 provided);
}
