// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IImpactSnapshotLog, NO_CORRECTION} from "../interfaces/IImpactSnapshotLog.sol";
import {IImpactAttestation} from "../interfaces/IImpactAttestation.sol";
import {IMethodologyVersioning} from "../interfaces/IMethodologyVersioning.sol";

contract ImpactSnapshotLog is IImpactSnapshotLog, IImpactAttestation, IMethodologyVersioning, AccessControl {
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER");
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR");
    uint256 public constant MAX_METHODOLOGY_LOOKAHEAD = 1000;

    struct PendingMethodology {
        bytes32 newMethodologyHash;
        string newMethodologyUri;
        uint256 effectiveFromOrdinal;
        bool pending;
    }

    // snapshots[subjectId] — index within array is the per-subject snapshotIndex
    mapping(bytes32 => IndicatorSnapshot[]) private _snapshots;

    // _indicatorIndices[subjectId][indicatorId] — ordered list of global snapshotIndices
    mapping(bytes32 => mapping(bytes32 => uint256[])) private _indicatorIndices;

    // _periodSlot[subjectId][indicatorId][periodKey] — snapshotIndex of the latest record for a period
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => uint256))) private _periodSlot;
    // tracks whether a period slot has been set (index 0 is valid)
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => bool))) private _periodSlotSet;

    // _attestations[subjectId][snapshotIndex]
    mapping(bytes32 => mapping(uint256 => Attestation[])) private _attestations;

    // _activeMethodologyHash[subjectId][indicatorId]
    mapping(bytes32 => mapping(bytes32 => bytes32)) private _activeMethodologyHash;
    // _activeMethodologyUri[subjectId][indicatorId]
    mapping(bytes32 => mapping(bytes32 => string)) private _activeMethodologyUri;
    // _methodologyInitialized[subjectId][indicatorId]
    mapping(bytes32 => mapping(bytes32 => bool)) private _methodologyInitialized;
    // _pendingMethodology[subjectId][indicatorId]
    mapping(bytes32 => mapping(bytes32 => PendingMethodology)) private _pendingMethodology;

    constructor(address admin) {
        require(admin != address(0), "ImpactSnapshotLog: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REPORTER_ROLE, admin);
        _grantRole(ATTESTOR_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // IImpactSnapshotLog
    // -------------------------------------------------------------------------

    function recordSnapshot(
        bytes32 subjectId,
        bytes32 indicatorId,
        int256 value,
        uint8 decimals,
        bytes32 unit,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 methodologyHash,
        string calldata methodologyURI,
        uint256 correctsIndex
    ) external onlyRole(REPORTER_ROLE) returns (uint256 snapshotIndex) {
        require(periodStart < periodEnd, "ImpactSnapshotLog: periodStart must be < periodEnd");
        require(periodEnd <= block.timestamp, "ImpactSnapshotLog: incomplete period");
        require(methodologyHash != bytes32(0), "ImpactSnapshotLog: zero methodology");
        require(bytes(methodologyURI).length != 0, "ImpactSnapshotLog: empty methodology URI");

        snapshotIndex = _snapshots[subjectId].length;
        bytes32 periodKey = keccak256(abi.encodePacked(periodStart, periodEnd));

        if (correctsIndex != NO_CORRECTION) {
            require(correctsIndex < _snapshots[subjectId].length, "ImpactSnapshotLog: correctsIndex out of range");
            IndicatorSnapshot storage target = _snapshots[subjectId][correctsIndex];
            require(target.correctedByIndex == 0, "ImpactSnapshotLog: target snapshot already corrected");
            require(
                target.indicatorId == indicatorId && target.periodStart == periodStart && target.periodEnd == periodEnd,
                "ImpactSnapshotLog: correction must match target period and indicator"
            );
            require(
                target.reportedBy == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
                "ImpactSnapshotLog: correction not authorized"
            );
            // correctedByIndex == 0 is also the zero-value; we disambiguate using the
            // snapshotIndex itself: index 0 can never correct another snapshot at index 0.
            target.correctedByIndex = snapshotIndex;
        } else {
            require(
                !_periodSlotSet[subjectId][indicatorId][periodKey],
                "ImpactSnapshotLog: period slot occupied, use correctsIndex"
            );
        }

        if (_methodologyInitialized[subjectId][indicatorId]) {
            _applyPendingMethodologyIfReady(subjectId, indicatorId);
            require(
                methodologyHash == _activeMethodologyHash[subjectId][indicatorId],
                "ImpactSnapshotLog: methodologyHash must match active methodology"
            );
        }

        _snapshots[subjectId].push(
            IndicatorSnapshot({
                subjectId: subjectId,
                indicatorId: indicatorId,
                value: value,
                decimals: decimals,
                unit: unit,
                periodStart: periodStart,
                periodEnd: periodEnd,
                methodologyHash: methodologyHash,
                methodologyURI: methodologyURI,
                reportedBy: msg.sender,
                reportedAt: uint64(block.timestamp),
                correctsIndex: correctsIndex,
                correctedByIndex: 0
            })
        );

        _indicatorIndices[subjectId][indicatorId].push(snapshotIndex);

        _periodSlot[subjectId][indicatorId][periodKey] = snapshotIndex;
        _periodSlotSet[subjectId][indicatorId][periodKey] = true;

        if (!_methodologyInitialized[subjectId][indicatorId]) {
            _activeMethodologyHash[subjectId][indicatorId] = methodologyHash;
            _activeMethodologyUri[subjectId][indicatorId] = methodologyURI;
            _methodologyInitialized[subjectId][indicatorId] = true;
        }

        emit SnapshotRecorded(
            subjectId,
            indicatorId,
            snapshotIndex,
            value,
            decimals,
            unit,
            periodStart,
            periodEnd,
            methodologyHash,
            correctsIndex,
            msg.sender
        );
    }

    function getSnapshot(bytes32 subjectId, uint256 snapshotIndex) external view returns (IndicatorSnapshot memory) {
        require(snapshotIndex < _snapshots[subjectId].length, "ImpactSnapshotLog: snapshotIndex out of range");
        return _snapshots[subjectId][snapshotIndex];
    }

    function snapshotCount(bytes32 subjectId) external view returns (uint256) {
        return _snapshots[subjectId].length;
    }

    function indicatorSnapshotCount(bytes32 subjectId, bytes32 indicatorId) external view returns (uint256) {
        return _indicatorIndices[subjectId][indicatorId].length;
    }

    function indicatorSnapshotAt(bytes32 subjectId, bytes32 indicatorId, uint256 ordinal)
        external
        view
        returns (uint256)
    {
        uint256[] storage indices = _indicatorIndices[subjectId][indicatorId];
        require(ordinal < indices.length, "ImpactSnapshotLog: ordinal out of range");
        return indices[ordinal];
    }

    function latestIndicatorSnapshot(bytes32 subjectId, bytes32 indicatorId) external view returns (uint256) {
        uint256[] storage indices = _indicatorIndices[subjectId][indicatorId];
        require(indices.length > 0, "ImpactSnapshotLog: no snapshots for indicator");
        return indices[indices.length - 1];
    }

    function currentSnapshotForPeriod(bytes32 subjectId, bytes32 indicatorId, uint64 periodStart, uint64 periodEnd)
        external
        view
        returns (uint256)
    {
        bytes32 periodKey = keccak256(abi.encodePacked(periodStart, periodEnd));
        require(_periodSlotSet[subjectId][indicatorId][periodKey], "ImpactSnapshotLog: no snapshot for period");

        uint256 idx = _periodSlot[subjectId][indicatorId][periodKey];
        // walk the correction chain to the terminal snapshot
        while (_snapshots[subjectId][idx].correctedByIndex != 0) {
            idx = _snapshots[subjectId][idx].correctedByIndex;
        }
        return idx;
    }

    // -------------------------------------------------------------------------
    // IImpactAttestation
    // -------------------------------------------------------------------------

    function attestSnapshot(
        bytes32 subjectId,
        uint256 snapshotIndex,
        bool endorsed,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external onlyRole(ATTESTOR_ROLE) returns (uint256 attestationIndex) {
        require(snapshotIndex < _snapshots[subjectId].length, "ImpactSnapshotLog: snapshotIndex out of range");
        require(evidenceHash != bytes32(0), "ImpactSnapshotLog: zero evidenceHash");
        require(
            _snapshots[subjectId][snapshotIndex].reportedBy != msg.sender,
            "ImpactSnapshotLog: reporter cannot self-attest"
        );

        attestationIndex = _attestations[subjectId][snapshotIndex].length;
        _attestations[subjectId][snapshotIndex].push(
            Attestation({
                attestor: msg.sender,
                endorsed: endorsed,
                evidenceHash: evidenceHash,
                evidenceURI: evidenceURI,
                attestedAt: uint64(block.timestamp)
            })
        );

        emit SnapshotAttested(subjectId, snapshotIndex, msg.sender, endorsed, evidenceHash, attestationIndex);
    }

    function attestationCount(bytes32 subjectId, uint256 snapshotIndex) external view returns (uint256) {
        return _attestations[subjectId][snapshotIndex].length;
    }

    function getAttestation(bytes32 subjectId, uint256 snapshotIndex, uint256 attestationIndex)
        external
        view
        returns (Attestation memory)
    {
        require(
            attestationIndex < _attestations[subjectId][snapshotIndex].length,
            "ImpactSnapshotLog: attestationIndex out of range"
        );
        return _attestations[subjectId][snapshotIndex][attestationIndex];
    }

    // -------------------------------------------------------------------------
    // IMethodologyVersioning
    // -------------------------------------------------------------------------

    function supersedeMethodology(
        bytes32 subjectId,
        bytes32 indicatorId,
        bytes32 oldMethodologyHash,
        bytes32 newMethodologyHash,
        string calldata newMethodologyURI,
        uint256 effectiveFromOrdinal
    ) external onlyRole(REPORTER_ROLE) {
        require(_methodologyInitialized[subjectId][indicatorId], "ImpactSnapshotLog: methodology not yet initialized");
        require(newMethodologyHash != bytes32(0), "ImpactSnapshotLog: zero methodology");
        require(bytes(newMethodologyURI).length != 0, "ImpactSnapshotLog: empty methodology URI");
        _applyPendingMethodologyIfReady(subjectId, indicatorId);
        require(
            !_pendingMethodology[subjectId][indicatorId].pending, "ImpactSnapshotLog: methodology supersession pending"
        );
        require(
            _activeMethodologyHash[subjectId][indicatorId] == oldMethodologyHash,
            "ImpactSnapshotLog: oldMethodologyHash does not match active methodology"
        );
        uint256 currentOrdinal = _indicatorIndices[subjectId][indicatorId].length;
        require(
            effectiveFromOrdinal >= currentOrdinal,
            "ImpactSnapshotLog: effectiveFromOrdinal before current indicatorSnapshotCount"
        );
        require(
            effectiveFromOrdinal <= currentOrdinal + MAX_METHODOLOGY_LOOKAHEAD,
            "ImpactSnapshotLog: effectiveFromOrdinal too far in the future"
        );

        if (effectiveFromOrdinal == currentOrdinal) {
            _setActiveMethodology(subjectId, indicatorId, newMethodologyHash, newMethodologyURI);
        } else {
            _pendingMethodology[subjectId][indicatorId] = PendingMethodology({
                newMethodologyHash: newMethodologyHash,
                newMethodologyUri: newMethodologyURI,
                effectiveFromOrdinal: effectiveFromOrdinal,
                pending: true
            });
        }

        emit MethodologySuperseded(subjectId, indicatorId, oldMethodologyHash, newMethodologyHash, effectiveFromOrdinal);
    }

    function activeMethodology(bytes32 subjectId, bytes32 indicatorId)
        external
        view
        returns (bytes32 methodologyHash, string memory methodologyURI)
    {
        PendingMethodology storage pending = _pendingMethodology[subjectId][indicatorId];
        if (pending.pending && _indicatorIndices[subjectId][indicatorId].length >= pending.effectiveFromOrdinal) {
            return (pending.newMethodologyHash, pending.newMethodologyUri);
        }
        return (_activeMethodologyHash[subjectId][indicatorId], _activeMethodologyUri[subjectId][indicatorId]);
    }

    function pendingMethodology(bytes32 subjectId, bytes32 indicatorId)
        external
        view
        returns (
            bytes32 newMethodologyHash,
            string memory newMethodologyURI,
            uint256 effectiveFromOrdinal,
            bool pending
        )
    {
        PendingMethodology storage pendingRecord = _pendingMethodology[subjectId][indicatorId];
        if (!pendingRecord.pending) return (bytes32(0), "", 0, false);
        if (_indicatorIndices[subjectId][indicatorId].length >= pendingRecord.effectiveFromOrdinal) {
            return (bytes32(0), "", 0, false);
        }
        return
            (
                pendingRecord.newMethodologyHash,
                pendingRecord.newMethodologyUri,
                pendingRecord.effectiveFromOrdinal,
                true
            );
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IImpactSnapshotLog).interfaceId
            || interfaceId == type(IImpactAttestation).interfaceId
            || interfaceId == type(IMethodologyVersioning).interfaceId || super.supportsInterface(interfaceId);
    }

    function _applyPendingMethodologyIfReady(bytes32 subjectId, bytes32 indicatorId) internal {
        PendingMethodology storage pending = _pendingMethodology[subjectId][indicatorId];
        if (!pending.pending) return;
        if (_indicatorIndices[subjectId][indicatorId].length < pending.effectiveFromOrdinal) return;

        _setActiveMethodology(subjectId, indicatorId, pending.newMethodologyHash, pending.newMethodologyUri);
        delete _pendingMethodology[subjectId][indicatorId];
    }

    function _setActiveMethodology(
        bytes32 subjectId,
        bytes32 indicatorId,
        bytes32 methodologyHash,
        string memory methodologyURI
    ) internal {
        _activeMethodologyHash[subjectId][indicatorId] = methodologyHash;
        _activeMethodologyUri[subjectId][indicatorId] = methodologyURI;
    }
}
