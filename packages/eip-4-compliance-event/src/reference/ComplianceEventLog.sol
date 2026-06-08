// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IComplianceEventLog, NO_CORRECTION} from "../interfaces/IComplianceEventLog.sol";
import {EVT_CORRECTION} from "../libraries/ComplianceConstants.sol";

contract ComplianceEventLog is IComplianceEventLog {
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

    uint256 public constant MAX_PARTIES = 10;
    uint256 public constant MAX_PAYLOAD_BYTES = 2048;
    uint64 public constant MAX_BACKDATE_SECONDS = 30 days;

    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER");

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    mapping(bytes32 => mapping(address => bool)) private _roles;
    mapping(bytes32 => ComplianceEvent[]) private _events;
    mapping(bytes32 => mapping(bytes32 => uint256[])) private _eventsByType;

    constructor(address admin) {
        require(admin != address(0), "ComplianceEventLog: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RECORDER_ROLE, admin);
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "ComplianceEventLog: missing role");
        _;
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

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
    ) external onlyRole(RECORDER_ROLE) returns (uint256 eventIndex) {
        _validateTemporal(occurredAt);
        require(evidenceHash != bytes32(0), "ComplianceEventLog: zero evidenceHash");
        require(parties.length <= MAX_PARTIES, "ComplianceEventLog: too many parties");
        require(payload.length <= MAX_PAYLOAD_BYTES, "ComplianceEventLog: payload too large");

        eventIndex = _events[subjectId].length;

        if (correctsIndex == NO_CORRECTION) {
            require(eventType != EVT_CORRECTION, "ComplianceEventLog: correction missing target");
        } else {
            require(eventType == EVT_CORRECTION, "ComplianceEventLog: correction event type required");
            require(correctsIndex < eventIndex, "ComplianceEventLog: correctsIndex out of range");

            ComplianceEvent storage target = _events[subjectId][correctsIndex];
            require(target.correctedByIndex == 0, "ComplianceEventLog: target already corrected");
            require(
                target.actor == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
                "ComplianceEventLog: correction not authorized"
            );
            target.correctedByIndex = eventIndex;
        }

        ComplianceEvent storage stored = _events[subjectId].push();
        stored.subjectId = subjectId;
        stored.subjectType = subjectType;
        stored.eventType = eventType;
        stored.outcome = outcome;
        stored.actor = msg.sender;
        stored.authority = authority;
        stored.evidenceHash = evidenceHash;
        stored.evidenceURI = evidenceURI;
        stored.payloadProfileId = payloadProfileId;
        stored.payload = payload;
        stored.operationRef = operationRef;
        stored.occurredAt = occurredAt;
        stored.recordedAt = uint64(block.timestamp);
        stored.correctsIndex = correctsIndex;
        stored.correctedByIndex = 0;

        for (uint256 i = 0; i < parties.length; i++) {
            stored.parties.push(Party({addr: parties[i].addr, role: parties[i].role}));
        }

        _eventsByType[subjectId][eventType].push(eventIndex);

        emit ComplianceEventRecorded(
            subjectId, eventType, msg.sender, eventIndex, outcome, authority, occurredAt, correctsIndex
        );
    }

    function getEvent(bytes32 subjectId, uint256 eventIndex) external view returns (ComplianceEvent memory) {
        require(eventIndex < _events[subjectId].length, "ComplianceEventLog: eventIndex out of range");
        return _copyEvent(_events[subjectId][eventIndex]);
    }

    function eventCount(bytes32 subjectId) external view returns (uint256) {
        return _events[subjectId].length;
    }

    function eventCountByType(bytes32 subjectId, bytes32 eventType) external view returns (uint256) {
        return _eventsByType[subjectId][eventType].length;
    }

    function eventByTypeAt(bytes32 subjectId, bytes32 eventType, uint256 ordinal)
        external
        view
        returns (uint256 eventIndex)
    {
        uint256[] storage indices = _eventsByType[subjectId][eventType];
        require(ordinal < indices.length, "ComplianceEventLog: ordinal out of range");
        return indices[ordinal];
    }

    function latestEventByType(bytes32 subjectId, bytes32 eventType) external view returns (uint256 eventIndex) {
        uint256[] storage indices = _eventsByType[subjectId][eventType];
        require(indices.length != 0, "ComplianceEventLog: no events for type");
        return indices[indices.length - 1];
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC165 || interfaceId == type(IComplianceEventLog).interfaceId;
    }

    function _grantRole(bytes32 role, address account) internal {
        require(account != address(0), "ComplianceEventLog: zero account");
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _validateTemporal(uint64 occurredAt) internal view {
        require(block.timestamp <= type(uint64).max, "ComplianceEventLog: timestamp overflow");
        require(occurredAt <= block.timestamp, "ComplianceEventLog: future event");
        require(block.timestamp - uint256(occurredAt) <= MAX_BACKDATE_SECONDS, "ComplianceEventLog: event too old");
    }

    function _copyEvent(ComplianceEvent storage stored) internal view returns (ComplianceEvent memory copy) {
        copy.subjectId = stored.subjectId;
        copy.subjectType = stored.subjectType;
        copy.eventType = stored.eventType;
        copy.outcome = stored.outcome;
        copy.actor = stored.actor;
        copy.authority = stored.authority;
        copy.evidenceHash = stored.evidenceHash;
        copy.evidenceURI = stored.evidenceURI;
        copy.payloadProfileId = stored.payloadProfileId;
        copy.payload = stored.payload;
        copy.operationRef = stored.operationRef;
        copy.occurredAt = stored.occurredAt;
        copy.recordedAt = stored.recordedAt;
        copy.correctsIndex = stored.correctsIndex;
        copy.correctedByIndex = stored.correctedByIndex;

        copy.parties = new Party[](stored.parties.length);
        for (uint256 i = 0; i < stored.parties.length; i++) {
            copy.parties[i] = stored.parties[i];
        }
    }
}
