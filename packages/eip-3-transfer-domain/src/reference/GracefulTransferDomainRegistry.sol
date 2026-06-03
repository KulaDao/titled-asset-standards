// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGracefulRouteRevocation} from "../interfaces/IGracefulRouteRevocation.sol";
import {ITransferDomainRegistry} from "../interfaces/ITransferDomainRegistry.sol";
import {TransferDomainRegistry} from "./TransferDomainRegistry.sol";

contract GracefulTransferDomainRegistry is TransferDomainRegistry, IGracefulRouteRevocation {
    uint64 public immutable gracePeriod;

    mapping(bytes32 => Revocation) internal _revocations;

    constructor(address admin, uint64 gracePeriod_) TransferDomainRegistry(admin) {
        gracePeriod = gracePeriod_;
    }

    function getRevocation(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        external
        view
        returns (Revocation memory)
    {
        return _revocations[_routeKey(sourceDomain, destinationDomain, assetClass)];
    }

    function setRoute(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 permissionEvidenceHash
    ) public override onlyRole(REGISTRAR_ROLE) {
        bytes32 key = _routeKey(sourceDomain, destinationDomain, assetClass);
        delete _revocations[key];
        uint64 effectiveAt = _now64();

        _routes[key] =
            Route({permitted: true, effectiveAt: effectiveAt, permissionEvidenceHash: permissionEvidenceHash});

        emit RouteSet(sourceDomain, destinationDomain, assetClass, permissionEvidenceHash, effectiveAt);
    }

    function revokeRoute(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 revocationEvidenceHash
    ) public override onlyRole(REGISTRAR_ROLE) {
        bytes32 key = _routeKey(sourceDomain, destinationDomain, assetClass);
        delete _revocations[key];
        uint64 effectiveAt = _now64();

        _routes[key].permitted = false;
        _routes[key].effectiveAt = effectiveAt;

        emit RouteRevoked(sourceDomain, destinationDomain, assetClass, revocationEvidenceHash, effectiveAt);
    }

    function initiateRevocation(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 revocationEvidenceHash
    ) external onlyRole(REGISTRAR_ROLE) {
        bytes32 key = _routeKey(sourceDomain, destinationDomain, assetClass);
        require(_isRoutePermitted(key), "GracefulTransferDomainRegistry: route not permitted");
        require(!_revocations[key].pending, "GracefulTransferDomainRegistry: revocation pending");
        require(
            block.timestamp <= uint256(type(uint64).max) - uint256(gracePeriod),
            "GracefulTransferDomainRegistry: timestamp overflow"
        );

        uint64 initiatedAt = _now64();
        uint64 effectiveAt = uint64(block.timestamp + gracePeriod);

        _revocations[key] = Revocation({
            initiatedAt: initiatedAt,
            effectiveAt: effectiveAt,
            revocationEvidenceHash: revocationEvidenceHash,
            pending: true,
            finalized: false
        });

        emit RouteRevocationInitiated(
            sourceDomain, destinationDomain, assetClass, revocationEvidenceHash, initiatedAt, effectiveAt
        );
    }

    function cancelRevocation(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 cancellationEvidenceHash
    ) external onlyRole(REGISTRAR_ROLE) {
        bytes32 key = _routeKey(sourceDomain, destinationDomain, assetClass);
        Revocation memory revocation = _revocations[key];

        require(revocation.pending, "GracefulTransferDomainRegistry: no pending revocation");
        require(block.timestamp < revocation.effectiveAt, "GracefulTransferDomainRegistry: grace period expired");

        delete _revocations[key];

        emit RouteRevocationCancelled(sourceDomain, destinationDomain, assetClass, cancellationEvidenceHash);
    }

    function finalizeRevocation(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        bytes32 key = _routeKey(sourceDomain, destinationDomain, assetClass);
        Revocation storage revocation = _revocations[key];

        require(revocation.pending || revocation.finalized, "GracefulTransferDomainRegistry: no revocation");
        require(!revocation.finalized, "GracefulTransferDomainRegistry: already finalized");
        require(block.timestamp >= revocation.effectiveAt, "GracefulTransferDomainRegistry: grace period active");

        revocation.pending = false;
        revocation.finalized = true;
        _routes[key].permitted = false;
        _routes[key].effectiveAt = revocation.effectiveAt;

        emit RouteRevoked(
            sourceDomain, destinationDomain, assetClass, revocation.revocationEvidenceHash, revocation.effectiveAt
        );
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IGracefulRouteRevocation).interfaceId || super.supportsInterface(interfaceId);
    }

    function _isRoutePermitted(bytes32 key) internal view override returns (bool) {
        if (!_routes[key].permitted) return false;

        Revocation memory revocation = _revocations[key];
        if (revocation.pending && block.timestamp >= revocation.effectiveAt) return false;

        return true;
    }

    function _getRoute(bytes32 key) internal view override returns (ITransferDomainRegistry.Route memory route) {
        route = _routes[key];

        Revocation memory revocation = _revocations[key];
        if (revocation.pending && block.timestamp >= revocation.effectiveAt) {
            route.permitted = false;
            route.effectiveAt = revocation.effectiveAt;
        }
    }
}
