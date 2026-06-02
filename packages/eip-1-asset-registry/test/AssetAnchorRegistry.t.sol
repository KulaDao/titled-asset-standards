// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {IAssetAnchorRegistry} from "../src/interfaces/IAssetAnchorRegistry.sol";
import {IAssetBoundToken} from "../src/interfaces/IAssetBoundToken.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";

contract MockAssetBoundToken is IAssetBoundToken {
    address public immutable override anchorRegistry;

    bytes32 private immutable _anchorId;
    uint256 private immutable _tokenId;
    bool    private immutable _perToken;

    constructor(address registry, bytes32 anchorId_, bool perToken_, uint256 tokenId_) {
        anchorRegistry = registry;
        _anchorId = anchorId_;
        _perToken = perToken_;
        _tokenId = tokenId_;
    }

    function anchorId() external view override returns (bytes32) {
        require(!_perToken, "MockAssetBoundToken: per-token binding");
        return _anchorId;
    }

    function anchorIdOf(uint256 tokenId) external view override returns (bytes32) {
        require(_perToken && tokenId == _tokenId, "MockAssetBoundToken: tokenId not bound");
        return _anchorId;
    }

    function isAssetBound() external pure override returns (bool) {
        return true;
    }

    function isAnchorActive() external pure override returns (bool) {
        return true;
    }

    function isAnchorActiveFor(uint256) external pure override returns (bool) {
        return true;
    }
}

contract AssetAnchorRegistryTest is Test {
    event AnchorRegistered(bytes32 indexed anchorId, bytes32 legalHash, bytes32 evidenceHash);
    event TokenBound(bytes32 indexed anchorId, address indexed token, uint256 tokenId);
    event AnchorDeactivated(bytes32 indexed anchorId, string reason);
    event AnchorReattested(bytes32 indexed anchorId, uint64 oldExpiresAt, uint64 newExpiresAt, uint64 newAttestationDate);

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
            attestationDate: uint64(1),
            expiresAt:       expiresAt,
            uri:             bytes("ipfs://QmFoo"),
            extensions:      bytes("")
        }));
    }

    function _wholeToken(bytes32 anchorId) internal returns (address) {
        return address(new MockAssetBoundToken(address(registry), anchorId, false, 0));
    }

    function _perToken(bytes32 anchorId, uint256 tokenId) internal returns (address) {
        return address(new MockAssetBoundToken(address(registry), anchorId, true, tokenId));
    }

    function _futureAnchorId(bytes32 legalHash, bytes32 evidenceHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(legalHash, evidenceHash));
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

    function test_registerAnchor_revertsZeroLegalHash() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero legalHash");
        registry.registerAnchor(bytes32(0), EVIDENCE_HASH, _validMetadata(2_000_000));
    }

    function test_registerAnchor_revertsZeroEvidenceHash() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero evidenceHash");
        registry.registerAnchor(LEGAL_HASH, bytes32(0), _validMetadata(2_000_000));
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

    function test_registerAnchor_revertsFutureAttestationDate() public {
        bytes memory meta = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("EQUITY"),
            jurisdiction:    bytes32("US"),
            attestationDate: uint64(1_000_000),
            expiresAt:       uint64(2_000_000),
            uri:             bytes("ipfs://QmFoo"),
            extensions:      bytes("")
        }));
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: future attestation date");
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, meta);
    }

    function test_registerAnchor_revertsExpiresAtNotAfterAttestationDate() public {
        vm.warp(1_000_000);
        bytes memory meta = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("EQUITY"),
            jurisdiction:    bytes32("US"),
            attestationDate: uint64(1_000_000),
            expiresAt:       uint64(1_000_000),
            uri:             bytes("ipfs://QmFoo"),
            extensions:      bytes("")
        }));
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: expiresAt not after attestationDate");
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, meta);
    }

    function test_registerAnchor_revertsMetadataAlreadyExpired() public {
        vm.warp(3_000_000);
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: metadata already expired");
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
    }

    // ─── bindToken ────────────────────────────────────────────────────

    function test_bindToken_succeeds_by_registrar() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _wholeToken(anchorId);

        vm.prank(registrar);
        registry.bindToken(anchorId, boundToken, 0);

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.boundToken,   boundToken, "boundToken mismatch");
        assertEq(rec.boundTokenId, 0,     "boundTokenId mismatch");
    }

    function test_bindToken_succeeds_by_admin() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _wholeToken(anchorId);

        vm.prank(admin);
        registry.bindToken(anchorId, boundToken, 0);

        assertEq(registry.getAnchor(anchorId).boundToken, boundToken, "admin bind failed");
    }

    function test_bindToken_revertsRegistryMismatch() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address wrongToken = address(new MockAssetBoundToken(address(0xDEAD), anchorId, false, 0));
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token registry mismatch");
        registry.bindToken(anchorId, wrongToken, 0);
    }

    function test_bindToken_revertsPlainTokenWithoutAnchorRegistry() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token not asset-bound");
        registry.bindToken(anchorId, token, 0);
    }

    function test_bindToken_allowsCompliantTokenPointingToThisRegistry() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address compliantToken = _wholeToken(anchorId);
        vm.prank(registrar);
        registry.bindToken(anchorId, compliantToken, 0);
        assertEq(registry.getAnchor(anchorId).boundToken, compliantToken);
    }

    function test_bindToken_revertsAnchorMismatch_wholeContract() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address mismatchedToken = _wholeToken(keccak256("different-anchor"));
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token anchor mismatch");
        registry.bindToken(anchorId, mismatchedToken, 0);
    }

    function test_bindToken_revertsAnchorMismatch_perToken() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address mismatchedToken = _perToken(keccak256("different-anchor"), 42);
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token anchor mismatch");
        registry.bindToken(anchorId, mismatchedToken, 42);
    }

    function test_bindToken_emitsTokenBound() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _perToken(anchorId, 42);

        vm.expectEmit(true, true, false, true);
        emit TokenBound(anchorId, boundToken, 42);
        vm.prank(registrar);
        registry.bindToken(anchorId, boundToken, 42);
    }

    function test_bindToken_revertsUnauthorized() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _wholeToken(anchorId);

        vm.prank(other);
        vm.expectRevert("AssetAnchorRegistry: not authorized to bind");
        registry.bindToken(anchorId, boundToken, 0);
    }

    function test_bindToken_revertsAnchorNotFound() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.bindToken(keccak256("nonexistent"), token, 0);
    }

    function test_bindToken_revertsAlreadyBound() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _wholeToken(anchorId);
        vm.prank(registrar);
        registry.bindToken(anchorId, boundToken, 0);

        address secondToken = _wholeToken(anchorId);
        vm.prank(admin);
        vm.expectRevert("AssetAnchorRegistry: already bound");
        registry.bindToken(anchorId, secondToken, 0);
    }

    function test_bindToken_revertsZeroAddress() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero token address");
        registry.bindToken(anchorId, address(0), 0);
    }

    function test_bindToken_revertsTokenPairAlreadyBound() public {
        vm.prank(registrar);
        bytes32 anchorId1 = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _perToken(anchorId1, 42);
        vm.prank(registrar);
        registry.bindToken(anchorId1, boundToken, 42);

        vm.prank(registrar);
        bytes32 anchorId2 = registry.registerAnchor(
            keccak256("other-legal"), keccak256("other-evidence"), _validMetadata(2_000_000)
        );
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token pair already bound");
        registry.bindToken(anchorId2, boundToken, 42);
    }

    function test_registerAndBind_revertsTokenPairAlreadyBound() public {
        vm.warp(500_000);
        address boundToken = _perToken(_futureAnchorId(LEGAL_HASH, EVIDENCE_HASH), 7);
        vm.prank(registrar);
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), boundToken, 7);

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token pair already bound");
        registry.registerAndBind(
            keccak256("other-legal"), keccak256("other-evidence"),
            _validMetadata(2_000_000), boundToken, 7
        );
    }

    function test_bindToken_revertsAnchorInactive() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _wholeToken(anchorId);

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "test");

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor inactive");
        registry.bindToken(anchorId, boundToken, 0);
    }

    function test_bindToken_revertsAnchorExpired() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _wholeToken(anchorId);

        vm.warp(2_000_001);
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor expired");
        registry.bindToken(anchorId, boundToken, 0);
    }

    function test_registerAndBind_revertsAnchorExpired() public {
        vm.warp(3_000_000);
        address boundToken = _wholeToken(_futureAnchorId(LEGAL_HASH, EVIDENCE_HASH));
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: metadata already expired");
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), boundToken, 0);
    }

    // ─── registerAndBind ──────────────────────────────────────────────

    function test_registerAndBind_storesAll() public {
        vm.warp(500_000);
        bytes32 expectedId = _futureAnchorId(LEGAL_HASH, EVIDENCE_HASH);
        address boundToken = _perToken(expectedId, 7);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAndBind(
            LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), boundToken, 7
        );

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.boundToken,   boundToken, "boundToken mismatch");
        assertEq(rec.boundTokenId, 7,     "boundTokenId mismatch");
        assertTrue(rec.active,            "active should be true");
    }

    function test_registerAndBind_emitsBothEvents() public {
        bytes32 expectedId = keccak256(abi.encode(LEGAL_HASH, EVIDENCE_HASH));
        address boundToken = _wholeToken(expectedId);

        vm.expectEmit(true, false, false, true);
        emit AnchorRegistered(expectedId, LEGAL_HASH, EVIDENCE_HASH);

        vm.expectEmit(true, true, false, true);
        emit TokenBound(expectedId, boundToken, 0);

        vm.prank(registrar);
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), boundToken, 0);
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
        address boundToken = _wholeToken(anchorId);
        vm.prank(registrar);
        registry.bindToken(anchorId, boundToken, 0);
        assertTrue(registry.isBound(anchorId), "should be bound");
    }

    // ─── isBound after deactivation ───────────────────────────────────

    function test_isBound_trueAfterDeactivation() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        address boundToken = _wholeToken(anchorId);

        vm.prank(registrar);
        registry.bindToken(anchorId, boundToken, 0);

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "retired");

        assertTrue(registry.isBound(anchorId), "isBound must remain true after deactivation");
    }

    // ─── deactivateAnchor ─────────────────────────────────────────────

    function test_deactivateAnchor_setsActiveFalse() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "custody failure");

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertFalse(rec.active, "active should be false after deactivation");
    }

    function test_deactivateAnchor_emitsAnchorDeactivated() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.expectEmit(true, false, false, true);
        emit AnchorDeactivated(anchorId, "custody failure");
        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "custody failure");
    }

    function test_deactivateAnchor_revertsNotFound() public {
        vm.prank(admin);
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.deactivateAnchor(keccak256("nonexistent"), "reason");
    }

    function test_deactivateAnchor_revertsAlreadyDeactivated() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "first");

        vm.prank(admin);
        vm.expectRevert("AssetAnchorRegistry: already deactivated");
        registry.deactivateAnchor(anchorId, "second");
    }

    function test_deactivateAnchor_revertsUnauthorized() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(other);
        vm.expectRevert();
        registry.deactivateAnchor(anchorId, "reason");
    }

    // ─── reattest ─────────────────────────────────────────────────────

    function test_reattest_updatesExpiresAt() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(registrar);
        registry.reattest(anchorId, 3_000_000, uint64(500_000));

        AnchorMetadataLib.AnchorMetadata memory meta = registry.getMetadata(anchorId);
        assertEq(meta.expiresAt,       3_000_000,      "expiresAt should be updated");
        assertEq(meta.attestationDate, uint64(500_000), "attestationDate should be updated");
    }

    function test_reattest_revertsIfManuallyDeactivated() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "retired");

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: manually deactivated");
        registry.reattest(anchorId, 3_000_000, uint64(500_000));
    }

    function test_reattest_revertsAnchorNotFound() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.reattest(keccak256("nonexistent"), 2_000_000, 1_000_000);
    }

    function test_reattest_revertsExpiresAtInPast() public {
        vm.warp(1_500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: expiresAt must be future");
        registry.reattest(anchorId, 1_000_000, uint64(1_500_000));
    }

    function test_reattest_revertsUnauthorized_otherRegistrar() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        address otherRegistrar = address(0xA3);
        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.grantRole(registrarRole, otherRegistrar);

        vm.prank(otherRegistrar);
        vm.expectRevert("AssetAnchorRegistry: not authorized to reattest");
        registry.reattest(anchorId, 3_000_000, uint64(500_000));
    }

    function test_reattest_succeedsByAdmin() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(admin);
        registry.reattest(anchorId, 3_000_000, uint64(500_000));

        assertEq(registry.getMetadata(anchorId).expiresAt, 3_000_000, "admin reattest failed");
    }

    function test_reattest_emitsAnchorReattested() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(registrar);
        vm.expectEmit(true, false, false, true);
        emit AnchorReattested(anchorId, 1_000_000, 3_000_000, uint64(500_000));
        registry.reattest(anchorId, 3_000_000, uint64(500_000));
    }

    function test_reattest_revertsZeroAttestationDate() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero attestation date");
        registry.reattest(anchorId, 3_000_000, 0);
    }

    function test_reattest_revertsFutureAttestationDate() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: future attestation date");
        registry.reattest(anchorId, 3_000_000, uint64(600_000));
    }

    // ─── isActive ─────────────────────────────────────────────────────

    function test_isActive_trueWhenActiveAndNotExpired() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        assertTrue(registry.isActive(anchorId), "should be active before expiry");
    }

    function test_isActive_falseWhenExpired() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.warp(1_000_001);
        assertFalse(registry.isActive(anchorId), "should be inactive after expiry");
    }

    function test_isActive_falseWhenManuallyDeactivated() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "retired");

        assertFalse(registry.isActive(anchorId), "should be inactive after manual deactivation");
    }

    function test_isActive_restoredAfterReattest() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.warp(1_000_001);
        assertFalse(registry.isActive(anchorId), "should be inactive after expiry");

        vm.prank(registrar);
        registry.reattest(anchorId, 3_000_000, uint64(1_000_001));
        assertTrue(registry.isActive(anchorId), "should be active after re-attestation");
    }

    function test_isActive_manualDeactivationBlocksReattest() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "retired");

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: manually deactivated");
        registry.reattest(anchorId, 3_000_000, uint64(500_000));
    }

    // ─── getMetadata ──────────────────────────────────────────────────

    function test_getMetadata_returnsDecodedFields() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        AnchorMetadataLib.AnchorMetadata memory meta = registry.getMetadata(anchorId);
        assertEq(meta.assetClass,      bytes32("EQUITY"),     "assetClass mismatch");
        assertEq(meta.jurisdiction,    bytes32("US"),         "jurisdiction mismatch");
        assertEq(meta.attestationDate, uint64(1),              "attestationDate mismatch");
        assertEq(meta.expiresAt,       uint64(2_000_000),     "expiresAt mismatch");
        assertEq(meta.uri,             bytes("ipfs://QmFoo"), "uri mismatch");
    }

    function test_getMetadata_revertsNotFound() public {
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.getMetadata(keccak256("nonexistent"));
    }
}
