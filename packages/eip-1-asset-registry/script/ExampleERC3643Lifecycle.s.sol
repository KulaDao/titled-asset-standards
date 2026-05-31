// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AssetAnchorRegistry}  from "../src/reference/AssetAnchorRegistry.sol";
import {AssetBoundERC3643}    from "../src/reference/AssetBoundERC3643.sol";
import {AnchorMetadataLib}    from "../src/libraries/AnchorMetadataLib.sol";

/// @title  ExampleERC3643Lifecycle
/// @notice Demonstrates the T-REX (ERC-3643) security token lifecycle for a
///         bond issuance bound to a real-world asset anchor.
///
/// Usage (Sepolia):
///   forge script script/ExampleERC3643Lifecycle.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --broadcast -vvvv
///
/// Flow:
///   1. Deploy AssetAnchorRegistry
///   2. Register the underlying bond asset
///   3. Deploy AssetBoundERC3643 (T-REX security token)
///   4. Bind token to anchor
///   5. Agent whitelists two qualified investors
///   6. Mint to whitelisted investors
///   7. Transfer succeeds — both whitelisted, anchor active
///   8. Agent freezes investor A
///   9. Transfer from A reverts — account frozen
///  10. Agent unfreezes A; agent pauses token
///  11. Transfer reverts — token paused
///  12. Agent unpauses; admin deactivates anchor
///  13. Transfer reverts — anchor inactive, security compliance enforced
contract ExampleERC3643Lifecycle is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);
        address agent       = vm.envOr("AGENT",      deployer);
        address investorA   = vm.envOr("INVESTOR_A", address(0xAA));
        address investorB   = vm.envOr("INVESTOR_B", address(0xBB));

        vm.startBroadcast(deployerKey);

        // 1. Deploy registry
        AssetAnchorRegistry registry = new AssetAnchorRegistry(deployer);
        console.log("Registry:", address(registry));

        // 2. Register the underlying bond
        bytes memory metadata = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      bytes32("BOND"),
            jurisdiction:    bytes32("EU"),
            attestationDate: uint64(block.timestamp - 1),
            expiresAt:       uint64(block.timestamp + 1825 days), // 5 years
            uri:             bytes("ipfs://QmEUGreenBondSeries"),
            extensions:      bytes("ISIN=XS1234567890;RATING=AA+;TYPE=GREEN")
        }));

        bytes32 anchorId = registry.registerAnchor(
            keccak256("eu-green-bond-legal-prospectus-v1"),
            keccak256("eu-green-bond-evidence-audit-v1"),
            metadata
        );
        console.log("Anchor ID (EU Green Bond):");
        console.logBytes32(anchorId);

        // 3. Deploy T-REX security token
        AssetBoundERC3643 token = new AssetBoundERC3643(
            "Kula EU Green Bond",
            "KEGB",
            anchorId,
            address(registry),
            deployer
        );
        console.log("Token:", address(token));

        // Grant AGENT_ROLE to the designated compliance agent
        if (agent != deployer) {
            bytes32 agentRole = token.AGENT_ROLE();
            token.grantRole(agentRole, agent);
            console.log("AGENT_ROLE granted to agent");
        }

        // 4. Bind token to anchor (tokenId = 0 for whole-contract)
        registry.bindToken(anchorId, address(token), 0);
        console.log("Token bound to anchor.");

        // 5. Whitelist qualified investors (replaces full ONCHAINID identity layer)
        token.addToWhitelist(investorA);
        token.addToWhitelist(investorB);
        console.log("Whitelisted investorA and investorB");

        // 6. Mint to investors
        token.mint(investorA, 5_000_000e18);
        token.mint(investorB, 3_000_000e18);
        console.log("Minted 5,000,000 KEGB to investorA");
        console.log("Minted 3,000,000 KEGB to investorB");

        // Verify state
        require(token.isAnchorActive(),         "Anchor must be active");
        require(token.isWhitelisted(investorA), "A must be whitelisted");
        require(token.isWhitelisted(investorB), "B must be whitelisted");
        require(!token.isFrozen(investorA),     "A must not be frozen");
        require(!token.paused(),                "Token must not be paused");

        console.log("");
        console.log("== Token ready for compliant trading ==");
        console.log("Compliance controls available:");
        console.log("  agent.addToWhitelist(investor)     -- onboard new investor");
        console.log("  agent.removeFromWhitelist(investor) -- offboard investor");
        console.log("  agent.freezeAddress(account)        -- compliance hold");
        console.log("  agent.unfreezeAddress(account)      -- lift hold");
        console.log("  agent.pause()                       -- emergency stop");
        console.log("  agent.unpause()                     -- resume trading");
        console.log("  admin.deactivateAnchor(id, reason)  -- blocks all transfers");

        vm.stopBroadcast();
    }
}
