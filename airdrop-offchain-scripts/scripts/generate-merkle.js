const fs = require("fs");
const path = require("path");
const { parse } = require("csv-parse/sync");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");
const { ethers, AbiCoder, keccak256: ethersKeccak } = require("ethers");

// --- CONFIGURATION ---
const CONFIG = {
  merkleOutputDir: path.join(__dirname, "..", "dist"),
  outputFileName: "airdrop-data.json",
};

/**
 * @notice Validates a string as a proper Ethereum address.
 */
function validateAddress(address, fieldName, row) {
  if (!ethers.isAddress(address)) {
    throw new Error(`Invalid ${fieldName} at row ${row}: ${address}`);
  }
  return ethers.getAddress(address); // Checksum
}

/**
 * @notice Validates a string as a non-negative integer.
 */
function validateUint(uintString, fieldName, row) {
  try {
    const val = BigInt(uintString);
    if (val < 0n) {
      throw new Error("Value cannot be negative");
    }
    return val.toString(); // Return as string to match ethers encoding
  } catch (e) {
    throw new Error(`Invalid ${fieldName} at row ${row}: ${uintString}`);
  }
}

/**
 * @notice Processes the CSV content into a structured, validated array.
 */
function processCSVData(csvContent) {
  const records = parse(csvContent, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

  const validAllocations = [];
  const errors = [];
  const uniqueSet = new Set();

  records.forEach((row, idx) => {
    const rowNum = idx + 2; // +1 for zero-index, +1 for header
    try {
      if (
        !row.claimant ||
        !row.tokenContract ||
        row.tokenId === undefined ||
        row.amount === undefined
      ) {
        throw new Error(
          "Missing required fields. Must have: claimant, tokenContract, tokenId, amount"
        );
      }

      const claimant = validateAddress(row.claimant, "claimant", rowNum);
      const tokenContract = validateAddress(
        row.tokenContract,
        "tokenContract",
        rowNum
      );
      const tokenId = validateUint(row.tokenId, "tokenId", rowNum);
      const amount = validateUint(row.amount, "amount", rowNum);

      // Add the auto-incrementing index, which is critical for the bitmap
      const allocation = {
        index: idx,
        claimant,
        tokenContract,
        tokenId,
        amount,
      };

      // Check for duplicate claimants (adjust if one claimant can have multiple airdrops)
      if (uniqueSet.has(claimant.toLowerCase())) {
        throw new Error(`Duplicate claimant address: ${claimant}`);
      }
      uniqueSet.add(claimant.toLowerCase());

      validAllocations.push(allocation);
    } catch (err) {
      errors.push(`Row ${rowNum}: ${err.message}`);
    }
  });

  return { validAllocations, errors };
}

/**
 * @notice Hashes a leaf identically to the MerkleAirdrop.sol contract.
 * @dev H(H(abi.encode(index, claimant, tokenContract, tokenId, amount)))
 */
function _hashLeaf(allocation) {
  // 1. Get the inner hash: keccak256(abi.encode(...))
  const innerHash = ethersKeccak(
    AbiCoder.defaultAbiCoder().encode(
      ["uint256", "address", "address", "uint256", "uint256"],
      [
        allocation.index,
        allocation.claimant,
        allocation.tokenContract,
        allocation.tokenId,
        allocation.amount,
      ]
    )
  );

  // 2. Get the outer hash: keccak256(abi.encodePacked(innerHash))
  // This must be converted to a Buffer for merkletreejs
  const leaf = ethersKeccak(
    AbiCoder.defaultAbiCoder().encode(["bytes32"], [innerHash])
  );

  // Convert hex string to Buffer for the MerkleTree library
  return Buffer.from(leaf.slice(2), "hex");
}

/**
 * @notice Builds the Merkle tree and generates proofs.
 */
function buildMerkleTree(allocations, leaves) {
  // We use `keccak256` from the 'keccak256' library as expected by merkletreejs
  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const rootHex = tree.getHexRoot();

  // Generate the full output object as specified in our plan
  const output = {
    merkleRoot: rootHex,
    claims: {},
  };

  allocations.forEach((alloc, idx) => {
    const leaf = leaves[idx];
    const proof = tree.getHexProof(leaf);
    output.claims[alloc.claimant] = {
      index: alloc.index,
      tokenContract: alloc.tokenContract,
      tokenId: alloc.tokenId,
      amount: alloc.amount,
      proof: proof,
    };
  });

  return { rootHex, output };
}

// --- MAIN EXECUTION ---
async function generateMerkle() {
  console.log("--- Starting Merkle Tree Generation (BinnaDev) ---");
  const t0 = Date.now();

  try {
    // 1. Get CSV file path from command line arguments
    const csvPath = process.argv[2];
    if (!csvPath) {
      throw new Error(
        "Missing CSV path. Usage: node scripts/generate-merkle.js <path/to/allocations.csv>"
      );
    }
    const fullCsvPath = path.resolve(csvPath);
    if (!fs.existsSync(fullCsvPath)) {
      throw new Error(`Input file not found at ${fullCsvPath}`);
    }
    console.log(`Loading allocations from: ${fullCsvPath}`);

    // 2. Read and process CSV
    const csvRaw = fs.readFileSync(fullCsvPath, { encoding: "utf-8" });
    const { validAllocations, errors } = processCSVData(csvRaw);

    if (errors.length > 0) {
      console.warn(`\n⚠️ Found ${errors.length} issues in CSV:`);
      errors.slice(0, 10).forEach((e) => console.warn(`  - ${e}`)); // Show first 10
      if (errors.length > 10)
        console.warn(`  ... and ${errors.length - 10} more.`);
    }
    if (validAllocations.length === 0) {
      throw new Error("No valid allocations found in CSV file. Aborting.");
    }
    console.log(`✅ Processed ${validAllocations.length} valid allocations.`);

    // 3. Generate leaves
    const leaves = validAllocations.map(_hashLeaf);

    // 4. Build tree and output JSON
    const { rootHex, output } = buildMerkleTree(validAllocations, leaves);
    console.log(`\n✅ Merkle Root: ${rootHex}`);

    // 5. Save output
    const outputDir = CONFIG.merkleOutputDir;
    const outputPath = path.join(outputDir, CONFIG.outputFileName);

    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    fs.writeFileSync(outputPath, JSON.stringify(output, null, 2), {
      encoding: "utf-8",
    });

    const duration = Date.now() - t0;
    console.log("\n--- Generation Complete ---");
    console.log(`⏱️  Duration: ${duration}ms`);
    console.log(`📁 Output saved to: ${outputPath}`);
  } catch (err) {
    console.error("\n--- ❌ Generation Failed ---");
    console.error("Error:", err.message);
    process.exit(1);
  }
}

generateMerkle();
