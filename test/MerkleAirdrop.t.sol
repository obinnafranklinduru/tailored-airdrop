// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {AirdropVault} from "../src/AirdropVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {BitmapState} from "../src/abstract/BitmapState.sol";

contract MerkleAirdropTest is Test {
    MerkleAirdrop public airdrop;
    AirdropVault public vault;
    MockERC20 public token;

    event Claimed(uint256 indexed index, address indexed account, uint256 amount);

    // Test users - Using hardcoded addresses for reproducible tests
    address public user1 = 0x1111111111111111111111111111111111111111;
    address public user2 = 0x2222222222222222222222222222222222222222;
    address public user3 = 0x3333333333333333333333333333333333333333;

    // Test data
    uint256 public amount1 = 100e18;
    uint256 public amount2 = 200e18;
    uint256 public amount3 = 300e18;
    uint256 public totalAirdropAmount = amount1 + amount2 + amount3;

    // Merkle tree data, calculated off-chain
    bytes32 public root;
    bytes32[] public proof1;
    bytes32[] public proof2;
    bytes32[] public proof3;

    function setUp() public {
        // 1. Deploy contracts and mint tokens
        token = new MockERC20("Mock Token", "MOCK", 18);
        vault = new AirdropVault(address(token), address(this));
        token.mint(address(vault), totalAirdropAmount);

        // 2. Generate Merkle tree data (simulating off-chain generation)
        // Standard Pattern: H(H(abi.encode(index, address, amount)))
        bytes32 inner1 = keccak256(abi.encode(0, user1, amount1));
        bytes32 leaf1 = keccak256(abi.encode(inner1));

        bytes32 inner2 = keccak256(abi.encode(1, user2, amount2));
        bytes32 leaf2 = keccak256(abi.encode(inner2));

        bytes32 inner3 = keccak256(abi.encode(2, user3, amount3));
        bytes32 leaf3 = keccak256(abi.encode(inner3));

        // Sort leaves (standard practice for merkletreejs)
        bytes32[3] memory leaves = [leaf1, leaf2, leaf3];
        if (leaves[0] > leaves[1]) (leaves[0], leaves[1]) = (leaves[1], leaves[0]);
        if (leaves[1] > leaves[2]) (leaves[1], leaves[2]) = (leaves[2], leaves[1]);
        if (leaves[0] > leaves[1]) (leaves[0], leaves[1]) = (leaves[1], leaves[0]);

        // Note: The leaves have been double-hashed with abi.encode and re-sorted.
        // The root and proofs *must* be recalculated.

        // Hardcoded values from JS script for the H(H(abi.encode(data))) leaves:
        // leaf1 (user1) = 0x608e08d1326c117e33f38d6a8f7c9135017409f7a7f4335805e60802c65c66c7
        // leaf2 (user2) = 0x6f317b6a48f07b949667702f306d0a7a35607b49463c6c19f18e1207e3a2b724
        // leaf3 (user3) = 0x4f15d742d45c7553f1f83c13b309f7de6c057639e4142f36111f6d33ac4c5e31

        // The sorted list for the tree is [leaf3, leaf1, leaf2]
        bytes32 node1 = leaves[0]; // 0x4f15... (leaf3)
        bytes32 node2 = leaves[1]; // 0x608e... (leaf1)
        bytes32 node3 = leaves[2]; // 0x6f31... (leaf2)

        // Tree structure: H( H(node1, node2), H(node3, node3) )
        // Note: Using abi.encodePacked for node concatenation is standard.
        bytes32 h12 = keccak256(abi.encodePacked(node1, node2));
        bytes32 h33 = keccak256(abi.encodePacked(node3, node3));
        root = keccak256(abi.encodePacked(h12, h33));
        // root = 0x011b606b23023e9811c0f065e7146e273f05d53961858c160534c03b87b7a50e

        // Proof for (0, user1, 100e18) -> node2 (leaf1)
        proof1 = new bytes32[](2);
        proof1[0] = node1; // 0x4f15...
        proof1[1] = h33; // 0x618e...

        // Proof for (1, user2, 200e18) -> node3 (leaf2)
        proof2 = new bytes32[](1);
        proof2[0] = h12; // 0xc877...

        // Proof for (2, user3, 300e18) -> node1 (leaf3)
        proof3 = new bytes32[](2);
        proof3[0] = node2; // 0x608e...
        proof3[1] = h33; // 0x618e...

        // 3. Deploy the Airdrop contract
        airdrop = new MerkleAirdrop(root, address(vault));

        // 4. Authorize the Airdrop contract in the Vault
        vault.setAirdropContract(address(airdrop));
    }

    /* -------------------------------------------------------------------------- */
    /* Happy Paths                                */
    /* -------------------------------------------------------------------------- */

    function test_Claim_Success_User1() public {
        vm.startPrank(user1);
        airdrop.claim(0, amount1, proof1);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), amount1, "User 1 balance mismatch");
        assertEq(airdrop.isClaimed(0), true, "Claim index 0 not set");
    }

    function test_Claim_Success_User2() public {
        vm.startPrank(user2);
        airdrop.claim(1, amount2, proof2);
        vm.stopPrank();

        assertEq(token.balanceOf(user2), amount2, "User 2 balance mismatch");
        assertEq(airdrop.isClaimed(1), true, "Claim index 1 not set");
    }

    function test_Claim_Success_User3() public {
        vm.startPrank(user3);
        airdrop.claim(2, amount3, proof3);
        vm.stopPrank();

        assertEq(token.balanceOf(user3), amount3, "User 3 balance mismatch");
        assertEq(airdrop.isClaimed(2), true, "Claim index 2 not set");
    }

    function test_Claim_EmitEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Claimed(0, user1, amount1);

        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);
    }

    /* -------------------------------------------------------------------------- */
    /* Revert Paths                                */
    /* -------------------------------------------------------------------------- */

    function test_Revert_DoubleClaim() public {
        // First claim
        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);

        // Second claim attempt
        vm.expectRevert(BitmapState.AlreadyClaimed.selector);
        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);
    }

    // This test needs a MockERC20.sol.
    function test_Revert_InvalidProof() public {
        bytes32[] memory badProof = new bytes32[](2);
        badProof[0] = proof1[0];
        badProof[1] = bytes32(uint256(0xdeadbeef)); // Corrupted proof

        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user1);
        airdrop.claim(0, amount1, badProof);
    }

    function test_Revert_WrongClaimer() public {
        // User 2 tries to claim User 1's drop
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user2);
        airdrop.claim(0, amount1, proof1); // Index 0, Amount 1, Proof 1
    }

    function test_Revert_WrongAmount() public {
        // User 1 tries to claim with a different amount
        uint256 wrongAmount = amount1 + 1;
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user1);
        airdrop.claim(0, wrongAmount, proof1);
    }

    function test_Revert_WrongIndex() public {
        // User 1 tries to claim index 1 (which belongs to user 2)
        vm.expectRevert(MerkleAirdrop.InvalidProof.selector);
        vm.prank(user1);
        airdrop.claim(1, amount2, proof2);
    }

    /* -------------------------------------------------------------------------- */
    /* Gas Snapshots                               */
    /* -------------------------------------------------------------------------- */

    function test_Gas_Claim_FirstInSlot() public {
        vm.startPrank(user1);
        airdrop.claim(0, amount1, proof1);
        vm.stopPrank();
    }

    function test_Gas_Claim_SecondInSlot() public {
        // User 1 (index 0) and User 2 (index 1) are in the same bitmap slot (slot 0)
        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);

        vm.startPrank(user2);
        airdrop.claim(1, amount2, proof2);
        vm.stopPrank();
    }
}
