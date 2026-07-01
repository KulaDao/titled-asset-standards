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

    event SlotPrincipalAssigned(bytes32 indexed subjectId, bytes32 indexed role, address indexed principal);

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

    /// @notice Returns the address currently authorized to supersede the active bundle for (subjectId, role).
    function slotPrincipal(bytes32 subjectId, bytes32 role) external view returns (address);

    /// @notice Admin-only: atomically reassign slot authority, breaking a squatter's supersede capability
    ///         without going through supersedeBundle (which the squatter could front-run).
    function assignSlotPrincipal(bytes32 subjectId, bytes32 role, address principal) external;
}
