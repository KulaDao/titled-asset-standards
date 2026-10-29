// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {INAVSnapshotOracle, NO_CORRECTION} from "../src/interfaces/INAVSnapshotOracle.sol";
import {NAVSnapshotOracle} from "../src/reference/NAVSnapshotOracle.sol";
import {PER_SHARE, USD} from "../src/libraries/NAVConstants.sol";

interface MedusaCheats {
    function warp(uint256 newTimestamp) external;
}

contract NAVProviderActor {
    NAVSnapshotOracle private immutable oracle;

    constructor(NAVSnapshotOracle oracle_) {
        oracle = oracle_;
    }

    function publish(
        bytes32 subjectId,
        bytes32 currency,
        bytes32 navBasis,
        int256 nav,
        uint8 decimals,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        uint256 correctsIndex
    ) external returns (uint256) {
        return oracle.publishNAV(
            subjectId, currency, navBasis, nav, decimals, valuationTimestamp, methodologyHash, "", correctsIndex
        );
    }
}

contract NAVSnapshotOracleFuzzTest {
    uint256 private constant PROVIDER_COUNT = 3;
    uint256 private constant QUORUM = 2;
    uint64 private constant MAX_SUBMISSION_AGE = 1 days;
    uint64 private constant MAX_VALUATION_AGE = 30 days;
    uint64 private constant VALUATION_TIMESTAMP = 1_700_000_000;

    struct ModelSubmission {
        bool active;
        uint256 snapshotIndex;
        int256 nav;
        uint8 decimals;
        uint64 publishedAt;
    }

    NAVSnapshotOracle private oracle;
    NAVProviderActor[PROVIDER_COUNT] private providers;
    ModelSubmission[PROVIDER_COUNT] private model;

    bytes32 private constant SUBJECT = keccak256("subject");
    bytes32 private constant METHOD = keccak256("method");

    constructor() {
        _vm().warp(VALUATION_TIMESTAMP);
        oracle = new NAVSnapshotOracle(address(this));
        oracle.setNAVBasis(SUBJECT, USD, PER_SHARE);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, MAX_VALUATION_AGE);
        oracle.setAggregationConfig(SUBJECT, USD, QUORUM, 10_000, MAX_SUBMISSION_AGE);

        bytes32 providerRole = oracle.PROVIDER_ROLE();
        for (uint256 i = 0; i < PROVIDER_COUNT; i++) {
            providers[i] = new NAVProviderActor(oracle);
            oracle.grantRole(providerRole, address(providers[i]));
        }

        // Seed original, correction, and invalidation paths before Medusa starts
        // varying provider updates and block time.
        _publishForProvider(0, 100, 2);
        _publishForProvider(1, 200, 2);
        _publishForProvider(2, 300, 2);
        _publishForProvider(0, 110, 2);
        oracle.invalidateSnapshot(SUBJECT, USD, model[2].snapshotIndex, keccak256("seed invalidation"));
        model[2].active = false;
    }

    function fuzz_publish(uint8 providerIndex, uint128 rawNav, uint8 decimals) external {
        providerIndex = uint8(uint256(providerIndex) % PROVIDER_COUNT);
        decimals = decimals % 19;
        int256 nav = int256(uint256(rawNav % type(uint64).max));
        _publishForProvider(providerIndex, nav, decimals);
    }

    function fuzz_invalidate(uint8 providerIndex) external {
        providerIndex = uint8(uint256(providerIndex) % PROVIDER_COUNT);
        ModelSubmission storage submission = model[providerIndex];
        if (!submission.active) return;

        INAVSnapshotOracle.NAVSnapshot memory target = oracle.getSnapshot(SUBJECT, USD, submission.snapshotIndex);

        try oracle.invalidateSnapshot(
            SUBJECT, USD, submission.snapshotIndex, keccak256(abi.encode("invalidate", providerIndex))
        ) {
            if (target.correctsIndex == NO_CORRECTION) {
                submission.active = false;
            } else {
                _setModelFromSnapshot(providerIndex, target.correctsIndex);
            }
        } catch {}
    }

    function property_latestSnapshotIsTerminal() external view returns (bool) {
        uint256 count = oracle.snapshotCount(SUBJECT, USD);
        if (count == 0) return true;

        bool hasTerminal;
        for (uint256 i = 0; i < count; i++) {
            INAVSnapshotOracle.NAVSnapshot memory snap = oracle.getSnapshot(SUBJECT, USD, i);
            if (snap.correctedByIndex == 0 && !oracle.isSnapshotInvalidated(SUBJECT, USD, i)) {
                hasTerminal = true;
                break;
            }
        }

        if (!hasTerminal) {
            try oracle.latestNAV(SUBJECT, USD) returns (int256, uint8, bytes32, uint64, uint64, address) {
                return false;
            } catch {
                return true;
            }
        }

        (
            int256 latestNav,
            uint8 latestDecimals,
            bytes32 latestBasis,
            uint64 latestValuation,
            uint64 latestPublishedAt,
            address latestProvider
        ) = oracle.latestNAV(SUBJECT, USD);

        bool foundExactTerminal;
        for (uint256 i = 0; i < count; i++) {
            INAVSnapshotOracle.NAVSnapshot memory snap = oracle.getSnapshot(SUBJECT, USD, i);
            if (snap.correctedByIndex != 0 || oracle.isSnapshotInvalidated(SUBJECT, USD, i)) continue;
            if (snap.valuationTimestamp > latestValuation) return false;
            if (snap.valuationTimestamp == latestValuation && snap.publishedAt > latestPublishedAt) return false;
            if (
                snap.nav == latestNav && snap.decimals == latestDecimals && snap.navBasis == latestBasis
                    && snap.valuationTimestamp == latestValuation && snap.publishedAt == latestPublishedAt
                    && snap.provider == latestProvider
            ) {
                foundExactTerminal = true;
            }
        }

        return foundExactTerminal;
    }

    function property_correctionsAreForkFree() external view returns (bool) {
        uint256 count = oracle.snapshotCount(SUBJECT, USD);
        for (uint256 i = 0; i < count; i++) {
            INAVSnapshotOracle.NAVSnapshot memory snap = oracle.getSnapshot(SUBJECT, USD, i);
            if (snap.correctedByIndex != 0) {
                if (snap.correctedByIndex >= count) return false;
                INAVSnapshotOracle.NAVSnapshot memory correction =
                    oracle.getSnapshot(SUBJECT, USD, snap.correctedByIndex);
                if (correction.correctsIndex != i) return false;
            }
        }
        return true;
    }

    function property_providerHistoryCoversAllSnapshots() external view returns (bool) {
        uint256 historyCount;
        for (uint256 i = 0; i < PROVIDER_COUNT; i++) {
            historyCount += oracle.providerSnapshotCount(SUBJECT, USD, address(providers[i]));
        }
        return historyCount == oracle.snapshotCount(SUBJECT, USD);
    }

    function property_freshAggregationMatchesIndependentModel() external view returns (bool) {
        (uint256 eligibleCount, uint256 freshCount, int256 expectedMedian, uint8 expectedDecimals) =
            _expectedAggregation();
        bool shouldAggregate = eligibleCount >= QUORUM && freshCount >= QUORUM;

        try oracle.aggregatedNAV(SUBJECT, USD) returns (
            int256 median,
            uint8 decimals,
            bytes32 basis,
            uint64 valuationTimestamp,
            uint256 freshProviderCount,
            bool valuationStale
        ) {
            if (!shouldAggregate) return false;
            return median == expectedMedian && decimals == expectedDecimals && basis == PER_SHARE
                && valuationTimestamp == VALUATION_TIMESTAMP && freshProviderCount == freshCount
                && valuationStale == _valuationIsStale();
        } catch {
            return !shouldAggregate;
        }
    }

    function _publishForProvider(uint256 providerIndex, int256 nav, uint8 decimals) internal {
        ModelSubmission storage submission = model[providerIndex];
        uint256 correctsIndex = submission.active ? submission.snapshotIndex : NO_CORRECTION;

        try providers[providerIndex].publish(
            SUBJECT, USD, PER_SHARE, nav, decimals, VALUATION_TIMESTAMP, METHOD, correctsIndex
        ) returns (
            uint256 snapshotIndex
        ) {
            submission.active = true;
            submission.snapshotIndex = snapshotIndex;
            submission.nav = nav;
            submission.decimals = decimals;
            submission.publishedAt = uint64(block.timestamp);
        } catch {}
    }

    function _setModelFromSnapshot(uint256 providerIndex, uint256 snapshotIndex) internal {
        INAVSnapshotOracle.NAVSnapshot memory snapshot = oracle.getSnapshot(SUBJECT, USD, snapshotIndex);
        ModelSubmission storage submission = model[providerIndex];
        submission.active = true;
        submission.snapshotIndex = snapshotIndex;
        submission.nav = snapshot.nav;
        submission.decimals = snapshot.decimals;
        submission.publishedAt = snapshot.publishedAt;
    }

    function _expectedAggregation()
        internal
        view
        returns (uint256 eligibleCount, uint256 freshCount, int256 median, uint8 maxDecimals)
    {
        int256[PROVIDER_COUNT] memory values;
        for (uint256 i = 0; i < PROVIDER_COUNT; i++) {
            ModelSubmission storage submission = model[i];
            if (!submission.active) continue;
            eligibleCount++;
            if (!_isFresh(submission)) continue;

            freshCount++;
            if (submission.decimals > maxDecimals) maxDecimals = submission.decimals;
        }

        if (freshCount == 0) return (eligibleCount, 0, 0, maxDecimals);

        uint256 valueIndex;
        for (uint256 i = 0; i < PROVIDER_COUNT; i++) {
            ModelSubmission storage submission = model[i];
            if (!submission.active || !_isFresh(submission)) continue;
            values[valueIndex++] = submission.nav * int256(10 ** uint256(maxDecimals - submission.decimals));
        }

        for (uint256 i = 1; i < freshCount; i++) {
            int256 value = values[i];
            uint256 j = i;
            while (j > 0 && values[j - 1] > value) {
                values[j] = values[j - 1];
                j--;
            }
            values[j] = value;
        }

        median = values[(freshCount - 1) / 2];
    }

    function _isFresh(ModelSubmission storage submission) internal view returns (bool) {
        return block.timestamp <= uint256(submission.publishedAt) + MAX_SUBMISSION_AGE;
    }

    function _valuationIsStale() internal view returns (bool) {
        return block.timestamp > uint256(VALUATION_TIMESTAMP) + MAX_VALUATION_AGE;
    }

    function _vm() internal pure returns (MedusaCheats) {
        return MedusaCheats(address(uint160(uint256(keccak256("hevm cheat code")))));
    }
}
