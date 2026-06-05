# eip-4-compliance-event

Subject-linked compliance event log with actor attribution, claimed authority,
evidence links, payload profiles, type indexing, and correction provenance.

## Interfaces

| Interface | Purpose |
|-----------|---------|
| `IComplianceEventLog` | Record, correct, and query compliance lifecycle events keyed by `subjectId` |

## Key Semantics

- Event indices are scoped per `subjectId`.
- `recordEvent()` is restricted to `RECORDER_ROLE`.
- Records are append-only. Existing fields are never mutated except `correctedByIndex`.
- `correctedByIndex == 0` means "not corrected"; when corrected, the target event's `correctedByIndex`
  is set to the correction event index.
- Corrections are fork-free and must use `EVT_CORRECTION`.
- A normal recorder can correct only events it originally recorded; an admin can correct any event once
  it also holds `RECORDER_ROLE` or grants that role to itself.
- `occurredAt` must not be in the future and must be within the reference implementation's 30-day backdating window.
- Party arrays are capped at 10 entries and payloads at 2048 bytes.
- Type-specific counters and ordinal getters allow per-event-type iteration without scanning the full subject log.

## Constants

`ComplianceConstants.sol` defines subject types, event types, party roles,
outcomes, common authorities, and base payload profile identifiers.

## Access Control

The reference implementation is dependency-free and includes minimal role control:

| Role | Permissions |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke roles; may correct any event once also holding `RECORDER_ROLE` |
| `RECORDER_ROLE` | Record original compliance events and correct own events |

## Build & Test

```bash
cd packages/eip-4-compliance-event

forge build
forge test -vvv

# Optional, when installed locally:
slither . --config-file slither.config.json
medusa fuzz
```

## Known Pre-deployment Blocker

The constants use `EIP-XXXX` domain strings. These domain strings should be
updated once the EIP number is assigned and before any production deployment.
