// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IDocumentBundleAnchor {
    struct AnchorRecord {
        bytes32 bundleHash;
        bytes32 subjectId;
        bytes32 role;
        address anchoredBy;
        uint64 anchoredAt;
        uint256 documentCount;
        string metadataURI;
        bool superseded;
        bytes32 supersededBy;
    }

    event BundleAnchored(
        bytes32 indexed bundleHash, bytes32 indexed subjectId, bytes32 indexed role, uint256 documentCount
    );

    event BundleSuperseded(
        bytes32 indexed oldBundleHash, bytes32 indexed newBundleHash, bytes32 indexed subjectId, bytes32 role
    );

    /// @dev Reference implementations MUST reject zero bundleHash, subjectId, role, and documentCount.
    function anchorBundle(
        bytes32 bundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external;

    /// @dev Reference implementations MUST reject zero newBundleHash, subjectId, role, and documentCount.
    function supersedeBundle(
        bytes32 oldBundleHash,
        bytes32 newBundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external;

    function getAnchor(bytes32 bundleHash, bytes32 subjectId, bytes32 role) external view returns (AnchorRecord memory);
    function isAnchored(bytes32 bundleHash, bytes32 subjectId, bytes32 role) external view returns (bool);
    function activeBundle(bytes32 subjectId, bytes32 role) external view returns (bytes32);
}

/// @notice Admin recovery extension for IDocumentBundleAnchor.
/// @dev Kept separate so the core IDocumentBundleAnchor interface ID is stable across
///      deployments that implement different recovery models. BundleAnchorVerifier checks
///      only IDocumentBundleAnchor; consumers that require recovery capability should
///      additionally check this interface.
interface IDocumentBundleAnchorRecovery {
    /// @notice Emitted when an admin atomically reassigns slot authority.
    event SlotPrincipalAssigned(bytes32 indexed subjectId, bytes32 indexed role, address indexed principal);

    /// @notice Returns the address currently authorized to supersede the active bundle for
    ///         (subjectId, role). The principal must also hold ANCHOR_ROLE or DEFAULT_ADMIN_ROLE
    ///         to successfully call supersedeBundle.
    function slotPrincipal(bytes32 subjectId, bytes32 role) external view returns (address);

    /// @notice Admin-only: atomically reassign slot authority without going through supersedeBundle.
    /// @dev supersedeBundle is front-runnable on a contested slot (the squatter, still holding
    ///      ANCHOR_ROLE and being the current slot principal, can call supersedeBundle first and
    ///      invalidate the admin's oldBundleHash argument). assignSlotPrincipal is NOT front-runnable
    ///      because the squatter lacks DEFAULT_ADMIN_ROLE. The required recovery sequence is:
    ///      1. Admin calls assignSlotPrincipal(subjectId, role, legitimateOperator).
    ///      2. Admin grants ANCHOR_ROLE to legitimateOperator if not already held.
    ///      3. legitimateOperator calls supersedeBundle using the now-stable active bundle hash.
    ///      The designated principal must hold ANCHOR_ROLE or DEFAULT_ADMIN_ROLE.
    function assignSlotPrincipal(bytes32 subjectId, bytes32 role, address principal) external;
}
