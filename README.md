# kula-eip-suite

Reference implementations, interfaces, and test suites for six standalone EIP specifications developed by Kula Protocol. Each EIP addresses an unoccupied gap in the EVM standards landscape for tokenized asset infrastructure.

## Packages

| Package | EIP | Status |
|---|---|---|
| `packages/eip-1-asset-registry` | Asset-Bound Token Registry | Spec in review |
| `packages/eip-2-transfer-domain` | Directional Transfer Domain Registry | Spec reviewed (Reagan) |
| `packages/eip-3-document-bundle` | Canonical Document Bundle Anchor | Spec reviewed (Reagan) |
| `packages/eip-4-impact-snapshot` | Subject-Linked Impact Snapshot Log | Spec reviewed (Reagan) |
| `packages/eip-5-nav-oracle` | On-Chain NAV Oracle Interface | Spec complete |
| `packages/eip-6-compliance-event` | On-Chain Compliance Event Schema | Spec complete |

Each package is a self-contained Foundry project with its own interfaces, reference implementation, and tests. No package depends on another. The EIPs are designed to compose but can be adopted independently.

## Architecture

Each package follows the same structure:

```
packages/eip-N-name/
  src/
    interfaces/       # Solidity interfaces (the standard)
    reference/        # Reference implementation
    libraries/        # Shared libraries (hash derivation, constants)
  test/               # Foundry tests
  foundry.toml
  README.md           # Package-specific docs linking to the EIP spec
```

## Building

```sh
cd packages/eip-3-document-bundle
forge build
forge test
```

## Standards Submission

Each EIP will be submitted independently to Ethereum Magicians and the EIPs repo. The specs (in docx and markdown) are maintained in the `specs/` folder at the repo root.

```
specs/
  EIP2_DirectionalTransferDomainRegistry_Spec.docx
  EIP3_CanonicalDocumentBundleAnchor_Spec.docx
  EIP4_SubjectLinkedImpactSnapshotLog_Spec.docx
  EIP5_OnChainNAVOracleInterface_Spec.docx
  EIP6_OnChainComplianceEventSchema_Spec.docx
  EIP6_TravelRuleComplianceInterface_Spec.docx
```

## License

- **Interfaces**: CC0-1.0 (public domain, as required for ERC submission)
- **Reference implementations**: MIT
