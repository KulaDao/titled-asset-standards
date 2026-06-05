// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface INAVAggregation {
    event NAVDeviationDetected(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        uint64 valuationTimestamp,
        int256 minNav,
        int256 maxNav,
        uint256 deviationBps
    );

    event AggregationConfigUpdated(
        bytes32 indexed subjectId, bytes32 indexed currency, uint256 quorum, uint256 deviationThresholdBps
    );

    function setAggregationConfig(bytes32 subjectId, bytes32 currency, uint256 quorum, uint256 deviationThresholdBps)
        external;

    function aggregatedNAV(bytes32 subjectId, bytes32 currency)
        external
        view
        returns (
            int256 nav,
            uint8 decimals,
            bytes32 navBasis,
            uint64 valuationTimestamp,
            uint256 providerCount,
            bool isPublishStale,
            bool isValuationStale
        );

    function providerSubmissionCount(bytes32 subjectId, bytes32 currency) external view returns (uint256);

    function providerSubmissionAt(bytes32 subjectId, bytes32 currency, uint256 index)
        external
        view
        returns (
            uint256 snapshotIndex,
            address provider,
            int256 nav,
            uint8 decimals,
            bytes32 navBasis,
            uint64 valuationTimestamp,
            uint64 publishedAt
        );

    function latestAggregationTimestamp(bytes32 subjectId, bytes32 currency) external view returns (uint64);

    function quorum(bytes32 subjectId, bytes32 currency) external view returns (uint256);

    function deviationThreshold(bytes32 subjectId, bytes32 currency) external view returns (uint256);
}
