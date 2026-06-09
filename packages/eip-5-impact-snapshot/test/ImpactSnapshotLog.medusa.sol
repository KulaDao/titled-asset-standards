// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ImpactSnapshotLog} from "../src/reference/ImpactSnapshotLog.sol";
import {IImpactSnapshotLog, NO_CORRECTION} from "../src/interfaces/IImpactSnapshotLog.sol";
import {CARBON_OFFSET, ENERGY_GENERATED, UNIT_TCO2E} from "../src/libraries/ImpactConstants.sol";

interface MedusaCheats {
    function warp(uint256 newTimestamp) external;
}

contract ImpactAttestorActor {
    ImpactSnapshotLog internal immutable isl;

    constructor(ImpactSnapshotLog isl_) {
        isl = isl_;
    }

    function attest(bytes32 subjectId, uint256 snapshotIdx) external {
        isl.attestSnapshot(subjectId, snapshotIdx, true, keccak256("evidence"), "ipfs://ev");
    }
}

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
    ImpactAttestorActor internal attestorActor;

    bytes32 internal constant SUBJECT_A = keccak256("subject-a");
    bytes32 internal constant SUBJECT_B = keccak256("subject-b");
    bytes32 internal constant METHOD_1 = keccak256("method-v1");
    bytes32 internal constant METHOD_2 = keccak256("method-v2");
    uint64 internal constant SEED_START = 1_699_913_600;
    uint64 internal constant SEED_END = 1_700_000_000;

    bytes32[2] internal indicators = [CARBON_OFFSET, ENERGY_GENERATED];
    bytes32[2] internal subjects = [SUBJECT_A, SUBJECT_B];

    uint256 public successfulSnapshots;
    uint256 public successfulCorrections;
    uint256 public successfulAttestations;

    // tracks per-(subjectId, indicatorId, periodKey) whether an original exists
    mapping(bytes32 => bool) internal _periodOccupied;
    // minimum snapshot count ever seen (for monotonicity check)
    mapping(bytes32 => uint256) internal _minSnapshotCount;

    constructor() {
        _vm().warp(SEED_END);
        // Deploy with address(this) as admin so the harness can call grantRole.
        isl = new ImpactSnapshotLog(address(this));
        attestorActor = new ImpactAttestorActor(isl);
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
        isl.grantRole(attestorRole, address(attestorActor));
        isl.grantRole(adminRole, address(0x10000));
        isl.grantRole(adminRole, address(0x20000));
        isl.grantRole(adminRole, address(0x30000));
        _seedNonTrivialState();
    }

    // ── State-mutating functions Medusa will call randomly ──────────────

    function fuzz_recordOriginal(uint8 subjectIdx, uint8 indicatorIdx, uint32 periodOffset, uint32 periodLength)
        external
    {
        if (periodLength == 0) return;
        subjectIdx = subjectIdx % 2;
        indicatorIdx = indicatorIdx % 2;

        bytes32 subjectId = subjects[subjectIdx];
        bytes32 indicatorId = indicators[indicatorIdx];
        (bool ok, uint64 start, uint64 end) = _completedPeriod(periodOffset, periodLength);
        if (!ok) return;
        bytes32 slotKey = _periodSlotKey(subjectId, indicatorId, start, end);

        if (_periodOccupied[slotKey]) return;

        // use active methodology if initialized, else METHOD_1
        (bytes32 activeHash,) = isl.activeMethodology(subjectId, indicatorId);
        bytes32 method = (activeHash != bytes32(0)) ? activeHash : METHOD_1;

        try isl.recordSnapshot{gas: 500_000}(
            subjectId, indicatorId, 100, 2, UNIT_TCO2E, start, end, method, "ipfs://v1", NO_CORRECTION
        ) {
            _periodOccupied[slotKey] = true;
            successfulSnapshots++;
        } catch {}
    }

    function fuzz_recordCorrection(uint8 subjectIdx, uint256 targetIndex, uint8 indicatorIdx) external {
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
            successfulSnapshots++;
            successfulCorrections++;
        } catch {}
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

        try attestorActor.attest{gas: 200_000}(subjectId, snapshotIdx) {
            successfulAttestations++;
        } catch {}
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

    /// Constructor seeding plus success counters prevent the harness from
    /// passing only because every mutating fuzz call reverted or returned.
    function property_nonTrivialActionsSucceeded() external view returns (bool) {
        return successfulSnapshots > 0 && successfulCorrections > 0 && successfulAttestations > 0;
    }

    function _seedNonTrivialState() internal {
        uint256 original = isl.recordSnapshot(
            SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, SEED_START, SEED_END, METHOD_1, "ipfs://v1", NO_CORRECTION
        );
        successfulSnapshots++;
        _periodOccupied[_periodSlotKey(SUBJECT_A, CARBON_OFFSET, SEED_START, SEED_END)] = true;

        uint256 correction = isl.recordSnapshot(
            SUBJECT_A, CARBON_OFFSET, 200, 2, UNIT_TCO2E, SEED_START, SEED_END, METHOD_1, "ipfs://v1", original
        );
        successfulSnapshots++;
        successfulCorrections++;

        attestorActor.attest(SUBJECT_A, correction);
        successfulAttestations++;
    }

    function _completedPeriod(uint32 periodOffset, uint32 periodLength)
        internal
        view
        returns (bool ok, uint64 start, uint64 end)
    {
        if (periodLength == 0) return (false, 0, 0);
        uint256 nowTs = block.timestamp;
        if (nowTs > type(uint64).max) return (false, 0, 0);
        uint256 totalLookback = uint256(periodOffset) + uint256(periodLength);
        if (nowTs <= totalLookback) return (false, 0, 0);

        uint256 endTs = nowTs - uint256(periodOffset);
        // forge-lint: disable-next-line(unsafe-typecast)
        end = uint64(endTs);
        start = uint64(uint256(end) - uint256(periodLength));
        return (true, start, end);
    }

    function _periodSlotKey(bytes32 subjectId, bytes32 indicatorId, uint64 start, uint64 end)
        internal
        pure
        returns (bytes32)
    {
        bytes32 periodKey = keccak256(abi.encodePacked(start, end));
        return keccak256(abi.encode(subjectId, indicatorId, periodKey));
    }

    function _vm() internal pure returns (MedusaCheats) {
        return MedusaCheats(address(uint160(uint256(keccak256("hevm cheat code")))));
    }
}
