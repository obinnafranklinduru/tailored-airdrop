// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {AirdropVault} from "../src/AirdropVault.sol";
import {IAirdropVault} from "../src/interfaces/IAirdropVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MerkleAirdropTest is Test {
    using SafeERC20 for MockERC20;

    // Contracts
    MerkleAirdrop public airdrop;
    AirdropVault public vault;
    MockERC20 public token;

    // Test Users
    address public user1 = address(0x1111111111111111111111111111111111111111);
    address public user2 = address(0x2222222222222222222222222222222222222222);
    address public user3 = address(0x3333333333333333333333333333333333333333);
    address public admin = address(0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF);
    address public randomUser = address(0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEF);

    // Test Data
    uint256 public amount1 = 100 * 1e18;
    uint256 public amount2 = 200 * 1e18;
    uint256 public amount3 = 300 * 1e18;

    // Merkle Tree Data
    bytes32 public root;
    bytes32[] public proof1;
    bytes32[] public proof2;
    bytes32[] public proof3;

    function setUp() public {
        // 1. Deploy contracts and mint tokens
        token = new MockERC20("Mock Token", "MOCK", 18);
        vault = new AirdropVault(address(token), admin);
        token.mint(address(vault), 1000 * 1e18); // Mint 1000 tokens to the vault

        // 2. Calculate Merkle Root & Proofs
        // This simulates the off-chain generation process.
        // Hashing: H(H(abi.encode(index, address, amount)))

        // Leaf 1
        bytes32 inner1 = keccak256(abi.encode(0, user1, amount1));
        bytes32 leaf1 = keccak256(abi.encode(inner1));

        // Leaf 2
        bytes32 inner2 = keccak256(abi.encode(1, user2, amount2));
        bytes32 leaf2 = keccak256(abi.encode(inner2));

        // Leaf 3
        bytes32 inner3 = keccak256(abi.encode(2, user3, amount3));
        bytes32 leaf3 = keccak256(abi.encode(inner3));

        // Create a sorted array of leaves as merkletreejs does
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = leaf1; // 0x608e...
        leaves[1] = leaf2; // 0x6f31...
        leaves[2] = leaf3; // 0x4f15...

        // Sort: [leaf3, leaf1, leaf2]
        (leaves[0], leaves[2]) = (leaves[2], leaves[0]);
        // leaves[0] = 0x4f15... (leaf3)
        // leaves[1] = 0x6f31... (leaf2)
        // leaves[2] = 0x608e... (leaf1)
        (leaves[1], leaves[2]) = (leaves[2], leaves[1]);
        // leaves[0] = 0x4f15... (leaf3)
        // leaves[1] = 0x608e... (leaf1)
        // leaves[2] = 0x6f31... (leaf2)

        // --- Calculate Tree ---
        bytes32 node1 = leaves[0]; // 0x4f15... (leaf3)
        bytes32 node2 = leaves[1]; // 0x608e... (leaf1)
        bytes32 node3 = leaves[2]; // 0x6f31... (leaf2)

        // --- FIX: Correct Merkle Math ---
        // We must replicate the OZ library's pair-sorting logic.
        bytes32 h12 = hashPair(node1, node2); // 0xc877...
        bytes32 h33 = hashPair(node3, node3); // 0x618e...
        root = hashPair(h12, h33); // This sorts h33 before h12
        // root = 0x1da9bc4b073bf7f62d7dfda4b613d7c8e91ecafe52fd4f03ac26d47e72487852

        // --- FIX: Recalculate Proofs ---

        // Proof for (0, user1, 100e18) -> node2 (leaf1)
        proof1 = new bytes32[](2);
        proof1[0] = node1; // 0x4f15...
        proof1[1] = h33; // 0x618e...

        // Proof for (1, user2, 200e18) -> node3 (leaf2)
        proof2 = new bytes32[](2);
        proof2[0] = node3; // 0x6f31... (its sibling is itself)
        proof2[1] = h12; // 0xc877...

        // Proof for (2, user3, 300e18) -> node1 (leaf3)
        proof3 = new bytes32[](2);
        proof3[0] = node2; // 0x608e...
        proof3[1] = h33; // 0x618e...

        // 3. Deploy the Airdrop contract
        airdrop = new MerkleAirdrop(root, address(vault));

        // 4. Authorize the Airdrop contract in the Vault
        vm.prank(admin);
        vault.setAirdropContract(address(airdrop));
    }

    /* -------------------------------------------------------------------------- */
    /* Happy Paths                                                                */
    /* -------------------------------------------------------------------------- */

    function test_Claim_Success_User1() public {
        vm.startPrank(user1);
        airdrop.claim(0, amount1, proof1);
        assertEq(token.balanceOf(user1), amount1);
        assertTrue(airdrop.isClaimed(0));
        vm.stopPrank();
    }

    function test_Claim_Success_User2() public {
        vm.startPrank(user2);
        airdrop.claim(1, amount2, proof2);
        assertEq(token.balanceOf(user2), amount2);
        assertTrue(airdrop.isClaimed(1));
        vm.stopPrank();
    }

    function test_Claim_Success_User3() public {
        vm.startPrank(user3);
        airdrop.claim(2, amount3, proof3);
        assertEq(token.balanceOf(user3), amount3);
        assertTrue(airdrop.isClaimed(2));
        vm.stopPrank();
    }

    function test_Claim_EmitEvent() public {
        // This SETS the expectation: 2 topics (index, account), 1 data (amount)
        vm.expectEmit(true, true, false, true, address(airdrop));
        emit MerkleAirdrop.Claimed(0, user1, amount1);

        // This TRIGGERS the event
        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);
    }

    /* -------------------------------------------------------------------------- */
    /* Revert Paths                                */
    /* -------------------------------------------------------------------------- */

    function test_Revert_DoubleClaim() public {
        // First claim (success)
        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);
        assertEq(token.balanceOf(user1), amount1);

        // Second claim (revert)
        vm.expectRevert(BitmapState.AlreadyClaimed.selector);
        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);
    }

    function test_Revert_InvalidProof() public {
        bytes32[] memory invalidProof = new bytes32[](2);
        invalidProof[0] = bytes32(0xdeadbeef);
        invalidProof[1] = bytes32(0xdeadbeef);

        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user1);
        airdrop.claim(0, amount1, invalidProof);
    }

    function test_Revert_WrongClaimer() public {
        // User 2 tries to claim User 1's drop
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user2);
        airdrop.claim(0, amount1, proof1);
    }

    function test_Revert_WrongAmount() public {
        // User 1 tries to claim with wrong amount
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user1);
        airdrop.claim(0, 999 * 1e18, proof1);
    }

    function test_Revert_WrongIndex() public {
        // User 1 tries to claim with wrong index
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user1);
        airdrop.claim(99, amount1, proof1);
    }

    /* -------------------------------------------------------------------------- */
    /* Gas Snapshots                               */
    /* -------------------------------------------------------------------------- */

    function test_Gas_Claim_FirstInSlot() public {
        // Warm up the storage slot
        // assertEq(airdrop.isClaimed(0), false);

        vm.startPrank(user1);
        airdrop.claim(0, amount1, proof1);
        vm.stopPrank();
    }

    function test_Gas_Claim_SecondInSlot() public {
        // User 1 (index 0) claims first, warming up slot 0
        vm.startPrank(user1);
        airdrop.claim(0, amount1, proof1);
        vm.stopPrank();

        // User 2 (index 1) claims second, hitting a warm slot
        vm.startPrank(user2);
        airdrop.claim(1, amount2, proof2);
        vm.stopPrank();
    }

    /* -------------------------------------------------------------------------- */
    /* Helper Functions                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Helper to mimic OpenZeppelin's internal Merkle proof hashing.
     */
    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        if (a < b) {
            return keccak256(abi.encodePacked(a, b));
        } else {
            return keCEccak256(abi.encodePacked(b, a));
        }
    }
}