// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {GracefulTransferDomainRegistry} from "../src/reference/GracefulTransferDomainRegistry.sol";
import {TransferDomainRegistry} from "../src/reference/TransferDomainRegistry.sol";

contract DeployTransferDomainRegistry is Script {
    function run()
        external
        returns (TransferDomainRegistry coreRegistry, GracefulTransferDomainRegistry gracefulRegistry)
    {
        address admin = vm.envOr("ADMIN", msg.sender);
        uint64 gracePeriod = uint64(vm.envOr("GRACE_PERIOD", uint256(1 days)));

        vm.startBroadcast();
        coreRegistry = new TransferDomainRegistry(admin);
        gracefulRegistry = new GracefulTransferDomainRegistry(admin, gracePeriod);
        vm.stopBroadcast();
    }
}
