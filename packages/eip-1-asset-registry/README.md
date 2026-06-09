# eip-1-asset-registry

On-chain registry that binds a dual-hash anchor (legal + evidence document commitments) to a token contract or token ID.

## Interfaces

| Interface | Purpose |
|-----------|---------|
| `IAssetAnchorRegistry` | Registry operations: register, bind, query |
| `IAssetAnchorRegistryLifecycle` | Metadata, active-status, re-attestation, and deactivation extension |
| `IAssetBoundToken` | Token-side view for whole-contract bindings |
| `IAssetBoundTokenId` | Token-side view for per-token-ID bindings |

### `IAssetAnchorRegistry`

```solidity
function registerAnchor(bytes32 legalHash, bytes32 evidenceHash, bytes calldata metadata)
    external returns (bytes32 anchorId);

function bindToken(
    bytes32 anchorId,
    address token,
    bytes32 bindingScope,
    uint256 tokenId
) external;

function registerAndBind(
    bytes32 legalHash, bytes32 evidenceHash, bytes calldata metadata,
    address token, bytes32 bindingScope, uint256 tokenId
) external returns (bytes32 anchorId);

function getAnchor(bytes32 anchorId) external view returns (AnchorRecord memory);
function isBound(bytes32 anchorId) external view returns (bool);
```

`anchorId = keccak256(abi.encode(legalHash, evidenceHash))` — deterministic, doubles as duplicate detection.

### `IAssetAnchorRegistryLifecycle`

```solidity
function getMetadata(bytes32 anchorId) external view returns (AnchorMetadataLib.AnchorMetadata memory);
function registeredBy(bytes32 anchorId) external view returns (address);
function isActive(bytes32 anchorId) external view returns (bool);
function deactivateAnchor(bytes32 anchorId, string calldata reason) external;
function reattest(bytes32 anchorId, uint64 newExpiresAt, uint64 newAttestationDate) external;
```

## Anchor Lifecycle

```
REGISTER ──► ACTIVE ──► EXPIRED (expiresAt reached)
                │              │
                │    reattest()│ (original registrar or admin only)
                │              ▼
                │          ACTIVE again
                │
                ▼
           DEACTIVATED (permanent — admin only, blocks reattest)
```

Expiry is inclusive in the reference implementation: an anchor remains active while `block.timestamp <= expiresAt` and expires when `block.timestamp > expiresAt`.

**Binding** creates a permanent, immutable link between an anchor and a `(token, bindingScope, tokenId)` tuple:
- Only possible while the anchor is active and unexpired
- Only the original registrar or `DEFAULT_ADMIN_ROLE` can bind
- Each `(token, bindingScope, tokenId)` tuple can be bound to at most one anchor in a given registry
- `isBound()` returns `true` even after the anchor is deactivated or expired

Binding scopes are explicit:

```solidity
bytes32 constant BINDING_SCOPE_CONTRACT = keccak256("EIP-XXXX:BINDING_SCOPE:CONTRACT");
bytes32 constant BINDING_SCOPE_TOKEN_ID = keccak256("EIP-XXXX:BINDING_SCOPE:TOKEN_ID");
```

For whole-contract binding, use `BINDING_SCOPE_CONTRACT` with `tokenId = 0` as the canonical unused value. For per-token binding, use `BINDING_SCOPE_TOKEN_ID`; token ID `0` is valid and is not treated as a sentinel.

## Access Control Roles

| Role | Selector constant | Permissions |
|------|-------------------|-------------|
| `DEFAULT_ADMIN_ROLE` | `0x00` | Grant/revoke roles, deactivate anchors, bind any anchor, re-attest any anchor |
| `REGISTRAR_ROLE` | `keccak256("REGISTRAR")` | Register anchors, bind own anchors, re-attest own anchors |

## Consumer Verification

A complete binding verification requires checking **both sides**:

```solidity
// 1. Registry side — anchor exists and is active
IAssetAnchorRegistry.AnchorRecord memory record = registry.getAnchor(anchorId);
bool active = IAssetAnchorRegistryLifecycle(address(registry)).isActive(anchorId);
require(record.anchorId == anchorId);
require(active);

// 2. Token side — token declares agreement when it implements a token-side interface
if (record.bindingScope == BINDING_SCOPE_CONTRACT) {
    require(IAssetBoundToken(token).anchorRegistry() == address(registry));
    require(IAssetBoundToken(token).anchorId() == anchorId);
} else if (record.bindingScope == BINDING_SCOPE_TOKEN_ID) {
    require(IAssetBoundTokenId(token).anchorRegistry() == address(registry));
    require(IAssetBoundTokenId(token).anchorIdOf(record.boundTokenId) == anchorId);
}
```

The registry enforces the registry-side of this check at bind time (`anchorRegistry()` must equal `address(this)` if declared). The token-side `anchorId()` / `anchorIdOf()` check is the caller's responsibility.

## Build & Test

```bash
cd packages/eip-1-asset-registry

# Build
forge build

# Unit, integration, and configured invariant tests
forge test

# Invariant tests
forge test --match-contract AssetAnchorRegistryInvariantTest

# Gas snapshot
forge snapshot
```

## Metadata Format

Packed ABI-encoded `AnchorMetadata` struct — encode/decode via `AnchorMetadataLib`:

```solidity
struct AnchorMetadata {
    bytes32 assetClass;      // e.g. keccak256("EIP-XXXX:ASSET_CLASS:EQUITY") — required
    bytes32 jurisdiction;    // e.g. keccak256("EIP-XXXX:JURISDICTION:US")    — required
    uint64  attestationDate; // Unix timestamp, <= block.timestamp at registration
    uint64  expiresAt;       // Unix timestamp, > attestationDate
    bytes   uri;             // IPFS / HTTPS pointer     — required
    bytes   extensions;      // ABI-encoded key-value pairs, may be empty
}
```

`assetClass` SHOULD be a domain-separated identifier for the implementation's taxonomy. `jurisdiction` SHOULD be a domain-separated identifier for the uppercase ISO 3166-1 alpha-2 code when the subject has a single primary country jurisdiction.

## Companion EIPs

The `anchorId` returned by `registerAnchor` is designed to serve as `subjectId` in:

- **EIP-2** — Document Bundle Anchor
- **EIP-4** — Compliance Event Log
- **EIP-5** — Impact Snapshot Log
- **EIP-6** — NAV Oracle Feed
