// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {BundleAnchorVerifier}  from "../src/reference/BundleAnchorVerifier.sol";

/// @title  ExampleERC721WithDocuments
/// @notice Shows how per-token ERC-721 assets each get their own independent
///         document bundle. Each NFT's EIP-1 anchorId is the subjectId for
///         its EIP-2 document bundles.
///
/// Prerequisites — run ExampleERC721Lifecycle.s.sol first (EIP-1 package):
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
    bytes32 constant ROLE_TITLE_DEED   = keccak256("TITLE_DEED");
    bytes32 constant ROLE_SURVEY       = keccak256("SURVEY_REPORT");
    bytes32 constant ROLE_COMPLIANCE   = keccak256("COMPLIANCE_PACK");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);
        bytes32 anchorA     = vm.envBytes32("ANCHOR_A");
        bytes32 anchorB     = vm.envBytes32("ANCHOR_B");

        vm.startBroadcast(deployerKey);

        // 1. Deploy one shared DocumentBundleAnchor for the whole collection
        DocumentBundleAnchor anchor = new DocumentBundleAnchor(deployer);
        BundleAnchorVerifier  verifier = new BundleAnchorVerifier(address(anchor));
        console.log("DocumentBundleAnchor:", address(anchor));
        console.log("BundleAnchorVerifier:", address(verifier));

        // 2. Anchor documents for property A (NYC Office) — token #1
        bytes32 titleA = keccak256(abi.encode("nyc-title-deed-v1", anchorA));
        bytes32 compA  = keccak256(abi.encode("nyc-compliance-pack-v1", anchorA));

        anchor.anchorBundle(titleA, anchorA, ROLE_TITLE_DEED,  1, "ipfs://QmNYCTitleDeed");
        anchor.anchorBundle(compA,  anchorA, ROLE_COMPLIANCE,  6, "ipfs://QmNYCCompliancePack");
        console.log("Property A (NYC): title deed and compliance pack anchored");

        // 3. Anchor documents for property B (London Warehouse) — token #2
        bytes32 titleB   = keccak256(abi.encode("london-title-deed-v1", anchorB));
        bytes32 surveyB  = keccak256(abi.encode("london-survey-v1", anchorB));

        anchor.anchorBundle(titleB,  anchorB, ROLE_TITLE_DEED, 1, "ipfs://QmLondonTitleDeed");
        anchor.anchorBundle(surveyB, anchorB, ROLE_SURVEY,     2, "ipfs://QmLondonSurvey");
        console.log("Property B (London): title deed and survey anchored");

        // 4. Verify per-asset isolation
        require(verifier.hasActiveBundle(anchorA, ROLE_TITLE_DEED),  "A: title deed missing");
        require(verifier.hasActiveBundle(anchorA, ROLE_COMPLIANCE),  "A: compliance pack missing");
        require(verifier.hasActiveBundle(anchorB, ROLE_TITLE_DEED),  "B: title deed missing");
        require(verifier.hasActiveBundle(anchorB, ROLE_SURVEY),      "B: survey missing");
        require(!verifier.hasActiveBundle(anchorA, ROLE_SURVEY),     "A should not have survey");
        require(!verifier.hasActiveBundle(anchorB, ROLE_COMPLIANCE), "B should not have compliance");
        console.log("Per-asset document isolation confirmed.");

        // 5. Supersede property A's compliance pack (updated filing)
        bytes32 compA_v2 = keccak256(abi.encode("nyc-compliance-pack-v2", anchorA));
        anchor.supersedeBundle(compA, compA_v2, anchorA, ROLE_COMPLIANCE, 7, "ipfs://QmNYCCompliancePackV2");
        console.log("Property A compliance pack superseded with v2.");

        // 6. Property B is completely unaffected
        require(verifier.hasActiveBundle(anchorB, ROLE_TITLE_DEED), "B: title deed must still be active");
        require(verifier.hasActiveBundle(anchorB, ROLE_SURVEY),     "B: survey must still be active");
        require(verifier.isBundleCurrent(titleB, anchorB, ROLE_TITLE_DEED), "B: title deed must still be current");
        console.log("Property B documents unaffected by property A supersession.");

        // 7. Property A now has v2 as current
        require(verifier.isBundleCurrent(compA_v2, anchorA, ROLE_COMPLIANCE), "A v2 must be current");
        require(!verifier.isBundleCurrent(compA, anchorA, ROLE_COMPLIANCE),   "A v1 must not be current");
        console.log("Property A compliance pack updated to v2.");

        vm.stopBroadcast();
    }
}
