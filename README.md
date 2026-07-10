# Titled Asset Standards

Composable ERC specifications and reference implementations for titled-asset infrastructure on EVM.

Umbrella discussion: [Ethereum Magicians](https://ethereum-magicians.org/t/proposing-a-family-of-candidate-erc-interfaces-for-titled-asset-infrastructure-architecture-review/28913)

## Abstract

This repository contains six composable ERC specifications designed to close structural gaps in the EVM standards landscape for tokenized real-world assets. Each standard addresses a narrow, well-defined problem and can be adopted independently. Together they form a complete infrastructure layer for compliant, auditable, and interoperable tokenized assets.

| ERC&nbsp;Number | Standard | Specification | Discussion | Reference&nbsp;Package |
|------------|----------|---------------|------------|-------------------|
| [`ERC-8325`](https://github.com/ethereum/ERCs/pull/1853) | Asset&nbsp;Anchor&nbsp;Registry | [spec](https://github.com/ethereum/ERCs/pull/1853/files) | [Magicians](https://ethereum-magicians.org/t/erc-8325-asset-anchor-registry-interface/28934) | <a href="./packages/erc-asset-registry"><code>erc&#8209;asset&#8209;registry</code></a> |
| [`ERC-8326`](https://github.com/ethereum/ERCs/pull/1854) | Canonical&nbsp;Document&nbsp;Bundle&nbsp;Anchor | [spec](https://github.com/ethereum/ERCs/pull/1854/files) | [Magicians](https://ethereum-magicians.org/t/erc-8326-canonical-document-bundle-anchor/28935) | <a href="./packages/erc-document-bundle-anchor"><code>erc&#8209;document&#8209;bundle&#8209;anchor</code></a> |
| [`ERC-8327`](https://github.com/ethereum/ERCs/pull/1855) | Directional&nbsp;Transfer&nbsp;Domain&nbsp;Registry | [spec](https://github.com/ethereum/ERCs/pull/1855/files) | [Magicians](https://ethereum-magicians.org/t/erc-8327-directional-transfer-domain-registry/28936) | <a href="./packages/erc-transfer-domain"><code>erc&#8209;transfer&#8209;domain</code></a> |
| [`ERC-8328`](https://github.com/ethereum/ERCs/pull/1856) | Subject&#8209;Linked&nbsp;Compliance&nbsp;Event&nbsp;Log | [spec](https://github.com/ethereum/ERCs/pull/1856/files) | [Magicians](https://ethereum-magicians.org/t/erc-8328-subject-linked-compliance-event-log/28937) | <a href="./packages/erc-compliance-event-log"><code>erc&#8209;compliance&#8209;event&#8209;log</code></a> |
| [`ERC-8329`](https://github.com/ethereum/ERCs/pull/1857) | Subject&#8209;Linked&nbsp;Impact&nbsp;Snapshot&nbsp;Log | [spec](https://github.com/ethereum/ERCs/pull/1857/files) | [Magicians](https://ethereum-magicians.org/t/erc-8329-subject-linked-impact-snapshot-log/28938) | <a href="./packages/erc-impact-snapshot"><code>erc&#8209;impact&#8209;snapshot</code></a> |
| [`ERC-8330`](https://github.com/ethereum/ERCs/pull/1858) | Subject&#8209;Linked&nbsp;NAV&nbsp;Snapshot&nbsp;Oracle | [spec](https://github.com/ethereum/ERCs/pull/1858/files) | [Magicians](https://ethereum-magicians.org/t/erc-8330-subject-linked-nav-snapshot-oracle/28939) | <a href="./packages/erc-nav-oracle"><code>erc&#8209;nav&#8209;oracle</code></a> |

Review aids: [example UI suite](https://kuladao.github.io/titled-asset-standards-ui/suite/), [technical white paper](./specs/Title%20Tokenisation%20Technical%20White%20Paper.pdf), and [Verichains security review](./docs/security).

---

## Motivation

Tokenized real-world assets — real estate, private credit, commodities, carbon credits — require infrastructure that existing ERC standards do not provide:

- **Asset provenance** — ERC-20, ERC-721, and ERC-3643 carry no on-chain pointer to the legal documents and evidence that establish what a token represents. A token holder cannot verify the underlying asset without off-chain coordination.
- **Document integrity** — Legal packets change over time. There is no standard mechanism to anchor a versioned, order-independent document set on-chain such that any party can independently verify the current canonical bundle.
- **Transfer governance** — Regulated assets require directional transfer controls scoped by jurisdiction and asset class. Existing standards expose no interface for querying whether a route is permitted before attempting a transfer.
- **Compliance audit trails** — On-chain compliance actions (KYC updates, sanctions hits, freeze events) are logged ad hoc in proprietary event schemas, making cross-protocol auditing impractical.
- **Impact reporting** — ESG and sustainability obligations generate structured time-series data that has no standard append-only representation on-chain.
- **NAV oracles** — Net asset value feeds for funds and structured products require a subject-keyed, provider-attributed snapshot model with staleness guarantees. No such standard exists.

These six standards are designed to compose: the `anchorId` returned by the asset registry serves as `subjectId` in the document bundle anchor, transfer domain registry, compliance event log, impact snapshot log, and NAV oracle — creating a single identity thread across the full asset lifecycle.

---

## Admin Recovery Trust Model

The reference implementations include narrowly scoped `DEFAULT_ADMIN_ROLE`
recovery paths for disputed or orphaned state: asset-registry admins can
invalidate token bindings, NAV-oracle admins can invalidate poisoned terminal
snapshots, and document-bundle admins can supersede orphaned bundle slots. These
paths preserve historical records and are intended for recovery from registrar,
provider, or anchorer failure. A compromised admin can misuse them, so production
deployments should protect admin keys with governance, multisig, timelocks, or
equivalent operational controls.

---

## Specification

### [ERC-8325 Asset Anchor Registry](./packages/erc-asset-registry)

Binds a dual-hash anchor — a legal document commitment and an evidence commitment — to a token contract or token ID. The `anchorId` is deterministic (`keccak256(abi.encode(legalHash, evidenceHash))`) and serves as the canonical on-chain identity for an asset across all companion standards.

**Core interface:**

```solidity
interface IAssetAnchorRegistry {
    function registerAnchor(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata
    ) external returns (bytes32 anchorId);

    function bindToken(
        bytes32 anchorId,
        address token,
        bytes32 bindingScope,
        uint256 tokenId
    ) external;

    function getAnchor(bytes32 anchorId) external view returns (AnchorRecord memory);
    function isBound(bytes32 anchorId) external view returns (bool);
}

interface IAssetAnchorRegistryRecovery {
    function invalidateTokenBinding(bytes32 anchorId, bytes32 reasonHash) external;
    function isBindingValid(bytes32 anchorId) external view returns (bool);
}
```

Disputed or squatted bindings can be invalidated by the registry admin. Invalidation permanently deactivates the disputed anchor and frees the token-binding slot while preserving the original binding fields for audit history.

**Anchor lifecycle:**

```
REGISTER ──► ACTIVE ──► EXPIRED (expiresAt reached)
                │
                │  reattest() (original registrar or admin only)
                ▼
           DEACTIVATED (permanent)
```

**Metadata** is packed ABI-encoded and carries `assetClass`, `jurisdiction`, `attestationDate`, `expiresAt`, `uri`, and `extensions`. Encoding and decoding is handled by `AnchorMetadataLib`.

**Consumer verification** requires checking both sides: the registry confirms the anchor is active and its binding is valid; the token confirms it declares the same registry and `anchorId`.

---

### [ERC-8326 Canonical Document Bundle Anchor](./packages/erc-document-bundle-anchor)

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

### [ERC-8327 Directional Transfer Domain Registry](./packages/erc-transfer-domain)

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

### [ERC-8328 Subject-Linked Compliance Event Log](./packages/erc-compliance-event-log)

An append-only on-chain log of structured compliance events bound to a `(subjectId, eventType)` namespace. Each event carries recorder attribution, claimed authority, parties, outcome, evidence hash, payload profile, payload bytes, and both occurrence and recording timestamps. This gives regulators, custodians, and auditors a tamper-evident compliance trail independent of any specific token standard.

Events are never overwritten. Corrections are recorded as new events using `EVT_CORRECTION`, and the corrected record points to the correcting event through `correctedByIndex`. Consumers can resolve the terminal event with `currentEventIndex(subjectId, eventIndex)` or check whether a record remains current with `isEventCurrent`.

The log is deliberately not a compliance rule engine. It records what an authorized actor asserted happened, with evidence and structured payloads, while applications remain responsible for enforcing policy before recording events. Type-specific counters and ordinal getters allow consumers to iterate events such as KYC approvals, freezes, sanctions hits, route checks, or forced transfers without scanning the full subject history.

**Core interface:**

```solidity
interface IComplianceEventLog {
    function recordEvent(
        bytes32 subjectId,
        bytes32 subjectType,
        bytes32 eventType,
        bytes32 outcome,
        bytes32 authority,
        Party[] calldata parties,
        bytes32 evidenceHash,
        string calldata evidenceURI,
        bytes32 payloadProfileId,
        bytes calldata payload,
        bytes32 operationRef,
        uint64 occurredAt,
        uint256 correctsIndex
    ) external returns (uint256 eventIndex);

    function currentEventIndex(bytes32 subjectId, uint256 eventIndex)
        external
        view
        returns (uint256);

    function eventByTypeAt(bytes32 subjectId, bytes32 eventType, uint256 ordinal)
        external
        view
        returns (uint256 eventIndex);
}
```

---

### [ERC-8329 Subject-Linked Impact Snapshot Log](./packages/erc-impact-snapshot)

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

**Canonical indicators** (domain-separated via `keccak256("ERC-8329:INDICATOR:<name>")`): `CARBON_OFFSET`, `CARBON_EMITTED`, `ENERGY_GENERATED`, `ENERGY_SAVED`, `WATER_TREATED`, `JOBS_CREATED`, `BENEFICIARIES`, `BIODIVERSITY_AREA`, `WASTE_DIVERTED`.

---

### [ERC-8330 Subject-Linked NAV Snapshot Oracle](./packages/erc-nav-oracle)

A subject-keyed, provider-attributed NAV snapshot oracle with quorum-based aggregation, decimal normalization, fork-free correction chains, and explicit publication and valuation staleness. NAV snapshots are keyed by `(subjectId, currency)`.

**Core interface:**

```solidity
interface INAVSnapshotOracle {
    function publishNAV(
        bytes32 subjectId,
        bytes32 currency,
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        string calldata methodologyURI,
        uint256 correctsIndex
    ) external returns (uint256 snapshotIndex);

    function invalidateSnapshot(
        bytes32 subjectId,
        bytes32 currency,
        uint256 snapshotIndex,
        bytes32 reasonHash
    ) external;

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

Every standard from the document bundle anchor through the NAV oracle accepts a `subjectId` parameter. By convention this is the `anchorId` returned by the asset registry's `registerAnchor`. This single identity thread means a consumer can pivot from a token address to its legal documents (document bundle anchor), permitted transfer routes (transfer domain registry), compliance history (compliance event log), impact performance (impact snapshot log), and current NAV (NAV oracle) using only the anchor ID — without any central registry or coordinator contract.

### Separation of concerns

Each standard is a narrow interface. None of the six standards knows about the others at the Solidity level. Composability is a naming convention, not an inheritance dependency. This keeps each standard independently adoptable and prevents one standard's upgrade path from blocking another's.

### `bytes32` identifiers

Domains, asset classes, indicator IDs, currencies, and subject IDs are all `bytes32`. This avoids string comparison costs, enables O(1) mapping lookups, and allows any hashing scheme to populate the namespace — `keccak256` of a human-readable string, a UUID, or a structured encoding.

### Append-only logs

The document bundle anchor, compliance event log, impact snapshot log, and NAV oracle are all append-only. Corrections and supersessions add new records and mark old ones — they never overwrite. This gives full audit history at the cost of slightly higher storage, a trade-off that is appropriate for regulated asset infrastructure where history is a compliance requirement.

### Methodology versioning is future-only

In the impact snapshot log, `effectiveFromOrdinal >= indicatorSnapshotCount` at call time. Retroactive methodology rewriting would break the chain of custody for any snapshot already attested under the old methodology. Future scheduling (`effectiveFromOrdinal > count`) lets a reporter pre-announce a methodology transition before it takes effect.

---

## Backwards Compatibility

Each standard is a new interface with no changes to existing interfaces. All six use ERC-165 for interface detection. The asset registry and NAV oracle reference implementations use OpenZeppelin `AccessControl`. None of the interfaces conflict with ERC-20, ERC-721, ERC-1155, or ERC-3643.

---

## Reference Implementation

Each package is a self-contained Foundry project:

```
packages/erc-<name>/
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
cd packages/erc-<name>
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

The correction and supersession mechanisms in the document bundle anchor, impact snapshot log, and NAV oracle are fork-free by construction — each record can be superseded or corrected at most once. Consumers must walk the correction chain to the terminal record rather than relying on the original index.

### Oracle trust model

The NAV oracle is a permissioned oracle. `PROVIDER_ROLE` holders are trusted to publish accurate NAV data. Quorum and deviation detection reduce the impact of a single compromised provider but do not eliminate it. Consumers should configure quorum thresholds and deviation limits appropriate to their trust assumptions.

### Staleness

`latestNAVStatus` in the NAV oracle returns explicit staleness flags. Consumers must check staleness before acting on NAV data. A stale feed must not be used for settlement or margin calculations without explicit operator override.

### `block.timestamp` dependency

Transfer domain registry grace period revocation, impact snapshot log `reportedAt`, and NAV oracle publication timestamps all use `block.timestamp`. Validators can shift this by up to approximately 12 seconds. None of the standards use `block.timestamp` for randomness or for security-critical timing that would be exploitable within a 12-second window.

### Assigned ERC namespaces

Domain-separated constants across this repository use the assigned ERC numbers below. Update source, tests, docs, and any off-chain consumers together if these namespaces ever change; any namespace change changes the `keccak256` of canonical identifiers.

| Package | ERC | Library |
|---------|-----|---------|
| `erc-asset-registry` | ERC-8325 | `AssetRegistryConstants.sol` |
| `erc-document-bundle-anchor` | ERC-8326 | `BundleHashLib.sol` |
| `erc-compliance-event-log` | ERC-8328 | `ComplianceConstants.sol` |
| `erc-impact-snapshot` | ERC-8329 | `ImpactConstants.sol` |
| `erc-nav-oracle` | ERC-8330 | `NAVConstants.sol` |

Off-chain consumers that hard-code indicator IDs, event types, bundle schema hashes, NAV basis identifiers, currency identifiers, or similar derived values must use the assigned namespace strings in the same release as the contracts they index.

---

## Copyright

Interfaces (all `src/interfaces/` files) are released under **CC0-1.0** — no rights reserved, as required for ERC submission.

Reference implementations (`src/reference/`) and libraries (`src/libraries/`) are released under the **MIT License**.
