# Advanced Airdrop System: Research & Implementation Plan

**Author:** BinnaDev (Obinna Franklin Duru)  
**Status:** Completed  
**Recommended Solidity:** ^0.8.24  
**Target Framework:** Foundry

---

## 0. Developer Quick Start (Foundry)

For an implementer ready to build immediately:

```bash
# 1. Setup Project & Install Libs
forge init --no-commit advanced-airdrop
cd advanced-airdrop
forge install OpenZeppelin/openzeppelin-contracts
forge install dmfxyz/murky

# 2. Create Core Files
touch src/interfaces/IAirdrop.sol
touch src/MerkleAirdrop.sol
touch src/SignatureAirdrop.sol
touch test/MerkleAirdrop.t.sol
touch test/SignatureAirdrop.t.sol
touch test/Gasless.t.sol

# 3. Build & Test
forge build
forge test --match-path test/MerkleAirdrop.t.sol -vv
forge test --match-path test/SignatureAirdrop.t.sol -vv
forge test --gas-report
```

---

## 1. Executive Summary

This document outlines the architecture for an advanced, secure, and gas-efficient airdrop system. The primary goal is to provide modular, reusable, and auditable contracts for distributing ERC20 and ERC721 tokens.

We will focus on two primary mechanisms:

- **Merkle tree proofs** (for large-scale, on-chain whitelists)
- **EIP-712 signatures** (for off-chain, authority-based claims)

The system is designed with a **security-first, reliability-focused mindset**, incorporating gas-efficient state tracking via bitmaps and optional meta-transaction support via ERC-2771.

The recommended architecture is modular, separating Merkle and Signature logic into distinct, non-reentrant contracts that serve as token vaults.

---

## 2. Background & Core Concepts

### Merkle Trees

A Merkle tree allows committing to a large dataset (e.g., 100,000 allocations) using a single 32-byte root. A user proves inclusion via a Merkle proof, validated against the root - costing gas proportional to \(\log(n)\), not \(n\).

**Construction:**

```solidity
keccak256(abi.encode(index, address, amount))
```

**Verification:**
Uses OpenZeppelin’s `MerkleProof.verify`.

### ECDSA Signatures (EIP-712)

Instead of storing a root, the contract accepts signed claim vouchers from an authority. This allows flexible, off-chain verification.

- **Verification:** Uses `ECDSA.recover()` on an EIP-712 hash.
- **Replay Protection:** Implemented via on-chain nonce mapping.

### Gasless/Metered Claims (ERC-2771)

Allows users to claim without ETH - a relayer pays gas. Implemented with `ERC2771Context` to restore the correct `msg.sender`.

### On-Chain State Patterns

- **Mapping:** `mapping(address => bool)` (simple, gas-heavy)
- **Bitmap:** `mapping(uint256 => uint256)` (recommended; efficient with `BitMaps.sol`)

---

## 3. Comparative Analysis & Real-World Patterns

| Implementation                       | Strengths            | Weaknesses                             |
| ------------------------------------ | -------------------- | -------------------------------------- |
| **OpenZeppelin MerkleProof Airdrop** | Simple & reliable    | Inefficient `mapping(address => bool)` |
| **Uniswap MerkleDistributor**        | Bitmap index support | Still uses mapping(index => bool)      |
| **Foundation (EIP-712)**             | Highly flexible      | Centralized signer                     |

### Our Hybrid Architecture

Implements **both** Merkle and Signature modules as separate contracts.

**Strengths:** Modular, flexible, supports ERC20/721/2771.  
**Weakness:** Slightly more complex codebase.

---

## 4. Threat Model & Security Checklist

| Threat                | Mitigation                              |
| --------------------- | --------------------------------------- |
| Double-Claim          | Bitmap (Merkle) or Nonces (Signature)   |
| Replay Attack         | Nonce included in signature             |
| Malformed Proofs      | `_hashLeaf()` reconstruction validation |
| Root Substitution     | Immutable `i_merkleRoot`                |
| Relayer Front-Running | Tokens go to claimant only              |
| Reentrancy            | `nonReentrant` modifier                 |

---

## 5. Recommended Architecture (Module-by-Module)

### Offchain Generator (`airdrop-offchain-scripts/scripts/`)

Generates Merkle proofs and signatures.

**Example Output:**

```json
{
  "merkleRoot": "0x...",
  "claims": {
    "0xUserA...": {
      "index": 0,
      "tokenContract": "0x...",
      "tokenId": "0",
      "amount": "100000000000000000000",
      "proof": ["0x...", "0x..."]
    }
  }
}
```

### Onchain Verifier (MerkleAirdrop.sol)

- Inherits: `IAirdrop`, `ERC2771Context`, `ReentrancyGuard`
- State: `bytes32 immutable MERKLEROOT; BitMaps.BitMap internal claimedBitmap;`

### Signature-Based Authorizer (SignatureAirdrop.sol)

- Inherits: `IAirdrop`, `EIP712`, `ERC2771Context`, `ReentrancyGuard`
- Uses EIP-712 structured data claims with nonces.

### Shared Interface (IAirdrop.sol)

Defines common events and custom errors.

---

## 6. Implementation Plan (Foundry-centric)

```bash
advanced-airdrop/
├── src/ # Smart Contracts
│ ├── interfaces/
│ │ └── IAirdrop.sol # Shared events and errors interface
│ ├── MerkleAirdrop.sol # The Merkle-proof airdrop contract
│ └── SignatureAirdrop.sol # The EIP-712 signature airdrop contract
├── test/ # Foundry Tests
│ ├── mocks/ # Mock contracts for testing
│ │ └── metatx/
│ │ └── ERC2771ForwarderMock.sol
│ │ └── tokens/
│ │ └── ERC721Mock.sol
│ ├── MerkleAirdrop.t.sol # Tests for MerkleAirdrop
│ ├── SignatureAirdrop.t.sol# Tests for SignatureAirdrop
│ └── Gasless.t.sol # Tests for ERC-2771 integration
|scripts/
│ ├── Deploy.s.sol # Foundry deployment script
|airdrop-offchain-scripts/ # Off-chain and deployment scripts
│ ├── scripts/
│ ├── generate-merkle.js # Node.js script to create Merkle tree
│ └── sign-claim.js # Node.js script to create EIP-712 sigs
├── data/
│ └── allocations.csv # Sample input data for generate-merkle.js
├── dist/
│ └── airdrop-data.json # Output of the Merkle generation script
├── package.json # Node.js dependencies
└── README.md # This file
└── foundry.toml
```

### Foundry Test Plan

Covers ERC20, ERC721, invalid proofs, replay, tampering, and reentrancy.

---

## 7. Gas & Optimization Guidance

| Operation                                | Gas Cost (approx.)    |
| ---------------------------------------- | --------------------- |
| `ecrecover`                              | 3,000                 |
| `MerkleProof.verify`                     | 32,000 (for depth 16) |
| `mapping(address => bool)` (cold SSTORE) | 22,100                |
| `BitMaps.set` (warm)                     | 5,000                 |

**Conclusion:** Merkle + Bitmap is cheaper for large batches; Signature-based more flexible for dynamic drops.

**Optimizations:**

- Use `calldata`
- Use `immutable` root
- Precompute EIP712 typehash
- Use `unchecked {}` where safe

---

## 8. Testing & Security Checklist

- [x] Run `forge test -vv`
- [x] Run `forge test --gas-report`
- [x] Run `forge coverage`

---

## 9. Deliverables & Milestones

| Milestone | Description               | Status      |
| --------- | ------------------------- | ----------- |
| **M1**    | Basic Merkle Airdrop      | ✅ Complete |
| **M2**    | Signature-Based Airdrop   | ✅ Complete |
| **M3**    | Gasless Claims (ERC-2771) | ✅ Complete |
| **M4**    | Audit-Ready Package       | ⏳ Pending  |

---

## 10. Appendix: EIP-712 Domain / Types

```js
const domain = {
  name: "SignatureAirdrop",
  version: "1",
  chainId: 31337,
  verifyingContract: "0x...",
};

const types = {
  Claim: [
    { name: "claimant", type: "address" },
    { name: "tokenContract", type: "address" },
    { name: "tokenId", type: "uint256" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ],
};
```

**Foundry Commands:**

```bash
forge test --match-path test/MerkleAirdrop.t.sol -vv
forge test --gas-report
forge coverage
slither .
```

**References:**

- OpenZeppelin MerkleProof
- OpenZeppelin EIP-712
- OpenZeppelin ERC-2771
- EIP-712 Standard

---

## 11. Future Research (Post-v1)

- **Signature Aggregation (EIP-1271):** Multi-claim aggregation
- **Sparse Merkle Trees:** Dynamic datasets (Useful for "proof of non-inclusion" or if the dataset is expected to change often.)
- **ZK-Proofs:** Privacy-preserving airdrops (e.g., "I can claim an amount" without revealing which one).
- **Batch Claims:** Multi-claim support. Implement `claimBatch(Claim[] calldata claims, bytes[] calldata signatures)` for SignatureAirdrop.
- **Vested Airdrops:** Integrate vesting mechanics
