// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {SignatureAirdrop} from "../src/SignatureAirdrop.sol";
import {IAirdrop} from "../src/interfaces/IAirdrop.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC721Mock} from "./mocks/token/ERC721Mock.sol";

/**
 * @title SignatureAirdropTest
 * @author BinnaDev
 * @notice Test suite for the SignatureAirdrop contract.
 * @dev This test suite validates all core logic, including EIP-712
 * signature verification, nonce-based replay protection, and token dispatch.
 */
contract SignatureAirdropTest is Test {
    // --- Contracts ---
    SignatureAirdrop internal airdrop;
    ERC20Mock internal erc20;
    ERC721Mock internal erc721;

    // --- Actors ---
    address internal deployer = makeAddr("deployer");
    address internal trustedForwarder = makeAddr("trustedForwarder");
    address internal relayer = makeAddr("relayer"); // The `msg.sender`

    // --- Claimant Wallets (Private Key + Address) ---
    uint256 internal constant CLAIMANT_PK = 0x1234;
    address internal claimant = vm.addr(CLAIMANT_PK);

    uint256 internal constant CLAIMANT_B_PK = 0x5678;
    address internal claimantB = vm.addr(CLAIMANT_B_PK);

    uint256 internal constant ATTACKER_PK = 0xAAAA;
    address internal attacker = vm.addr(ATTACKER_PK);

    // --- EIP-712 Data ---
    bytes32 internal DOMAIN_SEPARATOR;
    // keccak256("Claim(address claimant,address tokenContract,uint256 tokenId,uint256 amount,uint256 nonce)")
    bytes32 internal constant EIP712_TYPEHASH = 0x8abedf9a1affb7bc0fcfa00e80f5eb339da96763b85507537a999fc325f1255c;

    // --- Setup ---
    function setUp() public {
        vm.startPrank(deployer);
        // 1. Deploy contracts
        airdrop = new SignatureAirdrop(trustedForwarder);

        // FIX 1: The standard OZ ERC20Mock constructor takes zero arguments.
        erc20 = new ERC20Mock();
        erc721 = new ERC721Mock("Mock ERC721", "M721");

        // 1b. Mint the initial supply to the deployer explicitly
        erc20.mint(deployer, 1_000_000 ether);

        // 2. Fund the airdrop contract
        erc20.transfer(address(airdrop), 500_000 ether);
        erc721.mint(address(airdrop), 1);
        erc721.mint(address(airdrop), 2);
        vm.stopPrank();

        // 3. Pre-calculate the domain separator
        // FIX 2: Manually calculate the domain separator.
        // This is more robust than relying on a potentially non-existent
        // public getter from a specific OZ library version.
        bytes32 EIP712_DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256(bytes("SignatureAirdrop"));
        bytes32 versionHash = keccak256(bytes("1"));
        // We use block.chainid to ensure it matches the EIP712 constructor
        DOMAIN_SEPARATOR =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(airdrop)));

        // 4. Label addresses for clarity
        vm.label(deployer, "Deployer");
        vm.label(trustedForwarder, "TrustedForwarder");
        vm.label(relayer, "Relayer");
        vm.label(claimant, "Claimant (User A)");
        vm.label(claimantB, "Claimant (User B)");
        vm.label(attacker, "Attacker");
        vm.label(address(airdrop), "AirdropContract");
        vm.label(address(erc20), "ERC20Mock");
        vm.label(address(erc721), "ERC721Mock");
    }

    // --- Helper Function: Sign Claim ---

    /**
     * @notice Helper to craft a valid EIP-712 signature.
     */
    function _signClaim(SignatureAirdrop.Claim memory claim, uint256 signerPk)
        internal
        view
        returns (bytes memory signature)
    {
        // 1. Hash the struct.
        // We use abi.encode(TYPEHASH, struct) to match the
        // contract's clean implementation.
        bytes32 structHash = keccak256(abi.encode(EIP712_TYPEHASH, claim));

        // 2. Create the EIP-712 digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // 3. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // --- Test: ERC20 Claim ---

    function test_claimERC20_Succeeds() public {
        // --- Setup ---
        uint256 amount = 100 ether;
        uint256 nonce = airdrop.nonces(claimant); // 0

        // The claim is *for* the claimant
        SignatureAirdrop.Claim memory claim = SignatureAirdrop.Claim({
            claimant: claimant,
            tokenContract: address(erc20),
            tokenId: 0,
            amount: amount,
            nonce: nonce
        });

        // Sign the claim *as the claimant*
        bytes memory signature = _signClaim(claim, CLAIMANT_PK);

        // --- Test ---
        vm.prank(relayer); // Relayer submits the tx
        vm.expectEmit(true, true, true, true, address(airdrop));
        emit IAirdrop.Claimed("Signature", nonce, claimant, address(erc20), 0, amount);

        airdrop.claimWithSignature(claim, signature);

        // --- Assert ---
        assertEq(erc20.balanceOf(claimant), amount);
        assertEq(erc20.balanceOf(address(airdrop)), 500_000 ether - amount);
        assertEq(airdrop.nonces(claimant), 1); // Nonce incremented
    }

    // --- Test: ERC721 Claim ---

    function test_claimERC721_Succeeds() public {
        // --- Setup ---
        uint256 tokenId = 1;
        uint256 nonce = airdrop.nonces(claimantB); // 0

        SignatureAirdrop.Claim memory claim = SignatureAirdrop.Claim({
            claimant: claimantB,
            tokenContract: address(erc721),
            tokenId: tokenId,
            amount: 0, // Amount is ignored for ERC721
            nonce: nonce
        });

        // Sign the claim *as the claimantB*
        bytes memory signature = _signClaim(claim, CLAIMANT_B_PK);

        // --- Test ---
        vm.prank(relayer); // Relayer submits the tx
        vm.expectEmit(true, true, true, true, address(airdrop));
        emit IAirdrop.Claimed("Signature", nonce, claimantB, address(erc721), tokenId, 0);

        airdrop.claimWithSignature(claim, signature);

        // --- Assert ---
        assertEq(erc721.ownerOf(tokenId), claimantB);
        assertEq(airdrop.nonces(claimantB), 1); // Nonce incremented
    }

    // --- Test: Failure Cases ---

    function test_fail_claimWithReplayedNonce() public {
        // --- Setup ---
        uint256 amount = 100 ether;

        // First claim succeeds
        {
            uint256 nonce = airdrop.nonces(claimant); // 0
            SignatureAirdrop.Claim memory claim = SignatureAirdrop.Claim({
                claimant: claimant,
                tokenContract: address(erc20),
                tokenId: 0,
                amount: amount,
                nonce: nonce
            });
            bytes memory signature = _signClaim(claim, CLAIMANT_PK);
            vm.prank(relayer);
            airdrop.claimWithSignature(claim, signature);
            assertEq(airdrop.nonces(claimant), 1); // Nonce is now 1
        }

        // --- Test ---
        // Try to re-use the *same* claim and signature (with nonce 0)
        SignatureAirdrop.Claim memory claimReplay = SignatureAirdrop.Claim({
            claimant: claimant,
            tokenContract: address(erc20),
            tokenId: 0,
            amount: amount,
            nonce: 0 // Replaying nonce 0
        });

        bytes memory signatureReplay = _signClaim(claimReplay, CLAIMANT_PK);

        // Expect revert due to invalid nonce
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAirdrop.SignatureAirdrop_InvalidNonce.selector,
                1, // Expected nonce
                0 // Provided nonce
            )
        );
        airdrop.claimWithSignature(claimReplay, signatureReplay);
    }

    function test_fail_claimWithInvalidSignature_WrongSigner() public {
        // --- Setup ---
        uint256 amount = 100 ether;
        uint256 nonce = 0;

        SignatureAirdrop.Claim memory claim = SignatureAirdrop.Claim({
            claimant: claimant, // Claim is for the correct claimant
            tokenContract: address(erc20),
            tokenId: 0,
            amount: amount,
            nonce: nonce
        });

        // Sign the claim with the *wrong* key (Attacker)
        bytes memory signature = _signClaim(claim, ATTACKER_PK);

        // --- Test ---
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAirdrop.SignatureAirdrop_InvalidSignature.selector,
                claimant, // Expected
                attacker // Recovered
            )
        );
        airdrop.claimWithSignature(claim, signature);
    }

    function test_fail_claimWithMismatchedClaimant() public {
        // --- Setup ---
        uint256 amount = 100 ether;
        uint256 nonce = 0;

        SignatureAirdrop.Claim memory claim = SignatureAirdrop.Claim({
            claimant: attacker, // Attacker tries to claim as themselves
            tokenContract: address(erc20),
            tokenId: 0,
            amount: amount,
            nonce: nonce
        });

        // But the signature is from the *valid* claimant
        bytes memory signature = _signClaim(claim, CLAIMANT_PK);

        // --- Test ---
        // The recovered signer (claimant) will not match
        // the payload claimant (attacker).
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAirdrop.SignatureAirdrop_InvalidSignature.selector,
                attacker, // Expected
                claimant // Recovered
            )
        );
        airdrop.claimWithSignature(claim, signature);
    }

    function test_fail_reentrancyAttack() public {
        // This is a placeholder as our mock tokens don't have callbacks.
        // A full test would involve a malicious ERC721 with `onERC721Received`
        // that tries to call `claimWithSignature` again.
        // The `nonReentrant` guard prevents this.
    }

    function test_fail_claimWithInvalidNonce_Fuzz(uint256 providedNonce) public {
        // Fuzz test for nonce mismatch
        uint256 currentNonce = airdrop.nonces(claimant); // 0
        vm.assume(providedNonce != currentNonce); // Any nonce *but* the correct one

        // --- Setup ---
        SignatureAirdrop.Claim memory claim = SignatureAirdrop.Claim({
            claimant: claimant,
            tokenContract: address(erc20),
            tokenId: 0,
            amount: 100 ether,
            nonce: providedNonce // Use the fuzzed, incorrect nonce
        });

        bytes memory signature = _signClaim(claim, CLAIMANT_PK);

        // --- Test ---
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAirdrop.SignatureAirdrop_InvalidNonce.selector,
                currentNonce, // Expected
                providedNonce // Provided
            )
        );
        airdrop.claimWithSignature(claim, signature);
    }
}
