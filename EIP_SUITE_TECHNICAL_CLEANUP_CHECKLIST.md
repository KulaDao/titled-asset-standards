# EIP Suite Technical Cleanup Checklist

Audit source: `origin/main` at `0a18ece`.

This checklist tracks the remaining implementation and documentation cleanup after the EIP-1 through EIP-6 review pass. The goal is to close interface/reference drift, remove ambiguity before EIP submission, and make the technical implementations match the strengthened whitepaper language.

## Status Legend

- `[ ]` Not started
- `[~]` In progress
- `[x]` Complete
- `[?]` Needs product/legal decision before implementation

## Recommended Order

1. EIP-1 binding model fixes (complete)
2. Cross-suite zero-value policy (complete)
3. EIP-2 canonical hash hardening (complete)
4. EIP-3 evidence semantics (complete)
5. EIP-4 payload/evidence semantics (complete)
6. EIP-5 attestation/methodology polish (complete)
7. EIP-6 methodology/currency guidance (complete)
8. Root README and per-package limits pass
9. Medusa non-triviality assertions
10. Full verification run

---

## Cross-Suite Cleanup

### Zero-Value Policy

- [x] Decide suite-wide whether `bytes32(0)` means "not provided" or is invalid for evidence/methodology/hash fields.
- [x] Apply the policy consistently across:
  - EIP-3 route permission/revocation evidence hashes
  - EIP-4 compliance event evidence hashes
  - EIP-5 attestation evidence hashes
  - EIP-6 methodology hashes
- [x] Add tests for accepted/rejected zero values in each affected package.
- [x] Document the policy in every package README.

Acceptance criteria:

- A reviewer can tell from the interface/README whether zero hashes are valid.
- Code and tests match that policy.
- No package silently accepts zero values where the docs imply required evidence.

Implementation notes:

- Required evidence and methodology hash fields are invalid when `bytes32(0)`.
- EIP-3 rejects zero permission, revocation, graceful revocation, and cancellation evidence hashes.
- EIP-4 rejects zero compliance event evidence hashes.
- EIP-5 rejects zero attestation evidence hashes and already rejected zero methodology hashes.
- EIP-6 rejects zero methodology hashes.
- Evidence and methodology URI fields remain optional pointers unless a package-specific rule says otherwise.

### Interface / Reference Drift

- [ ] For each required behavior implemented only in a reference contract, either move it into the public interface or explicitly mark it as reference-only.
- [ ] Audit all package READMEs for "MUST" language that is not represented in interfaces or tests.
- [ ] Add or update NatSpec for every non-obvious invariant.

Acceptance criteria:

- If a behavior is normative, it appears in the interface, extension interface, or required behavior section.
- Reference-only choices are described as deployment choices, not standard requirements.

### ERC-165 Posture

- [ ] Standardize wording: ERC-165 is either required or recommended per package.
- [ ] Confirm every reference implementation supports the claimed interface IDs.
- [ ] Confirm tests cover positive and negative ERC-165 paths.
- [ ] Add token-interface ERC-165 support where package docs rely on token interface detection.

Acceptance criteria:

- No package says consumers can detect an interface unless ERC-165 or an equivalent mechanism is implemented and tested.

### Event Completeness

- [ ] Check each append-only log/oracle event for fields indexers need without storage calls.
- [ ] Add missing critical fields where appropriate:
  - Methodology hash / URI references
  - Correction references
  - Subject/currency/role keys
  - Provider/reporter/actor identity
- [ ] Avoid adding large dynamic data to events unless clearly needed.

Acceptance criteria:

- Off-chain indexers can reconstruct timelines without excessive storage calls for core identifiers.

### Known Limits Sections

- [ ] Add a short "Known Limits" section to each package README.
- [ ] Cover:
  - No legal truth guarantee
  - No global uniqueness across registries/chains
  - No off-chain document availability guarantee
  - No credentialing of reporters/providers/attestors unless implemented
  - No fraud prevention, only tamper-evident records

Acceptance criteria:

- Each README states what the package does not prove.

---

## EIP-1: Asset-Bound Token Registry

Package: `packages/eip-1-asset-registry`

Primary status: resolved in the local cleanup branch.

### Binding Mode Ambiguity

- [x] Remove `tokenId = 0` as the whole-contract sentinel.
- [x] Add explicit binding scope/mode, for example:
  - `BINDING_SCOPE_CONTRACT`
  - `BINDING_SCOPE_TOKEN_ID`
- [x] Include scope in:
  - `AnchorRecord`
  - `bindToken` / replacement binding functions
  - reverse binding key
  - `TokenBound` event
  - tests
- [x] Confirm ERC-721/1155 token ID `0` can be bound as a token-specific binding.

Implementation notes:

- Added `AssetRegistryConstants` with canonical binding scope IDs.
- Reverse uniqueness now keys by `(token, bindingScope, tokenId)`.
- Added unit and invariant coverage for token-ID `0` vs whole-contract scope.

Acceptance criteria:

- Whole-contract binding and token ID `0` binding are distinguishable.
- Reverse uniqueness includes binding scope.

### Token Interface Split

- [x] Split mixed token interface into whole-contract and per-token interfaces, or define exact unused-mode behavior.
- [x] Suggested split:
  - `IAssetBoundToken` for whole-contract anchors
  - `IAssetBoundTokenId` for token ID anchors
- [x] Add ERC-165 interface IDs for both if detection is expected.
- [x] Update examples/tests.

Implementation notes:

- `IAssetBoundToken` and `IAssetBoundTokenId` now extend `IERC165`.
- Removed the mixed `anchorId()` / `anchorIdOf()` requirement from a single token interface.

Acceptance criteria:

- ERC-20-style tokens are not forced to implement `anchorIdOf`.
- ERC-721/1155-style tokens are not forced to implement a misleading `anchorId`.

### Registry Interface Completeness

- [x] Move reference-only `getMetadata`, `isActive`, `reattest`, and `deactivate` behavior into an interface or extension interface.
- [x] Add `registeredBy` / owner semantics to the formal interface if authorization depends on it.
- [x] Ensure expiry fields are exposed through interface-level getters.

Implementation notes:

- Added `IAssetAnchorRegistryLifecycle` for metadata, active status, registrar lookup, deactivation, and re-attestation.
- Reference registry now supports ERC-165 for both the core and lifecycle interfaces.

Acceptance criteria:

- A third-party implementer can reproduce the active-anchor and re-attestation model from interfaces alone.

### Metadata / Expiry Consistency

- [x] Align README and code on expiry boundary: `block.timestamp >= expiresAt` or `block.timestamp > expiresAt`.
- [x] Standardize `assetClass` and `jurisdiction` encoding.
- [x] Replace inconsistent examples using `keccak256("EQUITY")` vs `bytes32("EQUITY")`.

Implementation notes:

- Reference expiry is inclusive: active while `block.timestamp <= expiresAt`, expired when `block.timestamp > expiresAt`.
- README and tests now use domain-separated metadata IDs such as `keccak256("EIP-XXXX:ASSET_CLASS:EQUITY")`.

Acceptance criteria:

- Tests and docs use the same encoding and expiry boundary.

---

## EIP-2: Canonical Document Bundle Anchor

Package: `packages/eip-2-document-bundle`

Primary status: mostly resolved, but canonicalization can still be misused.

### Canonical Hash Path

- [x] Decide whether `computeBundleHash()` should sort internally or reject unsorted entries.
- [x] If keeping a pre-sorted API, add `computeCanonicalBundleHash()` or `requireSorted`.
- [x] Add tests proving unsorted input cannot accidentally be treated as canonical.

Acceptance criteria:

- There is one obvious safe path for computing canonical bundle hashes.

Implementation notes:

- `computeCanonicalBundleHash()` is the recommended safe path and sorts before hashing.
- `computeBundleHash()` remains available for pre-sorted entries but rejects unsorted input.

### Subject / URI Validation

- [x] Decide whether `bytes32(0)` subject is allowed.
- [x] If allowed, document it clearly as standalone mode and explain collision risk.
- [x] Not applicable: zero subject remains allowed, so no rejection was added to `anchorBundle` or `supersedeBundle`.
- [x] Decide whether empty `metadataURI` is allowed.
- [x] Add tests for the chosen behavior.

Acceptance criteria:

- Standalone anchoring behavior is explicit.
- Empty metadata URI behavior is explicit.

Implementation notes:

- `bytes32(0)` subject is allowed as standalone mode.
- Empty `metadataURI` is allowed and means no on-chain retrieval pointer is supplied.

### Schema Constant

- [x] Keep `EIP-XXXX:BUNDLE:V1` only if the README clearly marks it as pre-assignment.
- [x] Add a single pre-deployment checklist item to update all constants after EIP number assignment.

Acceptance criteria:

- No one can miss that constants are provisional.

---

## EIP-3: Directional Transfer Domain Registry

Package: `packages/eip-3-transfer-domain`

Primary status: resolved.

### Evidence Hash Semantics

- [x] Define whether zero evidence hash is valid.
- [x] Either reject zero `permissionEvidenceHash` / `revocationEvidenceHash`, or document zero as "no evidence supplied."
- [x] Add tests for both immediate and graceful revocation paths.

Acceptance criteria:

- Zero evidence hash behavior is explicit and tested.

### Revocation Evidence Retrieval

- [x] Decide whether immediate `revocationEvidenceHash` must be readable on-chain after revocation.
- [x] If yes, add it to `Route` or a separate revocation record.
- [x] Not applicable: immediate revocation evidence is readable on-chain from `Route`.

Acceptance criteria:

- Docs no longer imply all revocation evidence is independently readable from route state unless it actually is.

Implementation notes:

- `Route` now includes `revocationEvidenceHash`.
- Immediate revocation stores revocation evidence directly on the route.
- Graceful revocation keeps pending evidence in `getRevocation()` and exposes it through `getRoute()` once the grace period has expired.
- Re-enabling a route clears prior route-level revocation evidence.

### Revert Wording

- [x] Update `revokeRoute()` NatSpec to qualify "MUST NOT revert" for authorized callers.
- [x] Confirm tests still cover nonexistent/already revoked routes.

Acceptance criteria:

- Interface wording does not imply unauthorized callers can revoke without revert.

---

## EIP-4: Subject-Linked Compliance Event Log

Package: `packages/eip-4-compliance-event`

Primary status: resolved.

### Evidence Hash Semantics

- [x] Define whether `evidenceHash == bytes32(0)` is valid.
- [x] Either reject zero evidence hashes or document zero as "no evidence provided."
- [x] Add tests for chosen behavior.

Acceptance criteria:

- Compliance records do not silently look documented when evidence is absent.

### Payload Profile Semantics

- [x] Define schemas for base payload profiles in README and/or constants docs.
- [x] State that unknown payload profiles MUST be treated as opaque bytes.
- [x] If the reference implementation does not validate payload/profile compatibility, document that validation is application-level.

Acceptance criteria:

- Consumers know how to decode standard payload profiles and how to handle unknown ones.

Implementation notes:

- README and `ComplianceConstants.sol` define base payload ABI encodings.
- Unknown payload profile IDs are accepted and stored as opaque bytes.
- The reference implementation validates only payload size, not profile compatibility.

### Event Type / Outcome Matrix

- [x] Decide whether the reference implementation should validate event type / outcome combinations.
- [x] Not applicable: the reference implementation intentionally does not validate event type / outcome combinations.
- [x] If no, document that combinations are not constrained by the reference implementation.

Acceptance criteria:

- Reviewers do not mistake unconstrained `bytes32` fields for validated compliance semantics.

Implementation notes:

- Event type / outcome matrix validation is application-layer policy.
- Tests assert that an unconstrained combination is accepted and stored.

### Correction Current-State Guidance

- [x] Add package README guidance for resolving corrected/current event state.
- [x] Consider adding a helper getter if current-state lookup is expected on-chain.

Acceptance criteria:

- Consumers know that `EVT_CORRECTION` indexing alone does not provide a current-state resolver.

Implementation notes:

- Added `currentEventIndex(subjectId, eventIndex)` to resolve terminal correction-chain state.
- Added `isEventCurrent(subjectId, eventIndex)` to check whether an event has not been corrected.
- README warns that `latestEventByType()` is type-indexing only, not current-state resolution.

---

## EIP-5: Subject-Linked Impact Snapshot Log

Package: `packages/eip-5-impact-snapshot`

Primary status: resolved.

### Attestation Evidence Semantics

- [x] Define whether `evidenceHash == bytes32(0)` / empty `evidenceURI` is valid.
- [x] Either reject zero/empty attestation evidence or document it as an unsupported/no-evidence attestation.
- [x] Add tests.

Acceptance criteria:

- Attestations cannot imply evidence exists when none is provided.

### Methodology Supersession Discoverability

- [x] Add `newMethodologyURI` to `MethodologySuperseded`, or add a getter for pending methodology details.
- [x] Document how consumers discover pending methodology URI before activation.
- [x] Add tests.

Acceptance criteria:

- Methodology URI is discoverable for both active and pending methodologies.

Implementation notes:

- Added `pendingMethodology(subjectId, indicatorId)` to expose scheduled future methodology hash, URI, and effective ordinal.
- `activeMethodology()` remains the source for currently effective methodology details.
- Unit tests cover pending URI/hash visibility before activation and cleared pending state after activation.

### README Warnings

- [x] Add warnings for privacy, double-counting/overlapping claims, and methodology URI/document availability.
- [x] Clarify "independent attestor" language: same reporter address is blocked, but credential independence is application-level.
- [x] Document custom indicator and unit naming rules.
- [x] Define overlapping period semantics.

Acceptance criteria:

- README no longer overstates what attestation/indicator semantics prove.

Implementation notes:

- README now calls attestation role-gated rather than intrinsically independent.
- README documents overlapping periods as allowed and exact duplicate originals as rejected.
- README adds custom indicator, canonical unit, privacy, double-counting, and document availability guidance.

### Medusa Non-Triviality

- [x] Add harness counters or invariants proving successful snapshots, corrections, and attestations happen.
- [x] Avoid silent no-op fuzz paths where all actions revert and invariants pass trivially.

Acceptance criteria:

- Fuzz success cannot be explained by swallowed reverts alone.

Implementation notes:

- Medusa harness seeds one original snapshot, one correction, and one attestation in the constructor.
- Added success counters and `property_nonTrivialActionsSucceeded()` so all-revert fuzz paths cannot satisfy the suite silently.

---

## EIP-6: Subject-Linked NAV Snapshot Oracle

Package: `packages/eip-6-nav-oracle`

Primary status: resolved.

### Methodology Validation

- [x] Require `methodologyHash != bytes32(0)`.
- [x] Require non-empty `methodologyURI`, or document empty URI semantics.
- [x] Add unit tests for both.

Acceptance criteria:

- NAV snapshots cannot become methodology-free unless explicitly allowed.

### ERC-4626 Integration Guidance

- [x] Add README warning that `latestNAVStatus()` may revert when unconfigured.
- [x] Recommend adapter/cached-value patterns for ERC-4626 `convertToAssets()` / `convertToShares()` if relevant.

Acceptance criteria:

- Vault integrators do not accidentally violate ERC-4626 expectations with a reverting oracle call.

Implementation notes:

- README warns that `latestNAVStatus()` and `aggregatedNAV()` revert until staleness config is set.
- README recommends adapters, cached accepted NAV values, and state-changing pricing paths instead of direct unconfigured oracle calls from ERC-4626 conversion functions.

### Methodology Hash Derivation

- [x] Document whether `methodologyHash` is raw bytes, document bundle hash, or implementation-defined.
- [x] If EIP-2 document bundles are recommended, add example derivation.

Acceptance criteria:

- Consumers can reproduce or verify methodology hashes.

Implementation notes:

- README documents the reference implementation as storage-only for methodology fields.
- Recommended derivations are `keccak256(methodologyDocumentBytes)` or an EIP-2 canonical document bundle hash.
- README documents what `methodologyURI` should resolve to for each derivation path.

### Currency Encoding

- [x] Add custom/token currency derivation guidance.
- [x] Example: `keccak256(abi.encodePacked("EIP-XXXX:CURRENCY:TOKEN", chainId, tokenAddress))`.
- [x] Add tests or constants if needed.

Acceptance criteria:

- Non-fiat NAV denominations are supported without ad hoc identifiers.

Implementation notes:

- Added `deriveTokenCurrency(chainId, tokenAddress)` to `NAVConstants.sol`.
- Added a unit test for the exact token currency domain string.
- README documents fiat, token, and other custom denomination conventions.

---

## Root README / Suite-Level Docs

- [ ] Remove or qualify broad claims around legal compliance, regulatory acceptance, "canonical" status, and proof of real-world truth.
- [ ] Make package numbering and descriptions consistent.
- [ ] Link each package to its Known Limits section.
- [ ] Add a "Pre-Submission Checklist" covering:
  - Replace `EIP-XXXX`
  - Confirm prior-art statuses
  - Confirm reference implementation repo links
  - Confirm test vectors where required
  - Confirm Slither/Medusa availability in CI

Acceptance criteria:

- The root README markets the suite without overclaiming what the standards prove.

---

## Verification Plan

Run per package after each package-specific patch:

```bash
cd /private/tmp/kula-eip-suite-audit-main/packages/<package>
/Users/reagansimpson/.foundry/bin/forge fmt --check
/Users/reagansimpson/.foundry/bin/forge build --sizes
/Users/reagansimpson/.foundry/bin/forge test -vvv
```

Run from repo root after all patches:

```bash
cd /private/tmp/kula-eip-suite-audit-main
git diff --check
git status --short
```

If available locally or in CI:

```bash
slither .
medusa fuzz
```

## PR Strategy

Recommended PR split:

1. `fix(eip-1): clarify binding scope and token interfaces`
2. `fix(eip-2): harden canonical bundle hashing`
3. `fix(eip-3): clarify evidence semantics`
4. `fix(eip-4): define evidence and payload semantics`
5. `fix(eip-5): improve attestation and methodology discoverability`
6. `fix(eip-6): require methodology metadata and document integrations`
7. `docs: align root README and known limits`

If time is tight, combine 2 through 6 into one technical cleanup PR, but keep EIP-1 separate because it changes the core interface shape.
