# eip-6-nav-oracle

Subject-linked NAV snapshot oracle with provider attribution, valuation timestamps,
methodology references, correction provenance, staleness metadata, and deterministic
median aggregation.

## Interfaces

| Interface | Purpose |
|-----------|---------|
| `INAVSnapshotOracle` | Publish, correct, and query NAV snapshots keyed by `(subjectId, currency)` |
| `INAVAggregation` | Query deterministic median NAV across provider submissions |

## Key Semantics

- Snapshot indices are scoped per `(subjectId, currency)` stream.
- `latestNAV()` returns the terminal snapshot with the most recent valuation timestamp, not a late correction for an older valuation period.
- A provider can publish only one original snapshot per stream and valuation timestamp. Updates to that provider/timestamp must be linked as corrections.
- Corrections are fork-free. A snapshot can be corrected once, only by the original provider, and the correction must match the provider's latest snapshot for that valuation timestamp, target valuation timestamp, and NAV basis.
- `latestNAVStatus()` reverts until both heartbeat and max valuation age are configured for the stream.
- Aggregation uses the latest valuation timestamp with quorum, rejects mixed NAV bases, normalizes decimals to the highest submitted decimal precision, and returns the lower median for even provider counts.
- `aggregatedNAV()` also reverts until heartbeat and max valuation age are configured, since it returns staleness flags.
- Deviation detection is emitted from the non-view `publishNAV()` path once quorum is reached.

## Constants

`NAVConstants.sol` defines:

- NAV basis IDs: `PER_UNIT`, `PER_SHARE`, `TOTAL`
- Currency IDs: `USD`, `EUR`, `GBP`, `KES`, `ZMW`

## Zero-Value Policy

`methodologyHash` is a required commitment for every NAV snapshot and
correction. The reference implementation rejects `bytes32(0)`. `methodologyURI`
may be empty in this package until the methodology-discoverability cleanup is
completed, but verifiers must still be able to reproduce or validate the
nonzero methodology hash through documented off-chain context.

## Access Control

The reference implementation is dependency-free and includes minimal role control:

| Role | Permissions |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Grant and revoke roles |
| `PROVIDER_ROLE` | Publish original NAV snapshots and corrections for its own snapshots |
| `CONFIG_ROLE` | Set staleness and aggregation configuration |

## Build & Test

```bash
cd packages/eip-6-nav-oracle

forge build
forge test -vvv

# Optional, when installed locally:
slither . --config-file slither.config.json
medusa fuzz
```

## Known Pre-deployment Blocker

The constants use `EIP-XXXX` domain strings. These domain strings should be updated
once the EIP number is assigned and before any production deployment.
