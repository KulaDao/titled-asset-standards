// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";

contract DeployAssetAnchorRegistry is Script {
    function run() external returns (AssetAnchorRegistry registry) {
        address admin      = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        registry = new AssetAnchorRegistry(admin);
        vm.stopBroadcast();

        console.log("AssetAnchorRegistry deployed:", address(registry));
        console.log("Admin:", admin);
    }
}
