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

    bytes32 constant SUBJECT_A = keccak256("subject-a");
    bytes32 constant SUBJECT_B = keccak256("subject-b");
    bytes32 constant ROLE_1    = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_2    = keccak256("EVIDENCE");
    bytes32 constant BUNDLE_1  = keccak256("bundle-1");
    bytes32 constant BUNDLE_2  = keccak256("bundle-2");
    bytes32 constant BUNDLE_3  = keccak256("bundle-3");

    function setUp() public {
        anchor = new DocumentBundleAnchor(admin);
        vm.startPrank(admin);
        anchor.grantRole(anchor.ANCHOR_ROLE(), anchorUser);
        vm.stopPrank();
    }

    function test_anchorBundle_storesAllFields() public {
        vm.warp(1_000_000);
        vm.prank(anchorUser);
        anchor.anchorBundle(BUNDLE_1, SUBJECT_A, ROLE_1, 3, "ipfs://QmFoo");

        IDocumentBundleAnchor.AnchorRecord memory rec = anchor.getAnchor(BUNDLE_1);
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

        IDocumentBundleAnchor.AnchorRecord memory old = anchor.getAnchor(BUNDLE_1);
        assertTrue(old.superseded,              "old bundle should be superseded");
        assertEq(old.supersededBy, BUNDLE_2,    "supersededBy should point to BUNDLE_2");

        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), BUNDLE_2, "active slot should be BUNDLE_2");

        IDocumentBundleAnchor.AnchorRecord memory newRec = anchor.getAnchor(BUNDLE_2);
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

        IDocumentBundleAnchor.AnchorRecord memory old = anchor.getAnchor(BUNDLE_1);
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
        vm.expectRevert("DocumentBundleAnchor: old bundle not active for given slot");
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

    function test_activeBundle_returnsZeroIfNone() public {
        assertEq(anchor.activeBundle(SUBJECT_A, ROLE_1), bytes32(0), "empty slot must return bytes32(0)");
    }
}
