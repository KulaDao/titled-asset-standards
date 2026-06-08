// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGracefulRouteRevocation} from "../src/interfaces/IGracefulRouteRevocation.sol";
import {ITransferDomainRegistry} from "../src/interfaces/ITransferDomainRegistry.sol";
import {GracefulTransferDomainRegistry} from "../src/reference/GracefulTransferDomainRegistry.sol";

/// @dev Medusa fuzz harness for the directional route registry.
///      Run: medusa fuzz (from packages/eip-3-transfer-domain)
///
///      Invariants checked after randomized route lifecycle calls:
///        property_routesMatchModel
///        property_revocationsMatchModel
///        property_batchMatchesIndividualQueries
contract TransferDomainRegistryFuzzTest {
    GracefulTransferDomainRegistry internal registry;

    uint64 internal constant GRACE_PERIOD = 1 days;

    bytes32[] internal domains;
    bytes32[] internal assetClasses;

    struct ModelRoute {
        bool permitted;
        uint64 effectiveAt;
        bytes32 permissionEvidenceHash;
        bytes32 routeRevocationEvidenceHash;
        uint64 revocationInitiatedAt;
        uint64 revocationEffectiveAt;
        bytes32 revocationEvidenceHash;
        bool revocationPending;
        bool revocationFinalized;
    }

    mapping(bytes32 => ModelRoute) internal model;

    constructor() {
        registry = new GracefulTransferDomainRegistry(address(this), GRACE_PERIOD);
        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        bytes32 adminRole = registry.DEFAULT_ADMIN_ROLE();

        registry.grantRole(registrarRole, address(0x10000));
        registry.grantRole(registrarRole, address(0x20000));
        registry.grantRole(registrarRole, address(0x30000));
        registry.grantRole(adminRole, address(0x10000));
        registry.grantRole(adminRole, address(0x20000));
        registry.grantRole(adminRole, address(0x30000));

        domains.push(keccak256("DOMAIN:MAURITIUS"));
        domains.push(keccak256("DOMAIN:ZAMBIA"));
        domains.push(keccak256("DOMAIN:KENYA"));

        assetClasses.push(keccak256("ASSET_CLASS:MINERAL_CONCESSION"));
        assetClasses.push(keccak256("ASSET_CLASS:REAL_ESTATE"));
    }

    function fuzz_setRoute(uint256 sourceIdx, uint256 destinationIdx, uint256 assetIdx, uint256 evidenceSeed) external {
        (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key) =
            _route(sourceIdx, destinationIdx, assetIdx);
        bytes32 evidenceHash = keccak256(abi.encode("permission", evidenceSeed));

        registry.setRoute(source, destination, assetClass, evidenceHash);

        ModelRoute storage expected = model[key];
        expected.permitted = true;
        expected.effectiveAt = _now64();
        expected.permissionEvidenceHash = evidenceHash;
        expected.routeRevocationEvidenceHash = bytes32(0);
        expected.revocationInitiatedAt = 0;
        expected.revocationEffectiveAt = 0;
        expected.revocationEvidenceHash = bytes32(0);
        expected.revocationPending = false;
        expected.revocationFinalized = false;
    }

    function fuzz_revokeRoute(uint256 sourceIdx, uint256 destinationIdx, uint256 assetIdx, uint256 evidenceSeed)
        external
    {
        (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key) =
            _route(sourceIdx, destinationIdx, assetIdx);
        bytes32 evidenceHash = keccak256(abi.encode("revocation", evidenceSeed));

        registry.revokeRoute(source, destination, assetClass, evidenceHash);

        ModelRoute storage expected = model[key];
        expected.permitted = false;
        expected.effectiveAt = _now64();
        expected.routeRevocationEvidenceHash = evidenceHash;
        expected.revocationInitiatedAt = 0;
        expected.revocationEffectiveAt = 0;
        expected.revocationEvidenceHash = bytes32(0);
        expected.revocationPending = false;
        expected.revocationFinalized = false;
    }

    function fuzz_initiateRevocation(uint256 sourceIdx, uint256 destinationIdx, uint256 assetIdx, uint256 evidenceSeed)
        external
    {
        (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key) =
            _route(sourceIdx, destinationIdx, assetIdx);
        ModelRoute storage expected = model[key];
        if (!_modelRoutePermitted(expected)) return;
        if (expected.revocationPending) return;
        if (block.timestamp > uint256(type(uint64).max) - uint256(GRACE_PERIOD)) return;

        bytes32 evidenceHash = keccak256(abi.encode("graceful-revocation", evidenceSeed));
        registry.initiateRevocation(source, destination, assetClass, evidenceHash);

        expected.revocationInitiatedAt = _now64();
        expected.revocationEffectiveAt = uint64(block.timestamp + GRACE_PERIOD);
        expected.revocationEvidenceHash = evidenceHash;
        expected.revocationPending = true;
        expected.revocationFinalized = false;
    }

    function fuzz_cancelRevocation(uint256 sourceIdx, uint256 destinationIdx, uint256 assetIdx, uint256 evidenceSeed)
        external
    {
        (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key) =
            _route(sourceIdx, destinationIdx, assetIdx);
        ModelRoute storage expected = model[key];
        if (!expected.revocationPending) return;
        if (block.timestamp >= expected.revocationEffectiveAt) return;

        bytes32 evidenceHash = keccak256(abi.encode("cancellation", evidenceSeed));
        registry.cancelRevocation(source, destination, assetClass, evidenceHash);

        expected.revocationInitiatedAt = 0;
        expected.revocationEffectiveAt = 0;
        expected.revocationEvidenceHash = bytes32(0);
        expected.revocationPending = false;
        expected.revocationFinalized = false;
    }

    function fuzz_finalizeRevocation(uint256 sourceIdx, uint256 destinationIdx, uint256 assetIdx) external {
        (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key) =
            _route(sourceIdx, destinationIdx, assetIdx);
        ModelRoute storage expected = model[key];
        if (!expected.revocationPending) return;
        if (block.timestamp < expected.revocationEffectiveAt) return;

        registry.finalizeRevocation(source, destination, assetClass);

        expected.permitted = false;
        expected.effectiveAt = expected.revocationEffectiveAt;
        expected.routeRevocationEvidenceHash = expected.revocationEvidenceHash;
        expected.revocationPending = false;
        expected.revocationFinalized = true;
    }

    function property_routesMatchModel() external view returns (bool) {
        for (uint256 s = 0; s < domains.length; s++) {
            for (uint256 d = 0; d < domains.length; d++) {
                for (uint256 a = 0; a < assetClasses.length; a++) {
                    (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key) = _route(s, d, a);
                    ModelRoute memory expected = model[key];
                    ITransferDomainRegistry.Route memory actual = registry.getRoute(source, destination, assetClass);

                    (bool expectedPermitted, uint64 expectedEffectiveAt) = _expectedRouteState(expected);
                    if (actual.permitted != expectedPermitted) return false;
                    if (actual.effectiveAt != expectedEffectiveAt) return false;
                    if (actual.permissionEvidenceHash != expected.permissionEvidenceHash) return false;
                    if (actual.revocationEvidenceHash != _expectedRouteRevocationEvidence(expected)) return false;
                    if (registry.isRoutePermitted(source, destination, assetClass) != expectedPermitted) return false;
                }
            }
        }
        return true;
    }

    function property_revocationsMatchModel() external view returns (bool) {
        for (uint256 s = 0; s < domains.length; s++) {
            for (uint256 d = 0; d < domains.length; d++) {
                for (uint256 a = 0; a < assetClasses.length; a++) {
                    (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key) = _route(s, d, a);
                    ModelRoute memory expected = model[key];
                    IGracefulRouteRevocation.Revocation memory actual =
                        registry.getRevocation(source, destination, assetClass);

                    if (actual.initiatedAt != expected.revocationInitiatedAt) return false;
                    if (actual.effectiveAt != expected.revocationEffectiveAt) return false;
                    if (actual.revocationEvidenceHash != expected.revocationEvidenceHash) return false;
                    if (actual.pending != expected.revocationPending) return false;
                    if (actual.finalized != expected.revocationFinalized) return false;
                }
            }
        }
        return true;
    }

    function property_batchMatchesIndividualQueries() external view returns (bool) {
        uint256 total = domains.length * domains.length * assetClasses.length;
        bytes32[] memory sources = new bytes32[](total);
        bytes32[] memory destinations = new bytes32[](total);
        bytes32[] memory assets = new bytes32[](total);

        uint256 i = 0;
        for (uint256 s = 0; s < domains.length; s++) {
            for (uint256 d = 0; d < domains.length; d++) {
                for (uint256 a = 0; a < assetClasses.length; a++) {
                    sources[i] = domains[s];
                    destinations[i] = domains[d];
                    assets[i] = assetClasses[a];
                    i++;
                }
            }
        }

        bool[] memory batch = registry.isRoutePermittedBatch(sources, destinations, assets);
        for (i = 0; i < total; i++) {
            if (batch[i] != registry.isRoutePermitted(sources[i], destinations[i], assets[i])) return false;
        }

        return true;
    }

    function _route(uint256 sourceIdx, uint256 destinationIdx, uint256 assetIdx)
        internal
        view
        returns (bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 key)
    {
        source = domains[sourceIdx % domains.length];
        destination = domains[destinationIdx % domains.length];
        assetClass = assetClasses[assetIdx % assetClasses.length];
        key = keccak256(abi.encodePacked(source, destination, assetClass));
    }

    function _modelRoutePermitted(ModelRoute memory route) internal view returns (bool) {
        if (!route.permitted) return false;
        if (route.revocationPending && block.timestamp >= route.revocationEffectiveAt) return false;
        return true;
    }

    function _expectedRouteState(ModelRoute memory route) internal view returns (bool permitted, uint64 effectiveAt) {
        permitted = _modelRoutePermitted(route);
        effectiveAt = route.effectiveAt;
        if (route.revocationPending && block.timestamp >= route.revocationEffectiveAt) {
            effectiveAt = route.revocationEffectiveAt;
        }
    }

    function _expectedRouteRevocationEvidence(ModelRoute memory route) internal view returns (bytes32) {
        if (route.revocationPending && block.timestamp >= route.revocationEffectiveAt) {
            return route.revocationEvidenceHash;
        }
        return route.routeRevocationEvidenceHash;
    }

    function _now64() internal view returns (uint64) {
        return uint64(block.timestamp);
    }
}
