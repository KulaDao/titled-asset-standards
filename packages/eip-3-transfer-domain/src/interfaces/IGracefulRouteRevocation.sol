// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IGracefulRouteRevocation {
    struct Revocation {
        uint64 initiatedAt;
        uint64 effectiveAt;
        bytes32 revocationEvidenceHash;
        bool pending;
        // Guards duplicate finalization and RouteRevoked emission; route permission is determined lazily.
        bool finalized;
    }

    event RouteRevocationInitiated(
        bytes32 indexed sourceDomain,
        bytes32 indexed destinationDomain,
        bytes32 indexed assetClass,
        bytes32 revocationEvidenceHash,
        uint64 initiatedAt,
        uint64 effectiveAt
    );

    event RouteRevocationCancelled(
        bytes32 indexed sourceDomain,
        bytes32 indexed destinationDomain,
        bytes32 indexed assetClass,
        bytes32 cancellationEvidenceHash
    );

    /// @notice Retrieve the revocation state for a route.
    function getRevocation(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        external
        view
        returns (Revocation memory);

    /// @notice Initiate a graceful revocation.
    /// @dev MUST emit RouteRevocationInitiated. The route remains permitted until effectiveAt.
    ///      MUST reject sourceDomain, destinationDomain, and assetClass == bytes32(0).
    ///      MUST reject revocationEvidenceHash == bytes32(0).
    function initiateRevocation(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 revocationEvidenceHash
    ) external;

    /// @notice Cancel a pending revocation.
    /// @dev MUST revert if no revocation is pending or if the grace period has expired.
    ///      MUST emit RouteRevocationCancelled.
    ///      MUST reject sourceDomain, destinationDomain, and assetClass == bytes32(0).
    ///      MUST reject cancellationEvidenceHash == bytes32(0).
    function cancelRevocation(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 cancellationEvidenceHash
    ) external;

    /// @notice Finalize a revocation after the grace period.
    /// @dev MUST revert if the grace period has not expired.
    ///      A nonexistent or already finalized revocation MUST NOT emit a duplicate RouteRevoked event.
    ///      MUST emit RouteRevoked from the base interface.
    ///      MAY be permissionless because revocation effectiveness is lazy and does not depend on finalization.
    ///      MUST reject sourceDomain, destinationDomain, and assetClass == bytes32(0).
    function finalizeRevocation(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass) external;
}
