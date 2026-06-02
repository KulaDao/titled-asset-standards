// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetBoundERC3643} from "../src/reference/AssetBoundERC3643.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";
import {IAssetBoundToken} from "../src/interfaces/IAssetBoundToken.sol";

contract AssetBoundERC3643Test is Test {
    AssetAnchorRegistry registry;
    AssetBoundERC3643   token;

    address admin     = address(0xA0);
    address agent     = address(0xA1);
    address registrar = address(0xA2);
    address alice     = address(0xA3);
    address bob       = address(0xA4);

    bytes32 anchorId;

    function setUp() public {
        vm.warp(2_000_000);
        registry = new AssetAnchorRegistry(admin);

        bytes memory meta = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("BOND"),
            jurisdiction:    bytes32("EU"),
            attestationDate: uint64(block.timestamp - 1),
            expiresAt:       uint64(block.timestamp + 365 days),
            uri:             bytes("ipfs://QmBond"),
            extensions:      bytes("ISIN=XS1234567890")
        }));

        vm.startPrank(admin);
        registry.grantRole(registry.REGISTRAR_ROLE(), registrar);
        vm.stopPrank();

        vm.prank(registrar);
        anchorId = registry.registerAnchor(keccak256("legal"), keccak256("evidence"), meta);

        token = new AssetBoundERC3643("Kula Green Bond", "KGB", anchorId, address(registry), admin);

        bytes32 agentRole = token.AGENT_ROLE();
        vm.prank(admin);
        token.grantRole(agentRole, agent);

        vm.prank(registrar);
        registry.bindToken(anchorId, address(token), 0);

        vm.startPrank(agent);
        token.addToWhitelist(alice);
        token.addToWhitelist(bob);
        vm.stopPrank();
    }

    // ── IAssetBoundToken ──────────────────────────────────────────────────

    function test_anchorId_correct() public {
        assertEq(token.anchorId(), anchorId);
    }

    function test_anchorRegistry_correct() public {
        assertEq(token.anchorRegistry(), address(registry));
    }

    function test_isAssetBound_true() public {
        assertTrue(token.isAssetBound());
    }

    function test_isAnchorActive_trueInitially() public {
        assertTrue(token.isAnchorActive());
    }

    function test_anchorIdOf_reverts() public {
        vm.expectRevert();
        token.anchorIdOf(0);
    }

    function test_isAnchorActiveFor_reverts() public {
        vm.expectRevert();
        token.isAnchorActiveFor(0);
    }

    function test_supportsInterface() public {
        assertTrue(token.supportsInterface(type(IAssetBoundToken).interfaceId));
    }

    // ── Whitelist ─────────────────────────────────────────────────────────

    function test_mint_revertsNonWhitelisted() public {
        address stranger = address(0xBB);
        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: recipient not whitelisted");
        token.mint(stranger, 1000e18);
    }

    function test_mint_succeeds_whitelisted() public {
        vm.prank(agent);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
    }

    function test_mint_revertsFrozenRecipient() public {
        vm.prank(agent);
        token.freezeAddress(alice);

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: recipient frozen");
        token.mint(alice, 1000e18);
    }

    function test_transfer_revertsNonWhitelistedRecipient() public {
        vm.prank(agent);
        token.mint(alice, 500e18);

        vm.prank(agent);
        token.removeFromWhitelist(bob);

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC3643: recipient not whitelisted");
        token.transfer(bob, 100e18);
    }

    function test_transfer_revertsNonWhitelistedSender() public {
        vm.prank(agent);
        token.mint(alice, 500e18);

        vm.prank(agent);
        token.removeFromWhitelist(alice);

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC3643: sender not whitelisted");
        token.transfer(bob, 100e18);
    }

    function test_transfer_succeeds_bothWhitelisted() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.prank(alice);
        token.transfer(bob, 200e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    // ── Freeze ────────────────────────────────────────────────────────────

    function test_transfer_revertsWhenSenderFrozen() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.prank(agent);
        token.freezeAddress(alice);

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC3643: sender frozen");
        token.transfer(bob, 100e18);
    }

    function test_transfer_revertsWhenRecipientFrozen() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.prank(agent);
        token.freezeAddress(bob);

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC3643: recipient frozen");
        token.transfer(bob, 100e18);
    }

    function test_unfreeze_restoresTransfers() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.prank(agent);
        token.freezeAddress(alice);
        vm.prank(agent);
        token.unfreezeAddress(alice);

        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    // ── Pause ─────────────────────────────────────────────────────────────

    function test_transfer_revertsWhenPaused() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.prank(agent);
        token.pause();

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC3643: token paused");
        token.transfer(bob, 100e18);
    }

    function test_mint_revertsWhenPaused() public {
        vm.prank(agent);
        token.pause();

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: token paused");
        token.mint(alice, 500e18);
    }

    function test_unpause_restoresTransfers() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.prank(agent);
        token.pause();
        vm.prank(agent);
        token.unpause();

        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_pause_revertsDoubledPause() public {
        vm.prank(agent);
        token.pause();
        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: already paused");
        token.pause();
    }

    // ── Anchor guard ──────────────────────────────────────────────────────

    function test_transfer_revertsWhenAnchorDeactivated() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "regulatory");

        assertFalse(token.isAnchorActive());
        vm.prank(alice);
        vm.expectRevert("AssetBoundERC3643: anchor inactive");
        token.transfer(bob, 100e18);
    }

    function test_mint_revertsWhenAnchorDeactivated() public {
        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "regulatory");

        assertFalse(token.isAnchorActive());

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: anchor inactive");
        token.mint(alice, 500e18);
    }

    function test_transfer_revertsWhenExpired() public {
        vm.prank(agent);
        token.mint(alice, 500e18);
        vm.warp(block.timestamp + 366 days);

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC3643: anchor inactive");
        token.transfer(bob, 100e18);
    }

    function test_mint_revertsWhenExpired() public {
        vm.warp(block.timestamp + 366 days);

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: anchor inactive");
        token.mint(alice, 500e18);
    }

    // ── Access control ────────────────────────────────────────────────────

    function test_onlyAgent_canMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 100e18);
    }

    function test_onlyAgent_canFreeze() public {
        vm.prank(alice);
        vm.expectRevert();
        token.freezeAddress(bob);
    }

    function test_onlyAgent_canPause() public {
        vm.prank(alice);
        vm.expectRevert();
        token.pause();
    }

    // ── Burn ──────────────────────────────────────────────────────────────

    function test_burn_agentCanBurn() public {
        vm.prank(agent);
        token.mint(alice, 1000e18);
        vm.prank(agent);
        token.burn(alice, 400e18);
        assertEq(token.balanceOf(alice), 600e18);
    }

    function test_burn_revertsWhenPaused() public {
        vm.prank(agent);
        token.mint(alice, 1000e18);
        vm.prank(agent);
        token.pause();

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: token paused");
        token.burn(alice, 400e18);
    }

    function test_burn_revertsWhenHolderFrozen() public {
        vm.prank(agent);
        token.mint(alice, 1000e18);
        vm.prank(agent);
        token.freezeAddress(alice);

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: holder frozen");
        token.burn(alice, 400e18);
    }

    function test_burn_revertsWhenHolderRemovedFromWhitelist() public {
        vm.prank(agent);
        token.mint(alice, 1000e18);
        vm.prank(agent);
        token.removeFromWhitelist(alice);

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: holder not whitelisted");
        token.burn(alice, 400e18);
    }

    function test_burn_revertsWhenAnchorInactive() public {
        vm.prank(agent);
        token.mint(alice, 1000e18);
        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "regulatory");

        vm.prank(agent);
        vm.expectRevert("AssetBoundERC3643: anchor inactive");
        token.burn(alice, 400e18);
    }
}
