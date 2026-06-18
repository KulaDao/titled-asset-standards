// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {INAVSnapshotOracle, NO_CORRECTION} from "../src/interfaces/INAVSnapshotOracle.sol";
import {NAVSnapshotOracle} from "../src/reference/NAVSnapshotOracle.sol";
import {PER_SHARE, USD} from "../src/libraries/NAVConstants.sol";

contract NAVSnapshotOracleFuzzTest {
    NAVSnapshotOracle private oracle;

    bytes32 private constant SUBJECT = keccak256("subject");
    bytes32 private constant METHOD = keccak256("method");

    constructor() {
        oracle = new NAVSnapshotOracle(address(this));
        oracle.setNAVBasis(SUBJECT, USD, PER_SHARE);
        oracle.setStalenessConfig(SUBJECT, USD, 1 days, 30 days);
        oracle.setAggregationConfig(SUBJECT, USD, 1, 10_000);
    }

    function publish(uint128 rawNav, uint8 decimals) external {
        decimals = decimals % 19;
        int256 nav = int256(uint256(rawNav));
        oracle.publishNAV(SUBJECT, USD, PER_SHARE, nav, decimals, uint64(block.timestamp), METHOD, "", NO_CORRECTION);
    }

    function correctLatest(uint128 rawNav, uint8 decimals) external {
        uint256 count = oracle.snapshotCount(SUBJECT, USD);
        if (count == 0) return;

        uint256 targetIndex = count - 1;
        INAVSnapshotOracle.NAVSnapshot memory target = oracle.getSnapshot(SUBJECT, USD, targetIndex);
        if (target.correctedByIndex != 0) return;

        decimals = decimals % 19;
        int256 nav = int256(uint256(rawNav));
        oracle.publishNAV(
            SUBJECT, USD, target.navBasis, nav, decimals, target.valuationTimestamp, METHOD, "", targetIndex
        );
    }

    function property_latestSnapshotIsTerminal() external view returns (bool) {
        uint256 count = oracle.snapshotCount(SUBJECT, USD);
        if (count == 0) return true;

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
            if (snap.correctedByIndex != 0) continue;
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
        return oracle.providerSnapshotCount(SUBJECT, USD, address(this)) == oracle.snapshotCount(SUBJECT, USD);
    }

    function property_aggregationProviderCountMatchesQuorumGroup() external view returns (bool) {
        uint256 count = oracle.snapshotCount(SUBJECT, USD);
        if (count == 0) return true;

        (,,,, uint256 providerCount,,) = oracle.aggregatedNAV(SUBJECT, USD);
        return providerCount == oracle.providerSubmissionCount(SUBJECT, USD);
    }
}
