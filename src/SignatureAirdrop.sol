// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {IAirdrop} from "./interfaces/IAirdrop.sol";

/**
 * @title SignatureAirdrop
 * @author BinnaDev
 * @notice A modular, secure contract for airdrops verified by EIP-712 signatures.
 * @dev This contract allows a trusted backend to sign claim payloads, which
 * users (or relayers) can submit. It uses EIP-712 for domain-separated,
 * typed signatures, and `nonces` for replay protection.
 * It inherits from `ERC2771Context` but the claim logic is designed to
 * send tokens to the `claimant` (the signer), not `_msgSender()`.
 */
contract SignatureAirdrop is IAirdrop, ERC2771Context, ReentrancyGuard, EIP712, Nonces {
    /**
     * @notice Defines the data structure for a valid claim.
     * @dev This struct *must* match the EIP-712 type definition.
     */
    struct Claim {
        address claimant;
        address tokenContract;
        uint256 tokenId;
        uint256 amount;
        uint256 nonce;
    }

    /**
     * @notice The EIP-712 typehash for our specific `Claim` struct.
     * @dev This is pre-computed for gas efficiency.
     * keccak256("Claim(address claimant,address tokenContract,uint256 tokenId,uint256 amount,uint256 nonce)")
     */
    bytes32 private constant EIP712_TYPEHASH = 0x8abedf9a1affb7bc0fcfa00e80f5eb339da96763b85507537a999fc325f1255c;

    /**
     * @notice Initializes the contract with the EIP-712 domain and trusted forwarder.
     * @param trustedForwarder The address of the ERC-2771 trusted forwarder.
     */
    constructor(address trustedForwarder)
        ERC2771Context(trustedForwarder)
        EIP712("SignatureAirdrop", "1") // EIP-712 Domain: Name, Version
    {}

    /**
     * @notice Claims an airdrop allocation by providing a valid EIP-712 signature.
     * @dev This function can be called by anyone (e.g., a relayer), but the
     * tokens will *only* be sent to the `claimant` address that signed
     * the payload, ensuring security.
     * @param claim The `Claim` struct containing all payload data.
     * @param signature The EIP-712 signature from the claimant.
     */
    function claimWithSignature(Claim calldata claim, bytes calldata signature) external nonReentrant {
        // --- CHECKS ---

        // 1. Check nonce for replay protection.
        // We fetch the *current* nonce and immediately increment it
        // in one atomic operation using OZ's `_useNonce`.
        uint256 currentNonce = _useNonce(claim.claimant);
        if (claim.nonce != currentNonce) {
            revert SignatureAirdrop_InvalidNonce(currentNonce, claim.nonce);
        }

        // 2. Hash the struct to get the EIP-712 digest.
        bytes32 structHash = _hash(claim);

        // 3. Recover the signer from the hash and signature.
        address signer = ECDSA.recover(structHash, signature);

        // 4. Validate the signer.
        if (claim.claimant != signer) {
            revert SignatureAirdrop_InvalidSignature(claim.claimant, signer);
        }

        // --- EFFECTS ---
        // Nonce was already incremented by `_useNonce`.
        // No other state to change *before* interaction.

        // --- INTERACTIONS ---

        // 5. Dispatch the token *to the claimant (signer)*.
        _dispatchToken(claim.tokenContract, claim.claimant, claim.tokenId, claim.amount);

        // 6. Emit the standardized event.
        // We use the nonce as the "claimIndex" for event consistency.
        emit Claimed("Signature", claim.nonce, claim.claimant, claim.tokenContract, claim.tokenId, claim.amount);
    }

    /**
     * @notice Internal function to hash the EIP-712 struct.
     * @dev This mirrors the off-chain hashing and uses the EIP-712
     * domain separator for chain-replay protection.
     * @dev REFACTOR: We now hash the struct directly, which is cleaner
     * and functionally identical to de-structuring.
     */
    function _hash(Claim calldata claim) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EIP712_TYPEHASH, claim)));
    }

    /**
     * @notice Internal function to dispatch the tokens (ERC20 or ERC721).
     * @dev This is a duplicate from MerkleAirdrop.sol for modularity.
     * A future refactor could move this to a shared Base.sol.
     * Assumes this contract holds the full supply of airdrop tokens.
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
            IERC721(tokenContract).safeTransferFrom(address(this), to, tokenId);
        }
    }

    /**
     * @dev Overrides the `_msgSender()` from `ERC2771Context`.
     * Note: This is *not* used by the claim logic (which uses `claimant`),
     * but is included for full compatibility if we add other
     * "sender-based" functions later.
     */
    function _msgSender() internal view override(ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }
}
