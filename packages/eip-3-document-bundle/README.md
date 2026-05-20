# eip-3-document-bundle

On-chain anchor that binds a deterministic bundle hash (derived from a set of document entries) to a `(subjectId, role)` namespace, with full lifecycle management and permanent supersession history.

## Interfaces

| Interface | Purpose |
|-----------|---------|
| `IDocumentBundleAnchor` | Anchor, supersede, and query document bundles |

### Key functions

```solidity
function anchorBundle(
    bytes32 bundleHash, bytes32 subjectId, bytes32 role,
    uint256 documentCount, string calldata metadataURI
) external;

function supersedeBundle(
    bytes32 oldBundleHash, bytes32 newBundleHash,
    bytes32 subjectId, bytes32 role,
    uint256 documentCount, string calldata metadataURI
) external;

function getAnchor(bytes32 bundleHash, bytes32 subjectId, bytes32 role)
    external view returns (AnchorRecord memory);

function activeBundle(bytes32 subjectId, bytes32 role)
    external view returns (bytes32);
```

## Bundle Hash Derivation

Use `BundleHashLib` to compute a canonical, order-independent bundle hash off-chain or in a consuming contract:

```solidity
DocumentEntry[] memory entries = ...; // populate fields
entries = BundleHashLib.sortEntries(entries); // sort is required
bytes32 bundleHash = BundleHashLib.computeBundleHash(entries);
```

`sortEntries` produces a **total order** over all 5 leaf fields (`role`, `filenameHash`, `contentHash`, `mimeTypeHash`, `normProfileId`) — any permutation of the same entry set yields the same hash.

### `DocumentEntry` struct

| Field | Description |
|-------|-------------|
| `contentHash` | keccak256 of the normalised document bytes |
| `role` | Use `BundleHashLib.LEGAL_BASIS`, `EVIDENCE`, `CERTIFICATION`, etc. |
| `mimeTypeHash` | keccak256 of the MIME type string |
| `filenameHash` | keccak256 of the normalised filename |
| `normProfileId` | Use `BundleHashLib.PROFILE_RAW`, `PROFILE_JSON_RFC8785`, `PROFILE_XML_C14N11` |

## Anchor Lifecycle

```
anchorBundle() ──► ACTIVE ──► supersedeBundle() ──► SUPERSEDED (permanent)
                                    │
                                    └──► new ACTIVE record for same (subjectId, role)
```

- Each `(bundleHash, subjectId, role)` triple has its own independent `AnchorRecord`.
- The same `bundleHash` can be anchored independently for different subjects — records never collide.
- `supersedeBundle()` marks the old record as superseded and creates a new active record atomically.
- Superseded records are retrievable via `getAnchor(oldBundleHash, subjectId, role)` — history is permanent.
- `activeBundle(subjectId, role)` always returns the current canonical hash for a namespace.

## Access Control Roles

| Role | Constant | Permissions |
|------|----------|-------------|
| `DEFAULT_ADMIN_ROLE` | `0x00` | Grant/revoke roles, supersede any anchor |
| `ANCHOR_ROLE` | `keccak256("ANCHOR")` | Anchor new bundles, supersede own anchors |

## Consumer Verification

```solidity
// 1. Retrieve the current active bundle for this subject+role
bytes32 active = registry.activeBundle(subjectId, role);

// 2. Verify the record matches expectations
IDocumentBundleAnchor.AnchorRecord memory rec = registry.getAnchor(active, subjectId, role);
require(!rec.superseded);

// 3. Recompute the bundle hash off-chain and compare
bytes32 recomputed = BundleHashLib.computeBundleHash(sortedEntries);
require(recomputed == active);
```

## Build & Test

```bash
cd packages/eip-3-document-bundle

forge build
forge test                          # 28 unit tests

# Invariant / fuzz
forge test --match-contract DocumentBundleAnchorInvariantTest
medusa fuzz                         # requires medusa.json
```

## Known Pre-deployment Blocker

`BundleHashLib.SCHEMA_V1 = keccak256("EIP-XXXX:BUNDLE:V1")` contains a placeholder EIP number. **This hash will change** when the EIP number is assigned — update `SCHEMA_V1` before any production deployment.

## Companion EIPs

The `subjectId` used here is designed to be the `anchorId` returned by **EIP-1** (Asset-Bound Token Registry), linking document bundles directly to on-chain asset anchors.
