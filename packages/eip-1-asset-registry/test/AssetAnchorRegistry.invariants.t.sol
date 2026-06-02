// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";
import {IAssetBoundToken} from "../src/interfaces/IAssetBoundToken.sol";

contract MockInvariantAssetBoundToken is IAssetBoundToken {
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
        require(!_perToken, "MockInvariantAssetBoundToken: per-token binding");
        return _anchorId;
    }

    function anchorIdOf(uint256 tokenId) external view override returns (bytes32) {
        require(_perToken && tokenId == _tokenId, "MockInvariantAssetBoundToken: tokenId not bound");
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

/// @dev Drives all registry state transitions for the invariant fuzzer.
contract RegistryHandler is Test {
    AssetAnchorRegistry public registry;

    address public admin     = address(0xA0);
    address public registrar = address(0xA1);

    bytes32[] public anchorIds;
    mapping(bytes32 => address)  public boundTokenOf;
    mapping(bytes32 => uint256)  public boundTokenIdOf;
    mapping(bytes32 => bytes32)  public legalHashOf;
    mapping(bytes32 => bytes32)  public evidenceHashOf;
    mapping(bytes32 => bool)     public wasDeactivated;

    mapping(bytes32 => bytes32)  public anchorByTokenPair;
    mapping(bytes32 => address)  public tokenForSyntheticPair;

    uint64 internal _ts = 1_000;

    constructor() {
        registry = new AssetAnchorRegistry(admin);
        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.grantRole(registrarRole, registrar);
    }

    function _metadata(uint64 expiry) internal view returns (bytes memory) {
        return AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("EQUITY"),
            jurisdiction:    bytes32("US"),
            attestationDate: uint64(block.timestamp),
            expiresAt:       expiry,
            uri:             bytes("ipfs://Qm"),
            extensions:      bytes("")
        }));
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
            legalHashOf[anchorId]    = legal;
            evidenceHashOf[anchorId] = evidence;
        } catch {}
    }

    function bindToken(uint256 anchorIdx, uint256 tokenIdx, uint256 tokenId) external {
        if (anchorIds.length == 0) return;
        anchorIdx = bound(anchorIdx, 0, anchorIds.length - 1);
        tokenIdx  = bound(tokenIdx,  0, 2);
        tokenId   = bound(tokenId,   0, 3);

        bytes32 anchorId = anchorIds[anchorIdx];

        if (boundTokenOf[anchorId] != address(0)) return;

        bytes32 syntheticPair = keccak256(abi.encode(tokenIdx, tokenId));
        address tok = tokenForSyntheticPair[syntheticPair];
        bool knownPair = tok != address(0);
        if (!knownPair) {
            tok = address(new MockInvariantAssetBoundToken(
                address(registry),
                anchorId,
                tokenId != 0,
                tokenId
            ));
        }

        vm.prank(registrar);
        try registry.bindToken(anchorId, tok, tokenId) {
            if (!knownPair) tokenForSyntheticPair[syntheticPair] = tok;
            boundTokenOf[anchorId]    = tok;
            boundTokenIdOf[anchorId]  = tokenId;

            bytes32 pairKey = keccak256(abi.encode(tok, tokenId));
            anchorByTokenPair[pairKey] = anchorId;
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
        uint64  newExpiry = _ts + extraDays * 1 days;

        vm.prank(registrar);
        try registry.reattest(anchorId, newExpiry, uint64(_ts)) {} catch {}
    }

    function anchorCount() external view returns (uint256) { return anchorIds.length; }
}

contract AssetAnchorRegistryInvariantTest is Test {
    RegistryHandler handler;

    function setUp() public {
        handler = new RegistryHandler();
        targetContract(address(handler));
    }

    /// Each (token, tokenId) pair maps to at most one anchorId in this registry.
    function invariant_tokenPairBoundToAtMostOneAnchor() public view {
        AssetAnchorRegistry registry = handler.registry();
        uint256 n = handler.anchorCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 ai = handler.anchorIds(i);
            address bt = handler.boundTokenOf(ai);
            if (bt == address(0)) continue;

            uint256 bid  = handler.boundTokenIdOf(ai);
            bytes32 pair = keccak256(abi.encode(bt, bid));

            bytes32 recorded = handler.anchorByTokenPair(pair);
            assertEq(recorded, ai, "token pair maps to unexpected anchor");

            // Confirm registry record agrees
            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            assertEq(rec.boundToken,   bt,  "registry boundToken mismatch");
            assertEq(rec.boundTokenId, bid, "registry boundTokenId mismatch");
        }
    }

    /// Once an anchor is bound, its boundToken and boundTokenId never change.
    function invariant_bindingIsImmutable() public view {
        AssetAnchorRegistry registry = handler.registry();
        uint256 n = handler.anchorCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 ai = handler.anchorIds(i);
            address expected = handler.boundTokenOf(ai);
            if (expected == address(0)) continue;

            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);
            assertEq(rec.boundToken,   expected,                  "boundToken mutated");
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
            assertFalse(rec.active,             "deactivated anchor became active");
            assertFalse(registry.isActive(ai),  "isActive true for deactivated anchor");
        }
    }

    /// Re-attestation never mutates legalHash, evidenceHash, or binding fields.
    function invariant_reattestDoesNotMutateImmutableFields() public view {
        AssetAnchorRegistry registry = handler.registry();
        uint256 n = handler.anchorCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 ai = handler.anchorIds(i);
            AssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(ai);

            assertEq(rec.legalHash,    handler.legalHashOf(ai),    "legalHash mutated");
            assertEq(rec.evidenceHash, handler.evidenceHashOf(ai),  "evidenceHash mutated");

            address expectedToken = handler.boundTokenOf(ai);
            if (expectedToken != address(0)) {
                assertEq(rec.boundToken,   expectedToken,                  "boundToken mutated by reattest");
                assertEq(rec.boundTokenId, handler.boundTokenIdOf(ai),     "boundTokenId mutated by reattest");
            }
        }
    }
}
