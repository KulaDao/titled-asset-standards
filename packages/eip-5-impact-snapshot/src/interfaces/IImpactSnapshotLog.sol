// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

uint256 constant NO_CORRECTION = type(uint256).max;

interface IImpactSnapshotLog {
    struct IndicatorSnapshot {
        bytes32 subjectId;
        bytes32 indicatorId;
        int256  value;
        uint8   decimals;
        bytes32 unit;
        uint64  periodStart;
        uint64  periodEnd;
        bytes32 methodologyHash;
        string  methodologyURI;
        address reportedBy;
        uint64  reportedAt;
        uint256 correctsIndex;
        uint256 correctedByIndex;
    }

    event SnapshotRecorded(
        bytes32 indexed subjectId,
        bytes32 indexed indicatorId,
        uint256 indexed snapshotIndex,
        int256  value,
        uint8   decimals,
        bytes32 unit,
        uint64  periodStart,
        uint64  periodEnd,
        bytes32 methodologyHash,
        uint256 correctsIndex,
        address reportedBy
    );

    function recordSnapshot(
        bytes32        subjectId,
        bytes32        indicatorId,
        int256         value,
        uint8          decimals,
        bytes32        unit,
        uint64         periodStart,
        uint64         periodEnd,
        bytes32        methodologyHash,
        string calldata methodologyURI,
        uint256        correctsIndex
    ) external returns (uint256 snapshotIndex);

    function getSnapshot(bytes32 subjectId, uint256 snapshotIndex)
        external view returns (IndicatorSnapshot memory);

    function snapshotCount(bytes32 subjectId) external view returns (uint256);

    function indicatorSnapshotCount(bytes32 subjectId, bytes32 indicatorId)
        external view returns (uint256);

    function indicatorSnapshotAt(bytes32 subjectId, bytes32 indicatorId, uint256 ordinal)
        external view returns (uint256 snapshotIndex);

    function latestIndicatorSnapshot(bytes32 subjectId, bytes32 indicatorId)
        external view returns (uint256 snapshotIndex);

    function currentSnapshotForPeriod(
        bytes32 subjectId,
        bytes32 indicatorId,
        uint64  periodStart,
        uint64  periodEnd
    ) external view returns (uint256 snapshotIndex);
}
