// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ComplianceEventLog} from "../src/reference/ComplianceEventLog.sol";

contract DeployComplianceEventLog is Script {
    function run() external returns (ComplianceEventLog log) {
        address admin       = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        log = new ComplianceEventLog(admin);
        vm.stopBroadcast();

        console.log("ComplianceEventLog deployed:", address(log));
        console.log("Admin:", admin);
    }
}
