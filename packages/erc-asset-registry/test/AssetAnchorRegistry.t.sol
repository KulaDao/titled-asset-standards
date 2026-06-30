// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {
    IAssetAnchorRegistry,
    IAssetAnchorRegistryLifecycle,
    IAssetAnchorRegistryRecovery
} from "../src/interfaces/IAssetAnchorRegistry.sol";
import {AssetRegistryConstants} from "../src/libraries/AssetRegistryConstants.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";

contract MockPlainToken {}

contract MockBoundToken {
    address public anchorRegistry;

    constructor(address registry) {
        anchorRegistry = registry;
    }
}

contract MockEmptyAnchorRegistryReturn {
    fallback(bytes calldata) external returns (bytes memory) {
        return bytes("");
    }
}

contract MockMalformedAnchorRegistryReturn {
    fallback(bytes calldata) external returns (bytes memory) {
        return hex"1234";
    }
}

contract MockTrailingAnchorRegistryReturn {
    address private immutable _registry;

    constructor(address registry) {
        _registry = registry;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        return abi.encode(_registry, uint256(1));
    }
}

contract AssetAnchorRegistryTest is Test {
    event AnchorRegistered(bytes32 indexed anchorId, bytes32 legalHash, bytes32 evidenceHash);
    event TokenBound(bytes32 indexed anchorId, address indexed token, bytes32 indexed bindingScope, uint256 tokenId);
    event TokenBindingInvalidated(
        bytes32 indexed anchorId,
        address indexed token,
        bytes32 indexed bindingScope,
        uint256 tokenId,
        bytes32 reasonHash
    );
    event AnchorDeactivated(bytes32 indexed anchorId, string reason);
    event AnchorReattested(
        bytes32 indexed anchorId, uint64 oldExpiresAt, uint64 newExpiresAt, uint64 newAttestationDate
    );

    AssetAnchorRegistry registry;

    address admin = address(0xA0);
    address registrar = address(0xA1);
    address other = address(0xA2);
    address token;

    bytes32 constant LEGAL_HASH = keccak256("legal-doc-1");
    bytes32 constant EVIDENCE_HASH = keccak256("evidence-doc-1");
    bytes32 constant LEGAL_HASH_2 = keccak256("legal-doc-2");
    bytes32 constant EVIDENCE_HASH_2 = keccak256("evidence-doc-2");
    bytes32 constant ASSET_CLASS_EQUITY = keccak256("ERC-XXXX:ASSET_CLASS:EQUITY");
    bytes32 constant JURISDICTION_US = keccak256("ERC-XXXX:JURISDICTION:US");
    bytes32 constant SCOPE_CONTRACT = AssetRegistryConstants.BINDING_SCOPE_CONTRACT;
    bytes32 constant SCOPE_TOKEN_ID = AssetRegistryConstants.BINDING_SCOPE_TOKEN_ID;

    function setUp() public {
        registry = new AssetAnchorRegistry(admin);
        token = address(new MockPlainToken());
        vm.startPrank(admin);
        registry.grantRole(registry.REGISTRAR_ROLE(), registrar);
        vm.stopPrank();
    }

    function _validMetadata(uint64 expiresAt) internal pure returns (bytes memory) {
        return AnchorMetadataLib.encode(
            AnchorMetadataLib.AnchorMetadata({
                assetClass: ASSET_CLASS_EQUITY,
                jurisdiction: JURISDICTION_US,
                attestationDate: uint64(1),
                expiresAt: expiresAt,
                uri: bytes("ipfs://QmFoo"),
                extensions: bytes("")
            })
        );
    }

    // ─── registerAnchor ───────────────────────────────────────────────

    function test_registerAnchor_storesAllFields() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        bytes32 expectedId = keccak256(abi.encode(LEGAL_HASH, EVIDENCE_HASH));
        assertEq(anchorId, expectedId, "anchorId derivation mismatch");

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.anchorId, anchorId, "rec.anchorId mismatch");
        assertEq(rec.legalHash, LEGAL_HASH, "rec.legalHash mismatch");
        assertEq(rec.evidenceHash, EVIDENCE_HASH, "rec.evidenceHash mismatch");
        assertEq(rec.boundToken, address(0), "should be unbound");
        assertEq(rec.bindingScope, bytes32(0), "bindingScope should be unset");
        assertEq(rec.boundTokenId, 0, "boundTokenId should be 0");
        assertEq(rec.registeredAt, uint64(500_000), "registeredAt mismatch");
        assertTrue(rec.active, "active should be true");
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
        bytes memory badMeta = AnchorMetadataLib.encode(
            AnchorMetadataLib.AnchorMetadata({
                assetClass: bytes32(0),
                jurisdiction: JURISDICTION_US,
                attestationDate: uint64(1_000_000),
                expiresAt: uint64(2_000_000),
                uri: bytes("ipfs://QmFoo"),
                extensions: bytes("")
            })
        );
        vm.prank(registrar);
        vm.expectRevert("AnchorMetadataLib: missing assetClass");
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, badMeta);
    }

    function test_registerAnchor_revertsFutureAttestationDate() public {
        bytes memory meta = AnchorMetadataLib.encode(
            AnchorMetadataLib.AnchorMetadata({
                assetClass: ASSET_CLASS_EQUITY,
                jurisdiction: JURISDICTION_US,
                attestationDate: uint64(1_000_000),
                expiresAt: uint64(2_000_000),
                uri: bytes("ipfs://QmFoo"),
                extensions: bytes("")
            })
        );
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: future attestation date");
        registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, meta);
    }

    function test_registerAnchor_revertsExpiresAtNotAfterAttestationDate() public {
        vm.warp(1_000_000);
        bytes memory meta = AnchorMetadataLib.encode(
            AnchorMetadataLib.AnchorMetadata({
                assetClass: ASSET_CLASS_EQUITY,
                jurisdiction: JURISDICTION_US,
                attestationDate: uint64(1_000_000),
                expiresAt: uint64(1_000_000),
                uri: bytes("ipfs://QmFoo"),
                extensions: bytes("")
            })
        );
        vm.prank(registrar);
        vm.expectRevert("AnchorMetadataLib: expiresAt not after attestationDate");
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

        vm.prank(registrar);
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.boundToken, token, "boundToken mismatch");
        assertEq(rec.bindingScope, SCOPE_CONTRACT, "bindingScope mismatch");
        assertEq(rec.boundTokenId, 0, "boundTokenId mismatch");
    }

    function test_bindToken_succeeds_by_admin() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(admin);
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);

        assertEq(registry.getAnchor(anchorId).boundToken, token, "admin bind failed");
    }

    function test_bindToken_revertsRegistryMismatch() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address wrongToken = address(new MockBoundToken(address(0xDEAD)));
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token registry mismatch");
        registry.bindToken(anchorId, wrongToken, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_allowsPlainTokenWithoutAnchorRegistry() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);
        assertEq(registry.getAnchor(anchorId).boundToken, token);
    }

    function test_bindToken_allowsCompliantTokenPointingToThisRegistry() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address compliantToken = address(new MockBoundToken(address(registry)));
        vm.prank(registrar);
        registry.bindToken(anchorId, compliantToken, SCOPE_CONTRACT, 0);
        assertEq(registry.getAnchor(anchorId).boundToken, compliantToken);
    }

    function test_bindToken_acceptsCompliantTokenWithTrailingReturnData() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address compliantToken = address(new MockTrailingAnchorRegistryReturn(address(registry)));
        vm.prank(registrar);
        registry.bindToken(anchorId, compliantToken, SCOPE_CONTRACT, 0);
        assertEq(registry.getAnchor(anchorId).boundToken, compliantToken);
    }

    function test_bindToken_revertsMalformedAnchorRegistryReturnData() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address malformedToken = address(new MockMalformedAnchorRegistryReturn());
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token registry mismatch");
        registry.bindToken(anchorId, malformedToken, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_revertsSuccessfulEmptyAnchorRegistryReturnData() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        address emptyReturnToken = address(new MockEmptyAnchorRegistryReturn());
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token registry mismatch");
        registry.bindToken(anchorId, emptyReturnToken, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_emitsTokenBound() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.expectEmit(true, true, true, true);
        emit TokenBound(anchorId, token, SCOPE_TOKEN_ID, 42);
        vm.prank(registrar);
        registry.bindToken(anchorId, token, SCOPE_TOKEN_ID, 42);
    }

    function test_bindToken_allowsTokenIdZeroAsTokenSpecificBinding() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        registry.bindToken(anchorId, token, SCOPE_TOKEN_ID, 0);

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.boundToken, token, "boundToken mismatch");
        assertEq(rec.bindingScope, SCOPE_TOKEN_ID, "bindingScope mismatch");
        assertEq(rec.boundTokenId, 0, "token ID 0 must remain valid for token-scope binding");
    }

    function test_bindToken_scopeSeparatesContractBindingFromTokenIdZero() public {
        vm.prank(registrar);
        bytes32 tokenScopeAnchor = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(tokenScopeAnchor, token, SCOPE_TOKEN_ID, 0);

        vm.prank(registrar);
        bytes32 contractScopeAnchor = registry.registerAnchor(LEGAL_HASH_2, EVIDENCE_HASH_2, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(contractScopeAnchor, token, SCOPE_CONTRACT, 0);

        IAssetAnchorRegistry.AnchorRecord memory tokenScope = registry.getAnchor(tokenScopeAnchor);
        IAssetAnchorRegistry.AnchorRecord memory contractScope = registry.getAnchor(contractScopeAnchor);
        assertEq(tokenScope.bindingScope, SCOPE_TOKEN_ID, "token scope mismatch");
        assertEq(contractScope.bindingScope, SCOPE_CONTRACT, "contract scope mismatch");
        assertEq(tokenScope.boundTokenId, 0, "token ID 0 should be token-specific");
        assertEq(contractScope.boundTokenId, 0, "contract scope should use canonical zero tokenId");
    }

    function test_bindToken_revertsContractScopeWithNonzeroTokenId() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: contract scope tokenId must be 0");
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 1);
    }

    function test_bindToken_revertsInvalidBindingScope() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: invalid binding scope");
        registry.bindToken(anchorId, token, keccak256("BAD_SCOPE"), 0);
    }

    function test_bindToken_revertsUnauthorized() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(other);
        vm.expectRevert("AssetAnchorRegistry: not authorized to bind");
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_revertsIfOriginalRegistrarRoleRevoked() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.revokeRole(registrarRole, registrar);

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: not authorized to bind");
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_revertsAnchorNotFound() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.bindToken(keccak256("nonexistent"), token, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_revertsAlreadyBound() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);

        vm.prank(admin);
        vm.expectRevert("AssetAnchorRegistry: already bound");
        registry.bindToken(anchorId, address(0xC0), SCOPE_CONTRACT, 0);
    }

    function test_bindToken_revertsZeroAddress() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero token address");
        registry.bindToken(anchorId, address(0), SCOPE_CONTRACT, 0);
    }

    function test_bindToken_revertsTokenBindingAlreadyBound() public {
        vm.prank(registrar);
        bytes32 anchorId1 = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(anchorId1, token, SCOPE_TOKEN_ID, 42);

        vm.prank(registrar);
        bytes32 anchorId2 =
            registry.registerAnchor(keccak256("other-legal"), keccak256("other-evidence"), _validMetadata(2_000_000));
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token binding already bound");
        registry.bindToken(anchorId2, token, SCOPE_TOKEN_ID, 42);
    }

    function test_registerAndBind_revertsTokenBindingAlreadyBound() public {
        vm.warp(500_000);
        vm.prank(registrar);
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), token, SCOPE_TOKEN_ID, 7);

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: token binding already bound");
        registry.registerAndBind(
            keccak256("other-legal"), keccak256("other-evidence"), _validMetadata(2_000_000), token, SCOPE_TOKEN_ID, 7
        );
    }

    function test_bindToken_revertsAnchorInactive() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "test");

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor inactive");
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_revertsAnchorExpired() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.warp(2_000_001);
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: anchor expired");
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);
    }

    function test_bindToken_succeedsAtExpiryBoundary() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.warp(2_000_000);
        vm.prank(registrar);
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);

        assertEq(registry.getAnchor(anchorId).boundToken, token, "anchor should remain bindable at expiresAt");
    }

    function test_registerAndBind_revertsAnchorExpired() public {
        vm.warp(3_000_000);
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: metadata already expired");
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), token, SCOPE_CONTRACT, 0);
    }

    // ─── registerAndBind ──────────────────────────────────────────────

    function test_registerAndBind_storesAll() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId =
            registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), token, SCOPE_TOKEN_ID, 7);

        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId);
        assertEq(rec.boundToken, token, "boundToken mismatch");
        assertEq(rec.bindingScope, SCOPE_TOKEN_ID, "bindingScope mismatch");
        assertEq(rec.boundTokenId, 7, "boundTokenId mismatch");
        assertTrue(rec.active, "active should be true");
    }

    function test_registerAndBind_emitsBothEvents() public {
        bytes32 expectedId = keccak256(abi.encode(LEGAL_HASH, EVIDENCE_HASH));

        vm.expectEmit(true, false, false, true);
        emit AnchorRegistered(expectedId, LEGAL_HASH, EVIDENCE_HASH);

        vm.expectEmit(true, true, true, true);
        emit TokenBound(expectedId, token, SCOPE_CONTRACT, 0);

        vm.prank(registrar);
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), token, SCOPE_CONTRACT, 0);
    }

    function test_registerAndBind_revertsZeroToken() public {
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: zero token address");
        registry.registerAndBind(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000), address(0), SCOPE_CONTRACT, 0);
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
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);
        assertTrue(registry.isBound(anchorId), "should be bound");
    }

    function test_isBound_revertsNotFound() public {
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.isBound(keccak256("nonexistent"));
    }

    // ─── isBound after deactivation ───────────────────────────────────

    function test_isBound_trueAfterDeactivation() public {
        vm.startPrank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);
        vm.stopPrank();

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "retired");

        assertTrue(registry.isBound(anchorId), "isBound must remain true after deactivation");
    }

    // ─── binding recovery ─────────────────────────────────────────────

    function test_invalidateTokenBindingPreservesHistoryAndFreesSlot() public {
        bytes32 reasonHash = keccak256("registrar binding-key squatting");

        vm.prank(registrar);
        bytes32 squattedAnchor = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(squattedAnchor, token, SCOPE_TOKEN_ID, 42);

        vm.expectEmit(true, false, false, true);
        emit AnchorDeactivated(squattedAnchor, "binding invalidated");
        vm.expectEmit(true, true, true, true);
        emit TokenBindingInvalidated(squattedAnchor, token, SCOPE_TOKEN_ID, 42, reasonHash);
        vm.prank(admin);
        registry.invalidateTokenBinding(squattedAnchor, reasonHash);

        IAssetAnchorRegistry.AnchorRecord memory historical = registry.getAnchor(squattedAnchor);
        assertEq(historical.boundToken, token, "historical token changed");
        assertEq(historical.bindingScope, SCOPE_TOKEN_ID, "historical scope changed");
        assertEq(historical.boundTokenId, 42, "historical tokenId changed");
        assertFalse(historical.active, "invalidated anchor remains active");
        assertTrue(registry.isBound(squattedAnchor), "historical binding must remain queryable");
        assertFalse(registry.isBindingValid(squattedAnchor), "invalidated binding reported valid");

        address otherToken = address(new MockPlainToken());
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: already bound");
        registry.bindToken(squattedAnchor, otherToken, SCOPE_CONTRACT, 0);

        vm.prank(registrar);
        bytes32 replacementAnchor = registry.registerAnchor(LEGAL_HASH_2, EVIDENCE_HASH_2, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(replacementAnchor, token, SCOPE_TOKEN_ID, 42);

        assertTrue(registry.isBindingValid(replacementAnchor), "replacement binding not valid");
        assertEq(registry.getAnchor(replacementAnchor).boundToken, token, "replacement token mismatch");
    }

    function test_invalidateTokenBindingRejectsUnauthorizedAndInvalidRequests() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));
        vm.prank(registrar);
        registry.bindToken(anchorId, token, SCOPE_CONTRACT, 0);

        vm.prank(other);
        vm.expectRevert();
        registry.invalidateTokenBinding(anchorId, keccak256("unauthorized"));

        vm.prank(admin);
        vm.expectRevert("AssetAnchorRegistry: zero reasonHash");
        registry.invalidateTokenBinding(anchorId, bytes32(0));

        vm.prank(admin);
        registry.invalidateTokenBinding(anchorId, keccak256("invalid"));

        vm.prank(admin);
        vm.expectRevert("AssetAnchorRegistry: binding already invalidated");
        registry.invalidateTokenBinding(anchorId, keccak256("again"));
    }

    // ─── ERC-165 ──────────────────────────────────────────────────────

    function test_supportsInterface_baseLifecycleAndRecovery() public view {
        assertTrue(
            registry.supportsInterface(type(IAssetAnchorRegistry).interfaceId), "missing base registry interface"
        );
        assertTrue(
            registry.supportsInterface(type(IAssetAnchorRegistryLifecycle).interfaceId), "missing lifecycle interface"
        );
        assertTrue(
            registry.supportsInterface(type(IAssetAnchorRegistryRecovery).interfaceId), "missing recovery interface"
        );
        assertFalse(registry.supportsInterface(0xffffffff), "unexpected invalid interface support");
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
        assertEq(meta.expiresAt, 3_000_000, "expiresAt should be updated");
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

    function test_reattest_revertsIfOriginalRegistrarRoleRevoked() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.revokeRole(registrarRole, registrar);

        vm.prank(registrar);
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

    function test_reattest_revertsNewExpiryBeforeCurrent() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(3_000_000));

        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: new expiry before current");
        registry.reattest(anchorId, 2_000_000, uint64(500_000));
    }

    function test_reattest_revertsOlderAttestationDate() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.prank(registrar);
        registry.reattest(anchorId, 2_000_000, uint64(500_000));

        vm.warp(600_000);
        vm.prank(registrar);
        vm.expectRevert("AssetAnchorRegistry: new attestation date before current");
        registry.reattest(anchorId, 3_000_000, uint64(400_000));
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

    function test_isActive_trueAtExpiryBoundary() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(1_000_000));

        vm.warp(1_000_000);
        assertTrue(registry.isActive(anchorId), "expiry boundary should be inclusive");
    }

    function test_isActive_falseWhenManuallyDeactivated() public {
        vm.warp(500_000);
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        vm.prank(admin);
        registry.deactivateAnchor(anchorId, "retired");

        assertFalse(registry.isActive(anchorId), "should be inactive after manual deactivation");
    }

    function test_isActive_revertsNotFound() public {
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.isActive(keccak256("nonexistent"));
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
        assertEq(meta.assetClass, ASSET_CLASS_EQUITY, "assetClass mismatch");
        assertEq(meta.jurisdiction, JURISDICTION_US, "jurisdiction mismatch");
        assertEq(meta.attestationDate, uint64(1), "attestationDate mismatch");
        assertEq(meta.expiresAt, uint64(2_000_000), "expiresAt mismatch");
        assertEq(meta.uri, bytes("ipfs://QmFoo"), "uri mismatch");
    }

    function test_registeredBy_returnsOriginalRegistrar() public {
        vm.prank(registrar);
        bytes32 anchorId = registry.registerAnchor(LEGAL_HASH, EVIDENCE_HASH, _validMetadata(2_000_000));

        assertEq(registry.registeredBy(anchorId), registrar, "registeredBy mismatch");
    }

    function test_registeredBy_revertsNotFound() public {
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.registeredBy(keccak256("nonexistent"));
    }

    function test_getMetadata_revertsNotFound() public {
        vm.expectRevert("AssetAnchorRegistry: anchor not found");
        registry.getMetadata(keccak256("nonexistent"));
    }
}
