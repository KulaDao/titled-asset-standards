// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AssetAnchorRegistry}  from "../src/reference/AssetAnchorRegistry.sol";
import {AssetBoundERC20}      from "../src/reference/AssetBoundERC20.sol";
import {AnchorMetadataLib}    from "../src/libraries/AnchorMetadataLib.sol";

/// @title  ExampleERC20Lifecycle
/// @notice Demonstrates the full lifecycle of an ERC-20 token bound to a
///         real-world asset anchor.
///
/// Usage (Sepolia):
///   forge script script/ExampleERC20Lifecycle.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// Flow:
///   1. Deploy AssetAnchorRegistry
///   2. Register a real-world asset anchor (gold reserve)
///   3. Deploy AssetBoundERC20 pointing at registry + anchorId
///   4. Bind the token to the anchor (registry records the link)
///   5. Mint tokens to two investors
///   6. Transfer between investors — succeeds while anchor is active
///   7. Admin deactivates the anchor
///   8. Transfer attempt reverts — anchor inactive
contract ExampleERC20Lifecycle is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);
        address investorA   = vm.envOr("INVESTOR_A", address(0xAA));
        address investorB   = vm.envOr("INVESTOR_B", address(0xBB));

        vm.startBroadcast(deployerKey);

        // 1. Deploy registry
        AssetAnchorRegistry registry = new AssetAnchorRegistry(deployer);
        console.log("Registry:   ", address(registry));

        // 2. Register the real-world asset (Zambia Gold Reserve)
        bytes memory metadata = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("GOLD"),
            jurisdiction:    bytes32("ZM"),
            attestationDate: uint64(block.timestamp - 1),
            expiresAt:       uint64(block.timestamp + 730 days),
            uri:             bytes("ipfs://QmZambiaGoldReserveSeriesA"),
            extensions:      bytes("PURITY=999.9;WEIGHT_KG=500;STANDARD=LBMA")
        }));

        bytes32 anchorId = registry.registerAnchor(
            keccak256("zambia-gold-legal-title-v1"),
            keccak256("zambia-gold-evidence-assay-v1"),
            metadata
        );
        console.log("Anchor ID:  ");
        console.logBytes32(anchorId);

        // 3. Deploy ERC-20 token
        AssetBoundERC20 token = new AssetBoundERC20(
            "Kula Zambia Gold Token",
            "KZGT",
            anchorId,
            address(registry),
            deployer
        );
        console.log("Token:      ", address(token));

        // 4. Bind token to anchor (tokenId = 0 for whole-contract ERC-20)
        registry.bindToken(anchorId, address(token), 0);
        console.log("Token bound to anchor.");

        // 5. Mint to investors
        token.mint(investorA, 1_000_000e18);
        token.mint(investorB,   500_000e18);
        console.log("Minted 1,000,000 KZGT to investor A");
        console.log("Minted   500,000 KZGT to investor B");

        // 6. isAnchorActive() should be true
        require(token.isAnchorActive(), "Anchor should be active");
        console.log("isAnchorActive: true");

        vm.stopBroadcast();
        console.log("");
        console.log("== Next steps ==");
        console.log("Transfer will succeed while anchor is active.");
        console.log("Call registry.deactivateAnchor(anchorId, reason) to block all transfers.");
    }
}
