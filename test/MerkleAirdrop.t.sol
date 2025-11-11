// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Merkle} from "murky/Merkle.sol";

// Contract Under Test
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {IAirdrop} from "../src/interfaces/IAirdrop.sol";

// Mocks
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC721Mock} from "./mocks/token/ERC721Mock.sol";

/**
 * @title MerkleAirdropTest
 * @author BinnaDev
 * @notice Test suite for the MerkleAirdrop contract.
 * @dev This test uses `murky` (dmfxyz/murky)
 * for reliable and clean Merkle tree generation, aligning with our
 * philosophy of using battle-tested tools.
 */
contract MerkleAirdropTest is Test {
    // --- Contract & Mocks ---
    MerkleAirdrop public airdrop;
    ERC20Mock public erc20;
    ERC721Mock public erc721;

    // --- Test Users ---
    address public owner = makeAddr("owner");
    address public userA = makeAddr("userA");
    address public userB = makeAddr("userB");
    address public userC = makeAddr("userC");
    address public attacker = makeAddr("attacker");

    // --- Merkle Tree Data ---
    // Use the correct Merkle contract from Murky
    Merkle internal merkleTree;
    bytes32 public merkleRoot;

    // We store the proofs for easy access in tests.
    bytes32[] public proofA; // Proof for leaf 0
    bytes32[] public proofB; // Proof for leaf 1
    bytes32[] public proofC; // Proof for leaf 2

    // --- Allocation Data ---
    // User A (index 0): 100 ERC20
    uint256 public constant INDEX_A = 0;
    uint256 public constant AMOUNT_A = 100e18;
    uint256 public constant TOKEN_ID_A = 0; // 0 for ERC20

    // User B (index 1): 1 ERC721 (ID 42)
    uint256 public constant INDEX_B = 1;
    uint256 public constant AMOUNT_B = 1; // 1 for ERC721
    uint256 public constant TOKEN_ID_B = 42;

    // User C (index 2): 50 ERC20
    uint256 public constant INDEX_C = 2;
    uint256 public constant AMOUNT_C = 50e18;
    uint256 public constant TOKEN_ID_C = 0; // 0 for ERC20

    /**
     * @notice Mirrors the on-chain leaf hashing (H(H(data))).
     * @dev MUST match MerkleAirdrop._hashLeaf exactly.
     */
    function _hashLeaf(uint256 index, address claimant, address tokenContract, uint256 tokenId, uint256 amount)
        internal
        pure
        returns (bytes32)
    {
        bytes32 innerHash = keccak256(abi.encode(index, claimant, tokenContract, tokenId, amount));

        return keccak256(abi.encode(innerHash));
    }

    /**
     * @notice Sets up the test environment, including the Merkle tree.
     */
    function setUp() public {
        vm.startPrank(owner);

        // 1. Deploy Mock Tokens
        erc20 = new ERC20Mock();
        erc721 = new ERC721Mock("TestNFT", "TNFT");

        // 2. Construct Merkle Tree using Murky
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = _hashLeaf(INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A);
        leaves[1] = _hashLeaf(INDEX_B, userB, address(erc721), TOKEN_ID_B, AMOUNT_B);
        leaves[2] = _hashLeaf(INDEX_C, userC, address(erc20), TOKEN_ID_C, AMOUNT_C);

        merkleTree = new Merkle();
        merkleRoot = merkleTree.getRoot(leaves);

        proofA = merkleTree.getProof(leaves, 0);
        proofB = merkleTree.getProof(leaves, 1);
        proofC = merkleTree.getProof(leaves, 2);

        // We pass address(0) for the trusted forwarder in this test.
        airdrop = new MerkleAirdrop(merkleRoot, address(0));

        //  Fund the Airdrop Contract
        erc20.mint(address(airdrop), 1_000_000e18);
        erc721.mint(address(airdrop), TOKEN_ID_B); // Mint NFT ID 42

        vm.stopPrank();
    }

    // --- Test: Happy Paths ---

    function test_claim_ERC20_succeeds() public {
        // Check initial state
        assertEq(erc20.balanceOf(userA), 0);
        assertEq(airdrop.isClaimed(INDEX_A), false);

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit IAirdrop.Claimed("Merkle", INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A);

        // Prank as User A and claim
        vm.prank(userA);
        airdrop.claim(INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A, proofA);

        // Check final state
        assertEq(erc20.balanceOf(userA), AMOUNT_A);
        assertEq(airdrop.isClaimed(INDEX_A), true);
    }

    function test_claim_ERC721_succeeds() public {
        // Check initial state
        assertEq(erc721.ownerOf(TOKEN_ID_B), address(airdrop));
        assertEq(airdrop.isClaimed(INDEX_B), false);

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit IAirdrop.Claimed("Merkle", INDEX_B, userB, address(erc721), TOKEN_ID_B, AMOUNT_B);

        // Prank as User B and claim
        vm.prank(userB);
        airdrop.claim(INDEX_B, userB, address(erc721), TOKEN_ID_B, AMOUNT_B, proofB);

        // Check final state
        assertEq(erc721.ownerOf(TOKEN_ID_B), userB);
        assertEq(airdrop.isClaimed(INDEX_B), true);
    }

    // --- Test: Failure Cases (Security) ---

    function test_fail_doubleClaim() public {
        // 1. First claim (success)
        vm.prank(userA);
        airdrop.claim(INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A, proofA);

        // 2. Second claim (fail)
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(IAirdrop.MerkleAirdrop_AlreadyClaimed.selector, INDEX_A));
        airdrop.claim(INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A, proofA);
    }

    function test_fail_invalidProof() public {
        // User A tries to claim with User B's proof
        vm.prank(userA);
        vm.expectRevert(IAirdrop.MerkleAirdrop_InvalidProof.selector);
        airdrop.claim(
            INDEX_A,
            userA,
            address(erc20),
            TOKEN_ID_A,
            AMOUNT_A,
            proofB // <-- Invalid proof
        );
    }

    function test_fail_tamperedLeafData() public {
        // User A tries to claim 1,000 tokens instead of 100
        // The proof is correct, but the leaf hash will be wrong
        uint256 tamperedAmount = 1000e18;

        vm.prank(userA);
        vm.expectRevert(IAirdrop.MerkleAirdrop_InvalidProof.selector);
        airdrop.claim(
            INDEX_A,
            userA,
            address(erc20),
            TOKEN_ID_A,
            tamperedAmount, // <-- Tampered data
            proofA
        );
    }

    function test_fail_notClaimant() public {
        // Attacker (pranked) tries to claim User A's allocation
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAirdrop.MerkleAirdrop_NotClaimant.selector,
                userA, // expected claimant
                attacker // sender
            )
        );
        airdrop.claim(
            INDEX_A,
            userA, // claimant in leaf
            address(erc20),
            TOKEN_ID_A,
            AMOUNT_A,
            proofA
        );
    }

    function test_fail_proofTooLong() public {
        // Create a proof longer than MAX_PROOF_DEPTH (32)
        bytes32[] memory longProof = new bytes32[](33);
        // (Proof content doesn't matter, just length)

        vm.prank(userA);
        vm.expectRevert();
        airdrop.claim(INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A, longProof);
    }

    function test_fail_invalidAllocation_zero() public {
        // For now, we will test the revert inside `claim`:
        // We create a new tree with a 0-amount leaf
        bytes32 zeroLeaf = _hashLeaf(0, userA, address(erc20), 0, 0);

        // Use Murky to create a 1-leaf tree
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = zeroLeaf;
        leaves[1] = zeroLeaf;

        // Use correct Murky API
        Merkle zeroMerkle = new Merkle();
        bytes32 zeroRoot = zeroMerkle.getRoot(leaves);
        bytes32[] memory zeroProof = zeroMerkle.getProof(leaves, 0);

        MerkleAirdrop zeroAirdrop = new MerkleAirdrop(zeroRoot, address(0));
        erc20.mint(address(zeroAirdrop), 1e18);

        vm.prank(userA);
        vm.expectRevert(IAirdrop.Airdrop_InvalidAllocation.selector);
        zeroAirdrop.claim(0, userA, address(erc20), 0, 0, zeroProof);
    }

    // --- Test: Gas Snapshots ---

    function test_gas_claim_ERC20_cold() public {
        // This is the first claim in the bitmap slot 0
        vm.prank(userA);
        vm.recordLogs();
        airdrop.claim(INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A, proofA);
        // (Gas report will show this)
    }

    function test_gas_claim_ERC20_warm() public {
        // Claim A (cold)
        vm.prank(userA);
        airdrop.claim(INDEX_A, userA, address(erc20), TOKEN_ID_A, AMOUNT_A, proofA);

        // Claim C (warm, as it's in the same bitmap slot < 256)
        vm.prank(userC);
        vm.recordLogs();
        airdrop.claim(INDEX_C, userC, address(erc20), TOKEN_ID_C, AMOUNT_C, proofC);
    }

    // TODO: test_claim_ERC2771_succeeds()
    // This requires a mock forwarder setup.
    // We will add this in Milestone 3.
}
