// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ImpactSnapshotLog} from "../src/reference/ImpactSnapshotLog.sol";

contract DeployImpactSnapshotLog is Script {
    function run() external returns (ImpactSnapshotLog log) {
        address admin       = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        log = new ImpactSnapshotLog(admin);
        vm.stopBroadcast();

        console.log("ImpactSnapshotLog deployed:", address(log));
        console.log("Admin:", admin);
    }
}
