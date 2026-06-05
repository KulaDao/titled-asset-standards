// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ComplianceEventLog} from "../src/reference/ComplianceEventLog.sol";
import {IComplianceEventLog, NO_CORRECTION} from "../src/interfaces/IComplianceEventLog.sol";
import {
    SUBJECT_TOKEN,
    EVT_TRANSFER,
    EVT_FREEZE,
    EVT_CORRECTION,
    ROLE_SENDER,
    ROLE_RECEIVER,
    ROLE_TARGET,
    OUTCOME_APPROVED,
    OUTCOME_EXECUTED,
    AUTHORITY_INTERNAL_POLICY,
    AUTHORITY_COURT_ORDER,
    PAYLOAD_TRANSFER_V1,
    PAYLOAD_FREEZE_V1
} from "../src/libraries/ComplianceConstants.sol";

interface Vm {
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function prank(address msgSender) external;
    function warp(uint256 newTimestamp) external;
}

contract ComplianceEventLogTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    ComplianceEventLog private log;

    address private constant ADMIN = address(0xA0);
    address private constant RECORDER = address(0xA1);
    address private constant RECORDER_2 = address(0xA2);
    address private constant OUTSIDER = address(0xB0);
    address private constant ALICE = address(0xC0);
    address private constant BOB = address(0xC1);

    bytes32 private constant SUBJECT = keccak256("subject");
    bytes32 private constant SUBJECT_2 = keccak256("subject-2");
    bytes32 private constant EVIDENCE = keccak256("evidence");
    bytes32 private constant OPERATION_REF = keccak256("operation");

    uint64 private constant T0 = 1_700_000_000;

    function setUp() public {
        log = new ComplianceEventLog(ADMIN);
        bytes32 recorderRole = log.RECORDER_ROLE();

        vm.prank(ADMIN);
        log.grantRole(recorderRole, RECORDER);
        vm.prank(ADMIN);
        log.grantRole(recorderRole, RECORDER_2);
    }

    function test_constructorRejectsZeroAdmin() public {
        vm.expectRevert(bytes("ComplianceEventLog: zero admin"));
        new ComplianceEventLog(address(0));
    }

    function test_grantAndRevokeRecorderRole() public {
        bytes32 recorderRole = log.RECORDER_ROLE();

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(recorderRole, OUTSIDER, ADMIN);
        vm.prank(ADMIN);
        log.grantRole(recorderRole, OUTSIDER);
        _assertTrue(log.hasRole(recorderRole, OUTSIDER), "role granted");

        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(recorderRole, OUTSIDER, ADMIN);
        vm.prank(ADMIN);
        log.revokeRole(recorderRole, OUTSIDER);
        _assertFalse(log.hasRole(recorderRole, OUTSIDER), "role revoked");
    }

    function test_recordEventStoresAndIndexes() public {
        IComplianceEventLog.Party[] memory parties = _transferParties();
        bytes memory payload = abi.encode(ALICE, BOB, uint256(100), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ComplianceEventRecorded(
            SUBJECT, EVT_TRANSFER, RECORDER, 0, OUTCOME_APPROVED, AUTHORITY_INTERNAL_POLICY, T0, NO_CORRECTION
        );
        uint256 index = _record(
            RECORDER,
            SUBJECT,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            parties,
            PAYLOAD_TRANSFER_V1,
            payload,
            T0,
            NO_CORRECTION
        );

        _assertEq(index, 0, "event index");
        _assertEq(log.eventCount(SUBJECT), 1, "subject count");
        _assertEq(log.eventCountByType(SUBJECT, EVT_TRANSFER), 1, "type count");
        _assertEq(log.eventByTypeAt(SUBJECT, EVT_TRANSFER, 0), 0, "type ordinal");
        _assertEq(log.latestEventByType(SUBJECT, EVT_TRANSFER), 0, "latest type");

        IComplianceEventLog.ComplianceEvent memory stored = log.getEvent(SUBJECT, 0);
        _assertEq(stored.subjectId, SUBJECT, "subject");
        _assertEq(stored.subjectType, SUBJECT_TOKEN, "subject type");
        _assertEq(stored.eventType, EVT_TRANSFER, "event type");
        _assertEq(stored.outcome, OUTCOME_APPROVED, "outcome");
        _assertEq(stored.actor, RECORDER, "actor");
        _assertEq(stored.authority, AUTHORITY_INTERNAL_POLICY, "authority");
        _assertEq(stored.evidenceHash, EVIDENCE, "evidence");
        _assertEq(stored.evidenceURI, "ipfs://evidence", "evidence uri");
        _assertEq(stored.payloadProfileId, PAYLOAD_TRANSFER_V1, "profile");
        _assertEq(keccak256(stored.payload), keccak256(payload), "payload");
        _assertEq(stored.operationRef, OPERATION_REF, "operation ref");
        _assertEq(stored.occurredAt, T0, "occurred at");
        _assertEq(stored.recordedAt, T0, "recorded at");
        _assertEq(stored.correctsIndex, NO_CORRECTION, "corrects");
        _assertEq(stored.correctedByIndex, 0, "corrected by");
        _assertEq(stored.parties.length, 2, "party count");
        _assertEq(stored.parties[0].addr, ALICE, "party 0 addr");
        _assertEq(stored.parties[0].role, ROLE_SENDER, "party 0 role");
        _assertEq(stored.parties[1].addr, BOB, "party 1 addr");
        _assertEq(stored.parties[1].role, ROLE_RECEIVER, "party 1 role");
    }

    function test_recordEventRequiresRecorderRole() public {
        vm.warp(T0);
        vm.prank(OUTSIDER);
        vm.expectRevert(bytes("ComplianceEventLog: missing role"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0,
            NO_CORRECTION
        );
    }

    function test_recordEventRejectsTemporalViolations() public {
        vm.warp(T0);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: future event"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0 + 1,
            NO_CORRECTION
        );

        vm.warp(uint256(T0) + log.MAX_BACKDATE_SECONDS() + 1);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: event too old"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0,
            NO_CORRECTION
        );
    }

    function test_recordEventRejectsPartiesAndPayloadAboveCaps() public {
        IComplianceEventLog.Party[] memory parties = new IComplianceEventLog.Party[](log.MAX_PARTIES() + 1);
        for (uint256 i = 0; i < parties.length; i++) {
            parties[i] = IComplianceEventLog.Party({addr: ALICE, role: ROLE_TARGET});
        }

        vm.warp(T0);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: too many parties"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_FREEZE,
            OUTCOME_EXECUTED,
            AUTHORITY_COURT_ORDER,
            parties,
            EVIDENCE,
            "",
            PAYLOAD_FREEZE_V1,
            "",
            OPERATION_REF,
            T0,
            NO_CORRECTION
        );

        bytes memory payload = new bytes(log.MAX_PAYLOAD_BYTES() + 1);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: payload too large"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_FREEZE,
            OUTCOME_EXECUTED,
            AUTHORITY_COURT_ORDER,
            _targetParty(),
            EVIDENCE,
            "",
            PAYLOAD_FREEZE_V1,
            payload,
            OPERATION_REF,
            T0,
            NO_CORRECTION
        );
    }

    function test_correctionsAreForkFreeAndIndexedByCorrectionType() public {
        _record(
            RECORDER,
            SUBJECT,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            PAYLOAD_TRANSFER_V1,
            abi.encode(ALICE, BOB, uint256(100), bytes32(0)),
            T0,
            NO_CORRECTION
        );

        uint256 correction = _record(
            RECORDER,
            SUBJECT,
            EVT_CORRECTION,
            OUTCOME_EXECUTED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            PAYLOAD_TRANSFER_V1,
            abi.encode(EVT_TRANSFER, uint256(0)),
            T0 + 1,
            0
        );

        _assertEq(correction, 1, "correction index");
        _assertEq(log.getEvent(SUBJECT, 0).correctedByIndex, 1, "target corrected by");
        _assertEq(log.getEvent(SUBJECT, 1).correctsIndex, 0, "correction corrects");
        _assertEq(log.eventCountByType(SUBJECT, EVT_CORRECTION), 1, "correction type count");
        _assertEq(log.latestEventByType(SUBJECT, EVT_CORRECTION), 1, "latest correction");

        vm.warp(T0 + 2);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: target already corrected"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_CORRECTION,
            OUTCOME_EXECUTED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0 + 2,
            0
        );
    }

    function test_correctionValidation() public {
        _record(
            RECORDER,
            SUBJECT,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            PAYLOAD_TRANSFER_V1,
            "",
            T0,
            NO_CORRECTION
        );

        vm.warp(T0 + 1);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: correction missing target"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_CORRECTION,
            OUTCOME_EXECUTED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0 + 1,
            NO_CORRECTION
        );

        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: correction event type required"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_TRANSFER,
            OUTCOME_EXECUTED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0 + 1,
            0
        );

        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: correctsIndex out of range"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_CORRECTION,
            OUTCOME_EXECUTED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0 + 1,
            99
        );
    }

    function test_correctionRequiresOriginalActorOrAdmin() public {
        _record(
            RECORDER,
            SUBJECT,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            PAYLOAD_TRANSFER_V1,
            "",
            T0,
            NO_CORRECTION
        );

        vm.warp(T0 + 1);
        vm.prank(RECORDER_2);
        vm.expectRevert(bytes("ComplianceEventLog: correction not authorized"));
        log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_CORRECTION,
            OUTCOME_EXECUTED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0 + 1,
            0
        );

        vm.prank(ADMIN);
        uint256 correction = log.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_CORRECTION,
            OUTCOME_EXECUTED,
            AUTHORITY_COURT_ORDER,
            _transferParties(),
            EVIDENCE,
            "",
            PAYLOAD_TRANSFER_V1,
            "",
            OPERATION_REF,
            T0 + 1,
            0
        );
        _assertEq(correction, 1, "admin correction");
    }

    function test_typeIndexingAndSubjectIsolation() public {
        _record(
            RECORDER,
            SUBJECT,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            PAYLOAD_TRANSFER_V1,
            "",
            T0,
            NO_CORRECTION
        );
        _record(
            RECORDER,
            SUBJECT,
            EVT_FREEZE,
            OUTCOME_EXECUTED,
            AUTHORITY_COURT_ORDER,
            _targetParty(),
            PAYLOAD_FREEZE_V1,
            "",
            T0 + 1,
            NO_CORRECTION
        );
        _record(
            RECORDER,
            SUBJECT_2,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            PAYLOAD_TRANSFER_V1,
            "",
            T0,
            NO_CORRECTION
        );

        _assertEq(log.eventCount(SUBJECT), 2, "subject count");
        _assertEq(log.eventCount(SUBJECT_2), 1, "subject 2 count");
        _assertEq(log.eventCountByType(SUBJECT, EVT_TRANSFER), 1, "subject transfer count");
        _assertEq(log.eventCountByType(SUBJECT, EVT_FREEZE), 1, "subject freeze count");
        _assertEq(log.latestEventByType(SUBJECT, EVT_FREEZE), 1, "latest freeze");
    }

    function test_gettersRevertForInvalidIndices() public {
        vm.expectRevert(bytes("ComplianceEventLog: eventIndex out of range"));
        log.getEvent(SUBJECT, 0);

        vm.expectRevert(bytes("ComplianceEventLog: ordinal out of range"));
        log.eventByTypeAt(SUBJECT, EVT_TRANSFER, 0);

        vm.expectRevert(bytes("ComplianceEventLog: no events for type"));
        log.latestEventByType(SUBJECT, EVT_TRANSFER);
    }

    function test_supportsInterface() public view {
        _assertTrue(log.supportsInterface(0x01ffc9a7), "erc165");
        _assertTrue(log.supportsInterface(type(IComplianceEventLog).interfaceId), "compliance");
        _assertFalse(log.supportsInterface(0xffffffff), "unsupported");
    }

    function _record(
        address recorder,
        bytes32 subjectId,
        bytes32 eventType,
        bytes32 outcome,
        bytes32 authority,
        IComplianceEventLog.Party[] memory parties,
        bytes32 payloadProfileId,
        bytes memory payload,
        uint64 occurredAt,
        uint256 correctsIndex
    ) internal returns (uint256) {
        if (block.timestamp < occurredAt) vm.warp(uint256(occurredAt));
        vm.prank(recorder);
        return log.recordEvent(
            subjectId,
            SUBJECT_TOKEN,
            eventType,
            outcome,
            authority,
            parties,
            EVIDENCE,
            "ipfs://evidence",
            payloadProfileId,
            payload,
            OPERATION_REF,
            occurredAt,
            correctsIndex
        );
    }

    function _transferParties() internal pure returns (IComplianceEventLog.Party[] memory parties) {
        parties = new IComplianceEventLog.Party[](2);
        parties[0] = IComplianceEventLog.Party({addr: ALICE, role: ROLE_SENDER});
        parties[1] = IComplianceEventLog.Party({addr: BOB, role: ROLE_RECEIVER});
    }

    function _targetParty() internal pure returns (IComplianceEventLog.Party[] memory parties) {
        parties = new IComplianceEventLog.Party[](1);
        parties[0] = IComplianceEventLog.Party({addr: ALICE, role: ROLE_TARGET});
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

    function _assertEq(address actual, address expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function _assertEq(bytes32 actual, bytes32 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function _assertEq(string memory actual, string memory expected, string memory message) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), message);
    }
}
