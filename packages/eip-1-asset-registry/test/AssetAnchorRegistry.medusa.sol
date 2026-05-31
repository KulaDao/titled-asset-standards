// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";

/// @dev Medusa fuzz harness for AssetAnchorRegistry.
///      Run: medusa fuzz (from packages/eip-1-asset-registry)
///
///      Invariants checked after every call sequence:
///        property_tokenPairBoundToAtMostOneAnchor
///        property_bindingIsImmutable
///        property_deactivatedAnchorStaysDeactivated
///        property_reattestDoesNotMutateImmutableFields
contract AssetAnchorRegistryFuzzTest {
    AssetAnchorRegistry internal registry;

    address internal admin     = address(0x10000);
    address internal registrar = address(0x20000);

    bytes32[] internal anchorIds;

    mapping(bytes32 => address)  internal boundTokenOf;
    mapping(bytes32 => uint256)  internal boundTokenIdOf;
    mapping(bytes32 => bytes32)  internal legalHashOf;
    mapping(bytes32 => bytes32)  internal evidenceHashOf;
    mapping(bytes32 => bool)     internal wasDeactivated;
    mapping(bytes32 => bytes32)  internal anchorByTokenPair;

    address[] internal tokens;
    uint64    internal _ts = 1_000;

    constructor() {
        // Deploy with address(this) as admin so the harness itself holds
        // DEFAULT_ADMIN_ROLE and REGISTRAR_ROLE and can call all registry functions.
        registry = new AssetAnchorRegistry(address(this));

        tokens.push(address(0xC001));
        tokens.push(address(0xC002));
        tokens.push(address(0xC003));
    }

    // ── State-mutating functions Medusa will call randomly ──────────────

    function fuzz_advanceTime(uint64 delta) external {
        if (delta == 0 || delta > 30 days) return;
        _ts += delta;
    }

    function fuzz_registerAnchor(bytes32 legal, bytes32 evidence) external {
        if (legal == bytes32(0) || evidence == bytes32(0)) return;
        bytes32 id = keccak256(abi.encode(legal, evidence));
        if (legalHashOf[id] != bytes32(0)) return;

        uint64 expiry = _ts + 365 days;
        bytes memory meta = _metadata(expiry);

        try registry.registerAnchor{gas: 500_000}(legal, evidence, meta) returns (bytes32 anchorId) {
            anchorIds.push(anchorId);
            legalHashOf[anchorId]    = legal;
            evidenceHashOf[anchorId] = evidence;
        } catch {}
    }

    function fuzz_bindToken(uint256 anchorIdx, uint256 tokenIdx, uint256 tokenId) external {
        if (anchorIds.length == 0) return;
        anchorIdx = anchorIdx % anchorIds.length;
        tokenIdx  = tokenIdx  % tokens.length;
        tokenId   = tokenId   % 4;

        bytes32 anchorId = anchorIds[anchorIdx];
        address tok      = tokens[tokenIdx];

        if (boundTokenOf[anchorId] != address(0)) return;

        try registry.bindToken{gas: 300_000}(anchorId, tok, tokenId) {
            boundTokenOf[anchorId]   = tok;
            boundTokenIdOf[anchorId] = tokenId;
            anchorByTokenPair[keccak256(abi.encode(tok, tokenId))] = anchorId;
        } catch {}
    }

    function fuzz_deactivateAnchor(uint256 anchorIdx) external {
        if (anchorIds.length == 0) return;
        bytes32 anchorId = anchorIds[anchorIdx % anchorIds.length];

        try registry.deactivateAnchor{gas: 100_000}(anchorId, "fuzz") {
            wasDeactivated[anchorId] = true;
        } catch {}
    }

    function fuzz_reattest(uint256 anchorIdx, uint64 extraDays) external {
        if (anchorIds.length == 0) return;
        if (extraDays == 0) extraDays = 1;
        if (extraDays > 365) extraDays = 365;
        bytes32 anchorId = anchorIds[anchorIdx % anchorIds.length];
        uint64 newExpiry = _ts + extraDays * 1 days;
        try registry.reattest{gas: 100_000}(anchorId, newExpiry, _ts) {} catch {}
    }

    // ── property_ functions — return false to signal failure ───────────

    /// Each (token, tokenId) pair maps to at most one anchorId.
    function property_tokenPairBoundToAtMostOneAnchor() external view returns (bool) {
        for (uint256 i = 0; i < anchorIds.length; i++) {
            bytes32 ai  = anchorIds[i];
            address bt  = boundTokenOf[ai];
            if (bt == address(0)) continue;

            uint256 bid  = boundTokenIdOf[ai];
            bytes32 pair = keccak256(abi.encode(bt, bid));
            if (anchorByTokenPair[pair] != ai) return false;

            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            if (rec.boundToken != bt || rec.boundTokenId != bid) return false;
        }
        return true;
    }

    /// Once bound, boundToken and boundTokenId never change.
    function property_bindingIsImmutable() external view returns (bool) {
        for (uint256 i = 0; i < anchorIds.length; i++) {
            bytes32 ai = anchorIds[i];
            if (boundTokenOf[ai] == address(0)) continue;

            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            if (rec.boundToken   != boundTokenOf[ai])    return false;
            if (rec.boundTokenId != boundTokenIdOf[ai])  return false;
        }
        return true;
    }

    /// Manually deactivated anchors stay deactivated and isActive returns false.
    function property_deactivatedAnchorStaysDeactivated() external view returns (bool) {
        for (uint256 i = 0; i < anchorIds.length; i++) {
            bytes32 ai = anchorIds[i];
            if (!wasDeactivated[ai]) continue;

            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            if (rec.active)              return false;
            if (registry.isActive(ai))   return false;
        }
        return true;
    }

    /// Re-attestation never mutates legalHash, evidenceHash, or binding fields.
    function property_reattestDoesNotMutateImmutableFields() external view returns (bool) {
        for (uint256 i = 0; i < anchorIds.length; i++) {
            bytes32 ai  = anchorIds[i];
            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);

            if (rec.legalHash    != legalHashOf[ai])    return false;
            if (rec.evidenceHash != evidenceHashOf[ai]) return false;

            if (boundTokenOf[ai] != address(0)) {
                if (rec.boundToken   != boundTokenOf[ai])   return false;
                if (rec.boundTokenId != boundTokenIdOf[ai]) return false;
            }
        }
        return true;
    }

    // ── helpers ─────────────────────────────────────────────────────────

    function _metadata(uint64 expiry) internal view returns (bytes memory) {
        return AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("EQUITY"),
            jurisdiction:    bytes32("US"),
            attestationDate: uint64(block.timestamp > 0 ? block.timestamp : 1),
            expiresAt:       expiry,
            uri:             bytes("ipfs://Qm"),
            extensions:      bytes("")
        }));
    }
}
