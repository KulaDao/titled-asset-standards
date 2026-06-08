// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";
import {BundleAnchorVerifier} from "../src/reference/BundleAnchorVerifier.sol";
import {BundleHashLib} from "../src/libraries/BundleHashLib.sol";

/// @notice Minimal interface for the T-REX token's compliance functions.
interface IERC3643Compliance {
    function isWhitelisted(address investor) external view returns (bool);
    function isFrozen(address account) external view returns (bool);
    function paused() external view returns (bool);
    function anchorId() external view returns (bytes32);
    function isAnchorActive() external view returns (bool);
}

/// @title  ExampleERC3643WithDocuments
/// @notice Shows the full compliance stack for a T-REX security token:
///         asset anchor (EIP-1) + document bundles (EIP-2) + BundleAnchorVerifier
///         used as a transfer pre-check in a downstream settlement contract.
///
/// Prerequisites — deploy/register an EIP-1 asset-bound ERC-3643-style token first:
///   export ASSET_ANCHOR_ID=<anchorId from registerAnchor>
///   export TOKEN_ADDRESS=<deployed AssetBoundERC3643 address>
///
/// Then run this script:
///   forge script script/ExampleERC3643WithDocuments.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// What this demonstrates:
///   1. Anchor regulatory documents against the bond's asset anchor ID
///   2. Deploy BundleAnchorVerifier and show how it wraps compliance checks
///   3. Deploy a minimal SettlementGuard that combines both compliance layers:
///        - EIP-1 anchor active (asset not expired/deactivated)
///        - EIP-2 document bundles present (regulatory docs anchored)
///        - ERC-3643 investor whitelisted and not frozen
///   4. Show what a compliant settlement check looks like
contract ExampleERC3643WithDocuments is Script {
    bytes32 constant ROLE_PROSPECTUS = keccak256("PROSPECTUS");
    bytes32 constant ROLE_LEGAL = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_AUDIT = keccak256("AUDIT_REPORT");

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        bytes32 assetAnchorId = vm.envBytes32("ASSET_ANCHOR_ID");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address investor = vm.envOr("INVESTOR_A", address(0xAA));

        vm.startBroadcast(deployerKey);

        // 1. Deploy EIP-2 DocumentBundleAnchor
        DocumentBundleAnchor bundleAnchor = new DocumentBundleAnchor(deployer);
        console.log("DocumentBundleAnchor:", address(bundleAnchor));

        // 2. Anchor the three required regulatory document bundles
        //    subjectId = assetAnchorId links documents to the bond asset (EIP-1)
        string[] memory prospectusDocs = new string[](2);
        prospectusDocs[0] = "bond-prospectus-v1.pdf";
        prospectusDocs[1] = "bond-risk-factors-v1.pdf";
        string[] memory legalDocs = new string[](1);
        legalDocs[0] = "bond-legal-opinion-v1.pdf";
        string[] memory auditDocs = new string[](3);
        auditDocs[0] = "bond-audit-report-v1.pdf";
        auditDocs[1] = "bond-custody-statement-v1.pdf";
        auditDocs[2] = "bond-reserve-attestation-v1.pdf";

        bytes32 prospectus = _rawPdfBundle(ROLE_PROSPECTUS, prospectusDocs);
        bytes32 legal = _rawPdfBundle(ROLE_LEGAL, legalDocs);
        bytes32 audit = _rawPdfBundle(ROLE_AUDIT, auditDocs);

        bundleAnchor.anchorBundle(
            prospectus, assetAnchorId, ROLE_PROSPECTUS, prospectusDocs.length, "ipfs://QmBondProspectus"
        );
        bundleAnchor.anchorBundle(legal, assetAnchorId, ROLE_LEGAL, legalDocs.length, "ipfs://QmBondLegalOpinion");
        bundleAnchor.anchorBundle(audit, assetAnchorId, ROLE_AUDIT, auditDocs.length, "ipfs://QmBondAuditReport");
        console.log("Three regulatory bundles anchored against bond asset.");

        // 3. Deploy BundleAnchorVerifier
        BundleAnchorVerifier verifier = new BundleAnchorVerifier(address(bundleAnchor));
        console.log("BundleAnchorVerifier:", address(verifier));

        // 4. Deploy the SettlementGuard — combines both compliance layers
        SettlementGuard guard = new SettlementGuard(token, address(verifier), assetAnchorId);
        console.log("SettlementGuard:", address(guard));

        // 5. Run a settlement compliance check for the investor
        SettlementGuard.ComplianceStatus memory status = guard.checkCompliance(investor);

        console.log("== Settlement compliance check ==");
        console.log("Asset anchor active:    ", status.assetAnchorActive);
        console.log("Prospectus anchored:    ", status.prospectusPresent);
        console.log("Legal opinion anchored: ", status.legalPresent);
        console.log("Audit report anchored:  ", status.auditPresent);
        console.log("Investor whitelisted:   ", status.investorWhitelisted);
        console.log("Investor not frozen:    ", !status.investorFrozen);
        console.log("Token not paused:       ", !status.tokenPaused);
        console.log("All checks pass:        ", status.allPass);

        vm.stopBroadcast();
    }

    function _rawPdfBundle(bytes32 role, string[] memory canonicalFilenames) internal pure returns (bytes32) {
        require(canonicalFilenames.length > 0, "ExampleERC3643WithDocuments: empty bundle");

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

/// @notice Minimal settlement guard that enforces both EIP-1 and EIP-2 compliance
///         before allowing a bond trade to settle.
/// @dev    In production this would be called by a DEX or OTC settlement contract.
contract SettlementGuard {
    bytes32 constant ROLE_PROSPECTUS = keccak256("PROSPECTUS");
    bytes32 constant ROLE_LEGAL = keccak256("LEGAL_BASIS");
    bytes32 constant ROLE_AUDIT = keccak256("AUDIT_REPORT");

    IERC3643Compliance private immutable _token;
    BundleAnchorVerifier private immutable _verifier;
    bytes32 private immutable _subjectId;

    struct ComplianceStatus {
        bool assetAnchorActive;
        bool prospectusPresent;
        bool legalPresent;
        bool auditPresent;
        bool investorWhitelisted;
        bool investorFrozen;
        bool tokenPaused;
        bool allPass;
    }

    constructor(address token_, address verifier_, bytes32 subjectId_) {
        require(token_ != address(0), "SettlementGuard: zero token");
        require(verifier_ != address(0), "SettlementGuard: zero verifier");
        require(subjectId_ != bytes32(0), "SettlementGuard: zero subject");

        _token = IERC3643Compliance(token_);
        _verifier = BundleAnchorVerifier(verifier_);
        _subjectId = subjectId_;

        require(_token.anchorId() == subjectId_, "SettlementGuard: token subject mismatch");
    }

    function checkCompliance(address investor) external view returns (ComplianceStatus memory s) {
        s.assetAnchorActive = _token.isAnchorActive();
        s.prospectusPresent = _verifier.hasActiveBundle(_subjectId, ROLE_PROSPECTUS);
        s.legalPresent = _verifier.hasActiveBundle(_subjectId, ROLE_LEGAL);
        s.auditPresent = _verifier.hasActiveBundle(_subjectId, ROLE_AUDIT);
        s.investorWhitelisted = _token.isWhitelisted(investor);
        s.investorFrozen = _token.isFrozen(investor);
        s.tokenPaused = _token.paused();
        s.allPass = s.assetAnchorActive && s.prospectusPresent && s.legalPresent && s.auditPresent
            && s.investorWhitelisted && !s.investorFrozen && !s.tokenPaused;
    }

    /// @notice Reverts if any compliance check fails. Use in settlement logic.
    function requireCompliant(address investor) external view {
        ComplianceStatus memory s = this.checkCompliance(investor);
        require(s.assetAnchorActive, "SettlementGuard: asset anchor inactive");
        require(s.prospectusPresent, "SettlementGuard: prospectus not anchored");
        require(s.legalPresent, "SettlementGuard: legal opinion not anchored");
        require(s.auditPresent, "SettlementGuard: audit report not anchored");
        require(s.investorWhitelisted, "SettlementGuard: investor not whitelisted");
        require(!s.investorFrozen, "SettlementGuard: investor frozen");
        require(!s.tokenPaused, "SettlementGuard: token paused");
    }
}
