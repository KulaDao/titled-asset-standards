---
eip: kula-suite
title: Kula Protocol EIP Suite — Tokenized Asset Infrastructure Standards
description: Six composable EIP specifications for on-chain asset registries, document anchoring, transfer governance, compliance logging, impact reporting, and NAV oracles.
author: Kula Protocol
discussions-to: https://ethereum-magicians.org
status: Draft
type: Standards Track
category: ERC
created: 2025-01-01
requires: EIP-165, EIP-20, EIP-721, EIP-1155, EIP-3643
---

## Abstract

This repository contains six composable EIP specifications designed to close structural gaps in the EVM standards landscape for tokenized real-world assets. Each EIP addresses a narrow, well-defined problem and can be adopted independently. Together they form a complete infrastructure layer for compliant, auditable, and interoperable tokenized assets.

| EIP | Title | Package |
|-----|-------|---------|
| EIP-1 | Asset-Bound Token Registry | `packages/eip-1-asset-registry` |
| EIP-2 | Canonical Document Bundle Anchor | `packages/eip-2-document-bundle` |
| EIP-3 | Directional Transfer Domain Registry | `packages/eip-3-transfer-domain` |
| EIP-4 | Subject-Linked Compliance Event Log | `packages/eip-4-compliance-event` |
| EIP-5 | Subject-Linked Impact Snapshot Log | `packages/eip-5-impact-snapshot` |
| EIP-6 | Subject-Linked NAV Snapshot Oracle | `packages/eip-6-nav-oracle` |

---

## Motivation

Tokenized real-world assets — real estate, private credit, commodities, carbon credits — require infrastructure that existing ERC standards do not provide:

- **Asset provenance** — ERC-20, ERC-721, and ERC-3643 carry no on-chain pointer to the legal documents and evidence that establish what a token represents. A token holder cannot verify the underlying asset without off-chain coordination.
- **Document integrity** — Legal packets change over time. There is no standard mechanism to anchor a versioned, order-independent document set on-chain such that any party can independently verify the current canonical bundle.
- **Transfer governance** — Regulated assets require directional transfer controls scoped by jurisdiction and asset class. Existing standards expose no interface for querying whether a route is permitted before attempting a transfer.
- **Compliance audit trails** — On-chain compliance actions (KYC updates, sanctions hits, freeze events) are logged ad hoc in proprietary event schemas, making cross-protocol auditing impractical.
- **Impact reporting** — ESG and sustainability obligations generate structured time-series data that has no standard append-only representation on-chain.
- **NAV oracles** — Net asset value feeds for funds and structured products require a subject-keyed, provider-attributed snapshot model with staleness guarantees. No such standard exists.

These six EIPs are designed to compose: the `anchorId` returned by EIP-1 serves as `subjectId` in EIP-2 through EIP-6, creating a single identity thread across the full asset lifecycle.

---

## Specification

### EIP-1 — Asset-Bound Token Registry

Binds a dual-hash anchor — a legal document commitment and an evidence commitment — to a token contract or token ID. The `anchorId` is deterministic (`keccak256(abi.encode(legalHash, evidenceHash))`) and serves as the canonical on-chain identity for an asset across all companion EIPs.

**Core interface:**

```solidity
interface IAssetAnchorRegistry {
    function registerAnchor(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata
    ) external returns (bytes32 anchorId);

    function bindToken(bytes32 anchorId, address token, uint256 tokenId) external;

    function getAnchor(bytes32 anchorId) external view returns (AnchorRecord memory);
    function isBound(bytes32 anchorId) external view returns (bool);
}
```

**Anchor lifecycle:**

```
REGISTER ──► ACTIVE ──► EXPIRED (expiresAt reached)
                │
                │  reattest() (original registrar or admin only)
                ▼
           DEACTIVATED (permanent)
```

**Metadata** is packed ABI-encoded and carries `assetClass`, `jurisdiction`, `attestationDate`, `expiresAt`, `uri`, and `extensions`. Encoding and decoding is handled by `AnchorMetadataLib`.

**Consumer verification** requires checking both sides: the registry confirms the anchor is active and bound; the token confirms it declares the same registry and `anchorId`.

---

### EIP-2 — Canonical Document Bundle Anchor

Anchors a deterministic, order-independent bundle hash derived from a set of document entries to a `(subjectId, role)` namespace with full supersession history. The bundle hash is computed off-chain using `BundleHashLib`, which applies a total order over all five leaf fields before hashing so that any permutation of the same document set produces the same hash.

**Core interface:**

```solidity
interface IDocumentBundleAnchor {
    function anchorBundle(
        bytes32 bundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external;

    function supersedeBundle(
        bytes32 oldBundleHash,
        bytes32 newBundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external;

    function activeBundle(bytes32 subjectId, bytes32 role) external view returns (bytes32);
    function getAnchor(bytes32 bundleHash, bytes32 subjectId, bytes32 role)
        external view returns (AnchorRecord memory);
}
```

**Bundle hash derivation:**

```solidity
DocumentEntry[] memory entries = ...; // populate fields
entries = BundleHashLib.sortEntries(entries); // total order required
bytes32 bundleHash = BundleHashLib.computeBundleHash(entries);
```

**Anchor lifecycle:**

```
anchorBundle() ──► ACTIVE ──► supersedeBundle() ──► SUPERSEDED (permanent)
                                    │
                                    └──► new ACTIVE record for same (subjectId, role)
```

Superseded records remain permanently queryable. `activeBundle(subjectId, role)` always returns the current canonical hash.

---

### EIP-3 — Directional Transfer Domain Registry

A token-agnostic registry for answering whether a route from `sourceDomain` to `destinationDomain` is permitted for a given `assetClass`. Domains and asset classes are opaque `bytes32` identifiers. The registry does not define what a domain means or enforce transfers — it is a lookup layer.

**Core interface:**

```solidity
interface ITransferDomainRegistry {
    function setRoute(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 permissionEvidenceHash
    ) external;

    function revokeRoute(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass,
        bytes32 revocationEvidenceHash
    ) external;

    function isRoutePermitted(
        bytes32 sourceDomain,
        bytes32 destinationDomain,
        bytes32 assetClass
    ) external view returns (bool);

    function isRoutePermittedBatch(
        bytes32[] calldata sourceDomains,
        bytes32[] calldata destinationDomains,
        bytes32[] calldata assetClasses
    ) external view returns (bool[] memory permitted);
}
```

**Graceful revocation extension** (`IGracefulRouteRevocation`) adds a fixed grace period before a revocation takes effect. Routes are lazily revoked — `isRoutePermitted` returns `false` once `block.timestamp >= effectiveAt` without requiring an explicit finalization write. Pending revocations can be cancelled before expiry or finalized after.

Route key derivation: `keccak256(abi.encodePacked(sourceDomain, destinationDomain, assetClass))`.

---

### EIP-4 — Subject-Linked Compliance Event Log

An append-only on-chain log of structured compliance events bound to a `(subjectId, eventType)` namespace. Each event carries an evidence hash, a structured payload hash, and a timestamp, giving regulators and auditors a tamper-evident audit trail independent of any specific token standard.

---

### EIP-5 — Subject-Linked Impact Snapshot Log

An append-only on-chain log that binds structured, auditable impact data to a `(subjectId, indicatorId)` namespace. Snapshots form immutable correction chains — a superseding snapshot links back to its predecessor, and `currentSnapshotForPeriod` walks the chain to the terminal value. Attestors independently endorse snapshots without ability to modify them. Methodology versioning is future-only: `effectiveFromOrdinal >= indicatorSnapshotCount` at the time of supersession.

**Core interface:**

```solidity
interface IImpactSnapshotLog {
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
    ) external returns (uint256 snapshotIndex);

    function currentSnapshotForPeriod(
        bytes32 subjectId,
        bytes32 indicatorId,
        uint64 periodStart,
        uint64 periodEnd
    ) external view returns (uint256);
}

interface IImpactAttestation {
    function attestSnapshot(
        bytes32 subjectId,
        uint256 snapshotIndex,
        bool endorsed,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external returns (uint256 attestationIndex);
}

interface IMethodologyVersioning {
    function supersedeMethodology(
        bytes32 subjectId,
        bytes32 indicatorId,
        bytes32 oldMethodologyHash,
        bytes32 newMethodologyHash,
        string calldata newMethodologyURI,
        uint256 effectiveFromOrdinal
    ) external;
}
```

**Correction chain:** `correctsIndex = NO_CORRECTION` (`type(uint256).max`) for original snapshots. A correction must match the target's `indicatorId`, `periodStart`, and `periodEnd`. Fork prevention is enforced — each snapshot can be corrected at most once.

**Canonical indicators** (domain-separated via `keccak256("EIP-XXXX:INDICATOR:<name>")`): `CARBON_OFFSET`, `CARBON_EMITTED`, `ENERGY_GENERATED`, `ENERGY_SAVED`, `WATER_TREATED`, `JOBS_CREATED`, `BENEFICIARIES`, `BIODIVERSITY_AREA`, `WASTE_DIVERTED`.

---

### EIP-6 — Subject-Linked NAV Snapshot Oracle

A subject-keyed, provider-attributed NAV snapshot oracle with quorum-based aggregation, decimal normalization, fork-free correction chains, and explicit publication and valuation staleness. NAV snapshots are keyed by `(subjectId, currency)`.

**Core interface:**

```solidity
interface INAVSnapshotOracle {
    function publishNAV(
        bytes32 subjectId,
        bytes32 currency,
        int256 nav,
        uint8 decimals,
        uint8 navBasis,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        string calldata methodologyURI,
        uint256 correctsIndex
    ) external returns (uint256 snapshotIndex);

    function latestNAV(bytes32 subjectId, bytes32 currency)
        external view returns (NAVSnapshot memory);

    function latestNAVStatus(bytes32 subjectId, bytes32 currency)
        external view returns (bool isPublishStale, bool isValuationStale);
}

interface INAVAggregation {
    function aggregatedNAV(bytes32 subjectId, bytes32 currency)
        external view returns (int256 nav, uint8 decimals, uint8 navBasis, uint64 valuationTimestamp);
}
```

**NAV basis constants:** `PER_UNIT`, `PER_SHARE`, `TOTAL`. **Currency constants:** `USD`, `EUR`, `GBP`, `KES`, `ZMW`.

**Aggregation:** Median over provider submissions at the most recent valuation timestamp with quorum. Decimals are normalized to the highest submitted precision. Mixed NAV basis submissions revert. Corrected snapshots are excluded from the aggregation set.

**Staleness:** Two independent thresholds — `heartbeat` (maximum age of last publication) and `maxValuationAge` (maximum age of the underlying valuation). Both are configured per `(subjectId, currency)` stream.

---

## Rationale

### Composability via `subjectId`

Every EIP from EIP-2 through EIP-6 accepts a `subjectId` parameter. By convention this is the `anchorId` returned by EIP-1 `registerAnchor`. This single identity thread means a consumer can pivot from a token address to its legal documents (EIP-2), permitted transfer routes (EIP-3), compliance history (EIP-4), impact performance (EIP-5), and current NAV (EIP-6) using only the anchor ID — without any central registry or coordinator contract.

### Separation of concerns

Each EIP is a narrow interface. None of the six standards knows about the others at the Solidity level. Composability is a naming convention, not an inheritance dependency. This keeps each standard independently adoptable and prevents one standard's upgrade path from blocking another's.

### `bytes32` identifiers

Domains, asset classes, indicator IDs, currencies, and subject IDs are all `bytes32`. This avoids string comparison costs, enables O(1) mapping lookups, and allows any hashing scheme to populate the namespace — `keccak256` of a human-readable string, a UUID, or a structured encoding.

### Append-only logs

EIP-2, EIP-4, EIP-5, and EIP-6 are all append-only. Corrections and supersessions add new records and mark old ones — they never overwrite. This gives full audit history at the cost of slightly higher storage, a trade-off that is appropriate for regulated asset infrastructure where history is a compliance requirement.

### Methodology versioning is future-only

In EIP-5, `effectiveFromOrdinal >= indicatorSnapshotCount` at call time. Retroactive methodology rewriting would break the chain of custody for any snapshot already attested under the old methodology. Future scheduling (`effectiveFromOrdinal > count`) lets a reporter pre-announce a methodology transition before it takes effect.

---

## Backwards Compatibility

Each EIP is a new standard with no changes to existing interfaces. All six EIPs use ERC-165 for interface detection. EIP-1 and EIP-6 reference implementations use OpenZeppelin `AccessControl`. None of the interfaces conflict with ERC-20, ERC-721, ERC-1155, or ERC-3643.

---

## Reference Implementation

Each package is a self-contained Foundry project:

```
packages/eip-N-name/
  src/
    interfaces/       # Solidity interfaces (the standard, CC0-1.0)
    reference/        # Reference implementation (MIT)
    libraries/        # Hash derivation and constants
  test/               # Foundry unit tests + Medusa fuzz harness
  script/             # Example deployment and usage scripts
  foundry.toml
  slither.config.json
  medusa.json
  README.md
```

**Build and test:**

```bash
cd packages/eip-N-name
forge install
forge build
forge test
```

**Static analysis and fuzz:**

```bash
slither . --config-file slither.config.json
medusa fuzz
```

**Specification documents** (docx and markdown) are maintained in `specs/` at the repository root.

---

## Security Considerations

### Access control

All state-changing functions in the reference implementations are protected by `AccessControl` roles. Deployers must ensure admin keys are held in multisigs or timelocks before production deployment. The `DEFAULT_ADMIN_ROLE` should be transferred away from the deployer EOA after initial setup.

### Append-only invariants

The correction and supersession mechanisms in EIP-2, EIP-5, and EIP-6 are fork-free by construction — each record can be superseded or corrected at most once. Consumers must walk the correction chain to the terminal record rather than relying on the original index.

### Oracle trust model

EIP-6 is a permissioned oracle. `PROVIDER_ROLE` holders are trusted to publish accurate NAV data. Quorum and deviation detection reduce the impact of a single compromised provider but do not eliminate it. Consumers should configure quorum thresholds and deviation limits appropriate to their trust assumptions.

### Staleness

`latestNAVStatus` in EIP-6 returns explicit staleness flags. Consumers must check staleness before acting on NAV data. A stale feed must not be used for settlement or margin calculations without explicit operator override.

### `block.timestamp` dependency

EIP-3 grace period revocation, EIP-5 `reportedAt`, and EIP-6 publication timestamps all use `block.timestamp`. Validators can shift this by up to approximately 12 seconds. None of the standards use `block.timestamp` for randomness or for security-critical timing that would be exploitable within a 12-second window.

### EIP number placeholders

Domain-separated constants in EIP-5 and EIP-6 contain `EIP-XXXX` placeholders that will change when EIP numbers are assigned. **Do not deploy to production until these are updated.** The hash values of all canonical identifiers will change.

---

## Copyright

Interfaces (all `src/interfaces/` files) are released under **CC0-1.0** — no rights reserved, as required for ERC submission.

Reference implementations (`src/reference/`) and libraries (`src/libraries/`) are released under the **MIT License**.
