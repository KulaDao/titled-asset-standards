# eip-3-document-bundle

Reference implementation for EIP-XXXX: Canonical Document Bundle Anchor.

Provides:
- `IDocumentBundleAnchor` — the on-chain anchoring interface (CC0-1.0)
- `BundleHashLib` — pure library for deterministic bundle hash derivation (MIT)
- `DocumentBundleAnchor` — AccessControl-based reference implementation (MIT)

## Build & Test

```bash
forge build
forge test
```

Spec: `../../specs/EIP3_CanonicalDocumentBundleAnchor_Spec.docx`
