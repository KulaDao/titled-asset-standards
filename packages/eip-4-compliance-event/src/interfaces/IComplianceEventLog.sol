// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

uint256 constant NO_CORRECTION = type(uint256).max;

interface IComplianceEventLog {
    struct Party {
        address addr;
        bytes32 role;
    }

    struct ComplianceEvent {
        bytes32 subjectId;
        bytes32 subjectType;
        bytes32 eventType;
        bytes32 outcome;
        address actor;
        bytes32 authority;
        Party[] parties;
        bytes32 evidenceHash;
        string evidenceURI;
        bytes32 payloadProfileId;
        bytes payload;
        bytes32 operationRef;
        uint64 occurredAt;
        uint64 recordedAt;
        uint256 correctsIndex;
        uint256 correctedByIndex;
    }

    event ComplianceEventRecorded(
        bytes32 indexed subjectId,
        bytes32 indexed eventType,
        address indexed actor,
        uint256 eventIndex,
        bytes32 outcome,
        bytes32 authority,
        uint64 occurredAt,
        uint256 correctsIndex
    );

    function recordEvent(
        bytes32 subjectId,
        bytes32 subjectType,
        bytes32 eventType,
        bytes32 outcome,
        bytes32 authority,
        Party[] calldata parties,
        bytes32 evidenceHash,
        string calldata evidenceURI,
        bytes32 payloadProfileId,
        bytes calldata payload,
        bytes32 operationRef,
        uint64 occurredAt,
        uint256 correctsIndex
    ) external returns (uint256 eventIndex);

    function getEvent(bytes32 subjectId, uint256 eventIndex) external view returns (ComplianceEvent memory);

    function eventCount(bytes32 subjectId) external view returns (uint256);

    function eventCountByType(bytes32 subjectId, bytes32 eventType) external view returns (uint256);

    function eventByTypeAt(bytes32 subjectId, bytes32 eventType, uint256 ordinal)
        external
        view
        returns (uint256 eventIndex);

    function latestEventByType(bytes32 subjectId, bytes32 eventType) external view returns (uint256 eventIndex);
}
