// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BundleHashLib} from "../src/libraries/BundleHashLib.sol";

contract BundleHashLibHarness {
    function computeBundleHash(BundleHashLib.DocumentEntry[] memory entries) external pure returns (bytes32) {
        return BundleHashLib.computeBundleHash(entries);
    }
}

contract BundleHashLibTest is Test {
    function _entry(bytes32 content, bytes32 role, bytes32 mime, bytes32 fname, bytes32 norm)
        internal pure returns (BundleHashLib.DocumentEntry memory)
    {
        return BundleHashLib.DocumentEntry({
            contentHash: content,
            role: role,
            mimeTypeHash: mime,
            filenameHash: fname,
            normProfileId: norm
        });
    }

    function test_computeBundleHash_deterministic() public {
        BundleHashLib.DocumentEntry[] memory entries1 = new BundleHashLib.DocumentEntry[](2);
        entries1[0] = _entry(keccak256("c1"), BundleHashLib.LEGAL_BASIS, keccak256("pdf"), keccak256("a.pdf"), BundleHashLib.PROFILE_RAW);
        entries1[1] = _entry(keccak256("c2"), BundleHashLib.EVIDENCE,    keccak256("json"), keccak256("b.json"), BundleHashLib.PROFILE_JSON_RFC8785);

        BundleHashLib.DocumentEntry[] memory entries2 = new BundleHashLib.DocumentEntry[](2);
        entries2[0] = _entry(keccak256("c2"), BundleHashLib.EVIDENCE,    keccak256("json"), keccak256("b.json"), BundleHashLib.PROFILE_JSON_RFC8785);
        entries2[1] = _entry(keccak256("c1"), BundleHashLib.LEGAL_BASIS, keccak256("pdf"),  keccak256("a.pdf"),  BundleHashLib.PROFILE_RAW);

        entries1 = BundleHashLib.sortEntries(entries1);
        entries2 = BundleHashLib.sortEntries(entries2);

        assertEq(
            BundleHashLib.computeBundleHash(entries1),
            BundleHashLib.computeBundleHash(entries2),
            "same entries in different insertion order must hash identically after sort"
        );
    }

    function test_computeBundleHash_schemaVersionChangesHash() public {
        BundleHashLib.DocumentEntry[] memory entries = new BundleHashLib.DocumentEntry[](1);
        entries[0] = _entry(keccak256("c1"), BundleHashLib.LEGAL_BASIS, keccak256("pdf"), keccak256("a.pdf"), BundleHashLib.PROFILE_RAW);

        bytes32 leaf = keccak256(abi.encodePacked(
            entries[0].contentHash,
            entries[0].role,
            entries[0].mimeTypeHash,
            entries[0].filenameHash,
            entries[0].normProfileId
        ));

        bytes32 hashWithV1   = keccak256(abi.encodePacked(BundleHashLib.SCHEMA_V1, leaf));
        bytes32 hashWithV2   = keccak256(abi.encodePacked(keccak256("EIP-XXXX:BUNDLE:V2"), leaf));

        assertEq(BundleHashLib.computeBundleHash(entries), hashWithV1, "library must use SCHEMA_V1");
        assertTrue(hashWithV1 != hashWithV2, "different schema versions must produce different hashes");
    }

    function test_computeBundleHash_orderMatters() public {
        BundleHashLib.DocumentEntry memory a = _entry(keccak256("c1"), bytes32(uint256(1)), keccak256("pdf"),  keccak256("a.pdf"),  BundleHashLib.PROFILE_RAW);
        BundleHashLib.DocumentEntry memory b = _entry(keccak256("c2"), bytes32(uint256(2)), keccak256("json"), keccak256("b.json"), BundleHashLib.PROFILE_RAW);

        BundleHashLib.DocumentEntry[] memory correct = new BundleHashLib.DocumentEntry[](2);
        correct[0] = a; // role 1 < role 2 — ascending order
        correct[1] = b;

        BundleHashLib.DocumentEntry[] memory reversed = new BundleHashLib.DocumentEntry[](2);
        reversed[0] = b;
        reversed[1] = a;

        assertTrue(
            BundleHashLib.computeBundleHash(correct) != BundleHashLib.computeBundleHash(reversed),
            "unsorted and sorted entries must produce different hashes - sort is required"
        );
    }

    function test_computeBundleHash_singleEntry() public {
        BundleHashLib.DocumentEntry[] memory entries = new BundleHashLib.DocumentEntry[](1);
        entries[0] = _entry(keccak256("sole-doc"), BundleHashLib.LEGAL_BASIS, keccak256("application/pdf"), keccak256("contract.pdf"), BundleHashLib.PROFILE_RAW);

        bytes32 h = BundleHashLib.computeBundleHash(entries);
        assertTrue(h != bytes32(0), "single-entry bundle hash must be non-zero");
    }

    function test_leafHash_computation() public {
        BundleHashLib.DocumentEntry memory entry = _entry(
            keccak256("content"),
            BundleHashLib.LEGAL_BASIS,
            keccak256("application/pdf"),
            keccak256("doc.pdf"),
            BundleHashLib.PROFILE_RAW
        );

        bytes32 expectedLeaf = keccak256(abi.encodePacked(
            entry.contentHash,
            entry.role,
            entry.mimeTypeHash,
            entry.filenameHash,
            entry.normProfileId
        ));
        bytes32 expectedBundle = keccak256(abi.encodePacked(BundleHashLib.SCHEMA_V1, expectedLeaf));

        BundleHashLib.DocumentEntry[] memory entries = new BundleHashLib.DocumentEntry[](1);
        entries[0] = entry;

        assertEq(
            BundleHashLib.computeBundleHash(entries),
            expectedBundle,
            "library must produce keccak256(SCHEMA_V1 || keccak256(content||role||mime||fname||norm))"
        );
    }

    function test_roleConstants() public {
        assertEq(BundleHashLib.LEGAL_BASIS,   keccak256("LEGAL_BASIS"),   "LEGAL_BASIS constant mismatch");
        assertEq(BundleHashLib.EVIDENCE,      keccak256("EVIDENCE"),      "EVIDENCE constant mismatch");
        assertEq(BundleHashLib.CERTIFICATION, keccak256("CERTIFICATION"), "CERTIFICATION constant mismatch");
        assertEq(BundleHashLib.AGREEMENT,     keccak256("AGREEMENT"),     "AGREEMENT constant mismatch");
        assertEq(BundleHashLib.AMENDMENT,     keccak256("AMENDMENT"),     "AMENDMENT constant mismatch");
        assertEq(BundleHashLib.SUPPORTING,    keccak256("SUPPORTING"),    "SUPPORTING constant mismatch");
    }

    function test_profileConstants() public {
        assertEq(BundleHashLib.SCHEMA_V1,            keccak256("EIP-XXXX:BUNDLE:V1"),      "SCHEMA_V1 constant mismatch");
        assertEq(BundleHashLib.PROFILE_RAW,          keccak256("NORM:RAW:V1"),             "PROFILE_RAW constant mismatch");
        assertEq(BundleHashLib.PROFILE_JSON_RFC8785, keccak256("NORM:JSON:RFC8785:V1"),    "PROFILE_JSON_RFC8785 constant mismatch");
        assertEq(BundleHashLib.PROFILE_XML_C14N11,   keccak256("NORM:XML:C14N11:V1"),      "PROFILE_XML_C14N11 constant mismatch");
    }

    function test_computeBundleHash_revertsOnEmptyBundle() public {
        BundleHashLib.DocumentEntry[] memory empty = new BundleHashLib.DocumentEntry[](0);
        BundleHashLibHarness harness = new BundleHashLibHarness();
        vm.expectRevert("BundleHashLib: empty bundle");
        harness.computeBundleHash(empty);
    }
}
