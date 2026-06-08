// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";
import {ITransferDomainRegistry} from "../src/interfaces/ITransferDomainRegistry.sol";
import {TransferDomainRegistry} from "../src/reference/TransferDomainRegistry.sol";

contract TransferDomainRegistryTest is Test {
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

    TransferDomainRegistry registry;

    address admin = address(0xA11CE);
    address registrar = address(0xB0B);
    address other = address(0xE0A);

    bytes32 constant DOMAIN_MU = keccak256("DOMAIN:MU");
    bytes32 constant DOMAIN_ZM = keccak256("DOMAIN:ZM");
    bytes32 constant DOMAIN_KE = keccak256("DOMAIN:KE");
    bytes32 constant ASSET_MINERAL = keccak256("ASSET_CLASS:MINERAL_CONCESSION");
    bytes32 constant ASSET_REAL_ESTATE = keccak256("ASSET_CLASS:REAL_ESTATE");
    bytes32 constant PERMISSION_EVIDENCE = keccak256("permission-evidence");
    bytes32 constant PERMISSION_EVIDENCE_2 = keccak256("permission-evidence-2");
    bytes32 constant REVOCATION_EVIDENCE = keccak256("revocation-evidence");

    function setUp() public {
        registry = new TransferDomainRegistry(admin);

        bytes32 registrarRole = registry.REGISTRAR_ROLE();
        vm.prank(admin);
        registry.grantRole(registrarRole, registrar);
    }

    function test_constructor_grantsAdminAndRegistrarRoles() public {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.REGISTRAR_ROLE(), admin));
        assertTrue(registry.hasRole(registry.REGISTRAR_ROLE(), registrar));
    }

    function test_constructor_revertsZeroAdmin() public {
        vm.expectRevert("TransferDomainRegistry: zero admin");
        new TransferDomainRegistry(address(0));
    }

    function test_setRoute_storesRouteAndEmits() public {
        vm.warp(1_000_000);

        vm.expectEmit(true, true, true, true);
        emit RouteSet(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE, uint64(block.timestamp));

        vm.prank(registrar);
        registry.setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertTrue(route.permitted);
        assertEq(route.effectiveAt, uint64(1_000_000));
        assertEq(route.permissionEvidenceHash, PERMISSION_EVIDENCE);
        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
    }

    function test_setRoute_revertsUnauthorized() public {
        vm.prank(other);
        vm.expectRevert();
        registry.setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
    }

    function test_routesAreDirectional() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
        assertFalse(registry.isRoutePermitted(DOMAIN_ZM, DOMAIN_MU, ASSET_MINERAL));
    }

    function test_routesAreAssetClassScoped() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        assertTrue(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
        assertFalse(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_REAL_ESTATE));
    }

    function test_routeQueryDoesNotDependOnCaller() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        vm.prank(admin);
        bool adminResult = registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        vm.prank(other);
        bool otherResult = registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertEq(adminResult, otherResult);
        assertTrue(adminResult);
    }

    function test_getRoute_returnsDefaultForUnknownRoute() public {
        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertFalse(route.permitted);
        assertEq(route.effectiveAt, 0);
        assertEq(route.permissionEvidenceHash, bytes32(0));
    }

    function test_revokeRoute_disablesRouteAndEmits() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        vm.warp(2_000_000);

        vm.expectEmit(true, true, true, true);
        emit RouteRevoked(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE, uint64(block.timestamp));

        vm.prank(registrar);
        registry.revokeRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);

        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertFalse(route.permitted);
        assertEq(route.effectiveAt, uint64(2_000_000));
        assertEq(route.permissionEvidenceHash, PERMISSION_EVIDENCE);
        assertFalse(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
    }

    function test_revokeRoute_doesNotRevertForUnknownRoute() public {
        vm.warp(3_000_000);

        vm.expectEmit(true, true, true, true);
        emit RouteRevoked(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE, uint64(block.timestamp));

        vm.prank(registrar);
        registry.revokeRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);

        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertFalse(route.permitted);
        assertEq(route.effectiveAt, uint64(3_000_000));
        assertEq(route.permissionEvidenceHash, bytes32(0));
    }

    function test_revokeRoute_doesNotRevertIfAlreadyRevoked() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        vm.prank(registrar);
        registry.revokeRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);

        vm.prank(registrar);
        registry.revokeRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, keccak256("second-revocation"));

        assertFalse(registry.isRoutePermitted(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL));
    }

    function test_setRoute_reenablesRevokedRouteWithNewPermissionEvidence() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);

        vm.prank(registrar);
        registry.revokeRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, REVOCATION_EVIDENCE);

        vm.warp(4_000_000);
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE_2);

        ITransferDomainRegistry.Route memory route = registry.getRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL);

        assertTrue(route.permitted);
        assertEq(route.effectiveAt, uint64(4_000_000));
        assertEq(route.permissionEvidenceHash, PERMISSION_EVIDENCE_2);
    }

    function test_isRoutePermittedBatch_returnsIndependentResults() public {
        _setRoute(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL, PERMISSION_EVIDENCE);
        _setRoute(DOMAIN_ZM, DOMAIN_KE, ASSET_REAL_ESTATE, PERMISSION_EVIDENCE_2);

        bytes32[] memory sources = new bytes32[](4);
        bytes32[] memory destinations = new bytes32[](4);
        bytes32[] memory assets = new bytes32[](4);

        sources[0] = DOMAIN_MU;
        destinations[0] = DOMAIN_ZM;
        assets[0] = ASSET_MINERAL;

        sources[1] = DOMAIN_ZM;
        destinations[1] = DOMAIN_MU;
        assets[1] = ASSET_MINERAL;

        sources[2] = DOMAIN_ZM;
        destinations[2] = DOMAIN_KE;
        assets[2] = ASSET_REAL_ESTATE;

        sources[3] = DOMAIN_ZM;
        destinations[3] = DOMAIN_KE;
        assets[3] = ASSET_MINERAL;

        bool[] memory permitted = registry.isRoutePermittedBatch(sources, destinations, assets);

        assertTrue(permitted[0]);
        assertFalse(permitted[1]);
        assertTrue(permitted[2]);
        assertFalse(permitted[3]);
    }

    function test_isRoutePermittedBatch_revertsLengthMismatch() public {
        bytes32[] memory sources = new bytes32[](1);
        bytes32[] memory destinations = new bytes32[](2);
        bytes32[] memory assets = new bytes32[](1);

        vm.expectRevert("TransferDomainRegistry: array length mismatch");
        registry.isRoutePermittedBatch(sources, destinations, assets);
    }

    function test_isRoutePermittedBatch_revertsAboveMaxBatchSize() public {
        uint256 length = registry.MAX_BATCH_SIZE() + 1;
        bytes32[] memory sources = new bytes32[](length);
        bytes32[] memory destinations = new bytes32[](length);
        bytes32[] memory assets = new bytes32[](length);

        vm.expectRevert("TransferDomainRegistry: batch too large");
        registry.isRoutePermittedBatch(sources, destinations, assets);
    }

    function test_supportsInterface() public {
        assertTrue(registry.supportsInterface(type(ITransferDomainRegistry).interfaceId));
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
        assertFalse(registry.supportsInterface(bytes4(0xffffffff)));
    }

    function test_routeKey_matchesCanonicalKey() public {
        assertEq(
            registry.routeKey(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL),
            keccak256(abi.encodePacked(DOMAIN_MU, DOMAIN_ZM, ASSET_MINERAL))
        );
    }

    function _setRoute(bytes32 source, bytes32 destination, bytes32 assetClass, bytes32 evidenceHash) internal {
        vm.prank(registrar);
        registry.setRoute(source, destination, assetClass, evidenceHash);
    }
}
