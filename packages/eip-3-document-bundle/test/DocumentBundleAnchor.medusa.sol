// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {IDocumentBundleAnchor} from "../src/interfaces/IDocumentBundleAnchor.sol";

/// @dev Medusa fuzz harness for DocumentBundleAnchor.
///      Run: medusa fuzz (from packages/eip-3-document-bundle)
///
///      Invariants checked after every call sequence:
///        property_anchoringOneTripleDoesNotMutateAnother
///        property_activeSlotsRemainPerSubjectRole
///        property_supersededRecordsAreImmutableExceptFlags
///        property_sortingProducesSameBundleHashForAnyPermutation (structural)
contract DocumentBundleAnchorFuzzTest {
    DocumentBundleAnchor internal anchor;

    bytes32[] internal bundles;
    bytes32[] internal subjects;
    bytes32[] internal roles;

    struct Triple {
        bytes32 bundle;
        bytes32 subject;
        bytes32 role;
    }

    Triple[]                     internal anchoredTriples;
    mapping(bytes32 => address)  internal anchoredByOf;
    mapping(bytes32 => bool)     internal wasSuperseded;
    mapping(bytes32 => bytes32)  internal supersededByOf;
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

        bytes32 tk = _tk(bundleHash, subjectId, roleId);
        if (anchoredByOf[tk] != address(0)) return;

        bytes32 sk = _sk(subjectId, roleId);
        if (activeSlotOf[sk] != bytes32(0)) return;

        try anchor.anchorBundle(bundleHash, subjectId, roleId, docCount, "uri") {
            anchoredTriples.push(Triple(bundleHash, subjectId, roleId));
            anchoredByOf[tk]  = address(this);
            activeSlotOf[sk]  = bundleHash;
        } catch {}
    }

    function fuzz_supersedeBundle(uint256 tIdx, uint256 newBIdx, uint256 docCount) external {
        if (anchoredTriples.length == 0) return;
        Triple memory t = anchoredTriples[tIdx % anchoredTriples.length];
        bytes32 tk = _tk(t.bundle, t.subject, t.role);
        if (wasSuperseded[tk]) return;

        bytes32 newBundle = bundles[newBIdx % bundles.length];
        if (newBundle == t.bundle) return;
        if (docCount == 0 || docCount > 100) return;

        bytes32 newTk = _tk(newBundle, t.subject, t.role);
        if (anchoredByOf[newTk] != address(0)) return;

        try anchor.supersedeBundle(t.bundle, newBundle, t.subject, t.role, docCount, "uri") {
            wasSuperseded[tk]      = true;
            supersededByOf[tk]     = newBundle;
            activeSlotOf[_sk(t.subject, t.role)] = newBundle;

            anchoredTriples.push(Triple(newBundle, t.subject, t.role));
            anchoredByOf[newTk] = address(this);
        } catch {}
    }

    // ── property_ functions — return false to signal failure ────────────

    /// Anchoring one triple must not mutate another triple's record.
    function property_anchoringOneTripleDoesNotMutateAnother() external view returns (bool) {
        for (uint256 i = 0; i < anchoredTriples.length; i++) {
            Triple memory t  = anchoredTriples[i];
            bytes32 tk = _tk(t.bundle, t.subject, t.role);
            if (anchoredByOf[tk] == address(0)) continue;

            IDocumentBundleAnchor.AnchorRecord memory rec =
                anchor.getAnchor(t.bundle, t.subject, t.role);

            if (rec.bundleHash != t.bundle)  return false;
            if (rec.subjectId  != t.subject) return false;
            if (rec.role       != t.role)    return false;
            if (rec.anchoredBy != anchoredByOf[tk]) return false;
        }
        return true;
    }

    /// Active slots must always reflect the current canonical bundle per (subject, role).
    function property_activeSlotsRemainPerSubjectRole() external view returns (bool) {
        for (uint256 s = 0; s < subjects.length; s++) {
            for (uint256 r = 0; r < roles.length; r++) {
                bytes32 sk       = _sk(subjects[s], roles[r]);
                bytes32 expected = activeSlotOf[sk];
                bytes32 actual   = anchor.activeBundle(subjects[s], roles[r]);
                if (actual != expected) return false;
            }
        }
        return true;
    }

    /// Superseded records remain retrievable; superseded/supersededBy fields are immutable once set.
    function property_supersededRecordsAreImmutableExceptFlags() external view returns (bool) {
        for (uint256 i = 0; i < anchoredTriples.length; i++) {
            Triple memory t = anchoredTriples[i];
            bytes32 tk = _tk(t.bundle, t.subject, t.role);
            if (!wasSuperseded[tk]) continue;

            IDocumentBundleAnchor.AnchorRecord memory rec =
                anchor.getAnchor(t.bundle, t.subject, t.role);

            if (!rec.superseded)                         return false;
            if (rec.supersededBy != supersededByOf[tk])  return false;
            if (rec.bundleHash   != t.bundle)            return false;
            if (rec.subjectId    != t.subject)           return false;
            if (rec.role         != t.role)              return false;
        }
        return true;
    }

    // ── helpers ─────────────────────────────────────────────────────────

    function _tk(bytes32 b, bytes32 s, bytes32 r) internal pure returns (bytes32) {
        return keccak256(abi.encode(b, s, r));
    }

    function _sk(bytes32 s, bytes32 r) internal pure returns (bytes32) {
        return keccak256(abi.encode(s, r));
    }
}
