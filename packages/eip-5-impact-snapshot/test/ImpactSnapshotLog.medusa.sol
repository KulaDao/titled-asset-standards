// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ImpactSnapshotLog} from "../src/reference/ImpactSnapshotLog.sol";
import {IImpactSnapshotLog, NO_CORRECTION} from "../src/interfaces/IImpactSnapshotLog.sol";
import {CARBON_OFFSET, ENERGY_GENERATED, UNIT_TCO2E} from "../src/libraries/ImpactConstants.sol";

/// @dev Medusa fuzz harness for ImpactSnapshotLog.
///      Run: medusa fuzz (from packages/eip-5-impact-snapshot)
///
///      Invariants checked after every call sequence:
///        property_currentPeriodSnapshotIsAlwaysTerminal
///        property_correctedSnapshotIsNeverCurrent
///        property_snapshotCountNeverDecreases
///        property_activeMethodologyNonZeroOnceInitialized
contract ImpactSnapshotLogFuzzTest {
    ImpactSnapshotLog internal isl;

    bytes32 internal constant SUBJECT_A = keccak256("subject-a");
    bytes32 internal constant SUBJECT_B = keccak256("subject-b");
    bytes32 internal constant METHOD_1 = keccak256("method-v1");
    bytes32 internal constant METHOD_2 = keccak256("method-v2");

    bytes32[2] internal indicators = [CARBON_OFFSET, ENERGY_GENERATED];
    bytes32[2] internal subjects = [SUBJECT_A, SUBJECT_B];

    // tracks per-(subjectId, indicatorId, periodKey) whether an original exists
    mapping(bytes32 => bool) internal _periodOccupied;
    // minimum snapshot count ever seen (for monotonicity check)
    mapping(bytes32 => uint256) internal _minSnapshotCount;

    uint64 internal _ts = 1_000_000;

    constructor() {
        // Deploy with address(this) as admin so the harness can call grantRole.
        isl = new ImpactSnapshotLog(address(this));
        bytes32 reporterRole = isl.REPORTER_ROLE();
        bytes32 attestorRole = isl.ATTESTOR_ROLE();
        bytes32 adminRole = isl.DEFAULT_ADMIN_ROLE();
        // Grant roles to all Medusa sender addresses.
        isl.grantRole(reporterRole, address(0x10000));
        isl.grantRole(reporterRole, address(0x20000));
        isl.grantRole(reporterRole, address(0x30000));
        isl.grantRole(attestorRole, address(0x10000));
        isl.grantRole(attestorRole, address(0x20000));
        isl.grantRole(attestorRole, address(0x30000));
        isl.grantRole(adminRole, address(0x10000));
        isl.grantRole(adminRole, address(0x20000));
        isl.grantRole(adminRole, address(0x30000));
    }

    // ── State-mutating functions Medusa will call randomly ──────────────

    function fuzz_advanceTime(uint32 delta) external {
        if (delta == 0 || delta > 30 days) return;
        _ts += delta;
    }

    function fuzz_recordOriginal(uint8 subjectIdx, uint8 indicatorIdx, uint32 periodOffset, uint32 periodLength)
        external
    {
        if (periodLength == 0) return;
        subjectIdx = subjectIdx % 2;
        indicatorIdx = indicatorIdx % 2;

        bytes32 subjectId = subjects[subjectIdx];
        bytes32 indicatorId = indicators[indicatorIdx];
        uint64 start = _ts + periodOffset;
        uint64 end = start + periodLength;
        bytes32 periodKey = keccak256(abi.encodePacked(start, end));
        bytes32 slotKey = keccak256(abi.encode(subjectId, indicatorId, periodKey));

        if (_periodOccupied[slotKey]) return;

        // use active methodology if initialized, else METHOD_1
        (bytes32 activeHash,) = isl.activeMethodology(subjectId, indicatorId);
        bytes32 method = (activeHash != bytes32(0)) ? activeHash : METHOD_1;

        try isl.recordSnapshot{gas: 500_000}(
            subjectId, indicatorId, 100, 2, UNIT_TCO2E, start, end, method, "ipfs://v1", NO_CORRECTION
        ) {
            _periodOccupied[slotKey] = true;
            // snapshot recorded
        } catch {}
    }

    function fuzz_recordCorrection(
        uint8 subjectIdx,
        uint256 targetIndex,
        uint8 indicatorIdx,
        uint32 periodOffset,
        uint32 periodLength
    ) external {
        subjectIdx = subjectIdx % 2;
        indicatorIdx = indicatorIdx % 2;
        bytes32 subjectId = subjects[subjectIdx];
        bytes32 indicatorId = indicators[indicatorIdx];

        uint256 count = isl.snapshotCount(subjectId);
        if (count == 0) return;
        targetIndex = targetIndex % count;

        IImpactSnapshotLog.IndicatorSnapshot memory target = isl.getSnapshot(subjectId, targetIndex);
        if (target.correctedByIndex != 0) return;
        if (target.indicatorId != indicatorId) return;

        (bytes32 activeHash,) = isl.activeMethodology(subjectId, indicatorId);
        bytes32 method = (activeHash != bytes32(0)) ? activeHash : METHOD_1;

        uint64 start = target.periodStart;
        uint64 end = target.periodEnd;

        try isl.recordSnapshot{gas: 500_000}(
            subjectId, indicatorId, 200, 2, UNIT_TCO2E, start, end, method, "ipfs://v1", targetIndex
        ) {
        // snapshot recorded
        }
            catch {}
    }

    function fuzz_supersedeMethodology(uint8 subjectIdx, uint8 indicatorIdx) external {
        subjectIdx = subjectIdx % 2;
        indicatorIdx = indicatorIdx % 2;
        bytes32 subjectId = subjects[subjectIdx];
        bytes32 indicatorId = indicators[indicatorIdx];

        (bytes32 activeHash,) = isl.activeMethodology(subjectId, indicatorId);
        if (activeHash == bytes32(0)) return;
        if (activeHash == METHOD_2) return;

        uint256 ordinal = isl.indicatorSnapshotCount(subjectId, indicatorId);

        try isl.supersedeMethodology{gas: 200_000}(
            subjectId, indicatorId, activeHash, METHOD_2, "ipfs://v2", ordinal
        ) {}
            catch {}
    }

    function fuzz_attest(uint8 subjectIdx, uint256 snapshotIdx) external {
        subjectIdx = subjectIdx % 2;
        bytes32 subjectId = subjects[subjectIdx];

        uint256 count = isl.snapshotCount(subjectId);
        if (count == 0) return;
        snapshotIdx = snapshotIdx % count;

        try isl.attestSnapshot{gas: 200_000}(subjectId, snapshotIdx, true, keccak256("evidence"), "ipfs://ev") {}
            catch {}
    }

    // ── property_ functions — return false to signal failure ───────────

    /// currentSnapshotForPeriod always returns a terminal (uncorrected) snapshot.
    function property_currentPeriodSnapshotIsAlwaysTerminal() external view returns (bool) {
        for (uint8 si = 0; si < 2; si++) {
            for (uint8 ii = 0; ii < 2; ii++) {
                bytes32 subjectId = subjects[si];
                bytes32 indicatorId = indicators[ii];
                uint256 count = isl.indicatorSnapshotCount(subjectId, indicatorId);
                for (uint256 o = 0; o < count; o++) {
                    uint256 globalIdx = isl.indicatorSnapshotAt(subjectId, indicatorId, o);
                    IImpactSnapshotLog.IndicatorSnapshot memory snap = isl.getSnapshot(subjectId, globalIdx);
                    if (snap.correctedByIndex != 0) continue;
                    uint256 current =
                        isl.currentSnapshotForPeriod(subjectId, indicatorId, snap.periodStart, snap.periodEnd);
                    IImpactSnapshotLog.IndicatorSnapshot memory cur = isl.getSnapshot(subjectId, current);
                    if (cur.correctedByIndex != 0) return false;
                }
            }
        }
        return true;
    }

    /// A snapshot that has been corrected (correctedByIndex != 0) is never
    /// the result of currentSnapshotForPeriod.
    function property_correctedSnapshotIsNeverCurrent() external view returns (bool) {
        for (uint8 si = 0; si < 2; si++) {
            bytes32 subjectId = subjects[si];
            uint256 total = isl.snapshotCount(subjectId);
            for (uint256 i = 0; i < total; i++) {
                IImpactSnapshotLog.IndicatorSnapshot memory snap = isl.getSnapshot(subjectId, i);
                if (snap.correctedByIndex == 0) continue;
                uint256 current =
                    isl.currentSnapshotForPeriod(subjectId, snap.indicatorId, snap.periodStart, snap.periodEnd);
                if (current == i) return false;
            }
        }
        return true;
    }

    /// snapshotCount can only grow — the log is append-only.
    function property_snapshotCountNeverDecreases() external returns (bool) {
        for (uint8 si = 0; si < 2; si++) {
            bytes32 subjectId = subjects[si];
            uint256 current = isl.snapshotCount(subjectId);
            if (current < _minSnapshotCount[subjectId]) return false;
            _minSnapshotCount[subjectId] = current;
        }
        return true;
    }

    /// Once a snapshot exists for a (subjectId, indicatorId), activeMethodology is non-zero.
    function property_activeMethodologyNonZeroOnceInitialized() external view returns (bool) {
        for (uint8 si = 0; si < 2; si++) {
            for (uint8 ii = 0; ii < 2; ii++) {
                bytes32 subjectId = subjects[si];
                bytes32 indicatorId = indicators[ii];
                uint256 count = isl.indicatorSnapshotCount(subjectId, indicatorId);
                if (count == 0) continue;
                (bytes32 hash,) = isl.activeMethodology(subjectId, indicatorId);
                if (hash == bytes32(0)) return false;
            }
        }
        return true;
    }
}
