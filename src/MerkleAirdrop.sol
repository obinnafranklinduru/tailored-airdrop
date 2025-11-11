// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAirdrop} from "./interfaces/IAirdrop.sol";

/**
 * @title MerkleAirdrop
 * @author BinnaDev
 * @notice A modular, gas-efficient, and secure contract for airdrops
 * verified by Merkle proofs.
 * @dev This contract implements the `IAirdrop` interface, uses OpenZeppelin's
 * `BitMaps` for gas-efficient claim tracking, `ReentrancyGuard` for security,
 * and `ERC2771Context` to natively support gasless claims via a trusted
 * forwarder. The Merkle root is immutable, set at deployment for
 * maximum trust.
 */
contract MerkleAirdrop is IAirdrop, ERC2771Context, ReentrancyGuard {
    using BitMaps for BitMaps.BitMap;

    /**
     * @notice The MerMonitor's root of the Merkle tree containing all allocations.
     * @dev This is immutable, meaning it can only be set once at deployment.
     * This is a critical security feature to build trust with users,
     * as the rules of the airdrop can never change.
     */
    bytes32 public immutable MERKLE_ROOT;

    /**
     * @notice The maximum allowed depth for a Merkle proof.
     * @dev This is a security measure to prevent gas-griefing (DOS) attacks
     * where an attacker might submit an excessively long (but valid) proof.
     * 32 is a safe and generous default.
     */
    uint256 public constant MAX_PROOF_DEPTH = 32;

    /**
     * @notice The bitmap storage that tracks all claimed indices.
     * @dev We use the `BitMaps` library (composition) rather than inheriting
     * (inheritance) for better modularity and clarity.
     */
    BitMaps.BitMap internal claimedBitmap;

    /**
     * @notice Initializes the contract with the airdrop's Merkle root
     * and the trusted forwarder for gasless transactions.
     * @param merkleRoot The `bytes32` root of the Merkle tree.
     * @param trustedForwarder The address of the ERC-2771 trusted forwarder.
     * Pass `address(0)` if gasless support is not needed.
     */
    constructor(bytes32 merkleRoot, address trustedForwarder) ERC2771Context(trustedForwarder) {
        MERKLE_ROOT = merkleRoot;
    }

    /**
     * @notice Claims an airdrop allocation by providing a valid Merkle proof.
     * @dev This function follows the Checks-Effects-Interactions pattern.
     * It uses `_msgSender()` to support both direct calls and gasless claims.
     * @param index The unique claim index for this user (from the Merkle tree data).
     * @param claimant The address that is eligible for the claim.
     * @param tokenContract The address of the ERC20 or ERC721 token.
     * @param tokenId The ID of the token (for ERC721); must be 0 for ERC20.
     * @param amount The amount of tokens (for ERC20); typically 1 for ERC721.
     * @param proof The Merkle proof (`bytes32[]`) showing the leaf is in the tree.
     */
    function claim(
        uint256 index,
        address claimant,
        address tokenContract,
        uint256 tokenId,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        // --- CHECKS ---

        // 1. Check if this index is already claimed (Bitmap check).
        // This is the cheapest check and should come first.
        if (claimedBitmap.get(index)) {
            revert MerkleAirdrop_AlreadyClaimed(index);
        }

        // 2. Check for proof length (Gas-griefing DOS protection).
        if (proof.length > MAX_PROOF_DEPTH) {
            revert MerkleAirdrop_ProofTooLong(proof.length, MAX_PROOF_DEPTH);
        }

        // 3. Check that the sender is the rightful claimant.
        // We use `_msgSender()` to transparently support ERC-2771.
        address sender = _msgSender();
        if (claimant != sender) {
            revert MerkleAirdrop_NotClaimant(claimant, sender);
        }

        // 4. Reconstruct the leaf on-chain.
        // This is a critical security step. We NEVER trust the client
        // to provide the leaf hash directly.
        bytes32 leaf = _hashLeaf(index, claimant, tokenContract, tokenId, amount);

        // 5. Verify the proof (Most expensive check).
        if (!MerkleProof.verify(proof, MERKLE_ROOT, leaf)) {
            revert MerkleAirdrop_InvalidProof();
        }

        // --- EFFECTS ---

        // 6. Mark the index as claimed *before* the interaction.
        // This satisfies the Checks-Effects-Interactions pattern and
        // mitigates reentrancy risk.
        claimedBitmap.set(index);

        // --- INTERACTIONS ---

        // 7. Dispatch the token.
        _dispatchToken(tokenContract, claimant, tokenId, amount);

        // 8. Emit the standardized event.
        emit Claimed("Merkle", index, claimant, tokenContract, tokenId, amount);
    }

    /**
     * @notice Public view function to check if an index has been claimed.
     * @param index The index to check.
     * @return bool True if the index is claimed, false otherwise.
     */
    function isClaimed(uint256 index) public view returns (bool) {
        return claimedBitmap.get(index);
    }

    /**
     * @notice Internal function to hash the leaf data.
     * @dev Must match the exact hashing scheme used in the off-chain
     * generator script. We use a double-hash (H(H(data))) pattern
     * with `abi.encode` for maximum security and standardization.
     * `abi.encode` is safer than `abi.encodePacked` as it pads elements.
     */
    function _hashLeaf(uint256 index, address claimant, address tokenContract, uint256 tokenId, uint256 amount)
        internal
        pure
        returns (bytes32)
    {
        // First hash: abi.encode() is safer than abi.encodePacked()
        // as it pads all elements, preventing ambiguity.
        bytes32 innerHash = keccak256(abi.encode(index, claimant, tokenContract, tokenId, amount));

        // Second hash: This is a standard pattern to ensure all leaves
        // are a uniform hash-of-a-hash.
        return keccak256(abi.encode(innerHash));
    }

    /**
     * @notice Internal function to dispatch the tokens (ERC20 or ERC721).
     * @dev Assumes this contract holds the full supply of airdrop tokens.
     */
    function _dispatchToken(address tokenContract, address to, uint256 tokenId, uint256 amount) internal {
        if (tokenId == 0) {
            // This is an ERC20 transfer.
            if (amount == 0) revert Airdrop_InvalidAllocation();
            bool success = IERC20(tokenContract).transfer(to, amount);
            if (!success) revert Airdrop_TransferFailed();
        } else {
            // This is an ERC721 transfer.
            // The `amount` parameter is ignored (implicitly 1).
            // `safeTransferFrom` is used for security, and our `nonReentrant`
            // guard on `claim()` protects against reentrancy attacks.
            IERC721(tokenContract).safeTransferFrom(address(this), to, tokenId);
        }
    }

    /**
     * @dev Overrides the `_msgSender()` from `ERC2771Context` to enable
     * meta-transactions. This is the heart of our gasless support.
     */
    function _msgSender() internal view override(ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }
}
