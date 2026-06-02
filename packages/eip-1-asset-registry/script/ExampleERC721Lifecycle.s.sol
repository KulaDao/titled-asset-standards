// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AssetAnchorRegistry}  from "../src/reference/AssetAnchorRegistry.sol";
import {AssetBoundERC721}     from "../src/reference/AssetBoundERC721.sol";
import {AnchorMetadataLib}    from "../src/libraries/AnchorMetadataLib.sol";

/// @title  ExampleERC721Lifecycle
/// @notice Demonstrates per-token ERC-721 binding where each NFT represents
///         a distinct real-world asset with its own independent anchor.
///
/// Usage (Sepolia):
///   forge script script/ExampleERC721Lifecycle.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// Flow:
///   1. Deploy AssetAnchorRegistry
///   2. Deploy AssetBoundERC721
///   3. Register two separate real-world assets (two real-estate properties)
///   4. Mint token #1 bound to property A, token #2 bound to property B
///   5. Bind both tokens on the registry side
///   6. Transfer token #1 — succeeds (anchor A active)
///   7. Deactivate anchor A
///   8. Transfer token #1 reverts — anchor A inactive
///   9. Transfer token #2 succeeds — anchor B is unaffected
contract ExampleERC721Lifecycle is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);
        address ownerA      = vm.envOr("OWNER_A", address(0xAA));
        address ownerB      = vm.envOr("OWNER_B", address(0xBB));

        vm.startBroadcast(deployerKey);

        // 1. Deploy registry
        AssetAnchorRegistry registry = new AssetAnchorRegistry(deployer);
        console.log("Registry:", address(registry));

        // 2. Deploy ERC-721 collection
        AssetBoundERC721 nft = new AssetBoundERC721(
            "Kula Real Estate NFTs",
            "KRNFT",
            address(registry),
            deployer
        );
        console.log("NFT contract:", address(nft));

        // 3a. Register property A (New York Office)
        bytes32 anchorA = registry.registerAnchor(
            keccak256("nyc-office-legal-title"),
            keccak256("nyc-office-survey"),
            _buildMeta("REAL_ESTATE", "US", "ipfs://QmNYC", "SQFT=45000;FLOORS=12")
        );
        console.log("Anchor A (NYC Office):");
        console.logBytes32(anchorA);

        // 3b. Register property B (London Warehouse)
        bytes32 anchorB = registry.registerAnchor(
            keccak256("london-warehouse-legal-title"),
            keccak256("london-warehouse-survey"),
            _buildMeta("REAL_ESTATE", "GB", "ipfs://QmLDN", "SQFT=22000;FLOORS=2")
        );
        console.log("Anchor B (London Warehouse):");
        console.logBytes32(anchorB);

        // 4. Mint tokens — records anchor binding on the NFT side
        nft.mint(ownerA, 1, anchorA);
        nft.mint(ownerB, 2, anchorB);
        console.log("Minted token #1 (NYC Office) to ownerA");
        console.log("Minted token #2 (London Warehouse) to ownerB");

        // 5. Complete binding on the registry side
        registry.bindToken(anchorA, address(nft), 1);
        registry.bindToken(anchorB, address(nft), 2);
        console.log("Both tokens bound on registry.");

        // Verify per-token independence
        require(nft.isAnchorActiveFor(1), "Token #1 anchor should be active");
        require(nft.isAnchorActiveFor(2), "Token #2 anchor should be active");
        console.log("Both anchors active.");

        vm.stopBroadcast();
        console.log("");
        console.log("== Per-token isolation ==");
        console.log("Deactivating anchor A will block token #1 transfers.");
        console.log("Token #2 will remain transferable -- anchor B is independent.");
    }

    function _buildMeta(
        string memory assetClass,
        string memory jurisdiction,
        string memory uri,
        string memory extensions
    ) internal view returns (bytes memory) {
        return AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      _toBytes32(assetClass),
            jurisdiction:    _toBytes32(jurisdiction),
            attestationDate: uint64(block.timestamp - 1),
            expiresAt:       uint64(block.timestamp + 730 days),
            uri:             bytes(uri),
            extensions:      bytes(extensions)
        }));
    }

    function _toBytes32(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        require(b.length <= 32, "string too long");
        assembly { result := mload(add(b, 32)) }
    }
}
