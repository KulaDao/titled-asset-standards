// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {AssetRegistryConstants} from "../src/libraries/AssetRegistryConstants.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";

/// @dev Drives all registry state transitions for the invariant fuzzer.
contract RegistryHandler is Test {
    AssetAnchorRegistry public registry;

    address public admin = address(0xA0);
    address public registrar = address(0xA1);

    bytes32[] public anchorIds;
    address[] public tokens;

    mapping(bytes32 => address) public boundTokenOf;
    mapping(bytes32 => bytes32) public boundBindingScopeOf;
    mapping(bytes32 => uint256) public boundTokenIdOf;
    mapping(bytes32 => bytes32) public legalHashOf;
    mapping(bytes32 => bytes32) public evidenceHashOf;
    mapping(bytes32 => bool) public wasDeactivated;

    mapping(bytes32 => bytes32) public anchorByTokenBinding;

    bytes32 internal constant ASSET_CLASS_EQUITY = keccak256("ERC-XXXX:ASSET_CLASS:EQUITY");
    bytes32 internal constant JURISDICTION_US = keccak256("ERC-XXXX:JURISDICTION:US");
    bytes32 internal constant SCOPE_CONTRACT = AssetRegistryConstants.BINDING_SCOPE_CONTRACT;
    bytes32 internal constant SCOPE_TOKEN_ID = AssetRegistryConstants.BINDING_SCOPE_TOKEN_ID;

    uint64 internal _ts = 1_000;

    constructor() {
        registry = new AssetAnchorRegistry(admin);
        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.grantRole(registrarRole, registrar);

        tokens.push(address(0xC1));
        tokens.push(address(0xC2));
        tokens.push(address(0xC3));
    }

    function _metadata(uint64 expiry) internal view returns (bytes memory) {
        return AnchorMetadataLib.encode(
            AnchorMetadataLib.AnchorMetadata({
                assetClass: ASSET_CLASS_EQUITY,
                jurisdiction: JURISDICTION_US,
                attestationDate: uint64(block.timestamp),
                expiresAt: expiry,
                uri: bytes("ipfs://Qm"),
                extensions: bytes("")
            })
        );
    }

    function advanceTime(uint64 delta) external {
        delta = uint64(bound(delta, 1, 30 days));
        _ts += delta;
        vm.warp(_ts);
    }

    function registerAnchor(bytes32 legal, bytes32 evidence) external {
        if (legal == bytes32(0) || evidence == bytes32(0)) return;
        bytes32 id = keccak256(abi.encode(legal, evidence));
        if (legalHashOf[id] != bytes32(0)) return;

        vm.warp(_ts);
        uint64 expiry = _ts + 365 days;
        vm.prank(registrar);
        try registry.registerAnchor(legal, evidence, _metadata(expiry)) returns (bytes32 anchorId) {
            anchorIds.push(anchorId);
            legalHashOf[anchorId] = legal;
            evidenceHashOf[anchorId] = evidence;
        } catch {}
    }

    function bindToken(uint256 anchorIdx, uint256 tokenIdx, uint256 bindingScopeIndex, uint256 tokenId) external {
        if (anchorIds.length == 0) return;
        anchorIdx = bound(anchorIdx, 0, anchorIds.length - 1);
        tokenIdx = bound(tokenIdx, 0, tokens.length - 1);
        tokenId = bound(tokenId, 0, 3);

        bytes32 anchorId = anchorIds[anchorIdx];
        address tok = tokens[tokenIdx];
        bytes32 scope = bindingScopeIndex % 2 == 0 ? SCOPE_CONTRACT : SCOPE_TOKEN_ID;
        if (scope == SCOPE_CONTRACT) tokenId = 0;

        if (boundTokenOf[anchorId] != address(0)) return;

        vm.prank(registrar);
        try registry.bindToken(anchorId, tok, scope, tokenId) {
            boundTokenOf[anchorId] = tok;
            boundBindingScopeOf[anchorId] = scope;
            boundTokenIdOf[anchorId] = tokenId;

            bytes32 bindingKey = keccak256(abi.encode(tok, scope, tokenId));
            anchorByTokenBinding[bindingKey] = anchorId;
        } catch {}
    }

    function deactivateAnchor(uint256 anchorIdx) external {
        if (anchorIds.length == 0) return;
        anchorIdx = bound(anchorIdx, 0, anchorIds.length - 1);
        bytes32 anchorId = anchorIds[anchorIdx];

        vm.prank(admin);
        try registry.deactivateAnchor(anchorId, "invariant-test") {
            wasDeactivated[anchorId] = true;
        } catch {}
    }

    function reattest(uint256 anchorIdx, uint64 extraDays) external {
        if (anchorIds.length == 0) return;
        anchorIdx = bound(anchorIdx, 0, anchorIds.length - 1);
        extraDays = uint64(bound(extraDays, 1, 365));

        bytes32 anchorId = anchorIds[anchorIdx];
        uint64 newExpiry = _ts + extraDays * 1 days;

        vm.prank(registrar);
        try registry.reattest(anchorId, newExpiry, uint64(_ts)) {} catch {}
    }

    function anchorCount() external view returns (uint256) {
        return anchorIds.length;
    }
}

contract AssetAnchorRegistryInvariantTest is Test {
    RegistryHandler handler;

    function setUp() public {
        handler = new RegistryHandler();
        targetContract(address(handler));
    }

    /// Each (token, bindingScope, tokenId) maps to at most one anchorId in this registry.
    function invariant_tokenBindingBoundToAtMostOneAnchor() public view {
        AssetAnchorRegistry registry = handler.registry();
        uint256 n = handler.anchorCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 ai = handler.anchorIds(i);
            address bt = handler.boundTokenOf(ai);
            if (bt == address(0)) continue;

            uint256 bid = handler.boundTokenIdOf(ai);
            bytes32 scope = handler.boundBindingScopeOf(ai);
            bytes32 bindingKey = keccak256(abi.encode(bt, scope, bid));

            bytes32 recorded = handler.anchorByTokenBinding(bindingKey);
            assertEq(recorded, ai, "token binding maps to unexpected anchor");

            // Confirm registry record agrees
            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            assertEq(rec.boundToken, bt, "registry boundToken mismatch");
            assertEq(rec.bindingScope, scope, "registry bindingScope mismatch");
            assertEq(rec.boundTokenId, bid, "registry boundTokenId mismatch");
        }
    }

    /// Once an anchor is bound, its binding fields never change.
    function invariant_bindingIsImmutable() public view {
        AssetAnchorRegistry registry = handler.registry();
        uint256 n = handler.anchorCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 ai = handler.anchorIds(i);
            address expected = handler.boundTokenOf(ai);
            if (expected == address(0)) continue;

            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            assertEq(rec.boundToken, expected, "boundToken mutated");
            assertEq(rec.bindingScope, handler.boundBindingScopeOf(ai), "bindingScope mutated");
            assertEq(rec.boundTokenId, handler.boundTokenIdOf(ai), "boundTokenId mutated");
        }
    }

    /// Manually deactivated anchors cannot become active again.
    function invariant_deactivatedAnchorStaysDeactivated() public view {
        AssetAnchorRegistry registry = handler.registry();
        uint256 n = handler.anchorCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 ai = handler.anchorIds(i);
            if (!handler.wasDeactivated(ai)) continue;

            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            assertFalse(rec.active, "deactivated anchor became active");
            assertFalse(registry.isActive(ai), "isActive true for deactivated anchor");
        }
    }

    /// Re-attestation never mutates legalHash, evidenceHash, or binding fields.
    function invariant_reattestDoesNotMutateImmutableFields() public view {
        AssetAnchorRegistry registry = handler.registry();
        uint256 n = handler.anchorCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 ai = handler.anchorIds(i);
            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);

            assertEq(rec.legalHash, handler.legalHashOf(ai), "legalHash mutated");
            assertEq(rec.evidenceHash, handler.evidenceHashOf(ai), "evidenceHash mutated");

            address expectedToken = handler.boundTokenOf(ai);
            if (expectedToken != address(0)) {
                assertEq(rec.boundToken, expectedToken, "boundToken mutated by reattest");
                assertEq(rec.bindingScope, handler.boundBindingScopeOf(ai), "bindingScope mutated by reattest");
                assertEq(rec.boundTokenId, handler.boundTokenIdOf(ai), "boundTokenId mutated by reattest");
            }
        }
    }
}
