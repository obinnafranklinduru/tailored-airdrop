// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";

// Contracts Under Test
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {SignatureAirdrop} from "../src/SignatureAirdrop.sol";
import {IAirdrop} from "../src/interfaces/IAirdrop.sol";

// Mocks
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC721Mock} from "./mocks/token/ERC721Mock.sol";
import {ERC2771ForwarderMock} from "./mocks/metatx/ERC2771ForwarderMock.sol";

/**
 * @title GaslessTest
 * @author BinnaDev
 * @notice Test suite for ERC-2771 (Gasless) integration.
 * @dev This test proves that the _msgSender() logic in both airdrop
 * contracts correctly identifies the original user when called
 * via a trusted forwarder.
 */
contract GaslessTest is Test {
    // --- Contracts ---
    MerkleAirdrop internal merkleAirdrop;
    SignatureAirdrop internal sigAirdrop;
    ERC20Mock internal erc20;
    ERC721Mock internal erc721;
    ERC2771ForwarderMock internal forwarder;
    Merkle internal merkle;

    // --- Actors ---
    address internal deployer = makeAddr("deployer");
    address internal relayer = makeAddr("relayer"); // Pays gas

    // --- User Wallets (with Private Keys) ---
    uint256 internal constant CLAIMANT_A_PK = 0x1111;
    address internal claimantA = vm.addr(CLAIMANT_A_PK); // For Merkle

    uint256 internal constant CLAIMANT_B_PK = 0x2222;
    address internal claimantB = vm.addr(CLAIMANT_B_PK); // For Signature

    uint256 internal constant ATTACKER_PK = 0xAAAA;
    address internal attacker = vm.addr(ATTACKER_PK); // Signs meta-tx

    // --- Merkle Data ---
    bytes32 internal merkleRoot;
    bytes32[] internal proofForClaimantA;
    uint256 internal constant CLAIM_INDEX_A = 0;
    uint256 internal constant AMOUNT_A = 100 ether;

    // --- Signature Data ---
    bytes32 internal DOMAIN_SEPARATOR;
    // keccak256("Claim(address claimant,address tokenContract,uint256 tokenId,uint256 amount,uint256 nonce)")
    bytes32 internal constant EIP712_TYPEHASH = 0x8abedf9a1affb7bc0fcfa00e80f5eb339da96763b85507537a999fc325f1255c;

    function setUp() public {
        vm.startPrank(deployer);
        // 1. Deploy Mocks
        forwarder = new ERC2771ForwarderMock();
        erc20 = new ERC20Mock();
        erc721 = new ERC721Mock("Mock NFT", "M721");
        merkle = new Merkle();

        // 2. Setup MerkleAirdrop
        // Build a simple 1-leaf tree
        bytes32 leafA = _hashLeaf(CLAIM_INDEX_A, claimantA, address(erc20), 0, AMOUNT_A);
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = leafA;
        leaves[1] = leafA;
        merkleRoot = merkle.getRoot(leaves);
        proofForClaimantA = merkle.getProof(leaves, 0);

        // Deploy MerkleAirdrop, *trusting the forwarder*
        merkleAirdrop = new MerkleAirdrop(merkleRoot, address(forwarder));

        // 3. Setup SignatureAirdrop
        // Deploy SignatureAirdrop, *trusting the forwarder*
        sigAirdrop = new SignatureAirdrop(address(forwarder));

        // Get its domain separator
        bytes32 EIP712_DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256(bytes("SignatureAirdrop"));
        bytes32 versionHash = keccak256(bytes("1"));
        DOMAIN_SEPARATOR =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(sigAirdrop)));

        // 4. Fund contracts
        erc20.mint(deployer, 1_000_000 ether);
        erc20.transfer(address(merkleAirdrop), 500_000 ether);
        erc20.transfer(address(sigAirdrop), 500_000 ether);
        vm.stopPrank();

        // 5. Label addresses
        vm.label(claimantA, "Claimant A (Merkle)");
        vm.label(claimantB, "Claimant B (Signature)");
        vm.label(relayer, "Relayer (pays gas)");
        vm.label(address(forwarder), "Trusted Forwarder");
    }

    // --- MerkleAirdrop Gasless Tests ---

    /**
     * @notice Tests a successful gasless claim for MerkleAirdrop.
     * The `relayer` submits the tx, but the `_msgSender()` becomes
     * `claimantA`, passing the `_msgSender() == claimant` check.
     */
    function test_Gasless_MerkleAirdrop_Succeeds() public {
        // 1. Prepare calldata for MerkleAirdrop.claim()
        bytes memory data = abi.encodeWithSelector(
            MerkleAirdrop.claim.selector, CLAIM_INDEX_A, claimantA, address(erc20), 0, AMOUNT_A, proofForClaimantA
        );

        // 2. Append the *original sender's* address.
        // This is how ERC-2771 works.
        bytes memory dataWithSender = abi.encodePacked(data, claimantA);

        // 3. Relayer pays gas and sends to the *Forwarder*
        vm.prank(relayer);
        (bool success,) = address(forwarder).call(
            abi.encodeWithSelector(ERC2771ForwarderMock.execute.selector, address(merkleAirdrop), dataWithSender)
        );
        assertTrue(success, "Forwarder call failed");

        // 4. Check state
        assertEq(erc20.balanceOf(claimantA), AMOUNT_A);
        assertTrue(merkleAirdrop.isClaimed(CLAIM_INDEX_A));
    }

    /**
     * @notice Tests that an attacker cannot claim someone else's
     * Merkle drop, even through a relayer.
     * The `_msgSender()` becomes `attacker`, failing the
     * `_msgSender() == claimant` check.
     */
    function test_Gasless_MerkleAirdrop_Fails_if_NotClaimant() public {
        // 1. Prepare calldata for MerkleAirdrop.claim()
        // The claim data is valid *for claimantA*
        bytes memory data = abi.encodeWithSelector(
            MerkleAirdrop.claim.selector, CLAIM_INDEX_A, claimantA, address(erc20), 0, AMOUNT_A, proofForClaimantA
        );

        // 2. Attacker appends *their own* address, trying to
        // become the _msgSender()
        bytes memory dataWithSender = abi.encodePacked(data, attacker);

        // 3. Relayer pays gas and sends to the Forwarder
        vm.prank(relayer);

        // Expect revert from MerkleAirdrop
        vm.expectRevert(
            abi.encodeWithSelector(
                IAirdrop.MerkleAirdrop_NotClaimant.selector,
                claimantA, // claimant
                attacker // _msgSender()
            )
        );
        forwarder.execute(address(merkleAirdrop), dataWithSender);
    }

    // --- SignatureAirdrop Gasless Tests ---

    /**
     * @notice Tests a successful gasless claim for SignatureAirdrop.
     * The relayer submits the tx, but the logic inside
     * `claimWithSignature` is based on the *signed payload*,
     * not the `_msgSender()`. This test proves compatibility.
     */
    function test_Gasless_SignatureAirdrop_Succeeds() public {
        // 1. Prepare signature
        uint256 nonce = 0;
        uint256 amount = 50 ether;
        SignatureAirdrop.Claim memory claim = SignatureAirdrop.Claim({
            claimant: claimantB,
            tokenContract: address(erc20),
            tokenId: 0,
            amount: amount,
            nonce: nonce
        });
        bytes memory signature = _signClaim(claim, CLAIMANT_B_PK);

        // 2. Prepare calldata for SignatureAirdrop.claimWithSignature()
        bytes memory data = abi.encodeWithSelector(SignatureAirdrop.claimWithSignature.selector, claim, signature);

        // 3. Append the *claimant's* address.
        bytes memory dataWithSender = abi.encodePacked(data, claimantB);

        // 4. Relayer pays gas and sends to the Forwarder
        vm.prank(relayer);
        (bool success,) = address(forwarder).call(
            abi.encodeWithSelector(ERC2771ForwarderMock.execute.selector, address(sigAirdrop), dataWithSender)
        );
        assertTrue(success, "Forwarder call failed");

        // 5. Check state
        assertEq(erc20.balanceOf(claimantB), amount);
        assertEq(sigAirdrop.nonces(claimantB), 1);
    }

    // --- Internal Helpers ---

    function _hashLeaf(uint256 index, address claimant, address tokenContract, uint256 tokenId, uint256 amount)
        internal
        pure
        returns (bytes32)
    {
        bytes32 innerHash = keccak256(abi.encode(index, claimant, tokenContract, tokenId, amount));
        return keccak256(abi.encodePacked(innerHash));
    }

    function _signClaim(SignatureAirdrop.Claim memory claim, uint256 signerPk)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 structHash = keccak256(abi.encode(EIP712_TYPEHASH, claim));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
