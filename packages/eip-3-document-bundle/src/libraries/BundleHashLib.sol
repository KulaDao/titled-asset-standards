// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library BundleHashLib {
    struct DocumentEntry {
        bytes32 contentHash;
        bytes32 role;
        bytes32 mimeTypeHash;
        bytes32 filenameHash;
        bytes32 normProfileId;
    }

    bytes32 internal constant SCHEMA_V1             = keccak256("EIP-XXXX:BUNDLE:V1");
    bytes32 internal constant PROFILE_RAW           = keccak256("NORM:RAW:V1");
    bytes32 internal constant PROFILE_JSON_RFC8785  = keccak256("NORM:JSON:RFC8785:V1");
    bytes32 internal constant PROFILE_XML_C14N11    = keccak256("NORM:XML:C14N11:V1");

    bytes32 internal constant LEGAL_BASIS   = keccak256("LEGAL_BASIS");
    bytes32 internal constant EVIDENCE      = keccak256("EVIDENCE");
    bytes32 internal constant CERTIFICATION = keccak256("CERTIFICATION");
    bytes32 internal constant AGREEMENT     = keccak256("AGREEMENT");
    bytes32 internal constant AMENDMENT     = keccak256("AMENDMENT");
    bytes32 internal constant SUPPORTING    = keccak256("SUPPORTING");

    function computeBundleHash(DocumentEntry[] memory entries) internal pure returns (bytes32) {
        bytes memory concatenated = abi.encodePacked(SCHEMA_V1);
        for (uint256 i = 0; i < entries.length; i++) {
            bytes32 leaf = keccak256(abi.encodePacked(
                entries[i].contentHash,
                entries[i].role,
                entries[i].mimeTypeHash,
                entries[i].filenameHash,
                entries[i].normProfileId
            ));
            concatenated = abi.encodePacked(concatenated, leaf);
        }
        return keccak256(concatenated);
    }

    function sortEntries(DocumentEntry[] memory entries) internal pure returns (DocumentEntry[] memory) {
        uint256 n = entries.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j + 1 < n - i; j++) {
                if (_gt(entries[j], entries[j + 1])) {
                    DocumentEntry memory tmp = entries[j];
                    entries[j] = entries[j + 1];
                    entries[j + 1] = tmp;
                }
            }
        }
        return entries;
    }

    function _gt(DocumentEntry memory a, DocumentEntry memory b) private pure returns (bool) {
        if (a.role != b.role)                     return a.role > b.role;
        if (a.filenameHash != b.filenameHash)     return a.filenameHash > b.filenameHash;
        return a.contentHash > b.contentHash;
    }
}
