// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {IDocumentBundleAnchor} from "../src/interfaces/IDocumentBundleAnchor.sol";

/// @dev Medusa fuzz harness for DocumentBundleAnchor.
///      Run: medusa fuzz (from packages/eip-3-document-bundle)
///
///      Invariants checked after every call sequence:
///        property_anchoredBundleIsRetrieval
///        property_activeSlotsRemainPerSubjectRole
///        property_supersededRecordStaysSuperseded
contract DocumentBundleAnchorFuzzTest {
    DocumentBundleAnchor internal anchor;

    bytes32[] internal bundles;
    bytes32[] internal subjects;
    bytes32[] internal roles;

    struct AnchoredEntry {
        bytes32 bundle;
        bytes32 subject;
        bytes32 role;
    }

    AnchoredEntry[]              internal anchoredEntries;
    mapping(bytes32 => bool)     internal wasAnchored;
    mapping(bytes32 => bool)     internal wasSuperseded;
    mapping(bytes32 => bytes32)  internal activeSlotOf;

    constructor() {
        // Deploy with address(this) as admin so the harness can call grantRole.
        anchor = new DocumentBundleAnchor(address(this));
        bytes32 anchorRole = anchor.ANCHOR_ROLE();
        bytes32 adminRole  = anchor.DEFAULT_ADMIN_ROLE();
        // Grant ANCHOR_ROLE + DEFAULT_ADMIN_ROLE to all Medusa sender addresses.
        anchor.grantRole(anchorRole, address(0x10000));
        anchor.grantRole(anchorRole, address(0x20000));
        anchor.grantRole(anchorRole, address(0x30000));
        anchor.grantRole(adminRole,  address(0x10000));
        anchor.grantRole(adminRole,  address(0x20000));
        anchor.grantRole(adminRole,  address(0x30000));

        bundles.push(keccak256("bundle-A"));
        bundles.push(keccak256("bundle-B"));
        bundles.push(keccak256("bundle-C"));
        bundles.push(keccak256("bundle-D"));

        subjects.push(keccak256("subject-1"));
        subjects.push(keccak256("subject-2"));

        roles.push(keccak256("LEGAL_BASIS"));
        roles.push(keccak256("EVIDENCE"));
    }

    // ── State-mutating functions Medusa calls randomly ──────────────────

    function fuzz_anchorBundle(uint256 bIdx, uint256 sIdx, uint256 rIdx, uint256 docCount) external {
        bytes32 bundleHash = bundles[bIdx % bundles.length];
        bytes32 subjectId  = subjects[sIdx % subjects.length];
        bytes32 roleId     = roles[rIdx % roles.length];
        if (docCount == 0 || docCount > 100) return;

        if (wasAnchored[bundleHash]) return;

        bytes32 sk = _sk(subjectId, roleId);
        if (activeSlotOf[sk] != bytes32(0)) return;

        try anchor.anchorBundle(bundleHash, subjectId, roleId, docCount, "uri") {
            anchoredEntries.push(AnchoredEntry(bundleHash, subjectId, roleId));
            wasAnchored[bundleHash] = true;
            activeSlotOf[sk]        = bundleHash;
        } catch {}
    }

    function fuzz_supersedeBundle(uint256 eIdx, uint256 newBIdx, uint256 docCount) external {
        if (anchoredEntries.length == 0) return;
        AnchoredEntry memory e = anchoredEntries[eIdx % anchoredEntries.length];
        if (wasSuperseded[e.bundle]) return;

        bytes32 newBundle = bundles[newBIdx % bundles.length];
        if (newBundle == e.bundle) return;
        if (docCount == 0 || docCount > 100) return;
        if (wasAnchored[newBundle]) return;

        try anchor.supersedeBundle(e.bundle, newBundle, e.subject, e.role, docCount, "uri") {
            wasSuperseded[e.bundle] = true;
            activeSlotOf[_sk(e.subject, e.role)] = newBundle;
            anchoredEntries.push(AnchoredEntry(newBundle, e.subject, e.role));
            wasAnchored[newBundle] = true;
        } catch {}
    }

    // ── property_ functions — return false to signal failure ───────────

    /// Every bundle recorded in our tracking is retrievable via isAnchored.
    function property_anchoredBundleIsRetrieval() external view returns (bool) {
        for (uint256 i = 0; i < anchoredEntries.length; i++) {
            bytes32 b = anchoredEntries[i].bundle;
            if (!anchor.isAnchored(b)) return false;
        }
        return true;
    }

    /// activeBundle(subjectId, role) always matches our tracked active slot.
    function property_activeSlotsRemainPerSubjectRole() external view returns (bool) {
        for (uint256 i = 0; i < anchoredEntries.length; i++) {
            AnchoredEntry memory e = anchoredEntries[i];
            bytes32 sk = _sk(e.subject, e.role);
            bytes32 expected = activeSlotOf[sk];
            if (expected == bytes32(0)) continue;
            if (anchor.activeBundle(e.subject, e.role) != expected) return false;
        }
        return true;
    }

    /// Once superseded in our tracking, the on-chain record's superseded flag is set.
    function property_supersededRecordStaysSuperseded() external view returns (bool) {
        for (uint256 i = 0; i < anchoredEntries.length; i++) {
            bytes32 b = anchoredEntries[i].bundle;
            if (!wasSuperseded[b]) continue;
            IDocumentBundleAnchor.AnchorRecord memory rec = anchor.getAnchor(b);
            if (!rec.superseded) return false;
        }
        return true;
    }

    // ── helpers ─────────────────────────────────────────────────────────

    function _sk(bytes32 subjectId, bytes32 role) internal pure returns (bytes32) {
        return keccak256(abi.encode(subjectId, role));
    }
}
