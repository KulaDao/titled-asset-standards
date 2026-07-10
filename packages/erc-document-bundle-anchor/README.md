# ERC-8326 Canonical Document Bundle Anchor

Reference implementation for ERC-8326: Canonical Document Bundle Anchor.

On-chain anchor that binds a deterministic bundle hash (derived from a set of document entries) to a `(subjectId, role)` namespace, with full lifecycle management and permanent supersession history.

## Specification

- [ERC-8326 Canonical Document Bundle Anchor](https://github.com/ethereum/ERCs/pull/1854/files)
- [Ethereum Magicians discussion](https://ethereum-magicians.org/t/erc-8326-canonical-document-bundle-anchor/28935)
- [ERC PR](https://github.com/ethereum/ERCs/pull/1854)

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

Use `BundleHashLib` to reproduce canonical, order-independent bundle hashes.
The recommended production pattern is to normalize, sort, and hash document
entries off-chain, then pass the resulting `bundleHash` to the anchor contract:

```solidity
DocumentEntry[] memory entries = ...; // populate fields
bytes32 bundleHash = BundleHashLib.computeCanonicalBundleHash(entries);
```

`computeCanonicalBundleHash` sorts entries before hashing. It is the safe
convenience path for tests, tooling, and small on-chain bundles, but its
`sortEntries` helper uses an O(n^2) bubble sort with struct copies and is not
intended as a gas-efficient large-bundle sorting algorithm.

`sortEntries` produces a **total order** over all 5 leaf fields (`role`, `filenameHash`, `contentHash`, `mimeTypeHash`, `normProfileId`) — any permutation of the same entry set yields the same hash. `computeBundleHash` is the low-level pre-sorted API: it reverts if entries are not already in canonical order. Downstream contracts that must verify large bundles on-chain SHOULD pass pre-sorted entries to `computeBundleHash()` or use a more efficient sorting/verification algorithm before hashing.

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

## Subject and Metadata URI Policy

`subjectId == bytes32(0)` and `role == bytes32(0)` are invalid in the
reference implementation. Applications that need standalone anchoring should
derive a nonzero subject identifier from application context, such as
`keccak256(abi.encodePacked("ERC-8326:DOCUMENT_SUBJECT", msg.sender, nonce))`,
rather than sharing a zero namespace.

`metadataURI` may be empty. An empty URI means the anchor stores the bundle commitment and document count without an on-chain retrieval pointer. Deployments that require off-chain document availability SHOULD require a non-empty URI at the application layer.

## Access Control Roles

| Role | Constant | Permissions |
|------|----------|-------------|
| `DEFAULT_ADMIN_ROLE` | `0x00` | Grant/revoke roles, supersede any bundle, reassign slot principals |
| `ANCHOR_ROLE` | `keccak256("ANCHOR")` | Anchor new bundles, supersede own slot's bundles |

### Slot principal model

Each `(subjectId, role)` slot has a **slot principal** — the address authorised to call `supersedeBundle` for that slot. The principal is set to `msg.sender` whenever a bundle is anchored or superseded into the slot. `DEFAULT_ADMIN_ROLE` can always supersede regardless of the current principal.

`slotPrincipal(subjectId, role)` and `assignSlotPrincipal(subjectId, role, principal)` are defined on the separate `IDocumentBundleAnchorRecovery` extension interface. The core `IDocumentBundleAnchor` interface ID is stable across deployments that use different recovery models; `BundleAnchorVerifier` checks only the core interface.

**Contested-slot recovery — use `assignSlotPrincipal`, not direct admin `supersedeBundle`**

> ⚠️ Calling `supersedeBundle` directly as admin on a contested slot is front-runnable. The squatter still holds `ANCHOR_ROLE` and is the current slot principal, so they can call `supersedeBundle` first with higher gas, invalidating the admin's `oldBundleHash` argument. Use the sequence below instead.

```
1. Admin calls assignSlotPrincipal(subjectId, role, legitimateOperator)
   — atomic and un-front-runnable: squatter lacks DEFAULT_ADMIN_ROLE
2. Admin grants ANCHOR_ROLE to legitimateOperator if not already held
3. legitimateOperator calls supersedeBundle() using the now-stable active bundle hash
   — squatter's supersedeBundle() calls now revert (no longer the slot principal)
```

**Pre-assignment (optional):** Call `assignSlotPrincipal` before any `anchorBundle` for a slot to reserve it. `anchorBundle` enforces `_slotPrincipal == address(0) || _slotPrincipal == msg.sender`, so the pre-assignment cannot be bypassed by another `ANCHOR_ROLE` holder.

## Consumer Verification

```solidity
// 1. Retrieve the current active bundle for this subject+role
bytes32 active = registry.activeBundle(subjectId, role);

// 2. Verify the record matches expectations
IDocumentBundleAnchor.AnchorRecord memory rec = registry.getAnchor(active, subjectId, role);
require(!rec.superseded);

// 3. Recompute the bundle hash off-chain and compare
bytes32 recomputed = BundleHashLib.computeCanonicalBundleHash(entries);
require(recomputed == active);
```

## Build & Test

```bash
cd packages/erc-document-bundle-anchor

forge build
forge test                          # unit tests

# Invariant / fuzz
forge test --match-contract DocumentBundleAnchorInvariantTest
medusa fuzz                         # requires medusa.json
```

## Assigned Namespace

`BundleHashLib.SCHEMA_V1 = keccak256("ERC-8326:BUNDLE:V1")` uses the assigned ERC-8326 namespace. Any namespace change changes the derived bundle schema hash and must be coordinated with tests, docs, fixtures, and off-chain consumers.

Pre-review checklist:

- Regenerate and publish normative test vectors after the namespace update.
- Confirm reference implementation repository links and fixture hashes before Review status.

## Companion standards

The `subjectId` used here is designed to be the `anchorId` returned by the [**ERC-8325 Asset Anchor Registry**](../erc-asset-registry), linking document bundles directly to on-chain asset anchors.
