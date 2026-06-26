// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {BundleAnchorVerifier} from "../src/reference/BundleAnchorVerifier.sol";
import {BundleHashLib} from "../src/libraries/BundleHashLib.sol";

/// @notice Minimal asset registry interface — only what this script needs.
interface IAssetRegistry {
    function isActive(bytes32 anchorId) external view returns (bool);
}

/// @title  ExampleERC20WithDocuments
/// @notice Shows how compliance document bundles are anchored against an
///         ERC-20 asset-bound token using the asset registry and document bundle anchor together.
///
/// Prerequisites — deploy/register an asset anchor in `erc-asset-registry` first:
///   export REGISTRY_ADDRESS=<deployed AssetAnchorRegistry address>
///   export ASSET_ANCHOR_ID=<anchorId returned by registerAnchor>
///   export COMPLIANCE_PRIVATE_KEY=<optional key that should anchor documents>
///
/// Then run this script:
///   forge script script/ExampleERC20WithDocuments.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// What this demonstrates:
///   1. Deploy DocumentBundleAnchor (`erc-document-bundle-anchor`)
///   2. Grant ANCHOR_ROLE to compliance officer
///   3. Anchor a LEGAL_BASIS document bundle linked to the ERC-20 asset
///   4. Anchor a DUE_DILIGENCE document bundle for the same asset
///   5. Deploy BundleAnchorVerifier and use it as a compliance pre-check
///   6. Show that the verifier can check both document types are present
///   7. Show that anchor deactivation in the asset registry still reflects correctly
///      — the asset and its documents are linked by the shared subjectId
contract ExampleERC20WithDocuments is Script {
    // Asset registry role constants — same derivation as in AssetAnchorRegistry
    bytes32 constant ROLE_LEGAL_BASIS = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_DUE_DILIGENCE = keccak256("DUE_DILIGENCE");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address registry = vm.envAddress("REGISTRY_ADDRESS");
        bytes32 assetAnchorId = vm.envBytes32("ASSET_ANCHOR_ID");
        uint256 complianceKey = vm.envOr("COMPLIANCE_PRIVATE_KEY", deployerKey);
        address compliance = vm.addr(complianceKey);

        require(IAssetRegistry(registry).isActive(assetAnchorId), "ExampleERC20WithDocuments: asset anchor inactive");

        // Demo bundle hashes still use placeholder document bytes, but the
        // manifest shape, fields, sorting, and schema prefix are document-bundle canonical.
        string[] memory legalDocs = new string[](3);
        legalDocs[0] = "title-deed-v1.pdf";
        legalDocs[1] = "legal-opinion-v1.pdf";
        legalDocs[2] = "prospectus-v1.pdf";

        string[] memory dueDiligenceDocs = new string[](5);
        dueDiligenceDocs[0] = "valuation-v1.pdf";
        dueDiligenceDocs[1] = "audit-v1.pdf";
        dueDiligenceDocs[2] = "kyc-summary-v1.pdf";
        dueDiligenceDocs[3] = "aml-summary-v1.pdf";
        dueDiligenceDocs[4] = "risk-assessment-v1.pdf";

        bytes32 legalBundle = _rawPdfBundle(ROLE_LEGAL_BASIS, legalDocs);
        bytes32 ddBundle = _rawPdfBundle(ROLE_DUE_DILIGENCE, dueDiligenceDocs);

        vm.startBroadcast(deployerKey);

        // 1. Deploy DocumentBundleAnchor
        DocumentBundleAnchor anchor = new DocumentBundleAnchor(deployer);
        console.log("DocumentBundleAnchor:", address(anchor));

        // 2. Grant ANCHOR_ROLE to compliance officer
        if (compliance != deployer) {
            bytes32 anchorRole = anchor.ANCHOR_ROLE();
            anchor.grantRole(anchorRole, compliance);
            console.log("ANCHOR_ROLE granted to compliance officer");
        }

        vm.stopBroadcast();

        // 3. Anchor legal basis documents (subjectId = asset anchorId)
        vm.startBroadcast(complianceKey);
        anchor.anchorBundle(
            legalBundle,
            assetAnchorId, // links this bundle to the asset registry anchor
            ROLE_LEGAL_BASIS,
            3, // 3 documents: title deed, legal opinion, prospectus
            "ipfs://QmLegalBasisV1"
        );
        console.log("Legal basis bundle anchored:");
        console.logBytes32(legalBundle);

        // 4. Anchor due diligence documents
        anchor.anchorBundle(
            ddBundle,
            assetAnchorId,
            ROLE_DUE_DILIGENCE,
            5, // 5 documents: valuation, audit, KYC, AML, risk assessment
            "ipfs://QmDueDiligenceV1"
        );
        console.log("Due diligence bundle anchored:");
        console.logBytes32(ddBundle);
        vm.stopBroadcast();

        // 5. Deploy BundleAnchorVerifier for downstream compliance checks
        vm.startBroadcast(deployerKey);
        BundleAnchorVerifier verifier = new BundleAnchorVerifier(address(anchor));
        console.log("BundleAnchorVerifier:", address(verifier));

        // 6. Verify both document types are present for the asset
        bytes32[] memory requiredRoles = new bytes32[](2);
        requiredRoles[0] = ROLE_LEGAL_BASIS;
        requiredRoles[1] = ROLE_DUE_DILIGENCE;

        bool allDocsPresent = verifier.hasActiveBundlesForAllRoles(assetAnchorId, requiredRoles);
        require(allDocsPresent, "Both document bundles must be active");
        console.log("All required document bundles confirmed active.");

        // 7. Show the asset anchor status from the asset registry still applies
        bool assetActive = IAssetRegistry(registry).isActive(assetAnchorId);
        console.log("Asset registry anchor active:", assetActive);

        vm.stopBroadcast();

        console.log("");
        console.log("== Integration summary ==");
        console.log("Asset registry anchorId doubles as the document bundle subjectId.");
        console.log("The verifier can be used by downstream contracts as:");
        console.log("  verifier.requireActiveBundle(assetAnchorId, ROLE_LEGAL_BASIS)");
        console.log("  verifier.requireActiveBundlesForAllRoles(assetAnchorId, roles)");
    }

    function _rawPdfBundle(bytes32 role, string[] memory canonicalFilenames) internal pure returns (bytes32) {
        require(canonicalFilenames.length > 0, "ExampleERC20WithDocuments: empty bundle");

        BundleHashLib.DocumentEntry[] memory entries = new BundleHashLib.DocumentEntry[](canonicalFilenames.length);

        for (uint256 i = 0; i < canonicalFilenames.length; i++) {
            bytes memory nameBytes = bytes(canonicalFilenames[i]);
            entries[i] = BundleHashLib.DocumentEntry({
                contentHash: keccak256(nameBytes),
                role: role,
                mimeTypeHash: keccak256("application/pdf"),
                filenameHash: keccak256(nameBytes),
                normProfileId: BundleHashLib.PROFILE_RAW
            });
        }

        return BundleHashLib.computeCanonicalBundleHash(entries);
    }
}
