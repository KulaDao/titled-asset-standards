// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {INAVSnapshotOracle, NO_CORRECTION} from "../src/interfaces/INAVSnapshotOracle.sol";
import {INAVAggregation} from "../src/interfaces/INAVAggregation.sol";
import {NAVSnapshotOracle} from "../src/reference/NAVSnapshotOracle.sol";
import {EUR, PER_SHARE, PER_UNIT, TOTAL, USD, deriveTokenCurrency} from "../src/libraries/NAVConstants.sol";

interface Vm {
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function prank(address msgSender) external;
    function warp(uint256 newTimestamp) external;
    function addr(uint256 privateKey) external returns (address keyAddr);
}

contract NAVSnapshotOracleTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    event NAVDeviationDetected(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        uint64 valuationTimestamp,
        int256 minNav,
        int256 maxNav,
        uint256 deviationBps
    );

    event NAVPublished(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        address indexed provider,
        uint256 snapshotIndex,
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        uint256 correctsIndex
    );

    event NAVBasisConfigured(bytes32 indexed subjectId, bytes32 indexed currency, bytes32 navBasis);

    event NAVSnapshotInvalidated(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        address indexed provider,
        uint256 snapshotIndex,
        address invalidatedBy,
        bytes32 reasonHash
    );

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    NAVSnapshotOracle private oracle;

    address private constant ADMIN = address(0xA0);
    address private constant PROVIDER_A = address(0xA1);
    address private constant PROVIDER_B = address(0xA2);
    address private constant PROVIDER_C = address(0xA3);
    address private constant OUTSIDER = address(0xB0);

    bytes32 private constant SUBJECT = keccak256("subject");
    bytes32 private constant SUBJECT_2 = keccak256("subject-2");
    bytes32 private constant METHOD_1 = keccak256("methodology-v1");
    bytes32 private constant METHOD_2 = keccak256("methodology-v2");

    uint64 private constant T0 = 1_700_000_000;
    uint64 private constant T1 = 1_700_086_400;
    uint64 private constant T2 = 1_700_172_800;

    function setUp() public {
        oracle = new NAVSnapshotOracle(ADMIN);
        bytes32 providerRole = oracle.PROVIDER_ROLE();

        vm.prank(ADMIN);
        oracle.grantRole(providerRole, PROVIDER_A);
        vm.prank(ADMIN);
        oracle.grantRole(providerRole, PROVIDER_B);
        vm.prank(ADMIN);
        oracle.grantRole(providerRole, PROVIDER_C);

        _configureBasis(SUBJECT, USD, PER_SHARE);
        _configureBasis(SUBJECT, EUR, PER_SHARE);
        _configureBasis(SUBJECT_2, USD, PER_SHARE);
    }

    function test_constructorRejectsZeroAdmin() public {
        vm.expectRevert(bytes("NAVSnapshotOracle: zero admin"));
        new NAVSnapshotOracle(address(0));
    }

    function test_setStalenessConfigStoresThresholds() public {
        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);

        _assertEq(oracle.heartbeat(SUBJECT, USD), 1 days, "heartbeat");
        _assertEq(oracle.maxValuationAge(SUBJECT, USD), 30 days, "max valuation age");
    }

    function test_setStalenessConfigRequiresConfigRole() public {
        vm.prank(OUTSIDER);
        vm.expectRevert(bytes("NAVSnapshotOracle: missing role"));
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);
    }

    function test_setStalenessConfigRejectsZeroThresholds() public {
        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: zero heartbeat"));
        oracle.setStalenessConfig(SUBJECT, USD, 0, 30 days);

        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: zero maxValuationAge"));
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 0);
    }

    function test_setNAVBasisStoresConfiguredBasis() public {
        vm.expectEmit(true, true, false, true);
        emit NAVBasisConfigured(SUBJECT_2, EUR, PER_UNIT);
        _configureBasis(SUBJECT_2, EUR, PER_UNIT);

        _assertEq(oracle.streamNAVBasis(SUBJECT_2, EUR), PER_UNIT, "stream nav basis");
    }

    function test_setNAVBasisRejectsInvalidOrRepeatedConfig() public {
        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: unknown navBasis"));
        oracle.setNAVBasis(SUBJECT_2, EUR, keccak256("BAD"));

        _configureBasis(SUBJECT_2, EUR, PER_UNIT);

        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: navBasis already configured"));
        oracle.setNAVBasis(SUBJECT_2, EUR, TOTAL);
    }

    function test_publishNAVRequiresConfiguredBasis() public {
        vm.warp(T0);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: navBasis unconfigured"));
        oracle.publishNAV(SUBJECT_2, EUR, PER_SHARE, 100, 2, T0, METHOD_1, "", NO_CORRECTION);
    }

    function test_grantRoleEmitsAndAllowsProvider() public {
        bytes32 providerRole = oracle.PROVIDER_ROLE();

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(providerRole, OUTSIDER, ADMIN);
        vm.prank(ADMIN);
        oracle.grantRole(providerRole, OUTSIDER);

        _assertTrue(oracle.hasRole(providerRole, OUTSIDER), "outsider granted provider role");
        _publish(OUTSIDER, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
    }

    function test_revokeRoleEmitsAndBlocksProvider() public {
        bytes32 providerRole = oracle.PROVIDER_ROLE();

        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(providerRole, PROVIDER_A, ADMIN);
        vm.prank(ADMIN);
        oracle.revokeRole(providerRole, PROVIDER_A);

        vm.warp(T0);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: missing role"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, "", NO_CORRECTION);
    }

    function test_publishNAVStoresLatestAndProviderHistory() public {
        vm.expectEmit(true, true, true, true);
        emit NAVPublished(SUBJECT, USD, PROVIDER_A, 0, 123_456, 4, PER_SHARE, T0, METHOD_1, NO_CORRECTION);
        uint256 idx = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 123_456, 4, T0, METHOD_1, NO_CORRECTION);

        _assertEq(idx, 0, "index");
        _assertEq(oracle.snapshotCount(SUBJECT, USD), 1, "snapshot count");
        _assertEq(oracle.providerSnapshotCount(SUBJECT, USD, PROVIDER_A), 1, "provider count");
        _assertEq(oracle.providerSnapshotAt(SUBJECT, USD, PROVIDER_A, 0), 0, "provider index");

        INAVSnapshotOracle.NAVSnapshot memory snap = oracle.getSnapshot(SUBJECT, USD, 0);
        _assertEq(snap.subjectId, SUBJECT, "subject");
        _assertEq(snap.currency, USD, "currency");
        _assertEq(snap.navBasis, PER_SHARE, "basis");
        _assertEq(snap.nav, 123_456, "nav");
        _assertEq(snap.decimals, 4, "decimals");
        _assertEq(snap.valuationTimestamp, T0, "valuation timestamp");
        _assertEq(snap.publishedAt, T0, "published at");
        _assertEq(snap.provider, PROVIDER_A, "provider");
        _assertEq(snap.methodologyHash, METHOD_1, "method");
        _assertEq(snap.methodologyURI, "ipfs://method", "method uri");
        _assertEq(snap.correctsIndex, NO_CORRECTION, "corrects");
        _assertEq(snap.correctedByIndex, 0, "corrected by");

        (int256 nav, uint8 decimals, bytes32 basis, uint64 valuationTimestamp, uint64 publishedAt, address provider) =
            oracle.latestNAV(SUBJECT, USD);
        _assertEq(nav, 123_456, "latest nav");
        _assertEq(decimals, 4, "latest decimals");
        _assertEq(basis, PER_SHARE, "latest basis");
        _assertEq(valuationTimestamp, T0, "latest valuation");
        _assertEq(publishedAt, T0, "latest published");
        _assertEq(provider, PROVIDER_A, "latest provider");
    }

    function test_publishNAVRequiresProviderRole() public {
        vm.warp(T0);
        vm.prank(OUTSIDER);
        vm.expectRevert(bytes("NAVSnapshotOracle: missing role"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, "", NO_CORRECTION);
    }

    function test_publishNAVRejectsInvalidFields() public {
        vm.warp(T0);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: unknown navBasis"));
        oracle.publishNAV(SUBJECT, USD, keccak256("BAD"), 100, 2, T0, METHOD_1, "", NO_CORRECTION);

        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: decimals too high"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 100, 19, T0, METHOD_1, "", NO_CORRECTION);

        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: future valuation"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 100, 2, T1, METHOD_1, "", NO_CORRECTION);

        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: unsupported nav"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, type(int256).min, 2, T0, METHOD_1, "", NO_CORRECTION);

        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: nav too large"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, type(int256).max, 2, T0, METHOD_1, "", NO_CORRECTION);
    }

    function test_publishNAVRejectsZeroMethodologyHash() public {
        vm.warp(T0);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: zero methodologyHash"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 100, 2, T0, bytes32(0), "", NO_CORRECTION);
    }

    function test_publishNAVAllowsEmptyMethodologyURI() public {
        vm.warp(T0);
        vm.prank(PROVIDER_A);
        uint256 idx = oracle.publishNAV(SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, "", NO_CORRECTION);

        INAVSnapshotOracle.NAVSnapshot memory snap = oracle.getSnapshot(SUBJECT, USD, idx);
        _assertEq(snap.methodologyHash, METHOD_1, "methodology hash");
        _assertEq(snap.methodologyURI, "", "methodology uri");
    }

    function test_publishNAVUsesDecimalAwareMagnitudeLimit() public {
        int256 maxDecimals18 = type(int256).max;
        uint256 idx = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, maxDecimals18, 18, T0, METHOD_1, NO_CORRECTION);
        _assertEq(idx, 0, "max decimals 18 index");

        (int256 latestNav, uint8 latestDecimals,,,,) = oracle.latestNAV(SUBJECT, USD);
        _assertEq(latestNav, maxDecimals18, "max decimals 18 accepted");
        _assertEq(latestDecimals, 18, "latest decimals");

        int256 maxDecimals17 = type(int256).max / 10;
        _publish(PROVIDER_A, SUBJECT, EUR, PER_SHARE, maxDecimals17, 17, T0, METHOD_1, NO_CORRECTION);

        vm.warp(T1);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: nav too large"));
        oracle.publishNAV(SUBJECT_2, USD, PER_SHARE, maxDecimals17 + 1, 17, T1, METHOD_1, "", NO_CORRECTION);
    }

    function test_publishNAVRejectsDuplicateProviderTimestampOriginal() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: duplicate submission"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 101, 2, T0, METHOD_1, "", NO_CORRECTION);
    }

    function test_latestNAVStatusRevertsUntilConfigured() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.expectRevert(bytes("NAVSnapshotOracle: heartbeat unconfigured"));
        oracle.latestNAVStatus(SUBJECT, USD);
    }

    function test_latestNAVStatusDetectsBothStalenessModes() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 100, 1_000);

        vm.warp(T0 + 50);
        (,,,,,, bool publishStaleEarly, bool valuationStaleEarly) = oracle.latestNAVStatus(SUBJECT, USD);
        _assertFalse(publishStaleEarly, "publish not stale early");
        _assertFalse(valuationStaleEarly, "valuation not stale early");

        vm.warp(T0 + 101);
        (,,,,,, bool publishStale, bool valuationStale) = oracle.latestNAVStatus(SUBJECT, USD);
        _assertTrue(publishStale, "publish stale");
        _assertFalse(valuationStale, "valuation not stale");

        vm.warp(T0 + 1_001);
        (,,,,,, bool publishStillStale, bool valuationNowStale) = oracle.latestNAVStatus(SUBJECT, USD);
        _assertTrue(publishStillStale, "publish still stale");
        _assertTrue(valuationNowStale, "valuation stale");
    }

    function test_correctionUpdatesTargetAndLatestWhenCorrectingCurrentValuation() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        uint256 correctionIndex = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 110, 2, T0, METHOD_2, 0);

        _assertEq(correctionIndex, 1, "correction index");
        INAVSnapshotOracle.NAVSnapshot memory original = oracle.getSnapshot(SUBJECT, USD, 0);
        _assertEq(original.correctedByIndex, 1, "original corrected by");

        INAVSnapshotOracle.NAVSnapshot memory latest = oracle.latestNAVByProvider(SUBJECT, USD, PROVIDER_A);
        _assertEq(latest.nav, 110, "provider latest correction");

        (int256 nav,,,,,) = oracle.latestNAV(SUBJECT, USD);
        _assertEq(nav, 110, "stream latest correction");
    }

    function test_currentSnapshotIndexFollowsCorrectionChain() public {
        uint256 original = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        uint256 correction = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 110, 2, T0, METHOD_2, original);
        uint256 terminal = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 120, 2, T0, METHOD_2, correction);

        _assertEq(oracle.currentSnapshotIndex(SUBJECT, USD, original), terminal, "original resolves to terminal");
        _assertEq(oracle.currentSnapshotIndex(SUBJECT, USD, correction), terminal, "correction resolves to terminal");
        _assertEq(oracle.currentSnapshotIndex(SUBJECT, USD, terminal), terminal, "terminal resolves to self");
        _assertFalse(oracle.isSnapshotCurrent(SUBJECT, USD, original), "original corrected");
        _assertFalse(oracle.isSnapshotCurrent(SUBJECT, USD, correction), "middle correction corrected");
        _assertTrue(oracle.isSnapshotCurrent(SUBJECT, USD, terminal), "terminal current");
    }

    function test_currentSnapshotHelpersRevertOutOfRange() public {
        vm.expectRevert(bytes("NAVSnapshotOracle: snapshotIndex out of range"));
        oracle.currentSnapshotIndex(SUBJECT, USD, 0);

        vm.expectRevert(bytes("NAVSnapshotOracle: snapshotIndex out of range"));
        oracle.isSnapshotCurrent(SUBJECT, USD, 0);
    }

    function test_correctionCannotForkOrCrossProvider() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 110, 2, T0, METHOD_2, 0);

        vm.warp(T0 + 2);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: target already corrected"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 120, 2, T0, METHOD_2, "", 0);

        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 200, 2, T1, METHOD_1, NO_CORRECTION);

        vm.warp(T1 + 1);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: provider mismatch"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 210, 2, T1, METHOD_2, "", 2);
    }

    function test_correctionMustMatchValuationTimestampAndBasis() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.warp(T1);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: valuation mismatch"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 110, 2, T1, METHOD_2, "", 0);

        vm.warp(T0 + 1);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: navBasis mismatch"));
        oracle.publishNAV(SUBJECT, USD, TOTAL, 110, 2, T0, METHOD_2, "", 0);
    }

    function test_correctionMustTargetLatestProviderTimestampSnapshot() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 110, 2, T0, METHOD_2, 0);

        vm.warp(T0 + 2);
        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: target already corrected"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 120, 2, T0, METHOD_2, "", 0);
    }

    function test_latestNAVUsesMostRecentValuationNotLateOldCorrection() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 200, 2, T1, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 111, 2, T0, METHOD_2, 0);

        (int256 nav,,, uint64 valuationTimestamp,,) = oracle.latestNAV(SUBJECT, USD);
        _assertEq(nav, 200, "newer valuation remains latest");
        _assertEq(valuationTimestamp, T1, "latest valuation timestamp");
    }

    function test_streamsAreScopedBySubjectAndCurrency() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, EUR, PER_SHARE, 200, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT_2, USD, PER_SHARE, 300, 2, T0, METHOD_1, NO_CORRECTION);

        _assertEq(oracle.snapshotCount(SUBJECT, USD), 1, "subject usd");
        _assertEq(oracle.snapshotCount(SUBJECT, EUR), 1, "subject eur");
        _assertEq(oracle.snapshotCount(SUBJECT_2, USD), 1, "subject2 usd");

        (int256 navUsd,,,,,) = oracle.latestNAV(SUBJECT, USD);
        (int256 navEur,,,,,) = oracle.latestNAV(SUBJECT, EUR);
        (int256 navSubject2,,,,,) = oracle.latestNAV(SUBJECT_2, USD);
        _assertEq(navUsd, 100, "usd nav");
        _assertEq(navEur, 200, "eur nav");
        _assertEq(navSubject2, 300, "subject2 nav");
    }

    function test_aggregationRequiresConfigAndQuorum() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.expectRevert(bytes("NAVSnapshotOracle: quorum unconfigured"));
        oracle.aggregatedNAV(SUBJECT, USD);

        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 1_000);

        vm.expectRevert(bytes("NAVSnapshotOracle: quorum not met"));
        oracle.aggregatedNAV(SUBJECT, USD);
    }

    function test_setAggregationConfigRejectsDeviationThresholdAboveBpsScale() public {
        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: deviationThresholdBps too high"));
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_001);
    }

    function test_setAggregationConfigRejectsQuorumAboveProviderCap() public {
        uint256 cap = oracle.MAX_PROVIDERS_PER_VALUATION();

        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: quorum too high"));
        oracle.setAggregationConfig(SUBJECT, USD, cap + 1, 10_000);
    }

    function test_publishNAVRejectsProviderSetAboveCap() public {
        bytes32 providerRole = oracle.PROVIDER_ROLE();
        uint256 cap = oracle.MAX_PROVIDERS_PER_VALUATION();

        for (uint256 i = 0; i < cap; i++) {
            address provider = vm.addr(10_000 + i);
            vm.prank(ADMIN);
            oracle.grantRole(providerRole, provider);
            _publish(provider, SUBJECT, USD, PER_SHARE, 100, 2, T2, METHOD_1, NO_CORRECTION);
        }

        address excessProvider = vm.addr(10_000 + cap);
        vm.prank(ADMIN);
        oracle.grantRole(providerRole, excessProvider);

        vm.prank(excessProvider);
        vm.expectRevert(bytes("NAVSnapshotOracle: provider cap exceeded"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 200, 2, T2, METHOD_1, "", NO_CORRECTION);
    }

    function test_aggregationMedianNormalizesDecimalsAndReturnsLatestQuorumTimestamp() public {
        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);
        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100_00, 2, T1, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 101_000, 3, T1, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_C, SUBJECT, USD, PER_SHARE, 99_00, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 98_000, 3, T0, METHOD_1, NO_CORRECTION);

        (
            int256 nav,
            uint8 decimals,
            bytes32 basis,
            uint64 valuationTimestamp,
            uint256 providerCount,
            bool publishStale,
            bool valuationStale
        ) = oracle.aggregatedNAV(SUBJECT, USD);

        _assertEq(nav, 100_000, "lower median normalized to 3 decimals");
        _assertEq(decimals, 3, "aggregation decimals");
        _assertEq(basis, PER_SHARE, "aggregation basis");
        _assertEq(valuationTimestamp, T1, "latest quorum timestamp");
        _assertEq(providerCount, 2, "provider count");
        _assertFalse(publishStale, "publish not stale");
        _assertFalse(valuationStale, "valuation not stale");
    }

    function test_aggregationProviderSubmissionAtUsesLatestQuorumTimestamp() public {
        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 101, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 200, 2, T1, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 201, 2, T1, METHOD_1, NO_CORRECTION);

        _assertEq(oracle.providerSubmissionCount(SUBJECT, USD), 2, "submission count");
        _assertEq(oracle.latestAggregationTimestamp(SUBJECT, USD), T1, "aggregation timestamp");

        (uint256 snapshotIndex, address provider,,,, uint64 valuationTimestamp,) =
            oracle.providerSubmissionAt(SUBJECT, USD, 0);
        _assertTrue(snapshotIndex == 2 || snapshotIndex == 3, "snapshot index in latest timestamp");
        _assertTrue(provider == PROVIDER_A || provider == PROVIDER_B, "provider in latest timestamp");
        _assertEq(valuationTimestamp, T1, "submission timestamp");
    }

    function test_setAggregationConfigRecomputesHistoricalLatestEligibleTimestamp() public {
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 101, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 200, 2, T1, METHOD_1, NO_CORRECTION);

        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);
        _assertEq(oracle.latestAggregationTimestamp(SUBJECT, USD), T0, "historical quorum timestamp");

        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 201, 2, T1, METHOD_1, NO_CORRECTION);
        _assertEq(oracle.latestAggregationTimestamp(SUBJECT, USD), T1, "incrementally updated timestamp");
    }

    function test_publishNAVRejectsMismatchedStreamBasis() public {
        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);
        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.prank(PROVIDER_B);
        vm.expectRevert(bytes("NAVSnapshotOracle: navBasis mismatch"));
        oracle.publishNAV(SUBJECT, USD, PER_UNIT, 101, 2, T0, METHOD_1, "", NO_CORRECTION);

        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 101, 2, T0, METHOD_1, NO_CORRECTION);

        (,, bytes32 basis,,,,) = oracle.aggregatedNAV(SUBJECT, USD);
        _assertEq(basis, PER_SHARE, "aggregation basis");
    }

    function test_setNAVBasisRejectsReconfigurationAfterPublish() public {
        _configureBasis(SUBJECT_2, EUR, PER_SHARE);
        _publish(PROVIDER_A, SUBJECT_2, EUR, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: navBasis already configured"));
        oracle.setNAVBasis(SUBJECT_2, EUR, PER_SHARE);
    }

    function test_aggregationDoesNotBrickAfterRejectedMismatchedBasis() public {
        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);
        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.prank(PROVIDER_B);
        vm.expectRevert(bytes("NAVSnapshotOracle: navBasis mismatch"));
        oracle.publishNAV(SUBJECT, USD, PER_UNIT, 101, 2, T0, METHOD_1, "", NO_CORRECTION);

        vm.expectRevert(bytes("NAVSnapshotOracle: quorum not met"));
        oracle.aggregatedNAV(SUBJECT, USD);

        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 101, 2, T0, METHOD_1, NO_CORRECTION);

        (int256 nav,, bytes32 basis,,,,) = oracle.aggregatedNAV(SUBJECT, USD);
        _assertEq(nav, 100, "lower median after valid provider submission");
        _assertEq(basis, PER_SHARE, "stream basis after rejected mismatch");
    }

    function test_aggregationUsesCorrectedProviderSubmission() public {
        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);
        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 200, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 120, 2, T0, METHOD_2, 1);

        (int256 nav,,,,,,) = oracle.aggregatedNAV(SUBJECT, USD);
        _assertEq(nav, 100, "lower median uses corrected terminal values");

        (uint256 snapshotIndex, address provider, int256 submissionNav,,,,) =
            oracle.providerSubmissionAt(SUBJECT, USD, 1);
        _assertEq(snapshotIndex, 2, "corrected provider snapshot index");
        _assertEq(provider, PROVIDER_B, "corrected provider");
        _assertEq(submissionNav, 120, "corrected provider nav");
    }

    function test_deviationEventEmitsFromPublishPath() public {
        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 100);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.expectEmit(true, true, false, true);
        emit NAVDeviationDetected(SUBJECT, USD, T0, 100, 150, 5_000);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 150, 2, T0, METHOD_1, NO_CORRECTION);
    }

    function test_deviationOverflowReturnsMaxInsteadOfReverting() public {
        int256 huge = type(int256).max / 1e18;
        int256 normalizedMin = -huge * int256(1e18);

        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 100);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, -huge, 0, T0, METHOD_1, NO_CORRECTION);

        vm.expectEmit(true, true, false, true);
        emit NAVDeviationDetected(SUBJECT, USD, T0, normalizedMin, huge, type(uint256).max);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, huge, 18, T0, METHOD_1, NO_CORRECTION);
    }

    function test_adminInvalidationEvictsRevokedProviderAndFallsBackToPriorQuorum() public {
        bytes32 reasonHash = keccak256("revoked provider poisoned snapshot");

        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);
        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 30 days, 30 days);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 110, 2, T0, METHOD_1, NO_CORRECTION);
        uint256 poisonedIndex = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 1_000, 2, T1, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_SHARE, 120, 2, T1, METHOD_1, NO_CORRECTION);

        bytes32 providerRole = oracle.PROVIDER_ROLE();
        vm.prank(ADMIN);
        oracle.revokeRole(providerRole, PROVIDER_A);

        vm.expectEmit(true, true, true, true);
        emit NAVSnapshotInvalidated(SUBJECT, USD, PROVIDER_A, poisonedIndex, ADMIN, reasonHash);
        vm.prank(ADMIN);
        oracle.invalidateSnapshot(SUBJECT, USD, poisonedIndex, reasonHash);

        _assertTrue(oracle.isSnapshotInvalidated(SUBJECT, USD, poisonedIndex), "snapshot invalidated");
        _assertFalse(oracle.isSnapshotCurrent(SUBJECT, USD, poisonedIndex), "invalidated snapshot not current");
        _assertEq(oracle.latestAggregationTimestamp(SUBJECT, USD), T0, "aggregation falls back to prior quorum");
        _assertEq(oracle.providerSubmissionCount(SUBJECT, USD), 2, "prior quorum provider count");

        (int256 aggregatedNav,,, uint64 valuationTimestamp, uint256 providerCount,,) =
            oracle.aggregatedNAV(SUBJECT, USD);
        _assertEq(aggregatedNav, 100, "prior quorum median");
        _assertEq(valuationTimestamp, T0, "prior quorum timestamp");
        _assertEq(providerCount, 2, "aggregation provider count");

        INAVSnapshotOracle.NAVSnapshot memory providerLatest = oracle.latestNAVByProvider(SUBJECT, USD, PROVIDER_A);
        _assertEq(providerLatest.nav, 100, "provider latest falls back");
    }

    function test_invalidateSnapshotRejectsUnauthorizedAndInvalidStates() public {
        uint256 original = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);

        vm.prank(PROVIDER_B);
        vm.expectRevert(bytes("NAVSnapshotOracle: missing role"));
        oracle.invalidateSnapshot(SUBJECT, USD, original, keccak256("unauthorized"));

        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: zero reasonHash"));
        oracle.invalidateSnapshot(SUBJECT, USD, original, bytes32(0));

        vm.prank(ADMIN);
        oracle.invalidateSnapshot(SUBJECT, USD, original, keccak256("invalid"));

        vm.expectRevert(bytes("NAVSnapshotOracle: no snapshots"));
        oracle.latestNAV(SUBJECT, USD);
        vm.expectRevert(bytes("NAVSnapshotOracle: no provider snapshot"));
        oracle.latestNAVByProvider(SUBJECT, USD, PROVIDER_A);

        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: already invalidated"));
        oracle.invalidateSnapshot(SUBJECT, USD, original, keccak256("again"));

        vm.prank(PROVIDER_A);
        vm.expectRevert(bytes("NAVSnapshotOracle: target invalidated"));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, 110, 2, T0, METHOD_2, "", original);
    }

    function test_invalidateSnapshotRejectsCorrectedSnapshot() public {
        uint256 original = _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 110, 2, T0, METHOD_2, original);

        vm.prank(ADMIN);
        vm.expectRevert(bytes("NAVSnapshotOracle: snapshot not current"));
        oracle.invalidateSnapshot(SUBJECT, USD, original, keccak256("superseded"));
    }

    function test_deriveTokenCurrencyUsesChainAndTokenDomain() public pure {
        address token = address(0xC0FFEE);
        bytes32 expected = keccak256(abi.encodePacked("ERC-XXXX:CURRENCY:TOKEN", uint256(1), token));

        _assertEq(deriveTokenCurrency(1, token), expected, "token currency derivation");
    }

    function test_supportsInterfaces() public view {
        _assertTrue(oracle.supportsInterface(0x01ffc9a7), "erc165");
        _assertTrue(oracle.supportsInterface(type(INAVSnapshotOracle).interfaceId), "oracle interface");
        _assertTrue(oracle.supportsInterface(type(INAVAggregation).interfaceId), "aggregation interface");
        _assertFalse(oracle.supportsInterface(0xffffffff), "unsupported interface");
    }

    function _publish(
        address provider,
        bytes32 subjectId,
        bytes32 currency,
        bytes32 navBasis,
        int256 nav,
        uint8 decimals,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        uint256 correctsIndex
    ) internal returns (uint256) {
        if (block.timestamp < valuationTimestamp) vm.warp(uint256(valuationTimestamp));
        if (correctsIndex != NO_CORRECTION && block.timestamp <= valuationTimestamp) {
            vm.warp(uint256(valuationTimestamp) + 1);
        }
        vm.prank(provider);
        return oracle.publishNAV(
            subjectId,
            currency,
            navBasis,
            nav,
            decimals,
            valuationTimestamp,
            methodologyHash,
            "ipfs://method",
            correctsIndex
        );
    }

    function _configureBasis(bytes32 subjectId, bytes32 currency, bytes32 navBasis) internal {
        vm.prank(ADMIN);
        oracle.setNAVBasis(subjectId, currency, navBasis);
    }

    function _assertTrue(bool condition, string memory message) internal pure {
        require(condition, message);
    }

    function _assertFalse(bool condition, string memory message) internal pure {
        require(!condition, message);
    }

    function _assertEq(uint256 actual, uint256 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function _assertEq(int256 actual, int256 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function _assertEq(bytes32 actual, bytes32 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function _assertEq(address actual, address expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function _assertEq(string memory actual, string memory expected, string memory message) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), message);
    }
}
