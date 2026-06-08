// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DocumentBundleAnchor} from "../src/reference/DocumentBundleAnchor.sol";

contract DeployDocumentBundleAnchor is Script {
    function run() external returns (DocumentBundleAnchor anchor) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        anchor = new DocumentBundleAnchor(admin);
        vm.stopBroadcast();

        console.log("DocumentBundleAnchor deployed:", address(anchor));
        console.log("Admin:", admin);
    }
}
