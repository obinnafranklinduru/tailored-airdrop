# Advanced Airdrop System

**Author:** [BinnaDev (Obinna Franklin Duru)](https://x.com/BinnaDev)
**Status:** Audit-Ready  
**Solidity:** ^0.8.24  
**Framework:** Foundry

A modular, secure, and gas-efficient system for distributing ERC20 and ERC721 tokens. This repository provides a production-ready implementation of advanced airdrop patterns, built with a security-first and reliability-focused mindset.

---

## Core Features

This system is not a single contract but a set of modular components designed for flexibility and security.

- **Modular Architecture:** Choose the right tool for the job. Deploy a Merkle-based drop, a Signature-based drop, or both.
- **Merkle Airdrops:** A `MerkleAirdrop.sol` contract for large-scale, one-time distributions. It's extremely gas-efficient for the deployer (only one bytes32 root is stored on-chain).
- **Signature Airdrops:** A `SignatureAirdrop.sol` contract for dynamic, off-chain, or authority-driven claims using EIP-712.
- **Gas-Efficient State:** Uses `BitMaps.sol` for Merkle claims, drastically reducing gas costs for users by packing 256 claims into a single storage slot.
- **Gasless Claims:** Both contracts are fully ERC-2771 compatible, allowing a relayer to pay gas fees on behalf of users for a seamless UX.
- **Robust Security:** Built-in protection against re-entrancy (`nonReentrant`), double-claims (`Bitmap`/`Nonces`), and replay attacks (EIP-712 Nonces).
- **Universal Token Support:** A single, unified logic path handles both ERC20 and ERC721 token transfers.
- **Auditable & Documented:** Every line of code is fully documented with Natspec comments.

---

## Architecture Overview

The system is split into two primary, independent contract modules.

### 1. MerkleAirdrop.sol

This contract acts as a token vault secured by a Merkle root. It is designed for "pull" based airdrops where users prove their inclusion in a large, pre-computed list.

- **Logic:** The deployer generates a Merkle tree off-chain from a list of allocations (e.g., `(index, claimant, token, amount)`). The tree's root is set as immutable in the contract's constructor.
- **Claiming:** A user calls `claim()`, providing their allocation data and a valid proof. The contract verifies the proof against the root and checks a `BitMaps.BitMap` to prevent double-claims.
- **Best For:** Large-scale, public airdrops (10k - 1M+ users) where the allocation list is fixed at deployment.

### 2. SignatureAirdrop.sol

This contract acts as a token vault secured by EIP-712 signatures. It is designed for "push" based airdrops where a trusted authority (a "signer") approves claims individually.

- **Logic:** A trusted off-chain signer (e.g., a backend service) generates EIP-712 signatures for valid claims. The `Claim` payload is domain-separated and includes a nonce for replay protection.
- **Claiming:** A user (or relayer) calls `claimWithSignature()`, providing the `Claim` payload and the signature. The contract uses `ECDSA.recover` to verify the signer and checks the nonce to prevent double-claims.
- **Best For:** Dynamic airdrops, "claim-as-you-go" rewards, or any system where the allocation logic is complex and managed off-chain.

---

## Off-Chain Tooling

Our JavaScript tools are essential for managing the airdrop.

### Prerequisites

```bash
npm install
```

### 1. Generating the Merkle Tree

This script reads a CSV and generates the `merkleRoot` and `airdrop-data.json` proof file.

**Format your `allocations.csv`:**

```bash
claimant,tokenContract,tokenId,amount
0x709...79C8,0x5Fb...0aa3,0,100000000000000000000
0x3C4...0b0B,0x016...Eb8F,42,1
```

**Run the script:**

```bash
# Reads from data/allocations.csv by default
npm run generate-merkle
```

This will create `dist/airdrop-data.json`. The `merkleRoot` printed in your console is what you need for deployment.

### 2. Generating an EIP-712 Signature

This script demonstrates how a backend would sign a claim. You must edit the file to point to your deployed contract address and chain ID.

```bash
# (After configuring contract address in the script)
npm run sign-claim
```

This will print a sample payload and signature that can be passed to `claimWithSignature()`.

---

## On-Chain Deployment

We use Foundry Scripts for reliable, repeatable deployments.

### Set Environment Variables

Your `MERKLE_ROOT` comes from the `generate-merkle.js` script. `TRUSTED_FORWARDER` is your ERC-2771 relayer, or `0x0000000000000000000000000000000000000000` if not used.

```bash
export MERKLE_ROOT=0x...
export TRUSTED_FORWARDER=0x...
export RPC_URL=...
export PRIVATE_KEY=...
```

### Run the Deployment Script

```bash
forge script scripts/foundry/Deploy.s.sol:DeployAirdropSystem \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

---

## Testing

This project uses Foundry for all testing.

```bash
# Run all tests
forge test

# Run a specific test suite with high verbosity
forge test --match-path test/MerkleAirdrop.t.sol -vvv

# Get a gas report
forge test --gas-report
```

---

## Security & Auditing

Security is the primary value of this project.

- **Natspec:** All contracts are fully documented with Natspec comments.
- **Checks-Effects-Interactions:** This pattern is strictly followed to prevent re-entrancy.
- **nonReentrant Guard:** All claim functions use OpenZeppelin's `nonReentrant` modifier.
- **Immutable Root:** The `MERKLEROOT` is immutable and cannot be changed.

## 🤝 Connect

### Obinna Franklin Duru

- [Follow on X](https://x.com/BinnaDev)
- [LinkedIn](https://www.linkedin.com/in/obinna-franklin-duru/)
- _Open for smart contract audits and development roles._
