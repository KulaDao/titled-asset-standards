// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {IAssetAnchorRegistry} from "../src/interfaces/IAssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";

contract AssetAnchorRegistryTest is Test {
    event AnchorRegistered(bytes32 indexed anchorId, bytes32 legalHash, bytes32 evidenceHash);
    event TokenBound(bytes32 indexed anchorId, address indexed token, uint256 tokenId);
    event AnchorDeactivated(bytes32 indexed anchorId, string reason);

    AssetAnchorRegistry registry;

    address admin     = address(0xA0);
    address registrar = address(0xA1);
    address other     = address(0xA2);
    address token     = address(0xB0);

    bytes32 constant LEGAL_HASH      = keccak256("legal-doc-1");
    bytes32 constant EVIDENCE_HASH   = keccak256("evidence-doc-1");
    bytes32 constant LEGAL_HASH_2    = keccak256("legal-doc-2");
    bytes32 constant EVIDENCE_HASH_2 = keccak256("evidence-doc-2");

    function setUp() public {
        registry = new AssetAnchorRegistry(admin);
        vm.startPrank(admin);
        registry.grantRole(registry.REGISTRAR_ROLE(), registrar);
        vm.stopPrank();
    }

    function _validMetadata(uint64 expiresAt) internal pure returns (bytes memory) {
        return AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("EQUITY"),
            jurisdiction:    bytes32("US"),
            attestationDate: uint64(1_000_000),
            expiresAt:       expiresAt,
            uri:             bytes("ipfs://QmFoo"),
            extensions:      bytes("")
        }));
    }

    // ─── registerAnchor ───────────────────────────────────────────────

    function test_registerAnchor_storesAllFields() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(
            LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000)
        );

        bytes32 expectedId = keccak256(abi.encode(LEGAL_HASH, EVIDENCE_HASH));
        assertEq(anchorId, expectedId, "anchorId derivation mismatch");

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.anchorId,     anchorId,       "rec.anchorId mismatch");
        assertEq(rec.legalHash,    LEGAL_HASH,     "rec.legalHash mismatch");
        assertEq(rec.evidenceHash, EVIDENCE_HASH,  "rec.evidenceHash mismatch");
        assertEq(rec.boundToken,   address(0),     "should be unbound");
        assertEq(rec.boundTokenId, 0,              "boundTokenId should be 0");
        assertEq(rec.registeredAt, uint64(500_000),"registeredAt mismatch");
        assertTrue(rec.active,                     "active should be true");
    }

    function test_registerAnchor_emitsAnchorRegistered() public {
        bytes32 expectedId = keccak256(abi.encode(LEGAL_HASH, EVIDENCE_HASH));
        vm.expectEmit(true, false, false, true);
        emit AnchorRegistered(expectedId, LEGAL_HASH, EVIDENCE_HASH);
        vm.prank(registrar);
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
    }

    function test_registerAnchor_rejectsDuplicate() public {
        vm.prank(registrar);
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: duplicate anchor");
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(3_000_000));
    }

    function test_registerAnchor_revertsUnauthorized() public {
        vm.prank(other);
        vm.expectRevert();
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
    }

    function test_registerAnchor_revertsInvalidMetadata() public {
        bytes memory badMeta = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32(0),
            jurisdiction:    bytes32("US"),
            attestationDate: uint64(1_000_000),
            expiresAt:       uint64(2_000_000),
            uri:             bytes("ipfs://QmFoo"),
            extensions:      bytes("")
        }));
        vm.prank(registrar);
        vm.expectRevert("AnchorMetadataLib: missing assetClass");
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, badMeta);
    }

    // ─── bindToken ────────────────────────────────────────────────────

    function test_bindToken_succeeds_by_registrar() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        registry.bindToken(anchorId, token, 0);

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.boundToken,   token, "boundToken mismatch");
        assertEq(rec.boundTokenId, 0,     "boundTokenId mismatch");
    }

    function test_bindToken_succeeds_by_admin() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(admin);
        registry.bindToken(anchorId, token, 0);

        assertEq(registry.getAnchor(anchorId).boundToken, token, "admin bind failed");
    }

    function test_bindToken_emitsTokenBound() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.expectEmit(true, true, false, true);
        emit TokenBound(anchorId, token, 42);
        vm.prank(registrar);
        registry.bindToken(anchorId, token, 42);
    }

    function test_bindToken_revertsUnauthorized() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(other);
        vm.expectRevert("AssetAnchorRegistry: not authorized to bind");
        registry.bindToken(anchorId, token, 0);
    }

    function test_bindToken_revertsAnchorNotFound() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.bindToken(keccak256("nonexistent"), token, 0);
    }

    function test_bindToken_revertsAlreadyBound() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(anchorId, token, 0);

        vm.prank(admin);
        vm.expectRevert("AssetAnchorRegistry: already bound");
        registry.bindToken(anchorId, address(0xC0), 0);
    }

    function test_bindToken_revertsZeroAddress() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero token address");
        registry.bindToken(anchorId, address(0), 0);
    }

    // ─── registerAndBind ──────────────────────────────────────────────

    function test_registerAndBind_storesAll() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAndBind(
            LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), token, 7
        );

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.boundToken,   token, "boundToken mismatch");
        assertEq(rec.boundTokenId, 7,     "boundTokenId mismatch");
        assertTrue(rec.active,            "active should be true");
    }

    function test_registerAndBind_emitsBothEvents() public {
        bytes32 expectedId = keccak256(abi.encode(LEGAL_HASH, EVIDENCE_HASH));

        vm.expectEmit(true, false, false, true);
        emit AnchorRegistered(expectedId, LEGAL_HASH, EVIDENCE_HASH);

        vm.expectEmit(true, true, false, true);
        emit TokenBound(expectedId, token, 0);

        vm.prank(registrar);
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), token, 0);
    }

    function test_registerAndBind_revertsZeroToken() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero token address");
        registry.registerAndBind(
            LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), address(0), 0
        );
    }

    // ─── getAnchor ────────────────────────────────────────────────────

    function test_getAnchor_revertsNotFound() public {
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.getAnchor(keccak256("nonexistent"));
    }

    // ─── isBound ──────────────────────────────────────────────────────

    function test_isBound_falseBeforeBind() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        assertFalse(registry.isBound(anchorId), "should not be bound yet");
    }

    function test_isBound_trueAfterBind() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(anchorId, token, 0);
        assertTrue(registry.isBound(anchorId), "should be bound");
    }
}
