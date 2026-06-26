// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ImpactSnapshotLog} from "../src/reference/ImpactSnapshotLog.sol";
import {NO_CORRECTION} from "../src/interfaces/IImpactSnapshotLog.sol";
import {CARBON_OFFSET, JOBS_CREATED, UNIT_TCO2E, UNIT_FTE} from "../src/libraries/ImpactConstants.sol";

/// @title  ExampleERC20ImpactSnapshot
/// @notice Shows how an ERC-20 asset-bound token (e.g. a gold reserve fund)
///         reports and attests quarterly impact data using the impact snapshot log.
///
/// Prerequisites -- run ExampleERC20Lifecycle.s.sol first (`erc-asset-registry`):
///   export ASSET_ANCHOR_ID=<anchorId from registerAnchor>
///
/// Run:
///   forge script script/ExampleERC20ImpactSnapshot.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// Flow:
///   1. Deploy ImpactSnapshotLog, grant roles to reporter and attestor
///   2. Q1 2025 -- record CARBON_OFFSET and JOBS_CREATED against the token's asset anchor
///   3. Independent attestor endorses the Q1 carbon snapshot with evidence
///   4. Q2 2025 -- record next quarter (originals, different period)
///   5. Discovery: Q1 CARBON_OFFSET value was understated -- record a correction
///   6. Verify the correction chain -- currentSnapshotForPeriod returns the corrected value
contract ExampleERC20ImpactSnapshot is Script {
    // Q1 and Q2 2025 timestamps
    uint64 constant Q1_START = 1735689600; // 2025-01-01
    uint64 constant Q1_END = 1743465600; // 2025-04-01
    uint64 constant Q2_START = 1743465600; // 2025-04-01
    uint64 constant Q2_END = 1751328000; // 2025-07-01

    bytes32 constant METHODOLOGY_V1 = keccak256("GHG-Protocol-Scope3-v1.0");
    string constant METHODOLOGY_V1_URI = "ipfs://QmGHGProtocolScope3v1";

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        bytes32 assetAnchorId = vm.envBytes32("ASSET_ANCHOR_ID");
        uint256 reporterKey = vm.envOr("REPORTER_PRIVATE_KEY", deployerKey);
        address reporter = vm.addr(reporterKey);
        uint256 attestorKey = vm.envOr("ATTESTOR_PRIVATE_KEY", deployerKey);
        address attestor = vm.addr(attestorKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy and configure
        ImpactSnapshotLog log = new ImpactSnapshotLog(deployer);
        bytes32 reporterRole = log.REPORTER_ROLE();
        bytes32 attestorRole = log.ATTESTOR_ROLE();
        if (reporter != deployer) log.grantRole(reporterRole, reporter);
        if (attestor != deployer) log.grantRole(attestorRole, attestor);
        console.log("ImpactSnapshotLog:", address(log));

        if (reporter != deployer) {
            vm.stopBroadcast();
            vm.startBroadcast(reporterKey);
        }

        // 2a. Q1 2025 -- Carbon offset (tCO2e, 2 decimals → value 1234 = 12.34 tCO2e)
        uint256 q1CarbonIdx = log.recordSnapshot(
            assetAnchorId,
            CARBON_OFFSET,
            1234,
            2,
            UNIT_TCO2E,
            Q1_START,
            Q1_END,
            METHODOLOGY_V1,
            METHODOLOGY_V1_URI,
            NO_CORRECTION
        );
        console.log("Q1 CARBON_OFFSET snapshot index:", q1CarbonIdx);

        // 2b. Q1 2025 -- Jobs created (FTE, 0 decimals)
        uint256 q1JobsIdx = log.recordSnapshot(
            assetAnchorId,
            JOBS_CREATED,
            47,
            0,
            UNIT_FTE,
            Q1_START,
            Q1_END,
            METHODOLOGY_V1,
            METHODOLOGY_V1_URI,
            NO_CORRECTION
        );
        console.log("Q1 JOBS_CREATED snapshot index:", q1JobsIdx);

        // 3. Attestor independently endorses Q1 carbon snapshot
        bool attested = false;
        if (attestor == deployer) {
            console.log(
                "Skipping attestation (self-attestation disallowed). Set ATTESTOR_PRIVATE_KEY to a different key."
            );
        } else {
            vm.stopBroadcast();
            vm.startBroadcast(attestorKey);
            log.attestSnapshot(
                assetAnchorId,
                q1CarbonIdx,
                true,
                keccak256("third-party-carbon-audit-q1-2025"),
                "ipfs://QmCarbonAuditQ12025"
            );
            vm.stopBroadcast();
            attested = true;
            console.log("Q1 CARBON_OFFSET attested by independent auditor.");
        }

        if (attested) vm.startBroadcast(reporterKey);

        // 4a. Q2 2025 -- Carbon offset (new period, original snapshot)
        uint256 q2CarbonIdx = log.recordSnapshot(
            assetAnchorId,
            CARBON_OFFSET,
            1580,
            2,
            UNIT_TCO2E,
            Q2_START,
            Q2_END,
            METHODOLOGY_V1,
            METHODOLOGY_V1_URI,
            NO_CORRECTION
        );
        console.log("Q2 CARBON_OFFSET snapshot index:", q2CarbonIdx);

        // 5. Correction -- Q1 carbon was understated; actual value is 1389 tCO2e * 0.01
        uint256 q1CarbonCorrIdx = log.recordSnapshot(
            assetAnchorId,
            CARBON_OFFSET,
            1389,
            2,
            UNIT_TCO2E,
            Q1_START,
            Q1_END,
            METHODOLOGY_V1,
            METHODOLOGY_V1_URI,
            q1CarbonIdx // correctsIndex -- links to original
        );
        console.log("Q1 CARBON_OFFSET correction index:", q1CarbonCorrIdx);

        // 6. Verify the correction chain
        uint256 current = log.currentSnapshotForPeriod(assetAnchorId, CARBON_OFFSET, Q1_START, Q1_END);
        require(current == q1CarbonCorrIdx, "currentSnapshotForPeriod must point to correction");
        console.log("currentSnapshotForPeriod returns corrected index:", current);

        vm.stopBroadcast();

        console.log("\n== ERC-20 impact summary ==");
        console.log("Asset anchor ID used as subjectId -- links impact data back to the asset registry anchor.");
        if (attested) {
            console.log("Q1 carbon corrected; Q2 original; Q1 carbon attested by independent auditor.");
        } else {
            console.log("Q1 carbon corrected; Q2 original; no attestation (set ATTESTOR_PRIVATE_KEY to attest).");
        }
    }
}
