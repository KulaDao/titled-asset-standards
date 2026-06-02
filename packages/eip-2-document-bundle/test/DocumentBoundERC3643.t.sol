// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DocumentBoundERC3643}  from "../src/reference/DocumentBoundERC3643.sol";
import {DocumentBundleAnchor}  from "../src/reference/DocumentBundleAnchor.sol";
import {IDocumentBound}        from "../src/interfaces/IDocumentBound.sol";

contract DocumentBoundERC3643Test is Test {
    DocumentBundleAnchor  registry;
    DocumentBoundERC3643  token;

    address admin    = address(0xA0);
    address agent    = address(0xA1);
    address anchorer = address(0xA2);
    address alice    = address(0xA3);
    address bob      = address(0xA4);

    bytes32 constant SUBJECT      = keccak256("bond-subject");
    bytes32 constant ROLE_PROS    = keccak256("PROSPECTUS");
    bytes32 constant ROLE_LEGAL   = keccak256("LEGAL_BASIS");
    bytes32 constant BUNDLE_PROS  = keccak256("bundle-prospectus");
    bytes32 constant BUNDLE_LEGAL = keccak256("bundle-legal");

    function setUp() public {
        registry = new DocumentBundleAnchor(admin);
        bytes32 anchorRole = registry.ANCHOR_ROLE();
        vm.prank(admin);
        registry.grantRole(anchorRole, anchorer);

        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_PROS;
        roles[1] = ROLE_LEGAL;

        token = new DocumentBoundERC3643("Kula Green Bond", "KGB", address(registry), SUBJECT, roles, admin);

        bytes32 agentRole = token.AGENT_ROLE();
        vm.prank(admin);
        token.grantRole(agentRole, agent);

        vm.startPrank(agent);
        token.addToWhitelist(alice);
        token.addToWhitelist(bob);
        vm.stopPrank();

        // Anchor both required bundles
        vm.prank(anchorer);
        registry.anchorBundle(BUNDLE_PROS,  SUBJECT, ROLE_PROS,  2, "ipfs://prospectus");
        vm.prank(anchorer);
        registry.anchorBundle(BUNDLE_LEGAL, SUBJECT, ROLE_LEGAL, 1, "ipfs://legal");

        vm.prank(agent);
        token.mint(alice, 1_000_000e18);
    }

    // ── IDocumentBound ────────────────────────────────────────────────────

    function test_documentRegistry()  public { assertEq(token.documentRegistry(), address(registry)); }
    function test_documentSubjectId() public { assertEq(token.documentSubjectId(), SUBJECT); }
    function test_isDocumentBound()   public { assertTrue(token.isDocumentBound()); }

    function test_hasActiveDocumentBundle_bothActive() public {
        assertTrue(token.hasActiveDocumentBundle(ROLE_PROS));
        assertTrue(token.hasActiveDocumentBundle(ROLE_LEGAL));
    }

    function test_supportsInterface() public {
        assertTrue(token.supportsInterface(type(IDocumentBound).interfaceId));
    }

    // ── Happy path ────────────────────────────────────────────────────────

    function test_transfer_succeedsWithAllCompliance() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    // ── Document compliance guard ─────────────────────────────────────────

    function test_transfer_revertsWhenDocumentMissing() public {
        // Deploy fresh token with no bundles anchored yet
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE_PROS;
        DocumentBoundERC3643 fresh = new DocumentBoundERC3643(
            "Fresh", "FRH", address(registry), keccak256("fresh-subject"), roles, admin
        );
        bytes32 agentRole = fresh.AGENT_ROLE();
        vm.prank(admin); fresh.grantRole(agentRole, agent);
        vm.prank(agent); fresh.addToWhitelist(alice);
        vm.prank(agent); fresh.addToWhitelist(bob);
        vm.prank(agent); fresh.mint(alice, 500e18);

        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC3643: required document bundle not active");
        fresh.transfer(bob, 100e18);
    }

    // ── ERC-3643 compliance guards ────────────────────────────────────────

    function test_transfer_revertsNonWhitelisted() public {
        address stranger = address(0xBB);
        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC3643: recipient not whitelisted");
        token.transfer(stranger, 100e18);
    }

    function test_transfer_revertsWhenSenderFrozen() public {
        bytes32 agentRole = token.AGENT_ROLE();
        vm.prank(admin); token.grantRole(agentRole, admin);
        vm.prank(admin); token.freezeAddress(alice);
        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC3643: sender frozen");
        token.transfer(bob, 100e18);
    }

    function test_transfer_revertsWhenPaused() public {
        vm.prank(agent); token.pause();
        vm.prank(alice);
        vm.expectRevert("DocumentBoundERC3643: token paused");
        token.transfer(bob, 100e18);
    }

    function test_unpause_restoresTransfer() public {
        vm.prank(agent); token.pause();
        vm.prank(agent); token.unpause();
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_burn_agentCanBurn() public {
        vm.prank(agent);
        token.burn(alice, 400e18);
        assertEq(token.balanceOf(alice), 1_000_000e18 - 400e18);
    }

    function test_mint_revertsNonWhitelisted() public {
        vm.prank(agent);
        vm.expectRevert("DocumentBoundERC3643: recipient not whitelisted");
        token.mint(address(0xBB), 1000e18);
    }

    function test_onlyAgent_canMint()    public { vm.prank(alice); vm.expectRevert(); token.mint(alice, 1e18); }
    function test_onlyAgent_canFreeze()  public { vm.prank(alice); vm.expectRevert(); token.freezeAddress(bob); }
    function test_onlyAgent_canPause()   public { vm.prank(alice); vm.expectRevert(); token.pause(); }
}
