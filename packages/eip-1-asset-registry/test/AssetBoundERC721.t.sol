// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetBoundERC721} from "../src/reference/AssetBoundERC721.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";
import {IAssetBoundToken} from "../src/interfaces/IAssetBoundToken.sol";

contract AssetBoundERC721Test is Test {
    AssetAnchorRegistry registry;
    AssetBoundERC721    token;

    address admin     = address(0xA0);
    address registrar = address(0xA1);
    address alice     = address(0xA2);
    address bob       = address(0xA3);

    bytes32 anchorA;
    bytes32 anchorB;

    uint256 constant TOKEN_A = 1;
    uint256 constant TOKEN_B = 2;

    function setUp() public {
        vm.warp(2_000_000);
        registry = new AssetAnchorRegistry(admin);
        token    = new AssetBoundERC721("Kula RWA NFT", "KRWA", address(registry), admin);

        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.grantRole(registrarRole, registrar);

        anchorA = _registerAnchor(keccak256("legalA"), keccak256("evidenceA"));
        anchorB = _registerAnchor(keccak256("legalB"), keccak256("evidenceB"));

        vm.prank(admin);
        token.mint(alice, TOKEN_A, anchorA);
        vm.prank(registrar);
        registry.bindToken(anchorA, address(token), TOKEN_A);

        vm.prank(admin);
        token.mint(alice, TOKEN_B, anchorB);
        vm.prank(registrar);
        registry.bindToken(anchorB, address(token), TOKEN_B);
    }

    function _registerAnchor(bytes32 lh, bytes32 eh) internal returns (bytes32) {
        bytes memory meta = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("REAL_ESTATE"),
            jurisdiction:    bytes32("US"),
            attestationDate: uint64(block.timestamp - 1),
            expiresAt:       uint64(block.timestamp + 365 days),
            uri:             bytes("ipfs://QmTest"),
            extensions:      bytes("")
        }));
        vm.prank(registrar);
        return registry.registerAnchor(lh, eh, meta);
    }

    // ── Interface conformance ─────────────────────────────────────────────

    function test_anchorIdOf_returnsCorrectAnchor() public {
        assertEq(token.anchorIdOf(TOKEN_A), anchorA);
        assertEq(token.anchorIdOf(TOKEN_B), anchorB);
    }

    function test_anchorIdOf_revertsForUnboundToken() public {
        vm.expectRevert("AssetBoundERC721: tokenId not bound");
        token.anchorIdOf(99);
    }

    function test_anchorId_reverts() public {
        vm.expectRevert();
        token.anchorId();
    }

    function test_isAnchorActive_reverts() public {
        vm.expectRevert();
        token.isAnchorActive();
    }

    function test_anchorRegistry_returnsRegistry() public {
        assertEq(token.anchorRegistry(), address(registry));
    }

    function test_isAssetBound_returnsTrue() public {
        assertTrue(token.isAssetBound());
    }

    function test_isAnchorActiveFor_trueWhenActive() public {
        assertTrue(token.isAnchorActiveFor(TOKEN_A));
        assertTrue(token.isAnchorActiveFor(TOKEN_B));
    }

    function test_isAnchorActiveFor_revertsUnbound() public {
        vm.expectRevert("AssetBoundERC721: tokenId not bound");
        token.isAnchorActiveFor(99);
    }

    function test_supportsInterface_IAssetBoundToken() public {
        assertTrue(token.supportsInterface(type(IAssetBoundToken).interfaceId));
    }

    // ── Per-token independence ────────────────────────────────────────────

    function test_deactivateA_doesNotAffectB() public {
        vm.prank(admin);
        registry.deactivateAnchor(anchorA, "regulatory");

        assertFalse(token.isAnchorActiveFor(TOKEN_A));
        assertTrue(token.isAnchorActiveFor(TOKEN_B));
    }

    // ── Transfer guard ────────────────────────────────────────────────────

    function test_transfer_allowedWhenActive() public {
        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_A);
        assertEq(token.ownerOf(TOKEN_A), bob);
    }

    function test_transfer_revertsWhenAnchorDeactivated() public {
        vm.prank(admin);
        registry.deactivateAnchor(anchorA, "test");

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC721: anchor inactive");
        token.transferFrom(alice, bob, TOKEN_A);
    }

    function test_transfer_tokenB_unaffectedByDeactivationOfA() public {
        vm.prank(admin);
        registry.deactivateAnchor(anchorA, "test");

        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_B);
        assertEq(token.ownerOf(TOKEN_B), bob);
    }

    function test_transfer_revertsWhenExpired() public {
        vm.warp(block.timestamp + 366 days);

        vm.prank(alice);
        vm.expectRevert("AssetBoundERC721: anchor inactive");
        token.transferFrom(alice, bob, TOKEN_A);
    }

    // ── Minting guards ────────────────────────────────────────────────────

    function test_mint_revertsZeroAnchorId() public {
        vm.prank(admin);
        vm.expectRevert("AssetBoundERC721: zero anchorId");
        token.mint(alice, 99, bytes32(0));
    }

    function test_mint_revertsAlreadyBound() public {
        vm.prank(admin);
        vm.expectRevert("AssetBoundERC721: tokenId already bound");
        token.mint(alice, TOKEN_A, anchorA);
    }

    function test_mint_revertsUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 99, anchorA);
    }
}
