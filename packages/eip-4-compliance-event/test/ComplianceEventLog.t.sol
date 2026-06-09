// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
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

contract ComplianceEventLogTest is Test {
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

    ComplianceEventLog private eventLog;

    address private constant ADMIN = address(0xA0);
    address private constant RECORDER = address(0xA1);
    address private constant RECORDER_2 = address(0xA2);
    address private constant ADMIN_ONLY = address(0xA3);
    address private constant OUTSIDER = address(0xB0);
    address private constant ALICE = address(0xC0);
    address private constant BOB = address(0xC1);

    bytes32 private constant SUBJECT = keccak256("subject");
    bytes32 private constant SUBJECT_2 = keccak256("subject-2");
    bytes32 private constant EVIDENCE = keccak256("evidence");
    bytes32 private constant OPERATION_REF = keccak256("operation");

    uint64 private constant T0 = 1_700_000_000;

    function setUp() public {
        eventLog = new ComplianceEventLog(ADMIN);
        bytes32 recorderRole = eventLog.RECORDER_ROLE();

        vm.prank(ADMIN);
        eventLog.grantRole(recorderRole, RECORDER);
        vm.prank(ADMIN);
        eventLog.grantRole(recorderRole, RECORDER_2);
    }

    function test_constructorRejectsZeroAdmin() public {
        vm.expectRevert(bytes("ComplianceEventLog: zero admin"));
        new ComplianceEventLog(address(0));
    }

    function test_grantAndRevokeRecorderRole() public {
        bytes32 recorderRole = eventLog.RECORDER_ROLE();

        vm.expectEmit(true, true, true, true);
        emit RoleGranted(recorderRole, OUTSIDER, ADMIN);
        vm.prank(ADMIN);
        eventLog.grantRole(recorderRole, OUTSIDER);
        assertTrue(eventLog.hasRole(recorderRole, OUTSIDER), "role granted");

        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(recorderRole, OUTSIDER, ADMIN);
        vm.prank(ADMIN);
        eventLog.revokeRole(recorderRole, OUTSIDER);
        assertFalse(eventLog.hasRole(recorderRole, OUTSIDER), "role revoked");
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

        assertEq(index, 0, "event index");
        assertEq(eventLog.eventCount(SUBJECT), 1, "subject count");
        assertEq(eventLog.eventCountByType(SUBJECT, EVT_TRANSFER), 1, "type count");
        assertEq(eventLog.eventByTypeAt(SUBJECT, EVT_TRANSFER, 0), 0, "type ordinal");
        assertEq(eventLog.latestEventByType(SUBJECT, EVT_TRANSFER), 0, "latest type");

        IComplianceEventLog.ComplianceEvent memory stored = eventLog.getEvent(SUBJECT, 0);
        assertEq(stored.subjectId, SUBJECT, "subject");
        assertEq(stored.subjectType, SUBJECT_TOKEN, "subject type");
        assertEq(stored.eventType, EVT_TRANSFER, "event type");
        assertEq(stored.outcome, OUTCOME_APPROVED, "outcome");
        assertEq(stored.actor, RECORDER, "actor");
        assertEq(stored.authority, AUTHORITY_INTERNAL_POLICY, "authority");
        assertEq(stored.evidenceHash, EVIDENCE, "evidence");
        assertEq(stored.evidenceURI, "ipfs://evidence", "evidence uri");
        assertEq(stored.payloadProfileId, PAYLOAD_TRANSFER_V1, "profile");
        assertEq(keccak256(stored.payload), keccak256(payload), "payload");
        assertEq(stored.operationRef, OPERATION_REF, "operation ref");
        assertEq(stored.occurredAt, T0, "occurred at");
        assertEq(stored.recordedAt, T0, "recorded at");
        assertEq(stored.correctsIndex, NO_CORRECTION, "corrects");
        assertEq(stored.correctedByIndex, 0, "corrected by");
        assertEq(stored.parties.length, 2, "party count");
        assertEq(stored.parties[0].addr, ALICE, "party 0 addr");
        assertEq(stored.parties[0].role, ROLE_SENDER, "party 0 role");
        assertEq(stored.parties[1].addr, BOB, "party 1 addr");
        assertEq(stored.parties[1].role, ROLE_RECEIVER, "party 1 role");
    }

    function test_recordEventRequiresRecorderRole() public {
        vm.warp(T0);
        vm.prank(OUTSIDER);
        vm.expectRevert(bytes("ComplianceEventLog: missing role"));
        eventLog.recordEvent(
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

    function test_recordEventRejectsZeroEvidenceHash() public {
        vm.warp(T0);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: zero evidenceHash"));
        eventLog.recordEvent(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_TRANSFER,
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _transferParties(),
            bytes32(0),
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
        eventLog.recordEvent(
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

        vm.warp(uint256(T0) + eventLog.MAX_BACKDATE_SECONDS() + 1);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: event too old"));
        eventLog.recordEvent(
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
        IComplianceEventLog.Party[] memory parties = new IComplianceEventLog.Party[](eventLog.MAX_PARTIES() + 1);
        for (uint256 i = 0; i < parties.length; i++) {
            parties[i] = IComplianceEventLog.Party({addr: ALICE, role: ROLE_TARGET});
        }

        vm.warp(T0);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: too many parties"));
        eventLog.recordEvent(
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

        bytes memory payload = new bytes(eventLog.MAX_PAYLOAD_BYTES() + 1);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: payload too large"));
        eventLog.recordEvent(
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

        assertEq(correction, 1, "correction index");
        assertEq(eventLog.getEvent(SUBJECT, 0).correctedByIndex, 1, "target corrected by");
        assertEq(eventLog.getEvent(SUBJECT, 1).correctsIndex, 0, "correction corrects");
        assertEq(eventLog.eventCountByType(SUBJECT, EVT_CORRECTION), 1, "correction type count");
        assertEq(eventLog.latestEventByType(SUBJECT, EVT_CORRECTION), 1, "latest correction");

        vm.warp(T0 + 2);
        vm.prank(RECORDER);
        vm.expectRevert(bytes("ComplianceEventLog: target already corrected"));
        eventLog.recordEvent(
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
        eventLog.recordEvent(
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
        eventLog.recordEvent(
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
        eventLog.recordEvent(
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
        eventLog.recordEvent(
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
        uint256 correction = eventLog.recordEvent(
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
        assertEq(correction, 1, "admin correction");
    }

    function test_adminCorrectionStillRequiresRecorderRole() public {
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

        bytes32 adminRole = eventLog.DEFAULT_ADMIN_ROLE();
        bytes32 recorderRole = eventLog.RECORDER_ROLE();

        vm.prank(ADMIN);
        eventLog.grantRole(adminRole, ADMIN_ONLY);

        vm.warp(T0 + 1);
        vm.prank(ADMIN_ONLY);
        vm.expectRevert(bytes("ComplianceEventLog: missing role"));
        eventLog.recordEvent(
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

        vm.prank(ADMIN_ONLY);
        eventLog.grantRole(recorderRole, ADMIN_ONLY);

        vm.prank(ADMIN_ONLY);
        uint256 correction = eventLog.recordEvent(
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
        assertEq(correction, 1, "admin-only correction after recorder role");
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

        assertEq(eventLog.eventCount(SUBJECT), 2, "subject count");
        assertEq(eventLog.eventCount(SUBJECT_2), 1, "subject 2 count");
        assertEq(eventLog.eventCountByType(SUBJECT, EVT_TRANSFER), 1, "subject transfer count");
        assertEq(eventLog.eventCountByType(SUBJECT, EVT_FREEZE), 1, "subject freeze count");
        assertEq(eventLog.latestEventByType(SUBJECT, EVT_FREEZE), 1, "latest freeze");
    }

    function test_gettersRevertForInvalidIndices() public {
        vm.expectRevert(bytes("ComplianceEventLog: eventIndex out of range"));
        eventLog.getEvent(SUBJECT, 0);

        vm.expectRevert(bytes("ComplianceEventLog: ordinal out of range"));
        eventLog.eventByTypeAt(SUBJECT, EVT_TRANSFER, 0);

        vm.expectRevert(bytes("ComplianceEventLog: no events for type"));
        eventLog.latestEventByType(SUBJECT, EVT_TRANSFER);
    }

    function test_supportsInterface() public view {
        assertTrue(eventLog.supportsInterface(0x01ffc9a7), "erc165");
        assertTrue(eventLog.supportsInterface(type(IComplianceEventLog).interfaceId), "compliance");
        assertFalse(eventLog.supportsInterface(0xffffffff), "unsupported");
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
        return eventLog.recordEvent(
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
}
