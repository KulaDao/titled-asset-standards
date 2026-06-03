// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IGracefulRouteRevocation {
    struct Revocation {
        uint64 initiatedAt;
        uint64 effectiveAt;
        bytes32 revocationEvidenceHash;
        bool pending;
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
    function initiateRevocation(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 revocationEvidenceHash
    ) external;

    /// @notice Cancel a pending revocation.
    /// @dev MUST revert if no revocation is pending or if the grace period has expired.
    ///      MUST emit RouteRevocationCancelled.
    function cancelRevocation(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 cancellationEvidenceHash
    ) external;

    /// @notice Finalize a revocation after the grace period.
    /// @dev MUST revert if the grace period has not expired or if already finalized.
    ///      MUST emit RouteRevoked from the base interface.
    function finalizeRevocation(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass) external;
}
