// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IImpactAttestation {
    struct Attestation {
        address attestor;
        bool endorsed;
        bytes32 evidenceHash;
        string evidenceURI;
        uint64 attestedAt;
    }

    event SnapshotAttested(
        bytes32 indexed subjectId,
        uint256 indexed snapshotIndex,
        address indexed attestor,
        bool endorsed,
        bytes32 evidenceHash,
        uint256 attestationIndex
    );

    /// @dev MUST reject evidenceHash == bytes32(0). An empty evidenceURI is allowed,
    ///      but the hash commitment itself is required.
    function attestSnapshot(
        bytes32 subjectId,
        uint256 snapshotIndex,
        bool endorsed,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external returns (uint256 attestationIndex);

    function attestationCount(bytes32 subjectId, uint256 snapshotIndex) external view returns (uint256);

    function getAttestation(bytes32 subjectId, uint256 snapshotIndex, uint256 attestationIndex)
        external
        view
        returns (Attestation memory);
}
