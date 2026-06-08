# eip-5-impact-snapshot

On-chain append-only impact snapshot log that binds structured, auditable impact data to a `(subjectId, indicatorId)` namespace, with correction chains, independent attestation, and methodology versioning.

## Interfaces

| Interface | Purpose | License |
|---|---|---|
| `src/interfaces/IImpactSnapshotLog.sol` | Core snapshot recording and querying | CC0-1.0 |
| `src/interfaces/IImpactAttestation.sol` | Third-party snapshot attestation | CC0-1.0 |
| `src/interfaces/IMethodologyVersioning.sol` | Methodology supersession lifecycle | CC0-1.0 |

## Libraries

| Library | Purpose | License |
|---|---|---|
| `src/libraries/ImpactConstants.sol` | Canonical indicator and unit identifiers | MIT |

## Reference Implementation

`src/reference/ImpactSnapshotLog.sol` — `AccessControl`-based reference that implements all three interfaces.

## Build & Test

```bash
cd packages/eip-5-impact-snapshot

forge build
forge test                # unit tests

# Invariant / fuzz
medusa fuzz --timeout 120
```

## Design Decisions

- Snapshot indices are global per subject; indicator-level ordinals are tracked separately via `_indicatorIndices`
- `recordSnapshot()` only accepts completed periods where `periodEnd <= block.timestamp`
- Methodology hashes and URIs are required for snapshots and methodology supersessions
- Attestation evidence hashes are required; `attestSnapshot()` rejects `bytes32(0)` evidence hashes
- A second original for the same `(subjectId, indicatorId, period)` is rejected — revisions must use `correctsIndex`
- `recordSnapshot()` is `REPORTER_ROLE` gated; corrections by non-original reporters additionally require `DEFAULT_ADMIN_ROLE`
- `currentSnapshotForPeriod()` walks the correction chain to the terminal snapshot
- Methodology is initialized by the first snapshot for a `(subjectId, indicatorId)` pair; all subsequent snapshots must use the active methodology hash
- `supersedeMethodology()` accepts `effectiveFromOrdinal >= indicatorSnapshotCount`; future ordinals are stored as pending and activate when the indicator reaches that ordinal
- Self-attestation is blocked: the address that recorded a snapshot cannot endorse it as attestor

## Zero-Value Policy

Methodology hashes and attestation evidence hashes are required commitments.
The reference implementation rejects `bytes32(0)` for snapshot methodology
hashes, methodology supersession hashes, and attestation evidence hashes.
Attestation `evidenceURI` may be empty when evidence is private or exchanged
out of band, but the nonzero hash must still commit to the evidence.
