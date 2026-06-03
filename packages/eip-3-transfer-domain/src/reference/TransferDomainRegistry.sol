// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ITransferDomainRegistry} from "../interfaces/ITransferDomainRegistry.sol";
import {TransferRouteLib} from "../libraries/TransferRouteLib.sol";

contract TransferDomainRegistry is ITransferDomainRegistry, AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR");

    mapping(bytes32 => Route) internal _routes;

    constructor(address admin) {
        require(admin != address(0), "TransferDomainRegistry: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function isRoutePermitted(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        public
        view
        virtual
        returns (bool)
    {
        return _isRoutePermitted(_routeKey(sourceDomain, destinationDomain, assetClass));
    }

    function getRoute(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        public
        view
        virtual
        returns (Route memory)
    {
        return _getRoute(_routeKey(sourceDomain, destinationDomain, assetClass));
    }

    function setRoute(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 permissionEvidenceHash
    ) public virtual onlyRole(REGISTRAR_ROLE) {
        bytes32 key = _routeKey(sourceDomain, destinationDomain, assetClass);
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
    ) public virtual onlyRole(REGISTRAR_ROLE) {
        bytes32 key = _routeKey(sourceDomain, destinationDomain, assetClass);
        uint64 effectiveAt = _now64();

        _routes[key].permitted = false;
        _routes[key].effectiveAt = effectiveAt;

        emit RouteRevoked(sourceDomain, destinationDomain, assetClass, revocationEvidenceHash, effectiveAt);
    }

    function isRoutePermittedBatch(
        bytes32[] calldata sourceDomains,
        bytes32[] calldata destinationDomains,
        bytes32[] calldata assetClasses
    ) external view returns (bool[] memory permitted) {
        require(
            sourceDomains.length == destinationDomains.length && destinationDomains.length == assetClasses.length,
            "TransferDomainRegistry: array length mismatch"
        );

        permitted = new bool[](sourceDomains.length);
        for (uint256 i = 0; i < sourceDomains.length; i++) {
            permitted[i] = _isRoutePermitted(_routeKey(sourceDomains[i], destinationDomains[i], assetClasses[i]));
        }
    }

    function routeKey(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        external
        pure
        returns (bytes32)
    {
        return _routeKey(sourceDomain, destinationDomain, assetClass);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ITransferDomainRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _isRoutePermitted(bytes32 key) internal view virtual returns (bool) {
        return _routes[key].permitted;
    }

    function _getRoute(bytes32 key) internal view virtual returns (Route memory) {
        return _routes[key];
    }

    function _routeKey(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        internal
        pure
        returns (bytes32)
    {
        return TransferRouteLib.routeKey(sourceDomain, destinationDomain, assetClass);
    }

    function _now64() internal view returns (uint64) {
        require(block.timestamp <= type(uint64).max, "TransferDomainRegistry: timestamp overflow");
        return uint64(block.timestamp);
    }
}
