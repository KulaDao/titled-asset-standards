// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DocumentBoundERC721}   from "../src/reference/DocumentBoundERC721.sol";
import {DocumentBundleAnchor}  from "../src/reference/DocumentBundleAnchor.sol";
import {IDocumentBound}        from "../src/interfaces/IDocumentBound.sol";

contract DocumentBoundERC721Test is Test {
    DocumentBundleAnchor registry;
    DocumentBoundERC721  token;

    address admin    = address(0xA0);
    address anchorer = address(0xA1);
    address alice    = address(0xA2);
    address bob      = address(0xA3);

    bytes32 constant SUBJECT_A  = keccak256("subject-a");
    bytes32 constant SUBJECT_B  = keccak256("subject-b");
    bytes32 constant ROLE_TITLE = keccak256("TITLE_DEED");
    bytes32 constant BUNDLE_A   = keccak256("bundle-a");
    bytes32 constant BUNDLE_B   = keccak256("bundle-b");

    uint256 constant TOKEN_A = 1;
    uint256 constant TOKEN_B = 2;

    function setUp() public {
        registry = new DocumentBundleAnchor(admin);
        bytes32 anchorRole = registry.ANCHOR_ROLE();
        vm.prank(admin);
        registry.grantRole(anchorRole, anchorer);

        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE_TITLE;

        token = new DocumentBoundERC721("Kula RWA", "KRWA", address(registry), roles, admin);

        vm.prank(admin); token.mint(alice, TOKEN_A, SUBJECT_A);
        vm.prank(admin); token.mint(alice, TOKEN_B, SUBJECT_B);
    }

    // ── Interface ─────────────────────────────────────────────────────────

    function test_documentRegistry() public { assertEq(token.documentRegistry(), address(registry)); }
    function test_isDocumentBound()  public { assertTrue(token.isDocumentBound()); }

    function test_documentSubjectIdOf_correct() public {
        assertEq(token.documentSubjectIdOf(TOKEN_A), SUBJECT_A);
        assertEq(token.documentSubjectIdOf(TOKEN_B), SUBJECT_B);
    }

    function test_documentSubjectIdOf_revertsUnbound() public {
        vm.expectRevert("DocumentBoundERC721: tokenId not bound");
        token.documentSubjectIdOf(99);
    }

    function test_documentSubjectId_reverts() public {
        vm.expectRevert();
        token.documentSubjectId();
    }

    function test_supportsInterface() public {
        assertTrue(token.supportsInterface(type(IDocumentBound).interfaceId));
    }

    // ── Per-token compliance isolation ────────────────────────────────────

    function test_transfer_revertsWithNoBundles() public {
        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC721: required document bundle not active");
        token.transferFrom(alice, bob, TOKEN_A);
    }

    function test_transfer_succeedsAfterBundle() public {
        vm.prank(anchorer);
        registry.anchorBundle(BUNDLE_A, SUBJECT_A, ROLE_TITLE, 1, "ipfs://a");
        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_A);
        assertEq(token.ownerOf(TOKEN_A), bob);
    }

    function test_bundleForA_doesNotUnlockB() public {
        vm.prank(anchorer);
        registry.anchorBundle(BUNDLE_A, SUBJECT_A, ROLE_TITLE, 1, "ipfs://a");
        // TOKEN_A transferable, TOKEN_B still blocked
        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_A);
        assertEq(token.ownerOf(TOKEN_A), bob);

        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC721: required document bundle not active");
        token.transferFrom(alice, bob, TOKEN_B);
    }

    function test_hasActiveDocumentBundleFor() public {
        assertFalse(token.hasActiveDocumentBundleFor(TOKEN_A, ROLE_TITLE));
        vm.prank(anchorer);
        registry.anchorBundle(BUNDLE_A, SUBJECT_A, ROLE_TITLE, 1, "ipfs://a");
        assertTrue(token.hasActiveDocumentBundleFor(TOKEN_A, ROLE_TITLE));
        assertFalse(token.hasActiveDocumentBundleFor(TOKEN_B, ROLE_TITLE));
    }

    function test_mint_revertsZeroSubjectId() public {
        vm.prank(admin);
        vm.expectRevert("DocumentBoundERC721: zero subjectId");
        token.mint(alice, 99, bytes32(0));
    }

    function test_mint_revertsAlreadyBound() public {
        vm.prank(admin);
        vm.expectRevert("DocumentBoundERC721: tokenId already bound");
        token.mint(alice, TOKEN_A, SUBJECT_A);
    }
}
