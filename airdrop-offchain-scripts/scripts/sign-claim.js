require("dotenv").config();
const { ethers, Wallet, getAddress } = require("ethers");

// --- CONFIGURATION ---

// This should be a securely stored private key (e.g., in .env)
// For this example, we use a known test wallet.
const SIGNER_PRIVATE_KEY = process.env.ANVIL_PRIVATE_KEY;

const AIRDROP_CONTRACT_ADDRESS =
  process.env.ANVIL_SIGNATURE_AIRDROP_CONTRACT_ADDRESS;
const CHAIN_ID = 31337; // localhost/hardhat/anvil

const provider = new ethers.JsonRpcProvider(process.env.ANVIL_RPC_URL);
const wallet = new Wallet(SIGNER_PRIVATE_KEY, provider);

// --- EIP-712 DEFINITIONS (must match contract) ---

const domain = {
  name: "SignatureAirdrop",
  version: "1",
  chainId: CHAIN_ID,
  verifyingContract: AIRDROP_CONTRACT_ADDRESS,
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

/**
 * @notice Fetches the current nonce for a claimant from the contract.
 */
async function getCurrentNonce(claimant) {
  const abi = ["function nonces(address) view returns (uint256)"];
  const contract = new ethers.Contract(AIRDROP_CONTRACT_ADDRESS, abi, provider);
  const nonce = await contract.nonces(claimant);
  return Number(nonce);
}

/**
 * @notice Signs a claim payload.
 */
async function signClaim(claimant, tokenContract, tokenId, amount, nonce) {
  const value = {
    claimant,
    tokenContract,
    tokenId,
    amount,
    nonce,
  };

  console.log("Signing payload:", JSON.stringify(value, null, 2));

  const signature = await wallet.signTypedData(domain, types, value);

  return { signature, value };
}

// --- MAIN EXECUTION ---
async function main() {
  console.log(`Signer Address: ${wallet.address}`);

  const claimantAddress = wallet.address;
  const currentNonce = await getCurrentNonce(claimantAddress);
  console.log(`Current Nonce: ${currentNonce}`);

  // Example: Sign a claim for 100 ERC20 tokens
  const payload = {
    claimant: getAddress(claimantAddress),
    tokenContract: getAddress("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"), // Mock ERC20
    tokenId: 0,
    amount: "100000000000000000000", // 100 tokens
    nonce: currentNonce,
  };

  const { signature, value } = await signClaim(
    payload.claimant,
    payload.tokenContract,
    payload.tokenId,
    payload.amount,
    payload.nonce
  );

  console.log("\n--- Signature Generated ---");
  console.log(`Signature: ${signature}`);
  console.log("\n--- Payload to submit to claimWithSignature() ---");
  console.log(`claimant: "${value.claimant}"`);
  console.log(`tokenContract: "${value.tokenContract}"`);
  console.log(`tokenId: ${value.tokenId}`);
  console.log(`amount: "${value.amount}"`);
  console.log(`nonce: ${value.nonce}`);
  console.log(`signature: "${signature}"`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
