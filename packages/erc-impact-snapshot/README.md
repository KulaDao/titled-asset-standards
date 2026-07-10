# ERC-8329 Subject-Linked Impact Snapshot Log

Reference implementation for ERC-8329: Subject-Linked Impact Snapshot Log.

On-chain append-only impact snapshot log that binds structured, auditable impact data to a `(subjectId, indicatorId)` namespace, with correction chains, role-gated attestation, and methodology versioning.

## Specification

- [ERC-8329 Subject-Linked Impact Snapshot Log](https://github.com/ethereum/ERCs/pull/1857/files)
- [Ethereum Magicians discussion](https://ethereum-magicians.org/t/erc-8329-subject-linked-impact-snapshot-log/28938)
- [ERC PR](https://github.com/ethereum/ERCs/pull/1857)

## Interfaces

| Interface | Purpose | License |
|---|---|---|
| `src/interfaces/IImpactSnapshotLog.sol` | Core snapshot recording and querying | CC0-1.0 |
| `src/interfaces/IImpactAttestation.sol` | Snapshot attestation extension | CC0-1.0 |
| `src/interfaces/IMethodologyVersioning.sol` | Methodology supersession lifecycle | CC0-1.0 |

## Libraries

| Library | Purpose | License |
|---|---|---|
| `src/libraries/ImpactConstants.sol` | Canonical indicator and unit identifiers | MIT |

## Reference Implementation

`src/reference/ImpactSnapshotLog.sol` — `AccessControl`-based reference that implements all three interfaces.

## Build & Test

```bash
cd packages/erc-impact-snapshot

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
- `pendingMethodology()` exposes scheduled future methodology hashes, URIs, and effective ordinals before activation
- Self-attestation is blocked: the address that recorded a snapshot cannot endorse it as attestor. This is an address-level guard only; auditor credentialing, affiliate independence, and legal independence are application-layer controls.
- Exact duplicate originals for the same `(subjectId, indicatorId, periodStart, periodEnd)` are rejected, but overlapping periods with different timestamps are allowed. Consumers that aggregate impact data must reconcile overlaps to avoid double counting.
- Custom indicators should use domain-separated identifiers such as `keccak256("ERC-8329:INDICATOR:<NAMESPACE>:<NAME>:V1")`. Do not use generic values such as `keccak256("CUSTOM")`.
- Unit identifiers are `keccak256` of canonical unit strings, preferably SI or UCUM-compatible (`"kWh"`, `"tCO2e"`, `"m3"`). Implementations should document exact case, pluralization, and conversion rules for every custom unit.

## Zero-Value Policy

Methodology hashes and attestation evidence hashes are required commitments.
The reference implementation rejects `bytes32(0)` for snapshot methodology
hashes, methodology supersession hashes, and attestation evidence hashes.
Attestation `evidenceURI` may be empty when evidence is private or exchanged
out of band, but the nonzero hash must still commit to the evidence.

## Methodology Discovery

`activeMethodology(subjectId, indicatorId)` returns the methodology currently
required for new snapshots. If a future supersession has been scheduled but the
effective ordinal has not been reached, `pendingMethodology(subjectId,
indicatorId)` returns the scheduled hash, URI, and ordinal. Once the ordinal is
reached, the pending getter returns `pending = false` and the methodology is
available through `activeMethodology()`.

Methodology URIs are locators, not availability guarantees. Consumers should
verify the document bytes against `methodologyHash` and mirror critical
methodology documents where long-term auditability matters.

## Known Limits

- The log is tamper-evident, not truth-verifying. It does not prove that a reported impact value is accurate.
- Attestation records do not prove auditor independence or credential status unless the deployment enforces those policies.
- Public-chain deployments should avoid plaintext sensitive data in subjects, evidence documents, or methodology documents. Use redacted documents or commitments when impact data can reveal personal, commercial, or site-sensitive information.
- Overlapping periods and semantically related indicators can double-count impact if consumers aggregate them without external methodology rules.
- The contract stores hashes and URIs but cannot guarantee off-chain document availability.
- Methodology supersession visibility does not imply regulatory acceptance of the new methodology.
