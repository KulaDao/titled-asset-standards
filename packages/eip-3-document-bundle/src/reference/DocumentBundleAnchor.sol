// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDocumentBundleAnchor} from "../interfaces/IDocumentBundleAnchor.sol";

contract DocumentBundleAnchor is IDocumentBundleAnchor, AccessControl {
    bytes32 public constant ANCHOR_ROLE = keccak256("ANCHOR");

    // Records keyed by bundleHash. When the same bundleHash is anchored for
    // multiple subjects, this stores the most-recently-anchored record.
    // Active slots remain per-(subjectId, role) and are always authoritative.
    mapping(bytes32 => AnchorRecord) private _records;

    // Tracks anchored (bundleHash, subjectId, role) triples to allow the same
    // bundleHash to be registered independently for different subjects.
    mapping(bytes32 => bool) private _anchored;

    // Active bundle hash per keccak256(subjectId, role) slot.
    mapping(bytes32 => bytes32) private _activeSlots;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ANCHOR_ROLE, admin);
    }

    function anchorBundle(
        bytes32 bundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external onlyRole(ANCHOR_ROLE) {
        bytes32 tripleKey = keccak256(abi.encodePacked(bundleHash, subjectId, role));
        require(!_anchored[tripleKey], "DocumentBundleAnchor: already anchored");

        bytes32 slotKey = keccak256(abi.encodePacked(subjectId, role));
        require(_activeSlots[slotKey] == bytes32(0), "DocumentBundleAnchor: active slot occupied, use supersedeBundle");

        _anchor(bundleHash, subjectId, role, documentCount, metadataURI, tripleKey, slotKey);
    }

    function supersedeBundle(
        bytes32 oldBundleHash,
        bytes32 newBundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external onlyRole(ANCHOR_ROLE) {
        AnchorRecord storage old = _records[oldBundleHash];
        require(old.anchoredAt != 0, "DocumentBundleAnchor: old bundle not anchored");
        require(!old.superseded,     "DocumentBundleAnchor: old bundle already superseded");

        bytes32 slotKey = keccak256(abi.encodePacked(subjectId, role));
        require(_activeSlots[slotKey] == oldBundleHash, "DocumentBundleAnchor: old bundle not active for given slot");

        require(
            old.anchoredBy == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "DocumentBundleAnchor: not authorized to supersede"
        );

        bytes32 newTripleKey = keccak256(abi.encodePacked(newBundleHash, subjectId, role));
        require(!_anchored[newTripleKey], "DocumentBundleAnchor: new bundle already anchored");

        old.superseded   = true;
        old.supersededBy = newBundleHash;

        emit BundleSuperseded(oldBundleHash, newBundleHash, subjectId);

        _anchor(newBundleHash, subjectId, role, documentCount, metadataURI, newTripleKey, slotKey);
    }

    function getAnchor(bytes32 bundleHash) external view returns (AnchorRecord memory) {
        require(_records[bundleHash].anchoredAt != 0, "DocumentBundleAnchor: not anchored");
        return _records[bundleHash];
    }

    function isAnchored(bytes32 bundleHash) external view returns (bool) {
        return _records[bundleHash].anchoredAt != 0;
    }

    function activeBundle(bytes32 subjectId, bytes32 role) external view returns (bytes32) {
        return _activeSlots[keccak256(abi.encodePacked(subjectId, role))];
    }

    function _anchor(
        bytes32 bundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI,
        bytes32 tripleKey,
        bytes32 slotKey
    ) internal {
        _anchored[tripleKey] = true;
        _activeSlots[slotKey] = bundleHash;
        _records[bundleHash] = AnchorRecord({
            bundleHash:    bundleHash,
            subjectId:     subjectId,
            role:          role,
            anchoredBy:    msg.sender,
            anchoredAt:    uint64(block.timestamp),
            documentCount: documentCount,
            metadataURI:   metadataURI,
            superseded:    false,
            supersededBy:  bytes32(0)
        });
        emit BundleAnchored(bundleHash, subjectId, role, documentCount);
    }
}
