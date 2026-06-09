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

    function anchorBundle(
        bytes32 bundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external;

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
