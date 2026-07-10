# ERC-8328 Subject-Linked Compliance Event Log

Reference implementation for ERC-8328: Subject-Linked Compliance Event Log.

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
- `correctsIndex == NO_CORRECTION` means an original/non-correction event.
- `correctedByIndex == NO_CORRECTED_BY` (`0`) means "not corrected"; when corrected,
  the target event's `correctedByIndex` is set to the correction event index.
  Index `0` is safe as the corrected-by sentinel because a correction always has
  an index greater than the event it corrects.
- Corrections are fork-free and must use `EVT_CORRECTION`.
- A normal recorder can correct only events it originally recorded; an admin can correct any event once
  it also holds `RECORDER_ROLE` or grants that role to itself.
- `occurredAt` must not be in the future and must be within the reference implementation's 30-day backdating window.
- Party arrays are capped at 10 entries and payloads at 2048 bytes.
- Type-specific counters and ordinal getters allow per-event-type iteration without scanning the full subject log.

## Constants

`ComplianceConstants.sol` defines subject types, event types, party roles,
outcomes, common authorities, and base payload profile identifiers.

## Payload Profile Semantics

Base payload profiles use the following ABI encodings:

| Profile | Encoding |
|---------|----------|
| `PAYLOAD_TRANSFER_V1` | `abi.encode(address from, address to, uint256 amount, bytes32 routeRef)` |
| `PAYLOAD_FREEZE_V1` | `abi.encode(address target, uint256 amount, uint64 expiresAt, bytes32 reason)` |
| `PAYLOAD_KYC_V1` | `abi.encode(address subject, bytes32 jurisdiction, bytes32 riskTier, uint64 expiresAt)` |
| `PAYLOAD_FORCED_TRANSFER_V1` | `abi.encode(address from, address to, uint256 amount, bytes32 legalBasis)` |

Consumers MUST check `payloadProfileId` before decoding `payload`. Unknown
payload profile identifiers MUST be treated as opaque bytes.

The reference implementation stores `payloadProfileId` and `payload` as
submitted. It enforces only the `MAX_PAYLOAD_BYTES` cap. It does not validate
that a payload's bytes match its declared profile, and it does not validate that
a profile is compatible with the submitted event type. That validation is an
application-layer responsibility for recorders and consumers.

## Event Type / Outcome Semantics

The reference implementation does not validate event type / outcome
combinations. For example, it stores the submitted `eventType` and `outcome`
bytes exactly as provided as long as the caller is authorized and the correction
rules are satisfied. This keeps the log as a reporting layer, not a compliance
rule engine. Applications that require a constrained matrix, such as
`EVT_KYC_APPROVED` only with `OUTCOME_APPROVED`, MUST enforce that policy before
calling `recordEvent()`.

## Current-State Resolution

Corrections are append-only. A corrected event remains in the log, and its
`correctedByIndex` points to the correcting event. Because each event can be
corrected at most once and corrections point to an earlier event, correction
chains are linear.

Use `currentEventIndex(subjectId, eventIndex)` to resolve the terminal event in
a correction chain. Use `isEventCurrent(subjectId, eventIndex)` to check whether
an event has not been corrected. `lastRecordedEventByType()` is only a type-index
helper by recording order: it returns the highest event index for that type, not
the event with the greatest `occurredAt`. It does not resolve correction chains
and should not be treated as the current state for an earlier event.

## Zero-Value Policy

`evidenceHash` is a required commitment for every compliance event, including
corrections. The reference implementation rejects `bytes32(0)`. `evidenceURI`
may be empty when the evidence location is not public or is exchanged out of
band, but a nonzero hash must still identify the evidence bundle or redacted
commitment.

## Access Control

The reference implementation is dependency-free and includes minimal role control:

| Role | Permissions |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke roles; may correct any event once also holding `RECORDER_ROLE` |
| `RECORDER_ROLE` | Record original compliance events and correct own events |

## Build & Test

```bash
cd packages/erc-compliance-event-log

forge build
forge test -vvv

# Optional, when installed locally:
slither . --config-file slither.config.json
medusa fuzz
```

## Assigned Namespace

The constants use assigned `ERC-8328` domain strings. Off-chain consumers that
hard-code subject types, event types, party roles, outcomes, authorities, or
payload schema identifiers must use the same namespace as the deployed
contracts.
