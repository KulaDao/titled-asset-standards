// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BundleAnchorVerifier} from "../src/reference/BundleAnchorVerifier.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {IDocumentBundleAnchor} from "../src/interfaces/IDocumentBundleAnchor.sol";

/// @dev Concrete subclass so we can call the internal guard functions from tests.
contract VerifierHarness is BundleAnchorVerifier {
    constructor(address reg) BundleAnchorVerifier(reg) {}
}

contract MockBundleAnchorRegistry is IDocumentBundleAnchor, IERC165 {
    bytes32 private _active;
    AnchorRecord private _record;
    bool private _revertGetAnchor;
    bool private _supportsDocumentBundleAnchor = true;

    function setActive(bytes32 active) external {
        _active = active;
    }

    function setRecord(AnchorRecord memory record) external {
        _record = record;
    }

    function setRevertGetAnchor(bool revertGetAnchor) external {
        _revertGetAnchor = revertGetAnchor;
    }

    function setSupportsDocumentBundleAnchor(bool supportsDocumentBundleAnchor) external {
        _supportsDocumentBundleAnchor = supportsDocumentBundleAnchor;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return _supportsDocumentBundleAnchor && interfaceId == type(IDocumentBundleAnchor).interfaceId;
    }

    function anchorBundle(bytes32, bytes32, bytes32, uint256, string calldata) external {}
    function supersedeBundle(bytes32, bytes32, bytes32, bytes32, uint256, string calldata) external {}

    function getAnchor(bytes32, bytes32, bytes32) external view returns (AnchorRecord memory) {
        require(!_revertGetAnchor, "mock getAnchor revert");
        return _record;
    }

    function isAnchored(bytes32, bytes32, bytes32) external pure returns (bool) {
        return true;
    }

    function activeBundle(bytes32, bytes32) external view returns (bytes32) {
        return _active;
    }
}

contract BundleAnchorVerifierTest is Test {
    DocumentBundleAnchor anchor;
    VerifierHarness      verifier;

    address admin   = address(0xA0);
    address anchorer = address(0xA1);

    bytes32 constant SUBJECT = keccak256("subject-x");
    bytes32 constant ROLE_L  = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_E  = keccak256("EVIDENCE");
    bytes32 constant BUNDLE_1 = keccak256("bundle-1");
    bytes32 constant BUNDLE_2 = keccak256("bundle-2");

    function setUp() public {
        anchor   = new DocumentBundleAnchor(admin);
        verifier = new VerifierHarness(address(anchor));

        bytes32 anchorRole = anchor.ANCHOR_ROLE();
        vm.prank(admin);
        anchor.grantRole(anchorRole, anchorer);
    }

    function _anchorBundle(bytes32 bundle, bytes32 subject, bytes32 role) internal {
        vm.prank(anchorer);
        anchor.anchorBundle(bundle, subject, role, 2, "ipfs://Qm");
    }

    // ── Constructor guard ─────────────────────────────────────────────────

    function test_constructor_revertsZeroRegistry() public {
        vm.expectRevert("BundleAnchorVerifier: zero registry");
        new VerifierHarness(address(0));
    }

    function test_constructor_revertsEOARegistry() public {
        vm.expectRevert("BundleAnchorVerifier: registry not contract");
        new VerifierHarness(address(0x1234));
    }

    function test_constructor_revertsUnsupportedRegistry() public {
        MockBundleAnchorRegistry mock = new MockBundleAnchorRegistry();
        mock.setSupportsDocumentBundleAnchor(false);
        vm.expectRevert("BundleAnchorVerifier: unsupported registry");
        new VerifierHarness(address(mock));
    }

    function test_bundleRegistry_returnsAnchorAddress() public {
        assertEq(verifier.bundleRegistry(), address(anchor));
    }

    // ── hasActiveBundle ───────────────────────────────────────────────────

    function test_hasActiveBundle_falseWhenNone() public {
        assertFalse(verifier.hasActiveBundle(SUBJECT, ROLE_L));
    }

    function test_hasActiveBundle_trueAfterAnchor() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        assertTrue(verifier.hasActiveBundle(SUBJECT, ROLE_L));
    }

    function test_hasActiveBundle_trueAfterSupersede_newHashActive() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        vm.prank(anchorer);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT, ROLE_L, 3, "ipfs://v2");
        // BUNDLE_2 is now active; SUBJECT/ROLE_L still has an active bundle
        assertTrue(verifier.hasActiveBundle(SUBJECT, ROLE_L));
    }

    function test_hasActiveBundle_falseIfActiveRecordSuperseded() public {
        MockBundleAnchorRegistry mock = new MockBundleAnchorRegistry();
        mock.setActive(BUNDLE_1);
        mock.setRecord(IDocumentBundleAnchor.AnchorRecord({
            bundleHash: BUNDLE_1,
            subjectId: SUBJECT,
            role: ROLE_L,
            anchoredBy: anchorer,
            anchoredAt: 1,
            documentCount: 1,
            metadataURI: "ipfs://old",
            superseded: true,
            supersededBy: BUNDLE_2
        }));
        VerifierHarness mockVerifier = new VerifierHarness(address(mock));

        assertFalse(mockVerifier.hasActiveBundle(SUBJECT, ROLE_L));
    }

    function test_hasActiveBundle_falseIfActiveRecordMismatched() public {
        MockBundleAnchorRegistry mock = new MockBundleAnchorRegistry();
        mock.setActive(BUNDLE_1);
        mock.setRecord(IDocumentBundleAnchor.AnchorRecord({
            bundleHash: BUNDLE_2,
            subjectId: SUBJECT,
            role: ROLE_L,
            anchoredBy: anchorer,
            anchoredAt: 1,
            documentCount: 1,
            metadataURI: "ipfs://wrong",
            superseded: false,
            supersededBy: bytes32(0)
        }));
        VerifierHarness mockVerifier = new VerifierHarness(address(mock));

        assertFalse(mockVerifier.hasActiveBundle(SUBJECT, ROLE_L));
    }

    function test_hasActiveBundle_falseIfGetAnchorReverts() public {
        MockBundleAnchorRegistry mock = new MockBundleAnchorRegistry();
        mock.setActive(BUNDLE_1);
        mock.setRevertGetAnchor(true);
        VerifierHarness mockVerifier = new VerifierHarness(address(mock));

        assertFalse(mockVerifier.hasActiveBundle(SUBJECT, ROLE_L));
    }

    // ── activeBundleFor ───────────────────────────────────────────────────

    function test_activeBundleFor_zeroWhenNone() public {
        assertEq(verifier.activeBundleFor(SUBJECT, ROLE_L), bytes32(0));
    }

    function test_activeBundleFor_returnsCorrectHash() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        assertEq(verifier.activeBundleFor(SUBJECT, ROLE_L), BUNDLE_1);
    }

    function test_activeBundleFor_updatesAfterSupersede() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        vm.prank(anchorer);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT, ROLE_L, 3, "ipfs://v2");
        assertEq(verifier.activeBundleFor(SUBJECT, ROLE_L), BUNDLE_2);
    }

    // ── isBundleCurrent ───────────────────────────────────────────────────

    function test_isBundleCurrent_trueForActiveBundle() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        assertTrue(verifier.isBundleCurrent(BUNDLE_1, SUBJECT, ROLE_L));
    }

    function test_isBundleCurrent_falseAfterSupersede() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        vm.prank(anchorer);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT, ROLE_L, 3, "ipfs://v2");
        assertFalse(verifier.isBundleCurrent(BUNDLE_1, SUBJECT, ROLE_L));
        assertTrue(verifier.isBundleCurrent(BUNDLE_2, SUBJECT, ROLE_L));
    }

    function test_isBundleCurrent_falseForWrongRole() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        assertFalse(verifier.isBundleCurrent(BUNDLE_1, SUBJECT, ROLE_E));
    }

    // ── hasActiveBundlesForAllRoles ───────────────────────────────────────

    function test_hasActiveBundlesForAllRoles_trueWhenAllPresent() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        _anchorBundle(BUNDLE_2, SUBJECT, ROLE_E);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_L; roles[1] = ROLE_E;
        assertTrue(verifier.hasActiveBundlesForAllRoles(SUBJECT, roles));
    }

    function test_hasActiveBundlesForAllRoles_falseIfOneIsMissing() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_L; roles[1] = ROLE_E;
        assertFalse(verifier.hasActiveBundlesForAllRoles(SUBJECT, roles));
    }

    function test_hasActiveBundlesForAllRoles_revertsForEmptyArray() public {
        bytes32[] memory roles = new bytes32[](0);
        vm.expectRevert(BundleAnchorVerifier.EmptyRoleSet.selector);
        verifier.hasActiveBundlesForAllRoles(SUBJECT, roles);
    }

    function test_hasActiveBundlesForAllRoles_revertsDuplicateRole() public {
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_L; roles[1] = ROLE_L;
        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.DuplicateRole.selector, ROLE_L));
        verifier.hasActiveBundlesForAllRoles(SUBJECT, roles);
    }

    // ── activeBundleBitmap ────────────────────────────────────────────────

    function test_activeBundleBitmap_correctBits() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_L; roles[1] = ROLE_E;
        uint256 bitmap = verifier.activeBundleBitmap(SUBJECT, roles);
        // bit 0 set (ROLE_L), bit 1 unset (ROLE_E missing)
        assertEq(bitmap, 1);
    }

    function test_activeBundleBitmap_bothBitsSet() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        _anchorBundle(BUNDLE_2, SUBJECT, ROLE_E);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_L; roles[1] = ROLE_E;
        assertEq(verifier.activeBundleBitmap(SUBJECT, roles), 3); // 0b11
    }

    function test_activeBundleBitmap_setsBit255() public {
        bytes32[] memory roles = new bytes32[](256);
        for (uint256 i = 0; i < roles.length; i++) {
            roles[i] = bytes32(uint256(i + 1));
        }

        _anchorBundle(BUNDLE_1, SUBJECT, roles[255]);
        assertEq(verifier.activeBundleBitmap(SUBJECT, roles), 1 << 255);
    }

    function test_activeBundleBitmap_revertsFor257Roles() public {
        bytes32[] memory roles = new bytes32[](257);
        for (uint256 i = 0; i < roles.length; i++) {
            roles[i] = bytes32(uint256(i + 1));
        }

        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.TooManyRoles.selector, 257));
        verifier.activeBundleBitmap(SUBJECT, roles);
    }

    function test_activeBundleBitmap_revertsForEmptyArray() public {
        bytes32[] memory roles = new bytes32[](0);
        vm.expectRevert(BundleAnchorVerifier.EmptyRoleSet.selector);
        verifier.activeBundleBitmap(SUBJECT, roles);
    }

    // ── getActiveBundleRecord ─────────────────────────────────────────────

    function test_getActiveBundleRecord_returnsRecord() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        IDocumentBundleAnchor.AnchorRecord memory rec = verifier.getActiveBundleRecord(SUBJECT, ROLE_L);
        assertEq(rec.bundleHash,    BUNDLE_1);
        assertEq(rec.subjectId,     SUBJECT);
        assertEq(rec.role,          ROLE_L);
        assertEq(rec.documentCount, 2);
        assertFalse(rec.superseded);
    }

    function test_getActiveBundleRecord_revertsWhenNone() public {
        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.NoBundleActive.selector, SUBJECT, ROLE_L));
        verifier.getActiveBundleRecord(SUBJECT, ROLE_L);
    }

    function test_getActiveBundleRecord_revertsIfActiveRecordSuperseded() public {
        MockBundleAnchorRegistry mock = new MockBundleAnchorRegistry();
        mock.setActive(BUNDLE_1);
        mock.setRecord(IDocumentBundleAnchor.AnchorRecord({
            bundleHash: BUNDLE_1,
            subjectId: SUBJECT,
            role: ROLE_L,
            anchoredBy: anchorer,
            anchoredAt: 1,
            documentCount: 1,
            metadataURI: "ipfs://old",
            superseded: true,
            supersededBy: BUNDLE_2
        }));
        VerifierHarness mockVerifier = new VerifierHarness(address(mock));

        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.BundleNotCurrent.selector, BUNDLE_1, SUBJECT, ROLE_L));
        mockVerifier.getActiveBundleRecord(SUBJECT, ROLE_L);
    }

    function test_getActiveBundleRecord_revertsIfGetAnchorReverts() public {
        MockBundleAnchorRegistry mock = new MockBundleAnchorRegistry();
        mock.setActive(BUNDLE_1);
        mock.setRevertGetAnchor(true);
        VerifierHarness mockVerifier = new VerifierHarness(address(mock));

        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.BundleNotCurrent.selector, BUNDLE_1, SUBJECT, ROLE_L));
        mockVerifier.getActiveBundleRecord(SUBJECT, ROLE_L);
    }

    // ── requireActiveBundle ───────────────────────────────────────────────

    function test_requireActiveBundle_passesWhenActive() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        verifier.requireActiveBundle(SUBJECT, ROLE_L); // no revert
    }

    function test_requireActiveBundle_revertsWhenNone() public {
        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.NoBundleActive.selector, SUBJECT, ROLE_L));
        verifier.requireActiveBundle(SUBJECT, ROLE_L);
    }

    // ── requireBundleIsCurrent ────────────────────────────────────────────

    function test_requireBundleIsCurrent_passesForActiveBundle() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        verifier.requireBundleIsCurrent(BUNDLE_1, SUBJECT, ROLE_L); // no revert
    }

    function test_requireBundleIsCurrent_revertsAfterSupersede() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        vm.prank(anchorer);
        anchor.supersedeBundle(BUNDLE_1, BUNDLE_2, SUBJECT, ROLE_L, 3, "ipfs://v2");

        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.BundleNotCurrent.selector, BUNDLE_1, SUBJECT, ROLE_L));
        verifier.requireBundleIsCurrent(BUNDLE_1, SUBJECT, ROLE_L);
    }

    function test_requireBundleIsCurrent_revertsIfActiveRecordMismatched() public {
        MockBundleAnchorRegistry mock = new MockBundleAnchorRegistry();
        mock.setActive(BUNDLE_1);
        mock.setRecord(IDocumentBundleAnchor.AnchorRecord({
            bundleHash: BUNDLE_2,
            subjectId: SUBJECT,
            role: ROLE_L,
            anchoredBy: anchorer,
            anchoredAt: 1,
            documentCount: 1,
            metadataURI: "ipfs://wrong",
            superseded: false,
            supersededBy: bytes32(0)
        }));
        VerifierHarness mockVerifier = new VerifierHarness(address(mock));

        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.BundleNotCurrent.selector, BUNDLE_1, SUBJECT, ROLE_L));
        mockVerifier.requireBundleIsCurrent(BUNDLE_1, SUBJECT, ROLE_L);
    }

    // ── requireActiveBundlesForAllRoles ───────────────────────────────────

    function test_requireActiveBundlesForAllRoles_passesWhenAll() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        _anchorBundle(BUNDLE_2, SUBJECT, ROLE_E);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_L; roles[1] = ROLE_E;
        verifier.requireActiveBundlesForAllRoles(SUBJECT, roles); // no revert
    }

    function test_requireActiveBundlesForAllRoles_revertsIfOneMissing() public {
        _anchorBundle(BUNDLE_1, SUBJECT, ROLE_L);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_L; roles[1] = ROLE_E;
        vm.expectRevert(abi.encodeWithSelector(BundleAnchorVerifier.NoBundleActive.selector, SUBJECT, ROLE_E));
        verifier.requireActiveBundlesForAllRoles(SUBJECT, roles);
    }

    function test_requireActiveBundlesForAllRoles_revertsForEmptyArray() public {
        bytes32[] memory roles = new bytes32[](0);
        vm.expectRevert(BundleAnchorVerifier.EmptyRoleSet.selector);
        verifier.requireActiveBundlesForAllRoles(SUBJECT, roles);
    }
}
