// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {BundleAnchorVerifier} from "../src/reference/BundleAnchorVerifier.sol";
import {BundleHashLib} from "../src/libraries/BundleHashLib.sol";

/// @title  ExampleERC721WithDocuments
/// @notice Shows how per-token ERC-721 assets each get their own independent
///         document bundle. Each NFT's EIP-1 anchorId is the subjectId for
///         its EIP-2 document bundles.
///
/// Prerequisites — deploy/register per-token EIP-1 asset anchors first:
///   export ANCHOR_A=<anchorId for property A (NYC Office)>
///   export ANCHOR_B=<anchorId for property B (London Warehouse)>
///
/// Then run this script:
///   forge script script/ExampleERC721WithDocuments.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// What this demonstrates:
///   1. One DocumentBundleAnchor serves all assets in the collection
///   2. Each token's anchorId is an independent subjectId
///   3. Anchoring documents for property A does not affect property B
///   4. BundleAnchorVerifier checks per-asset document compliance
///   5. Superseding property A's bundle does not touch property B's
contract ExampleERC721WithDocuments is Script {
    bytes32 constant ROLE_TITLE_DEED = keccak256("TITLE_DEED");
    bytes32 constant ROLE_SURVEY = keccak256("SURVEY_REPORT");
    bytes32 constant ROLE_COMPLIANCE = keccak256("COMPLIANCE_PACK");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        bytes32 anchorA = vm.envBytes32("ANCHOR_A");
        bytes32 anchorB = vm.envBytes32("ANCHOR_B");

        vm.startBroadcast(deployerKey);

        DocumentBundleAnchor anchor = new DocumentBundleAnchor(deployer);
        BundleAnchorVerifier verifier = new BundleAnchorVerifier(address(anchor));
        console.log("DocumentBundleAnchor:", address(anchor));
        console.log("BundleAnchorVerifier:", address(verifier));

        (, bytes32 compA) = _anchorPropertyA(anchor, anchorA);
        bytes32 titleB = _anchorPropertyB(anchor, anchorB);

        _verifyPerAssetIsolation(verifier, anchorA, anchorB);
        bytes32 compA_v2 = _supersedePropertyA(anchor, compA, anchorA);
        _verifyAfterSupersede(verifier, anchorA, anchorB, titleB, compA, compA_v2);

        vm.stopBroadcast();
    }

    function _anchorPropertyA(DocumentBundleAnchor anchor, bytes32 anchorA)
        internal
        returns (bytes32 titleA, bytes32 compA)
    {
        string[] memory titleADocs = new string[](1);
        titleADocs[0] = "nyc-title-deed-v1.pdf";
        string[] memory compADocs = new string[](6);
        compADocs[0] = "nyc-compliance-opinion-v1.pdf";
        compADocs[1] = "nyc-zoning-report-v1.pdf";
        compADocs[2] = "nyc-insurance-certificate-v1.pdf";
        compADocs[3] = "nyc-environmental-report-v1.pdf";
        compADocs[4] = "nyc-tax-clearance-v1.pdf";
        compADocs[5] = "nyc-regulatory-filing-v1.pdf";

        titleA = _rawPdfBundle(ROLE_TITLE_DEED, titleADocs);
        compA = _rawPdfBundle(ROLE_COMPLIANCE, compADocs);

        anchor.anchorBundle(titleA, anchorA, ROLE_TITLE_DEED, titleADocs.length, "ipfs://QmNYCTitleDeed");
        anchor.anchorBundle(compA, anchorA, ROLE_COMPLIANCE, compADocs.length, "ipfs://QmNYCCompliancePack");
        console.log("Property A (NYC): title deed and compliance pack anchored");
    }

    function _anchorPropertyB(DocumentBundleAnchor anchor, bytes32 anchorB) internal returns (bytes32 titleB) {
        string[] memory titleBDocs = new string[](1);
        titleBDocs[0] = "london-title-deed-v1.pdf";
        string[] memory surveyBDocs = new string[](2);
        surveyBDocs[0] = "london-boundary-survey-v1.pdf";
        surveyBDocs[1] = "london-structural-survey-v1.pdf";

        titleB = _rawPdfBundle(ROLE_TITLE_DEED, titleBDocs);
        bytes32 surveyB = _rawPdfBundle(ROLE_SURVEY, surveyBDocs);

        anchor.anchorBundle(titleB, anchorB, ROLE_TITLE_DEED, titleBDocs.length, "ipfs://QmLondonTitleDeed");
        anchor.anchorBundle(surveyB, anchorB, ROLE_SURVEY, surveyBDocs.length, "ipfs://QmLondonSurvey");
        console.log("Property B (London): title deed and survey anchored");
    }

    function _verifyPerAssetIsolation(BundleAnchorVerifier verifier, bytes32 anchorA, bytes32 anchorB) internal view {
        require(verifier.hasActiveBundle(anchorA, ROLE_TITLE_DEED), "A: title deed missing");
        require(verifier.hasActiveBundle(anchorA, ROLE_COMPLIANCE), "A: compliance pack missing");
        require(verifier.hasActiveBundle(anchorB, ROLE_TITLE_DEED), "B: title deed missing");
        require(verifier.hasActiveBundle(anchorB, ROLE_SURVEY), "B: survey missing");
        require(!verifier.hasActiveBundle(anchorA, ROLE_SURVEY), "A should not have survey");
        require(!verifier.hasActiveBundle(anchorB, ROLE_COMPLIANCE), "B should not have compliance");
        console.log("Per-asset document isolation confirmed.");
    }

    function _supersedePropertyA(DocumentBundleAnchor anchor, bytes32 compA, bytes32 anchorA)
        internal
        returns (bytes32 compA_v2)
    {
        string[] memory compAV2Docs = new string[](7);
        compAV2Docs[0] = "nyc-compliance-opinion-v2.pdf";
        compAV2Docs[1] = "nyc-zoning-report-v2.pdf";
        compAV2Docs[2] = "nyc-insurance-certificate-v2.pdf";
        compAV2Docs[3] = "nyc-environmental-report-v2.pdf";
        compAV2Docs[4] = "nyc-tax-clearance-v2.pdf";
        compAV2Docs[5] = "nyc-regulatory-filing-v2.pdf";
        compAV2Docs[6] = "nyc-board-approval-v2.pdf";
        compA_v2 = _rawPdfBundle(ROLE_COMPLIANCE, compAV2Docs);
        anchor.supersedeBundle(
            compA, compA_v2, anchorA, ROLE_COMPLIANCE, compAV2Docs.length, "ipfs://QmNYCCompliancePackV2"
        );
        console.log("Property A compliance pack superseded with v2.");
    }

    function _verifyAfterSupersede(
        BundleAnchorVerifier verifier,
        bytes32 anchorA,
        bytes32 anchorB,
        bytes32 titleB,
        bytes32 compA,
        bytes32 compA_v2
    ) internal view {
        require(verifier.hasActiveBundle(anchorB, ROLE_TITLE_DEED), "B: title deed must still be active");
        require(verifier.hasActiveBundle(anchorB, ROLE_SURVEY), "B: survey must still be active");
        require(verifier.isBundleCurrent(titleB, anchorB, ROLE_TITLE_DEED), "B: title deed must still be current");
        console.log("Property B documents unaffected by property A supersession.");

        require(verifier.isBundleCurrent(compA_v2, anchorA, ROLE_COMPLIANCE), "A v2 must be current");
        require(!verifier.isBundleCurrent(compA, anchorA, ROLE_COMPLIANCE), "A v1 must not be current");
        console.log("Property A compliance pack updated to v2.");
    }

    function _rawPdfBundle(bytes32 role, string[] memory canonicalFilenames) internal pure returns (bytes32) {
        require(canonicalFilenames.length > 0, "ExampleERC721WithDocuments: empty bundle");

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
