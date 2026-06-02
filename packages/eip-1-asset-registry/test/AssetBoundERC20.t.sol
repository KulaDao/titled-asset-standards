// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetBoundERC20} from "../src/reference/AssetBoundERC20.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";
import {IAssetBoundToken} from "../src/interfaces/IAssetBoundToken.sol";

contract AssetBoundERC20Test is Test {
    AssetAnchorRegistry registry;
    AssetBoundERC20     token;

    address admin     = address(0xA0);
    address registrar = address(0xA1);
    address alice     = address(0xA2);
    address bob       = address(0xA3);

    bytes32 anchorId;
    bytes32 legalHash    = keccak256("legal");
    bytes32 evidenceHash = keccak256("evidence");

    function setUp() public {
        vm.warp(2_000_000);
        registry = new AssetAnchorRegistry(admin);

        vm.startPrank(admin);
        registry.grantRole(registry.REGISTRAR_ROLE(), registrar);
        vm.stopPrank();

        bytes memory meta = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("GOLD"),
            jurisdiction:    bytes32("ZM"),
            attestationDate: uint64(block.timestamp - 1),
            expiresAt:       uint64(block.timestamp + 365 days),
            uri:             bytes("ipfs://QmTest"),
            extensions:      bytes("")
        }));

        vm.prank(registrar);
        anchorId = registry.registerAnchor(legalHash, evidenceHash, meta);

        token = new AssetBoundERC20("Kula Gold Token", "KGT", anchorId, address(registry), admin);

        vm.prank(registrar);
        registry.bindToken(anchorId, address(token), 0);
    }

    // ── Interface conformance ─────────────────────────────────────────────

    function test_anchorId_returnsCorrectId() public {
        assertEq(token.anchorId(), anchorId);
    }

    function test_anchorRegistry_returnsRegistry() public {
        assertEq(token.anchorRegistry(), address(registry));
    }

    function test_isAssetBound_returnsTrue() public {
        assertTrue(token.isAssetBound());
    }

    function test_isAnchorActive_trueWhenActive() public {
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

    function test_supportsInterface_IAssetBoundToken() public {
        assertTrue(token.supportsInterface(type(IAssetBoundToken).interfaceId));
    }

    // ── Minting ───────────────────────────────────────────────────────────

    function test_mint_adminCanMint() public {
        vm.prank(admin);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
    }

    function test_mint_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1000e18);
    }

    // ── Transfer guard ────────────────────────────────────────────────────

    function test_transfer_allowedWhenAnchorActive() public {
        vm.prank(admin);
        token.mint(alice, 500e18);
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_transfer_revertsBeforeRegistryBinding() public {
        vm.prank(registrar);
        bytes32 unboundAnchor = registry.registerAnchor(
            keccak256("unbound-legal"),
            keccak256("unbound-evidence"),
            AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
                assetClass:      bytes32("GOLD"),
                jurisdiction:    bytes32("ZM"),
                attestationDate: uint64(block.timestamp - 1),
                expiresAt:       uint64(block.timestamp + 365 days),
                uri:             bytes("ipfs://QmUnbound"),
                extensions:      bytes("")
            }))
        );
        AssetBoundERC20 unboundToken = new AssetBoundERC20(
            "Unbound Gold",
            "UGLD",
            unboundAnchor,
            address(registry),
            admin
        );

        vm.prank(admin);
        unboundToken.mint(alice, 500e18);

        assertFalse(unboundToken.isAnchorActive());

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC20: registry binding mismatch");
        unboundToken.transfer(bob, 100e18);
    }

    function test_transfer_revertsWhenAnchorDeactivated() public {
        vm.prank(admin);
        token.mint(alice, 500e18);

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "test deactivation");

        assertFalse(token.isAnchorActive());

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC20: anchor inactive");
        token.transfer(bob, 100e18);
    }

    function test_transfer_revertsWhenAnchorExpired() public {
        vm.prank(admin);
        token.mint(alice, 500e18);

        vm.warp(block.timestamp + 366 days);
        assertFalse(token.isAnchorActive());

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC20: anchor inactive");
        token.transfer(bob, 100e18);
    }

    function test_mint_allowedEvenWhenAnchorInactive() public {
        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "test");

        vm.prank(admin);
        token.mint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_isAnchorActive_falseAfterExpiry() public {
        vm.warp(block.timestamp + 366 days);
        assertFalse(token.isAnchorActive());
    }

    function test_isAnchorActive_falseAfterDeactivation() public {
        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "regulatory");
        assertFalse(token.isAnchorActive());
    }
}
