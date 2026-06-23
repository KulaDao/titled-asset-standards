// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AnchorMetadataLib} from "../src/libraries/AnchorMetadataLib.sol";

contract AnchorMetadataLibHarness {
    function validate(AnchorMetadataLib.AnchorMetadata memory m) external pure {
        AnchorMetadataLib.validate(m);
    }
}

contract AnchorMetadataLibTest is Test {
    bytes32 constant ASSET_CLASS_EQUITY = keccak256("EIP-XXXX:ASSET_CLASS:EQUITY");
    bytes32 constant JURISDICTION_US = keccak256("EIP-XXXX:JURISDICTION:US");

    AnchorMetadataLibHarness internal harness;

    function setUp() public {
        harness = new AnchorMetadataLibHarness();
    }

    function _validMeta() internal pure returns (AnchorMetadataLib.AnchorMetadata memory) {
        return AnchorMetadataLib.AnchorMetadata({
            assetClass: ASSET_CLASS_EQUITY,
            jurisdiction: JURISDICTION_US,
            attestationDate: uint64(1_000_000),
            expiresAt: uint64(2_000_000),
            uri: bytes("ipfs://QmFoo"),
            extensions: bytes("")
        });
    }

    function test_encode_decode_roundtrip() public pure {
        AnchorMetadataLib.AnchorMetadata memory original = _validMeta();
        bytes memory encoded = AnchorMetadataLib.encode(original);
        AnchorMetadataLib.AnchorMetadata memory decoded = AnchorMetadataLib.decode(encoded);

        assertEq(decoded.assetClass, original.assetClass, "assetClass mismatch");
        assertEq(decoded.jurisdiction, original.jurisdiction, "jurisdiction mismatch");
        assertEq(decoded.attestationDate, original.attestationDate, "attestationDate mismatch");
        assertEq(decoded.expiresAt, original.expiresAt, "expiresAt mismatch");
        assertEq(decoded.uri, original.uri, "uri mismatch");
        assertEq(decoded.extensions, original.extensions, "extensions mismatch");
    }

    function test_validate_passesWithAllFields() public view {
        harness.validate(_validMeta());
    }

    function test_validate_revertsEmptyAssetClass() public {
        AnchorMetadataLib.AnchorMetadata memory m = _validMeta();
        m.assetClass = bytes32(0);
        vm.expectRevert("AnchorMetadataLib: missing assetClass");
        harness.validate(m);
    }

    function test_validate_revertsEmptyJurisdiction() public {
        AnchorMetadataLib.AnchorMetadata memory m = _validMeta();
        m.jurisdiction = bytes32(0);
        vm.expectRevert("AnchorMetadataLib: missing jurisdiction");
        harness.validate(m);
    }

    function test_validate_revertsZeroAttestationDate() public {
        AnchorMetadataLib.AnchorMetadata memory m = _validMeta();
        m.attestationDate = 0;
        vm.expectRevert("AnchorMetadataLib: missing attestationDate");
        harness.validate(m);
    }

    function test_validate_revertsZeroExpiresAt() public {
        AnchorMetadataLib.AnchorMetadata memory m = _validMeta();
        m.expiresAt = 0;
        vm.expectRevert("AnchorMetadataLib: missing expiresAt");
        harness.validate(m);
    }

    function test_validate_revertsExpiresAtNotAfterAttestationDate() public {
        AnchorMetadataLib.AnchorMetadata memory m = _validMeta();
        m.expiresAt = m.attestationDate;
        vm.expectRevert("AnchorMetadataLib: expiresAt not after attestationDate");
        harness.validate(m);
    }

    function test_validate_revertsEmptyUri() public {
        AnchorMetadataLib.AnchorMetadata memory m = _validMeta();
        m.uri = bytes("");
        vm.expectRevert("AnchorMetadataLib: missing uri");
        harness.validate(m);
    }

    function test_validate_allowsEmptyExtensions() public view {
        AnchorMetadataLib.AnchorMetadata memory m = _validMeta();
        m.extensions = bytes("");
        harness.validate(m);
    }
}
