# eip-3-transfer-domain

Reference implementation for **EIP-3: Directional Transfer Domain Registry**.

This package implements a token-agnostic registry for answering one narrow
question:

> Is a route from `sourceDomain` to `destinationDomain` permitted for
> `assetClass`?

Domains and asset classes are opaque `bytes32` identifiers. The registry does
not define what a domain means, how asset classes are derived, or how a token
must enforce route status. It is a lookup layer that can be consumed by ERC-20,
ERC-721, ERC-1155, ERC-3643, ERC-7943, or application-specific transfer logic.

## Contracts

### Interfaces

- `ITransferDomainRegistry`
  - core route registry interface
  - `setRoute()` only enables routes
  - `revokeRoute()` is the only core disable path
  - `getRoute()` exposes route state
  - `isRoutePermittedBatch()` provides batch lookups

- `IGracefulRouteRevocation`
  - optional extension for delayed revocation
  - exposes pending/finalized revocation state
  - supports cancellation before the grace period expires
  - lazy expiry means a route is functionally revoked once
    `block.timestamp >= effectiveAt`, even before finalization

### Reference Implementations

- `TransferDomainRegistry`
  - immediate route set/revoke registry
  - role-based registrar access through OpenZeppelin `AccessControl`
  - ERC-165 support for `ITransferDomainRegistry`

- `GracefulTransferDomainRegistry`
  - extends `TransferDomainRegistry`
  - adds a fixed deployment-time `gracePeriod`
  - keeps `revokeRoute()` available for immediate revocation
  - implements lazy graceful revocation and duplicate-finalization protection
  - ERC-165 support for both interfaces

### Libraries

- `TransferRouteLib`
  - canonical route key derivation:
    `keccak256(abi.encodePacked(sourceDomain, destinationDomain, assetClass))`

## Build

```sh
forge build
forge test -vvv
```

## Analysis

```sh
slither . --config-file slither.config.json
medusa fuzz
```

The Medusa harness checks that route queries, lazy graceful revocation, stored
revocation state, and batch results remain consistent with an independent model
across randomized route lifecycle calls.

## Security Notes

- The registry is advisory. It does not enforce transfers by itself.
- `isRoutePermitted()` intentionally does not check balances, identity,
  sanctions, freezes, settlement state, or token-specific rules.
- Consumers that require enforcement must query the registry and execute the
  transfer atomically in the same transaction.
- Evidence hashes are stored/emitted but not validated on-chain.
- Registrar authorization is implementation policy; this reference uses
  `REGISTRAR_ROLE`.
