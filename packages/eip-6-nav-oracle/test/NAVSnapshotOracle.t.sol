// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {INAVSnapshotOracle, NO_CORRECTION} from "../src/interfaces/INAVSnapshotOracle.sol";
import {INAVAggregation} from "../src/interfaces/INAVAggregation.sol";
import {NAVSnapshotOracle} from "../src/reference/NAVSnapshotOracle.sol";
import {EUR, PER_SHARE, PER_UNIT, TOTAL, USD} from "../src/libraries/NAVConstants.sol";

interface Vm {
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function prank(address msgSender) external;
    function warp(uint256 newTimestamp) external;
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

    function test_publishNAVStoresLatestAndProviderHistory() public {
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

    function test_aggregationRejectsMixedBasis() public {
        vm.prank(ADMIN);
        oracle.setAggregationConfig(SUBJECT, USD, 2, 10_000);
        vm.prank(ADMIN);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);

        _publish(PROVIDER_A, SUBJECT, USD, PER_SHARE, 100, 2, T0, METHOD_1, NO_CORRECTION);
        _publish(PROVIDER_B, SUBJECT, USD, PER_UNIT, 101, 2, T0, METHOD_1, NO_CORRECTION);

        vm.expectRevert(bytes("NAVSnapshotOracle: mixed navBasis"));
        oracle.aggregatedNAV(SUBJECT, USD);
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
