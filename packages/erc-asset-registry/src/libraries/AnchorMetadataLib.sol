// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library AnchorMetadataLib {
    struct AnchorMetadata {
        bytes32 assetClass;
        bytes32 jurisdiction;
        uint64 attestationDate;
        uint64 expiresAt;
        bytes uri;
        bytes extensions;
    }

    function encode(AnchorMetadata memory m) internal pure returns (bytes memory) {
        return abi.encode(m.assetClass, m.jurisdiction, m.attestationDate, m.expiresAt, m.uri, m.extensions);
    }

    function decode(bytes memory data) internal pure returns (AnchorMetadata memory m) {
        (m.assetClass, m.jurisdiction, m.attestationDate, m.expiresAt, m.uri, m.extensions) =
            abi.decode(data, (bytes32, bytes32, uint64, uint64, bytes, bytes));
    }

    function validate(AnchorMetadata memory m) internal pure {
        require(m.assetClass != bytes32(0), "AnchorMetadataLib: missing assetClass");
        require(m.jurisdiction != bytes32(0), "AnchorMetadataLib: missing jurisdiction");
        require(m.attestationDate != 0, "AnchorMetadataLib: missing attestationDate");
        require(m.expiresAt != 0, "AnchorMetadataLib: missing expiresAt");
        require(m.attestationDate < m.expiresAt, "AnchorMetadataLib: expiresAt not after attestationDate");
        require(m.uri.length > 0, "AnchorMetadataLib: missing uri");
    }
}
