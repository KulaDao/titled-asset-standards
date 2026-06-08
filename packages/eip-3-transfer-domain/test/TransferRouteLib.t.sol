// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TransferRouteLib} from "../src/libraries/TransferRouteLib.sol";

contract TransferRouteLibTest is Test {
    function test_routeKey_matchesCanonicalPackedTriple() public {
        bytes32 source = keccak256("DOMAIN:MAURITIUS");
        bytes32 destination = keccak256("DOMAIN:ZAMBIA");
        bytes32 assetClass = keccak256("ASSET_CLASS:MINERAL_CONCESSION");

        bytes32 expected = keccak256(abi.encodePacked(source, destination, assetClass));
        assertEq(TransferRouteLib.routeKey(source, destination, assetClass), expected);
    }

    function test_routeKey_isDirectional() public {
        bytes32 domainA = keccak256("DOMAIN:A");
        bytes32 domainB = keccak256("DOMAIN:B");
        bytes32 assetClass = keccak256("ASSET_CLASS:CARBON_CREDIT");

        assertTrue(
            TransferRouteLib.routeKey(domainA, domainB, assetClass)
                != TransferRouteLib.routeKey(domainB, domainA, assetClass)
        );
    }

    function testFuzz_routeKey_matchesCanonicalPackedTriple(bytes32 source, bytes32 destination, bytes32 assetClass)
        public
    {
        assertEq(
            TransferRouteLib.routeKey(source, destination, assetClass),
            keccak256(abi.encodePacked(source, destination, assetClass))
        );
    }
}
