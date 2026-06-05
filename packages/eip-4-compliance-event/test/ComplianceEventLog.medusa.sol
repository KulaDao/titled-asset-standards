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
    PAYLOAD_TRANSFER_V1
} from "../src/libraries/ComplianceConstants.sol";

contract ComplianceEventLogFuzzTest {
    ComplianceEventLog internal log;

    bytes32 internal constant SUBJECT = keccak256("subject");
    bytes32[2] internal eventTypes = [EVT_TRANSFER, EVT_FREEZE];
    uint64 internal timestamp = 1_700_000_000;

    constructor() {
        log = new ComplianceEventLog(address(this));
        log.grantRole(log.RECORDER_ROLE(), address(0x10000));
        log.grantRole(log.RECORDER_ROLE(), address(0x20000));
        log.grantRole(log.RECORDER_ROLE(), address(0x30000));
        log.grantRole(log.DEFAULT_ADMIN_ROLE(), address(0x10000));
        log.grantRole(log.DEFAULT_ADMIN_ROLE(), address(0x20000));
        log.grantRole(log.DEFAULT_ADMIN_ROLE(), address(0x30000));
    }

    function fuzz_recordOriginal(uint8 eventTypeIndex) external {
        eventTypeIndex = eventTypeIndex % 2;
        try log.recordEvent{gas: 700_000}(
            SUBJECT,
            SUBJECT_TOKEN,
            eventTypes[eventTypeIndex],
            OUTCOME_APPROVED,
            AUTHORITY_INTERNAL_POLICY,
            _parties(eventTypeIndex),
            keccak256("evidence"),
            "ipfs://evidence",
            PAYLOAD_TRANSFER_V1,
            "",
            bytes32(0),
            timestamp,
            NO_CORRECTION
        ) {}
            catch {}
    }

    function fuzz_recordCorrection(uint256 targetIndex) external {
        uint256 count = log.eventCount(SUBJECT);
        if (count == 0) return;
        targetIndex = targetIndex % count;

        IComplianceEventLog.ComplianceEvent memory target = log.getEvent(SUBJECT, targetIndex);
        if (target.correctedByIndex != 0) return;
        if (target.actor != address(this)) return;

        try log.recordEvent{gas: 700_000}(
            SUBJECT,
            SUBJECT_TOKEN,
            EVT_CORRECTION,
            OUTCOME_EXECUTED,
            AUTHORITY_INTERNAL_POLICY,
            _parties(0),
            keccak256("correction-evidence"),
            "ipfs://correction",
            PAYLOAD_TRANSFER_V1,
            abi.encode(target.eventType, targetIndex),
            bytes32(0),
            timestamp,
            targetIndex
        ) {}
            catch {}
    }

    function property_eventCountMatchesTypeCounts() external view returns (bool) {
        uint256 count = log.eventCount(SUBJECT);
        uint256 typed = log.eventCountByType(SUBJECT, EVT_TRANSFER) + log.eventCountByType(SUBJECT, EVT_FREEZE)
            + log.eventCountByType(SUBJECT, EVT_CORRECTION);
        return count == typed;
    }

    function property_correctionsAreForkFree() external view returns (bool) {
        uint256 count = log.eventCount(SUBJECT);
        for (uint256 i = 0; i < count; i++) {
            IComplianceEventLog.ComplianceEvent memory eventRecord = log.getEvent(SUBJECT, i);
            if (eventRecord.correctedByIndex != 0) {
                if (eventRecord.correctedByIndex >= count) return false;
                IComplianceEventLog.ComplianceEvent memory correction =
                    log.getEvent(SUBJECT, eventRecord.correctedByIndex);
                if (correction.correctsIndex != i) return false;
                if (correction.eventType != EVT_CORRECTION) return false;
            }
        }
        return true;
    }

    function property_correctedEventsAreNeverCorrectionsWithoutTarget() external view returns (bool) {
        uint256 count = log.eventCount(SUBJECT);
        for (uint256 i = 0; i < count; i++) {
            IComplianceEventLog.ComplianceEvent memory eventRecord = log.getEvent(SUBJECT, i);
            if (eventRecord.eventType == EVT_CORRECTION && eventRecord.correctsIndex == NO_CORRECTION) return false;
        }
        return true;
    }

    function _parties(uint8 eventTypeIndex) internal pure returns (IComplianceEventLog.Party[] memory parties) {
        if (eventTypeIndex == 0) {
            parties = new IComplianceEventLog.Party[](2);
            parties[0] = IComplianceEventLog.Party({addr: address(0xAA), role: ROLE_SENDER});
            parties[1] = IComplianceEventLog.Party({addr: address(0xBB), role: ROLE_RECEIVER});
        } else {
            parties = new IComplianceEventLog.Party[](1);
            parties[0] = IComplianceEventLog.Party({addr: address(0xAA), role: ROLE_TARGET});
        }
    }
}
