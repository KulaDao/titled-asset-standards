// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ImpactSnapshotLog} from "../src/reference/ImpactSnapshotLog.sol";
import {IImpactSnapshotLog, NO_CORRECTION} from "../src/interfaces/IImpactSnapshotLog.sol";
import {IImpactAttestation} from "../src/interfaces/IImpactAttestation.sol";
import {
    CARBON_OFFSET,
    CARBON_EMITTED,
    ENERGY_GENERATED,
    ENERGY_SAVED,
    WATER_TREATED,
    JOBS_CREATED,
    BENEFICIARIES,
    BIODIVERSITY_AREA,
    WASTE_DIVERTED,
    UNIT_TCO2E,
    UNIT_KWH,
    UNIT_M3,
    UNIT_FTE,
    UNIT_PERSONS,
    UNIT_HECTARES,
    UNIT_TONNES
} from "../src/libraries/ImpactConstants.sol";

contract ImpactSnapshotLogTest is Test {
    event SnapshotRecorded(
        bytes32 indexed subjectId,
        bytes32 indexed indicatorId,
        uint256 indexed snapshotIndex,
        int256 value,
        uint8 decimals,
        bytes32 unit,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 methodologyHash,
        uint256 correctsIndex,
        address reportedBy
    );

    event SnapshotAttested(
        bytes32 indexed subjectId,
        uint256 indexed snapshotIndex,
        address indexed attestor,
        bool endorsed,
        bytes32 evidenceHash,
        uint256 attestationIndex
    );

    event MethodologySuperseded(
        bytes32 indexed subjectId,
        bytes32 indexed indicatorId,
        bytes32 oldMethodologyHash,
        bytes32 newMethodologyHash,
        uint256 effectiveFromOrdinal
    );

    ImpactSnapshotLog isl;

    address admin = address(0xA0);
    address reporter = address(0xA1);
    address reporter2 = address(0xA3);
    address attestor = address(0xA2);

    bytes32 constant SUBJECT_A = keccak256("subject-a");
    bytes32 constant SUBJECT_B = keccak256("subject-b");
    bytes32 constant METHOD_1 = keccak256("method-v1");
    bytes32 constant METHOD_2 = keccak256("method-v2");
    bytes32 constant EVIDENCE = keccak256("evidence-hash");

    uint64 constant T0 = 1_700_000_000;
    uint64 constant T1 = 1_700_086_400;
    uint64 constant T2 = 1_700_172_800;

    function setUp() public {
        isl = new ImpactSnapshotLog(admin);
        vm.startPrank(admin);
        isl.grantRole(isl.REPORTER_ROLE(), reporter);
        isl.grantRole(isl.REPORTER_ROLE(), reporter2);
        isl.grantRole(isl.ATTESTOR_ROLE(), attestor);
        vm.stopPrank();
    }

    function _record(bytes32 subjectId, bytes32 indicatorId, uint64 start, uint64 end, uint256 correctsIndex)
        internal
        returns (uint256)
    {
        if (block.timestamp < end) vm.warp(end);
        vm.prank(reporter);
        return isl.recordSnapshot(
            subjectId, indicatorId, 100, 2, UNIT_TCO2E, start, end, METHOD_1, "ipfs://v1", correctsIndex
        );
    }

    function _recordAs(
        address account,
        bytes32 subjectId,
        bytes32 indicatorId,
        uint64 start,
        uint64 end,
        uint256 correctsIndex,
        bytes32 methodologyHash,
        string memory methodologyURI
    ) internal returns (uint256) {
        if (block.timestamp < end) vm.warp(end);
        vm.prank(account);
        return isl.recordSnapshot(
            subjectId, indicatorId, 100, 2, UNIT_TCO2E, start, end, methodologyHash, methodologyURI, correctsIndex
        );
    }

    // -------------------------------------------------------------------------
    // 1. test_recordSnapshot_original
    // -------------------------------------------------------------------------
    function test_recordSnapshot_original() public {
        vm.warp(T0);
        uint256 idx = _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        assertEq(idx, 0, "first index must be 0");
        assertEq(isl.snapshotCount(SUBJECT_A), 1, "snapshotCount must be 1");

        IImpactSnapshotLog.IndicatorSnapshot memory snap = isl.getSnapshot(SUBJECT_A, 0);
        assertEq(snap.subjectId, SUBJECT_A, "subjectId mismatch");
        assertEq(snap.indicatorId, CARBON_OFFSET, "indicatorId mismatch");
        assertEq(snap.value, 100, "value mismatch");
        assertEq(snap.decimals, 2, "decimals mismatch");
        assertEq(snap.unit, UNIT_TCO2E, "unit mismatch");
        assertEq(snap.periodStart, T0, "periodStart mismatch");
        assertEq(snap.periodEnd, T1, "periodEnd mismatch");
        assertEq(snap.methodologyHash, METHOD_1, "methodologyHash mismatch");
        assertEq(snap.methodologyURI, "ipfs://v1", "methodologyURI mismatch");
        assertEq(snap.reportedBy, reporter, "reportedBy mismatch");
        assertEq(snap.reportedAt, T1, "reportedAt mismatch");
        assertEq(snap.correctsIndex, NO_CORRECTION, "correctsIndex must be NO_CORRECTION");
        assertEq(snap.correctedByIndex, 0, "correctedByIndex must be 0");
    }

    // -------------------------------------------------------------------------
    // 2. test_recordSnapshot_emitsEvent
    // -------------------------------------------------------------------------
    function test_recordSnapshot_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit SnapshotRecorded(
            SUBJECT_A, CARBON_OFFSET, 0, 100, 2, UNIT_TCO2E, T0, T1, METHOD_1, NO_CORRECTION, reporter
        );
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);
    }

    // -------------------------------------------------------------------------
    // 3. test_recordSnapshot_revertsInvalidPeriod
    // -------------------------------------------------------------------------
    function test_recordSnapshot_revertsInvalidPeriod() public {
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: periodStart must be < periodEnd");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T1, T0, METHOD_1, "", NO_CORRECTION);
    }

    function test_recordSnapshot_revertsEqualPeriod() public {
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: periodStart must be < periodEnd");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T0, T0, METHOD_1, "", NO_CORRECTION);
    }

    function test_recordSnapshot_revertsIncompletePeriod() public {
        vm.warp(T1 - 1);
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: incomplete period");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T0, T1, METHOD_1, "ipfs://v1", NO_CORRECTION);
    }

    function test_recordSnapshot_revertsZeroMethodologyHash() public {
        vm.warp(T1);
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: zero methodology");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T0, T1, bytes32(0), "ipfs://v1", NO_CORRECTION);
    }

    function test_recordSnapshot_revertsEmptyMethodologyURI() public {
        vm.warp(T1);
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: empty methodology URI");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T0, T1, METHOD_1, "", NO_CORRECTION);
    }

    // -------------------------------------------------------------------------
    // 4. test_recordSnapshot_revertsInvalidCorrectionTarget
    // -------------------------------------------------------------------------
    function test_recordSnapshot_revertsInvalidCorrectionTarget() public {
        vm.warp(T1);
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: correctsIndex out of range");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T0, T1, METHOD_1, "ipfs://v1", 99);
    }

    // -------------------------------------------------------------------------
    // 5. test_recordSnapshot_correction
    // -------------------------------------------------------------------------
    function test_recordSnapshot_correction() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);
        uint256 corrIdx = _record(SUBJECT_A, CARBON_OFFSET, T0, T1, 0);

        assertEq(corrIdx, 1, "correction index must be 1");

        IImpactSnapshotLog.IndicatorSnapshot memory original = isl.getSnapshot(SUBJECT_A, 0);
        assertEq(original.correctedByIndex, 1, "original correctedByIndex must point to correction");

        IImpactSnapshotLog.IndicatorSnapshot memory correction = isl.getSnapshot(SUBJECT_A, 1);
        assertEq(correction.correctsIndex, 0, "correction.correctsIndex must be 0");
        assertEq(correction.correctedByIndex, 0, "correction must not itself be corrected");
    }

    function test_recordSnapshot_revertsCorrectionByDifferentReporter() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(reporter2);
        vm.expectRevert("ImpactSnapshotLog: correction not authorized");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 200, 2, UNIT_TCO2E, T0, T1, METHOD_1, "ipfs://v1", 0);
    }

    function test_recordSnapshot_adminCanCorrectDifferentReporter() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(admin);
        uint256 correctionIndex =
            isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 200, 2, UNIT_TCO2E, T0, T1, METHOD_1, "ipfs://v1", 0);

        assertEq(correctionIndex, 1, "admin correction index must be 1");
        IImpactSnapshotLog.IndicatorSnapshot memory original = isl.getSnapshot(SUBJECT_A, 0);
        IImpactSnapshotLog.IndicatorSnapshot memory correction = isl.getSnapshot(SUBJECT_A, 1);
        assertEq(original.correctedByIndex, 1, "original must point to admin correction");
        assertEq(correction.reportedBy, admin, "admin must be recorded as correction reporter");
    }

    // -------------------------------------------------------------------------
    // 6. test_recordSnapshot_revertsForkCorrection
    // -------------------------------------------------------------------------
    function test_recordSnapshot_revertsForkCorrection() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // index 0
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, 0); // index 1 corrects 0

        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: target snapshot already corrected");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 200, 2, UNIT_TCO2E, T0, T1, METHOD_1, "ipfs://v1", 0);
    }

    // -------------------------------------------------------------------------
    // 7. test_recordSnapshot_correctionMustMatchPeriod
    // -------------------------------------------------------------------------
    function test_recordSnapshot_correctionMustMatchPeriod() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // index 0

        vm.warp(T2);
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: correction must match target period and indicator");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 200, 2, UNIT_TCO2E, T1, T2, METHOD_1, "ipfs://v1", 0);
    }

    // -------------------------------------------------------------------------
    // 8. test_getSnapshot_revertsInvalidIndex
    // -------------------------------------------------------------------------
    function test_getSnapshot_revertsInvalidIndex() public {
        vm.expectRevert("ImpactSnapshotLog: snapshotIndex out of range");
        isl.getSnapshot(SUBJECT_A, 0);
    }

    // -------------------------------------------------------------------------
    // 9. test_snapshotIndicesArePerSubject
    // -------------------------------------------------------------------------
    function test_snapshotIndicesArePerSubject() public {
        uint256 idxA = _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);
        uint256 idxB = _record(SUBJECT_B, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        assertEq(idxA, 0, "subject A first index must be 0");
        assertEq(idxB, 0, "subject B first index must be 0");
        assertEq(isl.snapshotCount(SUBJECT_A), 1, "subject A count must be 1");
        assertEq(isl.snapshotCount(SUBJECT_B), 1, "subject B count must be 1");
    }

    // -------------------------------------------------------------------------
    // 10. test_indicatorSnapshotCount
    // -------------------------------------------------------------------------
    function test_indicatorSnapshotCount() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);
        _record(SUBJECT_A, CARBON_OFFSET, T1, T2, NO_CORRECTION);
        _record(SUBJECT_A, CARBON_OFFSET, T2, T2 + 1, NO_CORRECTION);
        _record(SUBJECT_A, ENERGY_GENERATED, T0, T1, NO_CORRECTION);
        _record(SUBJECT_A, ENERGY_GENERATED, T1, T2, NO_CORRECTION);

        assertEq(isl.indicatorSnapshotCount(SUBJECT_A, CARBON_OFFSET), 3, "CARBON_OFFSET count must be 3");
        assertEq(isl.indicatorSnapshotCount(SUBJECT_A, ENERGY_GENERATED), 2, "ENERGY_GENERATED count must be 2");
    }

    // -------------------------------------------------------------------------
    // 11. test_indicatorSnapshotAt
    // -------------------------------------------------------------------------
    function test_indicatorSnapshotAt() public {
        _record(SUBJECT_A, ENERGY_GENERATED, T0, T1, NO_CORRECTION); // global index 0
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // global index 1
        _record(SUBJECT_A, CARBON_OFFSET, T1, T2, NO_CORRECTION); // global index 2
        _record(SUBJECT_A, CARBON_OFFSET, T2, T2 + 1, NO_CORRECTION); // global index 3

        assertEq(isl.indicatorSnapshotAt(SUBJECT_A, CARBON_OFFSET, 0), 1, "ordinal 0 must map to global index 1");
        assertEq(isl.indicatorSnapshotAt(SUBJECT_A, CARBON_OFFSET, 1), 2, "ordinal 1 must map to global index 2");
        assertEq(isl.indicatorSnapshotAt(SUBJECT_A, CARBON_OFFSET, 2), 3, "ordinal 2 must map to global index 3");
    }

    // -------------------------------------------------------------------------
    // 12. test_indicatorSnapshotAt_revertsInvalidOrdinal
    // -------------------------------------------------------------------------
    function test_indicatorSnapshotAt_revertsInvalidOrdinal() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.expectRevert("ImpactSnapshotLog: ordinal out of range");
        isl.indicatorSnapshotAt(SUBJECT_A, CARBON_OFFSET, 1);
    }

    // -------------------------------------------------------------------------
    // 13. test_latestIndicatorSnapshot
    // -------------------------------------------------------------------------
    function test_latestIndicatorSnapshot() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // global 0
        _record(SUBJECT_A, CARBON_OFFSET, T1, T2, NO_CORRECTION); // global 1

        assertEq(isl.latestIndicatorSnapshot(SUBJECT_A, CARBON_OFFSET), 1, "latest must be global index 1");
    }

    // -------------------------------------------------------------------------
    // 14. test_latestIndicatorSnapshot_revertsIfNone
    // -------------------------------------------------------------------------
    function test_latestIndicatorSnapshot_revertsIfNone() public {
        vm.expectRevert("ImpactSnapshotLog: no snapshots for indicator");
        isl.latestIndicatorSnapshot(SUBJECT_A, CARBON_OFFSET);
    }

    // -------------------------------------------------------------------------
    // 15. test_currentSnapshotForPeriod_returnsOriginal
    // -------------------------------------------------------------------------
    function test_currentSnapshotForPeriod_returnsOriginal() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // global 0

        uint256 current = isl.currentSnapshotForPeriod(SUBJECT_A, CARBON_OFFSET, T0, T1);
        assertEq(current, 0, "current snapshot for period must be index 0");
    }

    // -------------------------------------------------------------------------
    // 16. test_currentSnapshotForPeriod_returnsTerminalCorrection
    // -------------------------------------------------------------------------
    function test_currentSnapshotForPeriod_returnsTerminalCorrection() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // 0: original
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, 0); // 1: corrects 0
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, 1); // 2: corrects 1

        uint256 current = isl.currentSnapshotForPeriod(SUBJECT_A, CARBON_OFFSET, T0, T1);
        assertEq(current, 2, "terminal correction must be index 2");
    }

    // -------------------------------------------------------------------------
    // 17. test_currentSnapshotForPeriod_revertsIfNone
    // -------------------------------------------------------------------------
    function test_currentSnapshotForPeriod_revertsIfNone() public {
        vm.expectRevert("ImpactSnapshotLog: no snapshot for period");
        isl.currentSnapshotForPeriod(SUBJECT_A, CARBON_OFFSET, T0, T1);
    }

    // -------------------------------------------------------------------------
    // 18. test_attestSnapshot_stores
    // -------------------------------------------------------------------------
    function test_attestSnapshot_stores() public {
        vm.warp(T0);
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(attestor);
        uint256 aIdx = isl.attestSnapshot(SUBJECT_A, 0, true, EVIDENCE, "ipfs://evidence");

        assertEq(aIdx, 0, "first attestation index must be 0");
        assertEq(isl.attestationCount(SUBJECT_A, 0), 1, "attestationCount must be 1");

        IImpactAttestation.Attestation memory att = isl.getAttestation(SUBJECT_A, 0, 0);
        assertEq(att.attestor, attestor, "attestor mismatch");
        assertTrue(att.endorsed, "endorsed must be true");
        assertEq(att.evidenceHash, EVIDENCE, "evidenceHash mismatch");
        assertEq(att.evidenceURI, "ipfs://evidence", "evidenceURI mismatch");
        assertEq(att.attestedAt, T1, "attestedAt mismatch");
    }

    // -------------------------------------------------------------------------
    // 19. test_attestSnapshot_emitsEvent
    // -------------------------------------------------------------------------
    function test_attestSnapshot_emitsEvent() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.expectEmit(true, true, true, true);
        emit SnapshotAttested(SUBJECT_A, 0, attestor, false, EVIDENCE, 0);
        vm.prank(attestor);
        isl.attestSnapshot(SUBJECT_A, 0, false, EVIDENCE, "");
    }

    // -------------------------------------------------------------------------
    // 20. test_attestSnapshot_multipleByDifferentAttestors
    // -------------------------------------------------------------------------
    function test_attestSnapshot_multipleByDifferentAttestors() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        address attestor2 = address(0xA4);
        vm.startPrank(admin);
        isl.grantRole(isl.ATTESTOR_ROLE(), attestor2);
        vm.stopPrank();

        vm.prank(attestor);
        isl.attestSnapshot(SUBJECT_A, 0, true, EVIDENCE, "ipfs://a1");
        vm.prank(attestor2);
        isl.attestSnapshot(SUBJECT_A, 0, false, EVIDENCE, "ipfs://a2");

        assertEq(isl.attestationCount(SUBJECT_A, 0), 2, "must have 2 attestations");
        assertEq(isl.getAttestation(SUBJECT_A, 0, 0).attestor, attestor, "attestor 0 mismatch");
        assertEq(isl.getAttestation(SUBJECT_A, 0, 1).attestor, attestor2, "attestor 1 mismatch");
    }

    // -------------------------------------------------------------------------
    // 21. test_attestSnapshot_sameAttestorMultiple
    // -------------------------------------------------------------------------
    function test_attestSnapshot_sameAttestorMultiple() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(attestor);
        isl.attestSnapshot(SUBJECT_A, 0, true, EVIDENCE, "ipfs://first");
        vm.prank(attestor);
        isl.attestSnapshot(SUBJECT_A, 0, false, EVIDENCE, "ipfs://second");

        assertEq(isl.attestationCount(SUBJECT_A, 0), 2, "same attestor may attest twice");
        assertTrue(isl.getAttestation(SUBJECT_A, 0, 0).endorsed, "first attestation must be endorsed");
        assertFalse(isl.getAttestation(SUBJECT_A, 0, 1).endorsed, "second attestation must not be endorsed");
    }

    // -------------------------------------------------------------------------
    // 22. test_attestSnapshot_revertsInvalidSnapshot
    // -------------------------------------------------------------------------
    function test_attestSnapshot_revertsInvalidSnapshot() public {
        vm.prank(attestor);
        vm.expectRevert("ImpactSnapshotLog: snapshotIndex out of range");
        isl.attestSnapshot(SUBJECT_A, 0, true, EVIDENCE, "");
    }

    function test_attestSnapshot_revertsZeroEvidenceHash() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(attestor);
        vm.expectRevert("ImpactSnapshotLog: zero evidenceHash");
        isl.attestSnapshot(SUBJECT_A, 0, true, bytes32(0), "");
    }

    // -------------------------------------------------------------------------
    // 23. test_getAttestation_revertsInvalidIndex
    // -------------------------------------------------------------------------
    function test_getAttestation_revertsInvalidIndex() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(attestor);
        isl.attestSnapshot(SUBJECT_A, 0, true, EVIDENCE, "");

        vm.expectRevert("ImpactSnapshotLog: attestationIndex out of range");
        isl.getAttestation(SUBJECT_A, 0, 1);
    }

    // -------------------------------------------------------------------------
    // 24. test_firstSnapshot_initializesMethodology
    // -------------------------------------------------------------------------
    function test_firstSnapshot_initializesMethodology() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        (bytes32 hash, string memory uri) = isl.activeMethodology(SUBJECT_A, CARBON_OFFSET);
        assertEq(hash, METHOD_1, "active methodology hash mismatch");
        assertEq(uri, "ipfs://v1", "active methodology URI mismatch");
    }

    // -------------------------------------------------------------------------
    // 25. test_supersedeMethodology_works
    // -------------------------------------------------------------------------
    function test_supersedeMethodology_works() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(reporter);
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, "ipfs://v2", 1);

        (bytes32 hash, string memory uri) = isl.activeMethodology(SUBJECT_A, CARBON_OFFSET);
        assertEq(hash, METHOD_2, "methodology must be updated to METHOD_2");
        assertEq(uri, "ipfs://v2", "methodology URI must be updated");
    }

    // -------------------------------------------------------------------------
    // 26. test_supersedeMethodology_revertsWrongOldHash
    // -------------------------------------------------------------------------
    function test_supersedeMethodology_revertsWrongOldHash() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: oldMethodologyHash does not match active methodology");
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_2, keccak256("method-v3"), "ipfs://v3", 1);
    }

    function test_supersedeMethodology_revertsZeroNewMethodologyHash() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: zero methodology");
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, bytes32(0), "ipfs://v2", 1);
    }

    function test_supersedeMethodology_revertsEmptyNewMethodologyURI() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: empty methodology URI");
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, "", 1);
    }

    // -------------------------------------------------------------------------
    // 27. test_supersedeMethodology_revertsPastOrdinal
    // -------------------------------------------------------------------------
    function test_supersedeMethodology_revertsPastOrdinal() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // ordinal count = 1
        _record(SUBJECT_A, CARBON_OFFSET, T1, T2, NO_CORRECTION); // ordinal count = 2

        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: effectiveFromOrdinal before current indicatorSnapshotCount");
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, "ipfs://v2", 1);
    }

    // -------------------------------------------------------------------------
    // 28. test_supersedeMethodology_emitsEvent
    // -------------------------------------------------------------------------
    function test_supersedeMethodology_emitsEvent() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.expectEmit(true, true, false, true);
        emit MethodologySuperseded(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, 1);
        vm.prank(reporter);
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, "ipfs://v2", 1);
    }

    // -------------------------------------------------------------------------
    // 29. test_indicatorConstants
    // -------------------------------------------------------------------------
    function test_indicatorConstants() public pure {
        assertEq(CARBON_OFFSET, keccak256("EIP-XXXX:INDICATOR:CARBON_OFFSET"), "CARBON_OFFSET mismatch");
        assertEq(CARBON_EMITTED, keccak256("EIP-XXXX:INDICATOR:CARBON_EMITTED"), "CARBON_EMITTED mismatch");
        assertEq(ENERGY_GENERATED, keccak256("EIP-XXXX:INDICATOR:ENERGY_GENERATED"), "ENERGY_GENERATED mismatch");
        assertEq(ENERGY_SAVED, keccak256("EIP-XXXX:INDICATOR:ENERGY_SAVED"), "ENERGY_SAVED mismatch");
        assertEq(WATER_TREATED, keccak256("EIP-XXXX:INDICATOR:WATER_TREATED"), "WATER_TREATED mismatch");
        assertEq(JOBS_CREATED, keccak256("EIP-XXXX:INDICATOR:JOBS_CREATED"), "JOBS_CREATED mismatch");
        assertEq(BENEFICIARIES, keccak256("EIP-XXXX:INDICATOR:BENEFICIARIES"), "BENEFICIARIES mismatch");
        assertEq(BIODIVERSITY_AREA, keccak256("EIP-XXXX:INDICATOR:BIODIVERSITY_AREA"), "BIODIVERSITY_AREA mismatch");
        assertEq(WASTE_DIVERTED, keccak256("EIP-XXXX:INDICATOR:WASTE_DIVERTED"), "WASTE_DIVERTED mismatch");
    }

    // -------------------------------------------------------------------------
    // 30. test_unitConstants
    // -------------------------------------------------------------------------
    function test_unitConstants() public pure {
        assertEq(UNIT_TCO2E, keccak256("tCO2e"), "UNIT_TCO2E mismatch");
        assertEq(UNIT_KWH, keccak256("kWh"), "UNIT_KWH mismatch");
        assertEq(UNIT_M3, keccak256("m3"), "UNIT_M3 mismatch");
        assertEq(UNIT_FTE, keccak256("FTE"), "UNIT_FTE mismatch");
        assertEq(UNIT_PERSONS, keccak256("persons"), "UNIT_PERSONS mismatch");
        assertEq(UNIT_HECTARES, keccak256("hectares"), "UNIT_HECTARES mismatch");
        assertEq(UNIT_TONNES, keccak256("tonnes"), "UNIT_TONNES mismatch");
    }

    // -------------------------------------------------------------------------
    // 31. P1.1 — duplicate originals rejected
    // -------------------------------------------------------------------------
    function test_recordSnapshot_revertsDuplicateOriginal() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: period slot occupied, use correctsIndex");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 200, 2, UNIT_TCO2E, T0, T1, METHOD_1, "ipfs://v1", NO_CORRECTION);
    }

    // -------------------------------------------------------------------------
    // 32. P1.2 — active methodology enforced for new snapshots
    // -------------------------------------------------------------------------
    function test_recordSnapshot_revertsMethodologyMismatch() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.prank(reporter);
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, "ipfs://v2", 1);

        vm.warp(T2);
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: methodologyHash must match active methodology");
        isl.recordSnapshot(SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T1, T2, METHOD_1, "ipfs://v1", NO_CORRECTION);
    }

    // -------------------------------------------------------------------------
    // 33. P1.3 — effectiveFromOrdinal may equal current indicatorSnapshotCount
    // -------------------------------------------------------------------------
    function test_supersedeMethodology_requiresExactOrdinal() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // count = 1

        vm.prank(reporter);
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, "ipfs://v2", 1);

        (bytes32 hash,) = isl.activeMethodology(SUBJECT_A, CARBON_OFFSET);
        assertEq(hash, METHOD_2, "methodology must be updated when ordinal matches current count");
    }

    // -------------------------------------------------------------------------
    // 33b. P1.3 — effectiveFromOrdinal ahead of current count is scheduled
    // -------------------------------------------------------------------------
    function test_supersedeMethodology_schedulesFutureOrdinal() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION); // count = 1

        vm.prank(reporter);
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, METHOD_1, METHOD_2, "ipfs://v2", 3);

        (bytes32 hash, string memory uri) = isl.activeMethodology(SUBJECT_A, CARBON_OFFSET);
        assertEq(hash, METHOD_1, "future supersession must not activate immediately");
        assertEq(uri, "ipfs://v1", "active URI must remain v1 before scheduled ordinal");

        _record(SUBJECT_A, CARBON_OFFSET, T1, T2, NO_CORRECTION); // count = 2
        (hash, uri) = isl.activeMethodology(SUBJECT_A, CARBON_OFFSET);
        assertEq(hash, METHOD_1, "future supersession must remain pending before ordinal");
        assertEq(uri, "ipfs://v1", "active URI must still be v1 before scheduled ordinal");

        _record(SUBJECT_A, CARBON_OFFSET, T2, T2 + 1, NO_CORRECTION); // count = 3
        (hash, uri) = isl.activeMethodology(SUBJECT_A, CARBON_OFFSET);
        assertEq(hash, METHOD_2, "future supersession must become active when ordinal is reached");
        assertEq(uri, "ipfs://v2", "active URI must become v2 when ordinal is reached");

        vm.warp(T2 + 2);
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: methodologyHash must match active methodology");
        isl.recordSnapshot(
            SUBJECT_A, CARBON_OFFSET, 100, 2, UNIT_TCO2E, T2 + 1, T2 + 2, METHOD_1, "ipfs://v1", NO_CORRECTION
        );

        _recordAs(reporter, SUBJECT_A, CARBON_OFFSET, T2 + 1, T2 + 2, NO_CORRECTION, METHOD_2, "ipfs://v2");
    }

    // -------------------------------------------------------------------------
    // 34. P2.1 — supersedeMethodology rejected before methodology initialized
    // -------------------------------------------------------------------------
    function test_supersedeMethodology_revertsBeforeInit() public {
        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: methodology not yet initialized");
        isl.supersedeMethodology(SUBJECT_A, CARBON_OFFSET, bytes32(0), METHOD_1, "ipfs://v1", 0);
    }

    // -------------------------------------------------------------------------
    // 35. P2.1b — constructor rejects zero admin
    // -------------------------------------------------------------------------
    function test_constructor_revertsZeroAdmin() public {
        vm.expectRevert("ImpactSnapshotLog: zero admin");
        new ImpactSnapshotLog(address(0));
    }

    // -------------------------------------------------------------------------
    // 36. P2.2 — reporter cannot self-attest their own snapshot
    // -------------------------------------------------------------------------
    function test_attestSnapshot_revertsSelfAttestation() public {
        _record(SUBJECT_A, CARBON_OFFSET, T0, T1, NO_CORRECTION);

        vm.startPrank(admin);
        isl.grantRole(isl.ATTESTOR_ROLE(), reporter);
        vm.stopPrank();

        vm.prank(reporter);
        vm.expectRevert("ImpactSnapshotLog: reporter cannot self-attest");
        isl.attestSnapshot(SUBJECT_A, 0, true, EVIDENCE, "");
    }
}
