// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NAVSnapshotOracle} from "../src/reference/NAVSnapshotOracle.sol";

contract DeployNAVSnapshotOracle is Script {
    function run() external returns (NAVSnapshotOracle oracle) {
        address admin       = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        oracle = new NAVSnapshotOracle(admin);
        vm.stopBroadcast();

        console.log("NAVSnapshotOracle deployed:", address(oracle));
        console.log("Admin:", admin);
    }
}
