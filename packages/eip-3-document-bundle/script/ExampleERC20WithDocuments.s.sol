// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {BundleAnchorVerifier}  from "../src/reference/BundleAnchorVerifier.sol";
import {IDocumentBundleAnchor} from "../src/interfaces/IDocumentBundleAnchor.sol";

/// @notice Minimal EIP-1 registry interface — only what this script needs.
interface IAssetRegistry {
    function isActive(bytes32 anchorId) external view returns (bool);
}

/// @title  ExampleERC20WithDocuments
/// @notice Shows how compliance document bundles are anchored against an
///         ERC-20 asset-bound token using EIP-1 + EIP-2 together.
///
/// Prerequisites — run ExampleERC20Lifecycle.s.sol first (EIP-1 package):
///   export REGISTRY_ADDRESS=<deployed AssetAnchorRegistry address>
///   export ASSET_ANCHOR_ID=<anchorId returned by registerAnchor>
///
/// Then run this script:
///   forge script script/ExampleERC20WithDocuments.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// What this demonstrates:
///   1. Deploy DocumentBundleAnchor (EIP-2)
///   2. Grant ANCHOR_ROLE to compliance officer
///   3. Anchor a LEGAL_BASIS document bundle linked to the ERC-20 asset
///   4. Anchor a DUE_DILIGENCE document bundle for the same asset
///   5. Deploy BundleAnchorVerifier and use it as a compliance pre-check
///   6. Show that the verifier can check both document types are present
///   7. Show that anchor deactivation (EIP-1) still reflects correctly
///      — the asset and its documents are linked by the shared subjectId
contract ExampleERC20WithDocuments is Script {
    // EIP-1 role constants — same derivation as in AssetAnchorRegistry
    bytes32 constant ROLE_LEGAL_BASIS  = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_DUE_DILIGENCE = keccak256("DUE_DILIGENCE");

    function run() external {
        uint256 deployerKey    = vm.envUint("PRIVATE_KEY");
        address deployer       = vm.addr(deployerKey);
        address registry       = vm.envAddress("REGISTRY_ADDRESS");
        bytes32 assetAnchorId  = vm.envBytes32("ASSET_ANCHOR_ID");
        address compliance     = vm.envOr("COMPLIANCE_OFFICER", deployer);

        // Simulate two document bundles (hash of their content fingerprints)
        bytes32 legalBundle = keccak256(abi.encode("legal-basis-bundle-v1", assetAnchorId));
        bytes32 ddBundle    = keccak256(abi.encode("due-diligence-bundle-v1", assetAnchorId));

        vm.startBroadcast(deployerKey);

        // 1. Deploy EIP-2 DocumentBundleAnchor
        DocumentBundleAnchor anchor = new DocumentBundleAnchor(deployer);
        console.log("DocumentBundleAnchor:", address(anchor));

        // 2. Grant ANCHOR_ROLE to compliance officer
        if (compliance != deployer) {
            bytes32 anchorRole = anchor.ANCHOR_ROLE();
            anchor.grantRole(anchorRole, compliance);
            console.log("ANCHOR_ROLE granted to compliance officer");
        }

        // 3. Anchor legal basis documents (subjectId = EIP-1 assetAnchorId)
        anchor.anchorBundle(
            legalBundle,
            assetAnchorId,      // links this bundle to the EIP-1 asset
            ROLE_LEGAL_BASIS,
            3,                  // 3 documents: title deed, legal opinion, prospectus
            "ipfs://QmLegalBasisV1"
        );
        console.log("Legal basis bundle anchored:");
        console.logBytes32(legalBundle);

        // 4. Anchor due diligence documents
        anchor.anchorBundle(
            ddBundle,
            assetAnchorId,
            ROLE_DUE_DILIGENCE,
            5,                  // 5 documents: valuation, audit, KYC, AML, risk assessment
            "ipfs://QmDueDiligenceV1"
        );
        console.log("Due diligence bundle anchored:");
        console.logBytes32(ddBundle);

        // 5. Deploy BundleAnchorVerifier for downstream compliance checks
        BundleAnchorVerifier verifier = new BundleAnchorVerifier(address(anchor));
        console.log("BundleAnchorVerifier:", address(verifier));

        // 6. Verify both document types are present for the asset
        bytes32[] memory requiredRoles = new bytes32[](2);
        requiredRoles[0] = ROLE_LEGAL_BASIS;
        requiredRoles[1] = ROLE_DUE_DILIGENCE;

        bool allDocsPresent = verifier.hasActiveBundlesForAllRoles(assetAnchorId, requiredRoles);
        require(allDocsPresent, "Both document bundles must be active");
        console.log("All required document bundles confirmed active.");

        // 7. Show the asset anchor status from EIP-1 still applies
        bool assetActive = IAssetRegistry(registry).isActive(assetAnchorId);
        console.log("EIP-1 asset anchor active:", assetActive);

        vm.stopBroadcast();

        console.log("");
        console.log("== Integration summary ==");
        console.log("EIP-1 asset anchorId doubles as the EIP-2 subjectId.");
        console.log("The verifier can be used by downstream contracts as:");
        console.log("  verifier.requireActiveBundle(assetAnchorId, ROLE_LEGAL_BASIS)");
        console.log("  verifier.requireActiveBundlesForAllRoles(assetAnchorId, roles)");
    }
}
