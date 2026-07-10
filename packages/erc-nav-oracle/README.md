# ERC-8330 Subject-Linked NAV Snapshot Oracle

Reference implementation for ERC-8330: Subject-Linked NAV Snapshot Oracle.

Subject-linked NAV snapshot oracle with provider attribution, valuation timestamps,
methodology references, correction provenance, staleness metadata, and deterministic
median aggregation.

## Specification

- [ERC-8330 Subject-Linked NAV Snapshot Oracle](https://github.com/ethereum/ERCs/pull/1858/files)
- [Ethereum Magicians discussion](https://ethereum-magicians.org/t/erc-8330-subject-linked-nav-snapshot-oracle/28939)
- [ERC PR](https://github.com/ethereum/ERCs/pull/1858)

## Interfaces

| Interface | Purpose |
|-----------|---------|
| `INAVSnapshotOracle` | Publish, correct, invalidate, and query NAV snapshots keyed by `(subjectId, currency)` |
| `INAVAggregation` | Query deterministic median NAV across provider submissions |

## Key Semantics

- Snapshot indices are scoped per `(subjectId, currency)` stream.
- `latestNAV()` returns the terminal snapshot with the most recent valuation timestamp, not a late correction for an older valuation period.
- Each `(subjectId, currency)` stream has one configured NAV basis. `CONFIG_ROLE`
  must call `setNAVBasis()` before publication, and `publishNAV()` rejects
  submissions whose `navBasis` differs from the configured stream basis.
- A provider can publish only one original snapshot per stream and valuation timestamp. Updates to that provider/timestamp must be linked as corrections.
- `correctsIndex == NO_CORRECTION` means an original/non-correction snapshot.
- `correctedByIndex == NO_CORRECTED_BY` (`0`) means "not corrected"; when corrected,
  the target snapshot's `correctedByIndex` is set to the correction snapshot index.
  Index `0` is safe as the corrected-by sentinel because a correction always has
  an index greater than the snapshot it corrects.
- Corrections are fork-free. A snapshot can be corrected once, only by the original provider, and the correction must match the provider's latest snapshot for that valuation timestamp, target valuation timestamp, and configured NAV basis.
- `DEFAULT_ADMIN_ROLE` can permanently invalidate a terminal snapshot when a provider is revoked or compromised. Invalidation preserves the snapshot record but excludes it from current-value, provider-latest, quorum, aggregation, and deviation calculations.
- Invalidation requires a nonzero `reasonHash`, emits `NAVSnapshotInvalidated`, and recomputes latest-provider and latest-quorum pointers. Invalidated snapshots cannot be corrected or restored. Invalidating an original snapshot clears that provider's `(valuationTimestamp, provider)` slot so the provider can submit a replacement original at the same valuation timestamp. Invalidating a terminal correction restores the predecessor as the current terminal snapshot, allowing the provider to submit a replacement correction. For longer correction chains, invalidating the terminal restores only its direct predecessor; earlier corrected snapshots remain corrected unless their successor is also invalidated.
- Correction-of-correction chains are allowed. Use
  `currentSnapshotIndex(subjectId, currency, snapshotIndex)` to resolve the
  terminal snapshot in a chain and `isSnapshotCurrent(subjectId, currency,
  snapshotIndex)` to check whether a snapshot has no successor correction.
- `latestNAVStatus()` reverts until both heartbeat and max valuation age are configured for the stream.
- Aggregation uses the latest valuation timestamp with quorum, uses the configured stream NAV basis, normalizes decimals to the highest submitted decimal precision, and returns the lower median for even provider counts.
- `aggregatedNAV()` also reverts until heartbeat and max valuation age are configured, since it returns staleness flags.
- Deviation detection is emitted from the non-view `publishNAV()` path once quorum is reached.

## Constants

`NAVConstants.sol` defines:

- NAV basis IDs: `PER_UNIT`, `PER_SHARE`, `TOTAL`
- Currency IDs: `USD`, `EUR`, `GBP`, `KES`, `ZMW`
- Token-denominated currency derivation:
  `deriveTokenCurrency(chainId, tokenAddress)`, equivalent to
  `keccak256(abi.encodePacked("ERC-8330:CURRENCY:TOKEN", chainId, tokenAddress))`

Fiat currencies use `keccak256("ERC-8330:CURRENCY:<ISO4217>")`. Token
currencies include both `chainId` and `tokenAddress` so the same token address
on two chains does not collide. Other custom denominations should use an
application-documented, domain-separated string and should not reuse an ISO
4217 code unless the denomination is actually that fiat currency.

## Zero-Value Policy

`methodologyHash` is a required commitment for every NAV snapshot and
correction. The reference implementation rejects `bytes32(0)`.
`methodologyURI` may be empty only when the implementation documents how
verifiers retrieve the methodology out of band. A nonzero hash without a
retrievable or reproducible methodology document is not independently
verifiable.

## Methodology Hash Derivation

The reference implementation stores `methodologyHash` and `methodologyURI`
without interpreting the document format. Deployments must document the hash
derivation they use. Recommended derivations are:

- Raw document commitment: `keccak256(methodologyDocumentBytes)`.
- Document bundle anchor commitment: use the canonical bundle hash when the
  methodology is a bundle of documents or when deterministic document
  normalization is required.

When a document bundle anchor is used, `methodologyURI` should resolve to metadata that
identifies the bundle manifest and the normalization profiles needed to
reproduce the hash. When raw document bytes are used, `methodologyURI` should
resolve to those exact bytes or metadata that makes the retrieval path
unambiguous.

## ERC-4626 Integration Guidance

`latestNAVStatus()` and `aggregatedNAV()` revert until staleness configuration
is set for the `(subjectId, currency)` stream. ERC-4626 `convertToAssets()` and
`convertToShares()` integrations should not call these functions directly unless
the stream is guaranteed to be configured before the vault is enabled. A direct
unconfigured call can make ERC-4626 conversion functions revert unexpectedly.

Recommended integration patterns:

- Use an adapter that checks configuration during vault setup and exposes a
  non-reverting cached NAV to conversion functions.
- Keep subscription/redemption pricing in state-changing request or settlement
  functions, where stale or unconfigured NAV can be handled with explicit
  reverts and user-facing errors.
- Cache the last accepted NAV after validating `latestNAVStatus()` or
  `aggregatedNAV()`, then have conversion preview paths read the cached value.
- Treat `latestNAV()` as raw data only. Pricing paths should use staleness-aware
  validation before accepting a NAV.

## Access Control

The reference implementation is dependency-free and includes minimal role control:

| Role | Permissions |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Grant and revoke roles; invalidate poisoned or disputed snapshots |
| `PROVIDER_ROLE` | Publish original NAV snapshots and corrections for its own snapshots |
| `CONFIG_ROLE` | Set stream NAV basis, staleness configuration, and aggregation configuration |

## Stream NAV Basis

`navBasis` is stream-level configuration, not provider-selected data. Before
any provider can publish NAV for a `(subjectId, currency)` stream, an authorized
configurer must call:

```solidity
setNAVBasis(subjectId, currency, PER_SHARE);
```

The reference implementation rejects unknown bases, repeated configuration, and
publication before basis configuration. It also rejects any provider submission
whose `navBasis` does not match `streamNAVBasis(subjectId, currency)`. This
prevents a single provider from submitting a mismatched basis at a quorum
timestamp and bricking `aggregatedNAV()` for downstream consumers.

## Build & Test

```bash
cd packages/erc-nav-oracle

forge build
forge test -vvv

# Optional, when installed locally:
slither . --config-file slither.config.json
medusa fuzz
```

## Assigned Namespace

The constants use assigned `ERC-8330` domain strings. Off-chain consumers that
hard-code NAV basis identifiers, fiat currency identifiers, token currency
derivations, or related derived values must use the same namespace as the
deployed contracts.

## Known Limits

- NAV is an accounting or valuation input, not a liquid executable market price.
- Provider submissions are trusted assertions; the contract does not verify
  valuation accuracy or provider credentials.
- Methodology hashes are only independently useful when the methodology document
  remains available and its hash derivation is documented.
- Staleness flags protect consumers only when integrations check them before
  accepting a NAV.
- Aggregation reduces single-provider risk but does not prevent provider
  collusion or shared methodology errors.
- Administrative invalidation recomputes stream, provider, and quorum pointers
  in time linear to the stream history. Deployments with very long histories
  should use bounded or checkpointed indexing in their production implementation.
