# eip-1-asset-registry

On-chain registry that binds a dual-hash anchor (legal + evidence document commitments) to a token contract or token ID.

## Interfaces

| Interface | Purpose |
|-----------|---------|
| `IAssetAnchorRegistry` | Registry operations: register, bind, query |
| `IAssetBoundToken` | Token-side view of the binding (required for registry binding) |

### `IAssetAnchorRegistry`

```solidity
function registerAnchor(bytes32 legalHash, bytes32 evidenceHash, bytes calldata metadata)
    external returns (bytes32 anchorId);

function bindToken(bytes32 anchorId, address token, uint256 tokenId) external;

function registerAndBind(
    bytes32 legalHash, bytes32 evidenceHash, bytes calldata metadata,
    address token, uint256 tokenId
) external returns (bytes32 anchorId);

function getAnchor(bytes32 anchorId) external view returns (AnchorRecord memory);
function isBound(bytes32 anchorId) external view returns (bool);
```

`anchorId = keccak256(abi.encode(legalHash, evidenceHash))` — deterministic, doubles as duplicate detection.

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

**Binding** creates a permanent, immutable link between an anchor and a `(token, tokenId)` pair:
- Only possible while the anchor is active and unexpired
- Only the original registrar or `DEFAULT_ADMIN_ROLE` can bind
- Each bound token must expose `IAssetBoundToken`-compatible views
- The token's `anchorRegistry()` must point back to the registry
- The token's `anchorId()` / `anchorIdOf(tokenId)` must match the anchor being bound
- Each `(token, tokenId)` pair can be bound to at most one anchor in a given registry
- `isBound()` returns `true` even after the anchor is deactivated or expired

## Access Control Roles

| Role | Selector constant | Permissions |
|------|-------------------|-------------|
| `DEFAULT_ADMIN_ROLE` | `0x00` | Grant/revoke roles, deactivate anchors, bind any anchor, re-attest any anchor |
| `REGISTRAR_ROLE` | `keccak256("REGISTRAR")` | Register anchors, bind own anchors, re-attest own anchors |

## Consumer Verification

A complete binding verification checks **both sides**:

```solidity
// 1. Registry side — anchor exists and is active
bytes32 anchorId = registry.getAnchor(anchorId).anchorId;
bool active = registry.isActive(anchorId);

// 2. Token side — token declares agreement (if IAssetBoundToken)
address declaredRegistry = IAssetBoundToken(token).anchorRegistry();
require(declaredRegistry == address(registry));

// For whole-contract (ERC-20) binding:
bytes32 tokenAnchor = IAssetBoundToken(token).anchorId();

// For per-token (ERC-721/1155) binding:
bytes32 tokenAnchor = IAssetBoundToken(token).anchorIdOf(tokenId);

require(tokenAnchor == anchorId);
```

The registry enforces these token-side checks at bind time. Consumers SHOULD repeat
the same two-sided check when relying on an existing binding, especially if they
cache registry state off-chain.

## Build & Test

```bash
cd packages/eip-1-asset-registry

# Build
forge build

# Unit + integration tests (61 tests)
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
    bytes32 assetClass;      // e.g. keccak256("EQUITY") — required
    bytes32 jurisdiction;    // e.g. keccak256("US")     — required
    uint64  attestationDate; // Unix timestamp, <= block.timestamp at registration
    uint64  expiresAt;       // Unix timestamp, > attestationDate
    bytes   uri;             // IPFS / HTTPS pointer     — required
    bytes   extensions;      // ABI-encoded key-value pairs, may be empty
}
```

## Companion EIPs

The `anchorId` returned by `registerAnchor` is designed to serve as `subjectId` in:

- **EIP-3** — Document Bundle Anchor
- **EIP-4** — Impact Snapshot Log
- **EIP-5** — NAV Oracle Feed
- **EIP-6** — Compliance Event Log
