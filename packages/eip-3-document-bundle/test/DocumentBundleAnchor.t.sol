// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {IDocumentBundleAnchor} from "../src/interfaces/IDocumentBundleAnchor.sol";

contract DocumentBundleAnchorTest is Test {
    event BundleAnchored(
        bytes32 indexed bundleHash,
        bytes32 indexed subjectId,
        bytes32 indexed role,
        uint256 documentCount
    );

    DocumentBundleAnchor anchor;

    address admin      = address(0xA0);
    address anchorUser = address(0xA1);
    address other      = address(0xA2);
    address realAnchorUser = address(0x530eD37634153Ca6FFE5a33ed8Ee917B32DDBbf7);

    bytes32 constant SUBJECT_A = keccak256("subject-a");
    bytes32 constant SUBJECT_B = keccak256("subject-b");
    bytes32 constant ROLE_1    = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_2    = keccak256("EVIDENCE");
    bytes32 constant BUNDLE_1  = keccak256("bundle-1");
    bytes32 constant BUNDLE_2  = keccak256("bundle-2");
    bytes32 constant BUNDLE_3  = keccak256("bundle-3");
    bytes32 constant BUNDLE_R1 = keccak256("real-bundle-1");
    bytes32 constant BUNDLE_R2 = keccak256("real-bundle-2");

    function setUp() public {
        anchor = new DocumentBundleAnchor(admin);
        vm.startPrank(admin);
        anchor.grantRole(anchor.ANCHOR_ROLE(), anchorUser);
        anchor.grantRole(anchor.ANCHOR_ROLE(), realAnchorUser);
        vm.stopPrank();
    }

    function test_anchorBundle_storesAllFields() public {
        vm.warp(1_000_000);
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 3, "ipfs://QmFoo");

        IDocumentBundleAnchor.AnchorRecord memory rec = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        assertEq(rec.bundleHash,    BUNDLE_1,          "bundleHash mismatch");
        assertEq(rec.subjectId,     SUBJECT_A,         "subjectId mismatch");
        assertEq(rec.role,          ROLE_1,            "role mismatch");
        assertEq(rec.anchoredBy,    anchorUser,        "anchoredBy mismatch");
        assertEq(rec.anchoredAt,    uint64(1_000_000), "anchoredAt mismatch");
        assertEq(rec.documentCount, 3,                 "documentCount mismatch");
        assertEq(rec.metadataURI,   "ipfs://QmFoo",    "metadataURI mismatch");
        assertFalse(rec.superseded,                    "superseded should be false");
        assertEq(rec.supersededBy,  bytes32(0),        "supersededBy should be zero");
    }

    function test_anchorBundle_setsActiveSlot() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "");
        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_1, "active slot should be BUNDLE_1");
    }

    function test_anchorBundle_emitsBundleAnchored() public {
        vm.expectEmit(true, true, true, true);
        emit BundleAnchored(BUNDLE_1, SUBJECT_A, ROLE_1, 2);
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 2, "");
    }

    function test_anchorBundle_revertsDuplicate() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "");
        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: already anchored");
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "");
    }

    function test_anchorBundle_revertsIfActiveSlotOccupied() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "");
        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: active slot occupied, use supersedeBundle");
        anchor.anchorBundle(BUNDLE_2, SUBJECT_A, ROLE_1, 1, "");
    }

    function test_supersedeBundle_works() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "v1");

        vm.prank(anchorUser);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 2, "v2");

        IDocumentBundleAnchor.AnchorRecord memory old = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        assertTrue(old.superseded,              "old bundle should be superseded");
        assertEq(old.supersededBy, BUNDLE_2,    "supersededBy should point to BUNDLE_2");

        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_2, "active slot should be BUNDLE_2");

        IDocumentBundleAnchor.AnchorRecord memory newRec = anchor.getAnchor(BUNDLE_2, SUBJECT_A, ROLE_1);
        assertEq(newRec.bundleHash,    BUNDLE_2,   "new record bundleHash mismatch");
        assertEq(newRec.subjectId,     SUBJECT_A,  "new record subjectId mismatch");
        assertFalse(newRec.superseded,             "new record must not be superseded");
        assertEq(newRec.supersededBy,  bytes32(0), "new record supersededBy must be zero");
    }

    function test_supersedeBundle_revertsUnauthorized() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "");

        vm.startPrank(admin);
        anchor.grantRole(anchor.ANCHOR_ROLE(), other);
        vm.stopPrank();

        vm.prank(other);
        vm.expectRevert("DocumentBundleAnchor: not authorized to supersede");
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 1, "");
    }

    function test_supersedeBundle_adminCanSupersede() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "v1");

        // admin has DEFAULT_ADMIN_ROLE but did NOT anchor BUNDLE_1 — should still succeed
        vm.prank(admin);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 2, "v2-admin");

        IDocumentBundleAnchor.AnchorRecord memory old = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        assertTrue(old.superseded, "old bundle should be superseded by admin");
        assertEq(old.supersededBy, BUNDLE_2, "supersededBy mismatch");
        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_2, "active slot should be BUNDLE_2");
    }

    function test_supersedeBundle_revertsAlreadySuperseded() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "");
        vm.prank(anchorUser);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 1, "");

        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: old bundle already superseded");
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_3, SUBJECT_A, ROLE_1, 1, "");
    }

    function test_supersedeBundle_revertsNonExistent() public {
        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: old bundle not anchored");
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 1, "");
    }

    function test_supersedeBundle_revertsWrongSlot() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "");

        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: old bundle not anchored");
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_B, ROLE_1, 1, "");
    }

    function test_differentSubjects_sameBundle() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "for-a");

        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_B, ROLE_1, 1, "for-b");

        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_1, "SUBJECT_A active slot wrong");
        assertEq(anchor.activeBundle(SUBJECT_B, ROLE_1), BUNDLE_1, "SUBJECT_B active slot wrong");
    }

    function test_differentSubjects_sameBundle_independentRecords() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "for-a");
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_B, ROLE_1, 2, "for-b");

        IDocumentBundleAnchor.AnchorRecord memory recA = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        IDocumentBundleAnchor.AnchorRecord memory recB = anchor.getAnchor(BUNDLE_1, SUBJECT_B, ROLE_1);

        assertEq(recA.subjectId,     SUBJECT_A, "recA subjectId wrong");
        assertEq(recA.documentCount, 1,         "recA documentCount wrong");
        assertEq(recA.metadataURI,   "for-a",   "recA metadataURI wrong");
        assertFalse(recA.superseded,             "recA should not be superseded");

        assertEq(recB.subjectId,     SUBJECT_B, "recB subjectId wrong");
        assertEq(recB.documentCount, 2,         "recB documentCount wrong");
        assertEq(recB.metadataURI,   "for-b",   "recB metadataURI wrong");
        assertFalse(recB.superseded,             "recB should not be superseded");
    }

    function test_differentSubjects_supersedeA_doesNotAffectB() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "for-a");
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_B, ROLE_1, 1, "for-b");

        vm.prank(anchorUser);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 2, "v2-a");

        IDocumentBundleAnchor.AnchorRecord memory recA = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        IDocumentBundleAnchor.AnchorRecord memory recB = anchor.getAnchor(BUNDLE_1, SUBJECT_B, ROLE_1);

        assertTrue(recA.superseded,  "recA should be superseded");
        assertFalse(recB.superseded, "recB must not be affected by SUBJECT_A supersession");
        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_2, "SUBJECT_A active wrong");
        assertEq(anchor.activeBundle(SUBJECT_B, ROLE_1), BUNDLE_1, "SUBJECT_B active wrong");
    }

    function test_anchorBundle_revertsZeroBundleHash() public {
        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: zero bundleHash");
        anchor.anchorBundle(bytes32(0), SUBJECT_A, ROLE_1, 1, "");
    }

    function test_anchorBundle_revertsZeroDocumentCount() public {
        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: zero documentCount");
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 0, "");
    }

    function test_supersedeBundle_revertsZeroNewBundleHash() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "v1");

        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: zero newBundleHash");
        anchor.supersedeBundle(BUNDLE_1, bytes32(0), SUBJECT_A, ROLE_1, 1, "");
    }

    function test_supersedeBundle_revertsZeroDocumentCount() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "v1");

        vm.prank(anchorUser);
        vm.expectRevert("DocumentBundleAnchor: zero documentCount");
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 0, "");
    }

    function test_activeBundle_returnsZeroIfNone() public {
        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), bytes32(0), "empty slot must return bytes32(0)");
    }

    // ── Fixtures for 0x530eD37634153Ca6FFE5a33ed8Ee917B32DDBbf7 ──────────────

    function test_realAnchorUser_canAnchorBundle() public {
        vm.warp(2_000_000);
        vm.prank(realAnchorUser);
        anchor.anchorBundle(BUNDLE_R1, SUBJECT_A, ROLE_1, 5, "ipfs://QmRealBundle1");

        IDocumentBundleAnchor.AnchorRecord memory rec = anchor.getAnchor(BUNDLE_R1, SUBJECT_A, ROLE_1);
        assertEq(rec.anchoredBy,    realAnchorUser,   "anchoredBy mismatch");
        assertEq(rec.anchoredAt,    uint64(2_000_000), "anchoredAt mismatch");
        assertEq(rec.documentCount, 5,                 "documentCount mismatch");
        assertEq(rec.metadataURI,   "ipfs://QmRealBundle1", "metadataURI mismatch");
        assertFalse(rec.superseded,                    "superseded should be false");
    }

    function test_realAnchorUser_activeSlot() public {
        vm.prank(realAnchorUser);
        anchor.anchorBundle(BUNDLE_R1, SUBJECT_A, ROLE_1, 2, "ipfs://QmRealBundle1");

        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_R1, "active slot should be BUNDLE_R1");
    }

    function test_realAnchorUser_canSupersedeOwnBundle() public {
        vm.prank(realAnchorUser);
        anchor.anchorBundle(BUNDLE_R1, SUBJECT_A, ROLE_1, 2, "v1");

        vm.prank(realAnchorUser);
        anchor.supersedeBundle(BUNDLE_R1, BUNDLE_R2, SUBJECT_A, ROLE_1, 3, "v2");

        IDocumentBundleAnchor.AnchorRecord memory old = anchor.getAnchor(BUNDLE_R1, SUBJECT_A, ROLE_1);
        assertTrue(old.superseded,              "old bundle should be superseded");
        assertEq(old.supersededBy, BUNDLE_R2,   "supersededBy mismatch");

        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_R2, "active slot should be BUNDLE_R2");

        IDocumentBundleAnchor.AnchorRecord memory newRec = anchor.getAnchor(BUNDLE_R2, SUBJECT_A, ROLE_1);
        assertEq(newRec.anchoredBy, realAnchorUser, "new record anchoredBy mismatch");
        assertFalse(newRec.superseded,              "new record must not be superseded");
    }

    function test_realAnchorUser_isolatedFromOtherAnchorUser() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "from-anchorUser");

        vm.prank(realAnchorUser);
        anchor.anchorBundle(BUNDLE_R1, SUBJECT_B, ROLE_1, 1, "from-realAnchorUser");

        IDocumentBundleAnchor.AnchorRecord memory recA = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        IDocumentBundleAnchor.AnchorRecord memory recR = anchor.getAnchor(BUNDLE_R1, SUBJECT_B, ROLE_1);

        assertEq(recA.anchoredBy, anchorUser,     "recA anchoredBy mismatch");
        assertEq(recR.anchoredBy, realAnchorUser, "recR anchoredBy mismatch");
        assertFalse(recA.superseded, "recA must not be superseded");
        assertFalse(recR.superseded, "recR must not be superseded");
    }

    // ── isAnchored ────────────────────────────────────────────────────────

    function test_isAnchored_falseBeforeAnchor() public {
        assertFalse(anchor.isAnchored(BUNDLE_1, SUBJECT_A, ROLE_1));
    }

    function test_isAnchored_trueAfterAnchor() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "ipfs://v1");
        assertTrue(anchor.isAnchored(BUNDLE_1, SUBJECT_A, ROLE_1));
    }

    function test_isAnchored_trueEvenAfterSuperseded() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "v1");
        vm.prank(anchorUser);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 2, "v2");
        // old bundle is still "anchored" (exists), just superseded
        assertTrue(anchor.isAnchored(BUNDLE_1, SUBJECT_A, ROLE_1));
        assertTrue(anchor.isAnchored(BUNDLE_2, SUBJECT_A, ROLE_1));
    }

    function test_isAnchored_falseForWrongTriple() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "ipfs://v1");
        assertFalse(anchor.isAnchored(BUNDLE_1, SUBJECT_B, ROLE_1));
        assertFalse(anchor.isAnchored(BUNDLE_1, SUBJECT_A, ROLE_2));
        assertFalse(anchor.isAnchored(BUNDLE_2, SUBJECT_A, ROLE_1));
    }

    // ── supportsInterface ─────────────────────────────────────────────────

    function test_supportsInterface_IDocumentBundleAnchor() public {
        assertTrue(anchor.supportsInterface(type(IDocumentBundleAnchor).interfaceId));
    }

    function test_supportsInterface_AccessControl() public {
        // 0x7965db0b = IAccessControl
        assertTrue(anchor.supportsInterface(0x7965db0b));
    }

    function test_supportsInterface_falseForUnknown() public {
        assertFalse(anchor.supportsInterface(0xdeadbeef));
    }

    // ── Edge cases ────────────────────────────────────────────────────────

    function test_anchorBundle_sameBundleHashDifferentRoles() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "role1");
        // same hash, same subject, different role -- allowed (different triple)
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_2, 1, "role2");

        assertTrue(anchor.isAnchored(BUNDLE_1, SUBJECT_A, ROLE_1));
        assertTrue(anchor.isAnchored(BUNDLE_1, SUBJECT_A, ROLE_2));
    }

    function test_anchorBundle_longMetadataURI() public {
        string memory longURI = string(abi.encodePacked(
            "ipfs://Qm",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ));
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 100, longURI);
        IDocumentBundleAnchor.AnchorRecord memory rec = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        assertEq(rec.metadataURI, longURI);
    }

    function test_supersedeBundle_chainOfThree() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "v1");
        vm.prank(anchorUser);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 2, "v2");
        vm.prank(anchorUser);
        anchor.supersedeBundle(BUNDLE_2, BUNDLE_3, SUBJECT_A, ROLE_1, 3, "v3");

        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_3, "BUNDLE_3 must be active");

        IDocumentBundleAnchor.AnchorRecord memory r1 = anchor.getAnchor(BUNDLE_1, SUBJECT_A, ROLE_1);
        IDocumentBundleAnchor.AnchorRecord memory r2 = anchor.getAnchor(BUNDLE_2, SUBJECT_A, ROLE_1);
        IDocumentBundleAnchor.AnchorRecord memory r3 = anchor.getAnchor(BUNDLE_3, SUBJECT_A, ROLE_1);

        assertTrue(r1.superseded);  assertEq(r1.supersededBy, BUNDLE_2);
        assertTrue(r2.superseded);  assertEq(r2.supersededBy, BUNDLE_3);
        assertFalse(r3.superseded); assertEq(r3.supersededBy, bytes32(0));
    }

    function test_anchorBundle_revertsZeroSubjectId() public {
        vm.prank(anchorUser);
        // zero subjectId is allowed by the contract (no explicit check) --
        // document this behaviour explicitly so any future restriction is caught.
        anchor.anchorBundle(BUNDLE_1, bytes32(0), ROLE_1, 1, "ipfs://");
        assertTrue(anchor.isAnchored(BUNDLE_1, bytes32(0), ROLE_1));
    }

    function test_supersedeBundle_revertsWhenRoleRevoked() public {
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 1, "v1");

        bytes32 anchorRole = anchor.ANCHOR_ROLE();
        vm.prank(admin);
        anchor.revokeRole(anchorRole, anchorUser);

        vm.prank(anchorUser);
        vm.expectRevert();
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT_A, ROLE_1, 2, "v2");
    }
}
