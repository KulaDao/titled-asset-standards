// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AssetAnchorRegistry} from "../src/reference/AssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";

contract RegisterTestAnchors is Script {
    AssetAnchorRegistry constant REGISTRY =
        AssetAnchorRegistry(0x2b0578497ced999000518E3786D4a5Ac16fdf00E);

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(key);

        _register(
            "GOLD",
            "ZM",
            1746057600, // 2025-05-01
            1809302400, // 2027-05-01
            "ipfs://QmZambiaGoldReserveSeriesA2025Lusaka",
            "PURITY=999.9;WEIGHT_KG=500;VAULT=Lusaka_CBZ_Vault_A;STANDARD=LBMA",
            keccak256("zambia-gold-legal-title-v1"),
            keccak256("zambia-gold-evidence-assay-v1")
        );

        _register(
            "COMMODITY",
            "KE",
            1762041600, // 2025-11-10
            1825286400, // 2027-11-10
            "ipfs://QmKenyaAASpecialtyCoffeeReserve2025Nairobi",
            "GRADE=AA;WEIGHT_KG=12000;WAREHOUSE=Nairobi_CMA_Store_7;ORIGIN=Nyeri",
            keccak256("kenya-coffee-legal-title-v1"),
            keccak256("kenya-coffee-evidence-cert-v1")
        );

        _register(
            "REAL_ESTATE",
            "US",
            1710028800, // 2024-03-10
            1804723200, // 2027-03-10
            "ipfs://QmNewYorkOfficeComplexRWA2024TitleDeed",
            "SQFT=45000;FLOORS=12;ZONE=Commercial",
            keccak256("nyc-office-legal-title-v1"),
            keccak256("nyc-office-evidence-survey-v1")
        );

        vm.stopBroadcast();
    }

    function _register(
        string memory assetClass,
        string memory jurisdiction,
        uint64  attestationDate,
        uint64  expiresAt,
        string memory uri,
        string memory extensions,
        bytes32 legalHash,
        bytes32 evidenceHash
    ) internal {
        bytes32 ac = _toBytes32(assetClass);
        bytes32 jur = _toBytes32(jurisdiction);

        bytes memory meta = AnchorMetadataLib.encode(AnchorMetadataLib.AnchorMetadata({
            assetClass:      ac,
            jurisdiction:    jur,
            attestationDate: attestationDate,
            expiresAt:       expiresAt,
            uri:             bytes(uri),
            extensions:      bytes(extensions)
        }));

        bytes32 anchorId = REGISTRY.registerAnchor(legalHash, evidenceHash, meta);
        console.log("Registered:", assetClass, jurisdiction);
        console.logBytes32(anchorId);
    }

    function _toBytes32(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        require(b.length <= 32, "string too long");
        assembly { result := mload(add(b, 32)) }
    }
}
