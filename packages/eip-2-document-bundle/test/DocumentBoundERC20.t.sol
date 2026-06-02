// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DocumentBoundERC20}    from "../src/reference/DocumentBoundERC20.sol";
import {DocumentBundleAnchor}  from "../src/reference/DocumentBundleAnchor.sol";
import {IDocumentBound}        from "../src/interfaces/IDocumentBound.sol";

contract DocumentBoundERC20Test is Test {
    DocumentBundleAnchor registry;
    DocumentBoundERC20   token;

    address admin    = address(0xA0);
    address anchorer = address(0xA1);
    address alice    = address(0xA2);
    address bob      = address(0xA3);

    bytes32 constant SUBJECT   = keccak256("subject-x");
    bytes32 constant ROLE_LEGAL = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_AUDIT = keccak256("AUDIT_REPORT");
    bytes32 constant BUNDLE_1   = keccak256("bundle-1");
    bytes32 constant BUNDLE_2   = keccak256("bundle-2");

    function setUp() public {
        registry = new DocumentBundleAnchor(admin);
        bytes32 anchorRole = registry.ANCHOR_ROLE();
        vm.prank(admin);
        registry.grantRole(anchorRole, anchorer);

        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_LEGAL;
        roles[1] = ROLE_AUDIT;

        token = new DocumentBoundERC20("Kula Bond", "KBND", address(registry), SUBJECT, roles, admin);

        vm.prank(admin);
        token.mint(alice, 1000e18);
    }

    function _anchorRole(bytes32 bundle, bytes32 role) internal {
        vm.prank(anchorer);
        registry.anchorBundle(bundle, SUBJECT, role, 1, "ipfs://Qm");
    }

    // ── Interface ─────────────────────────────────────────────────────────

    function test_documentRegistry() public {
        assertEq(token.documentRegistry(), address(registry));
    }

    function test_documentSubjectId() public {
        assertEq(token.documentSubjectId(), SUBJECT);
    }

    function test_isDocumentBound() public {
        assertTrue(token.isDocumentBound());
    }

    function test_supportsInterface() public {
        assertTrue(token.supportsInterface(type(IDocumentBound).interfaceId));
    }

    function test_documentSubjectIdOf_reverts() public {
        vm.expectRevert();
        token.documentSubjectIdOf(0);
    }

    function test_hasActiveDocumentBundleFor_reverts() public {
        vm.expectRevert();
        token.hasActiveDocumentBundleFor(0, ROLE_LEGAL);
    }

    // ── hasActiveDocumentBundle ───────────────────────────────────────────

    function test_hasActiveDocumentBundle_falseBeforeAnchor() public {
        assertFalse(token.hasActiveDocumentBundle(ROLE_LEGAL));
        assertFalse(token.hasActiveDocumentBundle(ROLE_AUDIT));
    }

    function test_hasActiveDocumentBundle_trueAfterAnchor() public {
        _anchorRole(BUNDLE_1, ROLE_LEGAL);
        assertTrue(token.hasActiveDocumentBundle(ROLE_LEGAL));
        assertFalse(token.hasActiveDocumentBundle(ROLE_AUDIT));
    }

    // ── Transfer guard ────────────────────────────────────────────────────

    function test_transfer_revertsWhenNoBundles() public {
        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC20: required document bundle not active");
        token.transfer(bob, 100e18);
    }

    function test_transfer_revertsWhenOnlyOneRolePresent() public {
        _anchorRole(BUNDLE_1, ROLE_LEGAL);
        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC20: required document bundle not active");
        token.transfer(bob, 100e18);
    }

    function test_transfer_succeedsWhenAllRolesPresent() public {
        _anchorRole(BUNDLE_1, ROLE_LEGAL);
        _anchorRole(BUNDLE_2, ROLE_AUDIT);
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_mint_succeedsWithoutBundles() public {
        vm.prank(admin);
        token.mint(bob, 500e18);
        assertEq(token.balanceOf(bob), 500e18);
    }

    function test_transfer_remainsUnblockedAfterSupersession() public {
        _anchorRole(BUNDLE_1, ROLE_LEGAL);
        _anchorRole(BUNDLE_2, ROLE_AUDIT);
        // supersedeBundle anchors newBundle atomically -- active slot stays filled
        bytes32 newBundle = keccak256("bundle-3");
        vm.prank(anchorer);
        registry.supersedeBundle(BUNDLE_1, newBundle, SUBJECT, ROLE_LEGAL, 2, "ipfs://v2");
        assertTrue(token.hasActiveDocumentBundle(ROLE_LEGAL));
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_transfer_blockedWhenActiveBundleRevoked() public {
        _anchorRole(BUNDLE_1, ROLE_LEGAL);
        // AUDIT not anchored -- should still block
        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC20: required document bundle not active");
        token.transfer(bob, 100e18);
    }
}
