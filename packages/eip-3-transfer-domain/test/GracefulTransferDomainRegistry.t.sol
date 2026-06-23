// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";
import {IGracefulRouteRevocation} from "../src/interfaces/IGracefulRouteRevocation.sol";
import {ITransferDomainRegistry} from "../src/interfaces/ITransferDomainRegistry.sol";
import {GracefulTransferDomainRegistry} from "../src/reference/GracefulTransferDomainRegistry.sol";

contract GracefulTransferDomainRegistryTest is Test {
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

    GracefulTransferDomainRegistry registry;

    address admin = address(0xA11CE);
    address registrar = address(0xB0B);
    address other = address(0xE0A);

    uint64 constant GRACE_PERIOD = 1 days;
    bytes32 constant DOMAIN_MU = keccak256("DOMAIN:MU");
    bytes32 constant DOMAIN_ZM = keccak256("DOMAIN:ZM");
    bytes32 constant DOMAIN_KE = keccak256("DOMAIN:KE");
    bytes32 constant ASSET_MINERAL = keccak256("ASSET_CLASS:MINERAL_CONCESSION");
    bytes32 constant ASSET_REAL_ESTATE = keccak256("ASSET_CLASS:REAL_ESTATE");
    bytes32 constant PERMISSION_EVIDENCE = keccak256("permission-evidence");
    bytes32 constant PERMISSION_EVIDENCE_2 = keccak256("permission-evidence-2");
    bytes32 constant REVOCATION_EVIDENCE = keccak256("revocation-evidence");
    bytes32 constant CANCELLATION_EVIDENCE = keccak256("cancellation-evidence");

    function setUp() public {
        registry = new GracefulTransferDomainRegistry(admin, GRACE_PERIOD);

        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.grantRole(registrarRole, registrar);
    }

    function test_constructor_storesGracePeriod() public {
        assertEq(registry.gracePeriod(), GRACE_PERIOD);
    }

    function test_constructor_revertsZeroGracePeriod() public {
        vm.expectRevert("GracefulTransferDomainRegistry: zero grace period");
        new GracefulTransferDomainRegistry(admin, 0);
    }

    function test_supportsBaseAndGracefulInterfaces() public {
        assertTrue(registry.supportsInterface(type(ITransferDomainRegistry).interfaceId));
        assertTrue(registry.supportsInterface(type(IGracefulRouteRevocation).interfaceId));
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
    }

    function test_initiateRevocation_recordsPendingStateAndEmits() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        vm.warp(1_100_000);
        uint64 expectedEffectiveAt = uint64(block.timestamp + GRACE_PERIOD);

        vm.expectEmit(true, true, true, true);
        emit RouteRevocationInitiated(
            DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE, uint64(block.timestamp), expectedEffectiveAt
        );

        vm.prank(registrar);
        registry.initiateRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertEq(revocation.initiatedAt, uint64(1_100_000));
        assertEq(revocation.effectiveAt, expectedEffectiveAt);
        assertEq(revocation.revocationEvidenceHash, REVOCATION_EVIDENCE);
        assertTrue(revocation.pending);
        assertFalse(revocation.finalized);
        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
    }

    function test_initiateRevocation_revertsUnknownRoute() public {
        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: route not permitted");
        registry.initiateRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);
    }

    function test_initiateRevocation_revertsZeroRevocationEvidenceHash() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: zero revocationEvidenceHash");
        registry.initiateRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, bytes32(0));
    }

    function test_initiateRevocation_revertsZeroRouteIdentifiers() public {
        vm.prank(registrar);
        vm.expectRevert("TransferDomainRegistry: zero sourceDomain");
        registry.initiateRevocation(bytes32(0), DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);

        vm.prank(registrar);
        vm.expectRevert("TransferDomainRegistry: zero destinationDomain");
        registry.initiateRevocation(DOMAIN_MU, bytes32(0), ASSET_MINERAL, REVOCATION_EVIDENCE);

        vm.prank(registrar);
        vm.expectRevert("TransferDomainRegistry: zero assetClass");
        registry.initiateRevocation(DOMAIN_MU, DOMAIN_ZM, bytes32(0), REVOCATION_EVIDENCE);
    }

    function test_initiateRevocation_revertsUnauthorized() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        vm.prank(other);
        vm.expectRevert();
        registry.initiateRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);
    }

    function test_initiateRevocation_revertsIfAlreadyPending() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: revocation pending");
        registry.initiateRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);
    }

    function test_pendingRouteRemainsPermittedUntilEffectiveAt() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.warp(revocation.effectiveAt - 1);
        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));

        vm.warp(revocation.effectiveAt);
        assertFalse(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
    }

    function test_getRouteReflectsLazyRevocationAfterEffectiveAt() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.warp(revocation.effectiveAt - 1);
        ITransferDomainRegistry.Route memory pendingRoute = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        assertTrue(pendingRoute.permitted);
        assertEq(pendingRoute.revocationEvidenceHash, bytes32(0));

        vm.warp(revocation.effectiveAt);
        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertFalse(route.permitted);
        assertEq(route.effectiveAt, revocation.effectiveAt);
        assertEq(route.permissionEvidenceHash, PERMISSION_EVIDENCE);
        assertEq(route.revocationEvidenceHash, REVOCATION_EVIDENCE);
    }

    function test_finalizeRevocation_afterGracePeriodEmitsOnceAndStoresFinalizedState() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory beforeFinalize =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.warp(beforeFinalize.effectiveAt);

        vm.expectEmit(true, true, true, true);
        emit RouteRevoked(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE, beforeFinalize.effectiveAt);

        vm.prank(registrar);
        registry.finalizeRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory afterFinalize =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertFalse(afterFinalize.pending);
        assertTrue(afterFinalize.finalized);
        assertFalse(route.permitted);
        assertEq(route.effectiveAt, beforeFinalize.effectiveAt);
        assertEq(route.revocationEvidenceHash, REVOCATION_EVIDENCE);

        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: no revocation");
        registry.finalizeRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
    }

    function test_finalizeRevocation_isPermissionlessAfterGracePeriod() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory beforeFinalize =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.warp(beforeFinalize.effectiveAt);
        vm.prank(other);
        registry.finalizeRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory afterFinalize =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertFalse(afterFinalize.pending);
        assertTrue(afterFinalize.finalized);
        assertFalse(route.permitted);
        assertEq(route.effectiveAt, beforeFinalize.effectiveAt);
        assertEq(route.revocationEvidenceHash, REVOCATION_EVIDENCE);
    }

    function test_finalizeRevocation_revertsBeforeGracePeriodExpires() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: grace period active");
        registry.finalizeRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
    }

    function test_finalizeRevocation_revertsIfNoRevocation() public {
        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: no revocation");
        registry.finalizeRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
    }

    function test_finalizeRevocation_revertsZeroRouteIdentifiers() public {
        vm.expectRevert("TransferDomainRegistry: zero sourceDomain");
        registry.finalizeRevocation(bytes32(0), DOMAIN_ZM, ASSET_MINERAL);
    }

    function test_cancelRevocation_beforeExpiryClearsStateAndKeepsRoutePermitted() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.warp(revocation.effectiveAt - 1);

        vm.expectEmit(true, true, true, true);
        emit RouteRevocationCancelled(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, CANCELLATION_EVIDENCE);

        vm.prank(registrar);
        registry.cancelRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, CANCELLATION_EVIDENCE);

        IGracefulRouteRevocation.Revocation memory cancelled =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        assertEq(cancelled.initiatedAt, 0);
        assertEq(cancelled.effectiveAt, 0);
        assertFalse(cancelled.pending);
        assertFalse(cancelled.finalized);

        vm.warp(revocation.effectiveAt + 10);
        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
    }

    function test_cancelRevocation_revertsIfNoPendingRevocation() public {
        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: no pending revocation");
        registry.cancelRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, CANCELLATION_EVIDENCE);
    }

    function test_cancelRevocation_revertsZeroCancellationEvidenceHash() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: zero cancellationEvidenceHash");
        registry.cancelRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, bytes32(0));
    }

    function test_cancelRevocation_revertsAfterExpiry() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.warp(revocation.effectiveAt);

        vm.prank(registrar);
        vm.expectRevert("GracefulTransferDomainRegistry: grace period expired");
        registry.cancelRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, CANCELLATION_EVIDENCE);
    }

    function test_immediateRevokeClearsPendingGracefulRevocation() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.prank(registrar);
        registry.revokeRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertFalse(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
        assertEq(route.revocationEvidenceHash, REVOCATION_EVIDENCE);
        assertFalse(revocation.pending);
        assertFalse(revocation.finalized);
    }

    function test_setRouteDuringActiveGracePeriodClearsPendingRevocation() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory beforeReset =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertTrue(beforeReset.pending);
        assertFalse(beforeReset.finalized);
        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));

        vm.warp(beforeReset.effectiveAt - 1);
        uint64 expectedEffectiveAt = uint64(block.timestamp);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE_2);

        IGracefulRouteRevocation.Revocation memory reset = registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertTrue(route.permitted);
        assertEq(route.effectiveAt, expectedEffectiveAt);
        assertEq(route.permissionEvidenceHash, PERMISSION_EVIDENCE_2);
        assertEq(route.revocationEvidenceHash, bytes32(0));
        assertEq(reset.initiatedAt, 0);
        assertEq(reset.effectiveAt, 0);
        assertEq(reset.revocationEvidenceHash, bytes32(0));
        assertFalse(reset.pending);
        assertFalse(reset.finalized);

        vm.warp(beforeReset.effectiveAt);
        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
    }

    function test_setRouteAfterFinalizedRevocationReenablesAndClearsRevocationState() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.warp(revocation.effectiveAt);
        vm.prank(registrar);
        registry.finalizeRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE_2);

        IGracefulRouteRevocation.Revocation memory reset = registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertTrue(route.permitted);
        assertEq(route.permissionEvidenceHash, PERMISSION_EVIDENCE_2);
        assertEq(route.revocationEvidenceHash, bytes32(0));
        assertFalse(reset.pending);
        assertFalse(reset.finalized);
    }

    function test_batchReflectsLazyRevocationIndependently() public {
        vm.warp(1_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _setRoute(DOMAIN_ZM, DOMAIN_KE, ASSET_REAL_ESTATE, PERMISSION_EVIDENCE_2);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        vm.warp(revocation.effectiveAt);

        bytes32[] memory sources = new bytes32[](2);
        bytes32[] memory destinations = new bytes32[](2);
        bytes32[] memory assets = new bytes32[](2);

        sources[0] = DOMAIN_MU;
        destinations[0] = DOMAIN_ZM;
        assets[0] = ASSET_MINERAL;

        sources[1] = DOMAIN_ZM;
        destinations[1] = DOMAIN_KE;
        assets[1] = ASSET_REAL_ESTATE;

        bool[] memory permitted = registry.isRoutePermittedBatch(sources, destinations, assets);
        assertFalse(permitted[0]);
        assertTrue(permitted[1]);
    }

    function test_gracefulRevocationIsRouteScoped() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _setRoute(DOMAIN_ZM, DOMAIN_MU, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _initiate(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        IGracefulRouteRevocation.Revocation memory revocation =
            registry.getRevocation(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);
        vm.warp(revocation.effectiveAt);

        assertFalse(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
        assertTrue(registry.isRoutePermitted(DOMAIN_ZM, DOMAIN_MU, ASSET_MINERAL));
    }

    function _setRoute(bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 evidenceHash) internal {
        vm.prank(registrar);
        registry.setRoute(source, destination, assetClass, evidenceHash);
    }

    function _initiate(bytes32 source, bytes32 destination, bytes32 assetClass) internal {
        vm.prank(registrar);
        registry.initiateRevocation(source, destination, assetClass, REVOCATION_EVIDENCE);
    }
}
