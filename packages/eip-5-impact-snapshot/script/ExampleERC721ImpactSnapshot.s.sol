// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ImpactSnapshotLog} from "../src/reference/ImpactSnapshotLog.sol";
import {NO_CORRECTION} from "../src/interfaces/IImpactSnapshotLog.sol";
import {ENERGY_SAVED, CARBON_OFFSET, UNIT_KWH, UNIT_TCO2E} from "../src/libraries/ImpactConstants.sol";

/// @title  ExampleERC721ImpactSnapshot
/// @notice Shows how an ERC-721 real-estate collection reports per-property
///         impact data using EIP-5. Each token's EIP-1 anchorId is the subjectId --
///         every property has independent, isolated impact records.
///
///
/// Prerequisites -- run ExampleERC721Lifecycle.s.sol first (EIP-1 package):
///   export ANCHOR_A=<anchorId for property A (NYC Office)>
///   export ANCHOR_B=<anchorId for property B (London Warehouse)>
///
/// Run:
///   forge script script/ExampleERC721ImpactSnapshot.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// Flow:
///   1. Deploy ImpactSnapshotLog shared across the whole NFT collection
///   2. Property A -- record Q1 ENERGY_SAVED and CARBON_OFFSET (retrofit savings)
///   3. Property B -- record Q1 ENERGY_SAVED with a different value (independent)
///   4. Update methodology for property A to v2 (new measurement standard)
///   5. Property A Q2 must use new methodology; property B is unaffected
///   6. Verify per-property isolation of snapshot counts
contract ExampleERC721ImpactSnapshot is Script {
    uint64 constant Q1_START = 1735689600; // 2025-01-01
    uint64 constant Q1_END = 1743465600; // 2025-04-01
    uint64 constant Q2_START = 1743465600; // 2025-04-01
    uint64 constant Q2_END = 1751328000; // 2025-07-01

    bytes32 constant METH_V1 = keccak256("ENERGY-STAR-CBECS-2018");
    bytes32 constant METH_V2 = keccak256("ENERGY-STAR-CBECS-2024");
    string constant METH_V1_URI = "ipfs://QmEnergyStarCBECS2018";
    string constant METH_V2_URI = "ipfs://QmEnergyStarCBECS2024";

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        bytes32 anchorA = vm.envBytes32("ANCHOR_A"); // NYC Office -- token #1
        bytes32 anchorB = vm.envBytes32("ANCHOR_B"); // London Warehouse -- token #2
        address attestorA = vm.envOr("ATTESTOR_A", deployer);

        vm.startBroadcast(deployerKey);

        // 1. One shared ImpactSnapshotLog for the whole collection
        ImpactSnapshotLog log = new ImpactSnapshotLog(deployer);
        bytes32 attestorRole = log.ATTESTOR_ROLE();
        if (attestorA != deployer) log.grantRole(attestorRole, attestorA);
        console.log("ImpactSnapshotLog (shared):", address(log));

        // 2a. Property A -- Q1 energy saved (kWh, 0 decimals) from retrofit
        uint256 aNrgIdx = log.recordSnapshot(
            anchorA, ENERGY_SAVED, 182000, 0, UNIT_KWH, Q1_START, Q1_END, METH_V1, METH_V1_URI, NO_CORRECTION
        );
        console.log("Property A (NYC): Q1 ENERGY_SAVED index:", aNrgIdx);

        // 2b. Property A -- Q1 carbon offset from energy savings
        uint256 aCo2Idx = log.recordSnapshot(
            anchorA,
            CARBON_OFFSET,
            3600,
            2,
            UNIT_TCO2E, // 36.00 tCO2e
            Q1_START,
            Q1_END,
            METH_V1,
            METH_V1_URI,
            NO_CORRECTION
        );
        console.log("Property A (NYC): Q1 CARBON_OFFSET index:", aCo2Idx);

        // 3. Property B -- Q1 energy saved (completely independent, different value)
        uint256 bNrgIdx = log.recordSnapshot(
            anchorB, ENERGY_SAVED, 54000, 0, UNIT_KWH, Q1_START, Q1_END, METH_V1, METH_V1_URI, NO_CORRECTION
        );
        console.log("Property B (London): Q1 ENERGY_SAVED index:", bNrgIdx);

        // 4. Methodology update for property A only (new CBECS 2024 standard)
        //    effectiveFromOrdinal may be the current indicatorSnapshotCount
        //    for immediate activation, or a higher ordinal for scheduled activation.
        //    Property A has 1 ENERGY_SAVED snapshot so far (index 0), count = 1.
        log.supersedeMethodology(
            anchorA,
            ENERGY_SAVED,
            METH_V1,
            METH_V2,
            METH_V2_URI,
            1 // effectiveFromOrdinal = current count (1 snapshot so far)
        );
        console.log("Property A: ENERGY_SAVED methodology updated to CBECS 2024.");

        // 5a. Property A Q2 -- must use new methodology (METH_V2)
        uint256 aNrgQ2Idx = log.recordSnapshot(
            anchorA,
            ENERGY_SAVED,
            210000,
            0,
            UNIT_KWH,
            Q2_START,
            Q2_END,
            METH_V2,
            METH_V2_URI, // must match active methodology
            NO_CORRECTION
        );
        console.log("Property A (NYC): Q2 ENERGY_SAVED index:", aNrgQ2Idx);

        // 5b. Property B Q2 -- still uses METH_V1 (unaffected by A's methodology change)
        uint256 bNrgQ2Idx = log.recordSnapshot(
            anchorB, ENERGY_SAVED, 61000, 0, UNIT_KWH, Q2_START, Q2_END, METH_V1, METH_V1_URI, NO_CORRECTION
        );
        console.log("Property B (London): Q2 ENERGY_SAVED index:", bNrgQ2Idx);

        // 6. Verify per-property isolation
        uint256 aCount = log.indicatorSnapshotCount(anchorA, ENERGY_SAVED);
        uint256 bCount = log.indicatorSnapshotCount(anchorB, ENERGY_SAVED);
        require(aCount == 2, "Property A must have 2 ENERGY_SAVED snapshots");
        require(bCount == 2, "Property B must have 2 ENERGY_SAVED snapshots");
        console.log("Property A ENERGY_SAVED count:", aCount);
        console.log("Property B ENERGY_SAVED count:", bCount);

        vm.stopBroadcast();

        console.log("\n== ERC-721 impact summary ==");
        console.log("Each NFT's anchorId is an independent subjectId in EIP-5.");
        console.log("Methodology update on property A does not affect property B.");
    }
}
