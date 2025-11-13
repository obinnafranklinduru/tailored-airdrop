// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Import our contracts to be deployed
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {SignatureAirdrop} from "../src/SignatureAirdrop.sol";

/**
 * @title DeployAirdropSystem
 * @author BinnaDev (Obinna Franklin Duru)
 * @notice A Foundry script to deploy the MerkleAirdrop and SignatureAirdrop contracts.
 * @dev This script reads parameters from environment variables for security and flexibility.
 */
contract DeployAirdropSystem is Script {
    /**
     * @notice The main entry point for the deployment script.
     */
    function run() external {
        // --- 1. Load Deployment Parameters ---
        // These are loaded securely from your environment variables
        // We use vm.envBytes32 for the root
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");
        // We use vm.envAddress for the forwarder
        // address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER");
        address trustedForwarder = address(0); // No gasless system by default

        // --- 2. Parameter Validation ---
        // A 'thoughtful' script validates its inputs before spending gas.
        if (merkleRoot == bytes32(0)) {
            revert("MERKLE_ROOT environment variable not set or is zero.");
        }
        // Note: We allow trustedForwarder to be address(0) if no gasless
        // system is being used.

        console.log("--- Starting Deployment ---");
        console.log("Trusted Forwarder:", trustedForwarder);
        console.log("Deployer Address:", msg.sender);

        // --- 3. Start Broadcast ---
        // This tells Foundry to send the following as real transactions.
        vm.startBroadcast();

        // --- 4. Deploy MerkleAirdrop ---
        console.log("\nDeploying MerkleAirdrop...");
        MerkleAirdrop merkleAirdrop = new MerkleAirdrop(merkleRoot, trustedForwarder);
        console.log("MerkleAirdrop deployed to:", address(merkleAirdrop));

        // --- 5. Deploy SignatureAirdrop ---
        console.log("\nDeploying SignatureAirdrop...");
        SignatureAirdrop signatureAirdrop = new SignatureAirdrop(trustedForwarder);
        console.log("SignatureAirdrop deployed to:", address(signatureAirdrop));

        // --- 6. Stop Broadcast ---
        vm.stopBroadcast();

        console.log("\n--- Deployment Complete ---");
    }
}
