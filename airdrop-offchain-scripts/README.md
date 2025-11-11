# Merkle Tree Generator

**Author:** [BinnaDev](https://binnadev.vercel.app)
**Purpose:** Generate a **Merkle Root**, **Proofs**, and **Claim Data** for the `MerkleAirdrop.sol` contract.

---

## Overview

This Node.js script reads an airdrop allocation CSV, validates all records, hashes each leaf using the **exact same logic** as the on-chain Solidity contract, and generates:

- ✅ A **Merkle Root** (for on-chain verification)
- ✅ A **claim mapping** of proofs and allocations
- ✅ A **JSON output file** (`airdrop-data.json`) to be imported by the smart contract or frontend

The script is designed for **security parity** with the Solidity implementation:

```txt
H(H(abi.encode(index, claimant, tokenContract, tokenId, amount)))
```

---

## Project Structure

```txt
scripts/
  └── generate-merkle.js   # This script
data/
  └── allocations.csv       # Input data file
dist/
  └── airdrop-data.json     # Generated output
```

---

## Quick Start

### 1️⃣ Install Dependencies

```bash
npm install
```

This installs:

- `ethers`
- `merkletreejs`
- `keccak256`
- `csv-parse`
- `fs`, `path` (Node built-ins)

---

### 2️⃣ Prepare Input Data

Create a CSV file at `data/allocations.csv` with the following headers:

| claimant | tokenContract | tokenId | amount |
| -------- | ------------- | ------- | ------ |
| 0x123... | 0xABC...      | 1       | 1000   |
| 0x456... | 0xDEF...      | 2       | 500    |

Each row represents one **airdrop allocation**.
The script auto-generates the **index** field internally.

---

### 3️⃣ Run the Script

```bash
npm run generate-merkle
```

or manually:

```bash
node scripts/generate-merkle.js data/allocations.csv
```

---

## Under the Hood

### Hash Function

Each leaf is computed as:

```solidity
keccak256(
  abi.encode(
    keccak256(
      abi.encode(index, claimant, tokenContract, tokenId, amount)
    )
  )
)
```

- This **double hash** prevents ambiguity in encoding.
- The outer hash ensures compatibility with `MerkleProof.verify()` in Solidity.

---

### Validation Rules

| Field         | Validation                       | Notes                     |
| ------------- | -------------------------------- | ------------------------- |
| claimant      | Must be a valid Ethereum address | Case-checked via checksum |
| tokenContract | Must be a valid Ethereum address | Valid ERC20/721 contract  |
| tokenId       | Must be a non-negative integer   | Supports uint256          |
| amount        | Must be a non-negative integer   | Required                  |
| duplicates    | Not allowed                      | Ensures unique claimants  |

If any invalid rows exist, they are logged with row numbers but **do not stop** valid ones from being processed (unless none are valid).

---

## Output

After successful generation, the following file will be created:

**`dist/airdrop-data.json`**

Example:

```json
{
  "merkleRoot": "0xa634...9b12",
  "claims": {
    "0x123...": {
      "index": 0,
      "tokenContract": "0xABC...",
      "tokenId": "1",
      "amount": "1000",
      "proof": ["0x12ab...", "0x34cd..."]
    }
  }
}
```

### Root

The `merkleRoot` can be passed directly into your Solidity airdrop contract.

### Proofs

Each `proof` array allows a claimant to verify their eligibility on-chain via `MerkleProof.verify()`.

---

## Integration with Solidity

Example (in `MerkleAirdrop.sol`):

```solidity
function claim(
        uint256 index,
        address claimant,
        address tokenContract,
        uint256 tokenId,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        ...
        bytes32 leaf = _hashLeaf(index, claimant, tokenContract, tokenId, amount);

        if (!MerkleProof.verify(proof, MERKLE_ROOT, leaf)) {
            revert MerkleAirdrop_InvalidProof();
        }
        ...
    }

    function _hashLeaf(uint256 index, address claimant, address tokenContract, uint256 tokenId, uint256 amount)
        internal
        pure
        returns (bytes32)
    {
        bytes32 innerHash = keccak256(abi.encode(index, claimant, tokenContract, tokenId, amount));
        return keccak256(abi.encode(innerHash));
    }
```

---

## CLI Reference

| Command                                     | Description                                   |
| ------------------------------------------- | --------------------------------------------- |
| `node scripts/generate-merkle.js <csvPath>` | Generate merkle tree and proofs               |
| `npm run generate-merkle`                   | Shortcut to the above (uses default CSV path) |

---

## Common Errors

| Error                                 | Cause                      | Fix                    |
| ------------------------------------- | -------------------------- | ---------------------- |
| `won't generate root for single leaf` | Only one allocation in CSV | Add at least two rows  |
| `Invalid address`                     | Malformed Ethereum address | Use a checksum address |
| `No valid allocations`                | Empty or invalid CSV       | Check input format     |
| `Duplicate claimant address`          | Repeated wallet            | Use unique wallets     |

---

## Example Test Integration (Foundry)

In `test/MerkleAirdrop.t.sol`:

```solidity
bytes32 root = merkleRootFrom("dist/airdrop-data.json");
MerkleAirdrop airdrop = new MerkleAirdrop(root, address(0));
```

---

## Author Notes

This generator ensures **off-chain and on-chain parity** between:

- Node.js hashing (ethers.js + merkletreejs)
- Solidity hashing (abi.encode, keccak256)

It's built for **precision**, **audit-readiness**, and **developer clarity**.

> "Security starts with determinism." - _BinnaDev_
