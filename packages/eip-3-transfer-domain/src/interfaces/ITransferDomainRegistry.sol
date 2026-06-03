// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface ITransferDomainRegistry {
    struct Route {
        bool permitted;
        uint64 effectiveAt;
        bytes32 permissionEvidenceHash;
    }

    event RouteSet(
        bytes32 indexed sourceDomain,
        bytes32 indexed destinationDomain,
        bytes32 indexed assetClass,
        bytes32 permissionEvidenceHash,
        uint64 effectiveAt
    );

    event RouteRevoked(
        bytes32 indexed sourceDomain,
        bytes32 indexed destinationDomain,
        bytes32 indexed assetClass,
        bytes32 revocationEvidenceHash,
        uint64 effectiveAt
    );

    /// @notice Query whether a route is currently permitted.
    /// @dev MUST be deterministic for any given block.
    ///      MUST NOT depend on msg.sender or tx.origin.
    function isRoutePermitted(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        external
        view
        returns (bool);

    /// @notice Retrieve the full route state.
    function getRoute(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        external
        view
        returns (Route memory);

    /// @notice Register a route as permitted.
    /// @dev MUST emit RouteSet. Only enables routes; use revokeRoute() to disable.
    function setRoute(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 permissionEvidenceHash
    ) external;

    /// @notice Revoke a route immediately.
    /// @dev MUST emit RouteRevoked. MUST NOT revert if the route does not exist
    ///      or is already revoked.
    function revokeRoute(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 revocationEvidenceHash
    ) external;

    /// @notice Bulk query for multiple routes.
    /// @dev MUST revert if input arrays differ in length.
    function isRoutePermittedBatch(
        bytes32[] calldata sourceDomains,
        bytes32[] calldata destinationDomains,
        bytes32[] calldata assetClasses
    ) external view returns (bool[] memory permitted);
}
