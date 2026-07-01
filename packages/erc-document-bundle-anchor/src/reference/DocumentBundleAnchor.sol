// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDocumentBundleAnchor} from "../interfaces/IDocumentBundleAnchor.sol";

contract DocumentBundleAnchor is IDocumentBundleAnchor, AccessControl {
    bytes32 public constant ANCHOR_ROLE = keccak256("ANCHOR");

    // Records keyed by keccak256(abi.encode(bundleHash, subjectId, role)).
    // Each (bundleHash, subjectId, role) triple has its own independent record.
    mapping(bytes32 => AnchorRecord) private _records;

    // Active bundle hash per keccak256(abi.encode(subjectId, role)) slot.
    mapping(bytes32 => bytes32) private _activeSlots;

    // Slot principal: the address authorized to call supersedeBundle for a given slot.
    // Set to msg.sender when a slot is first occupied or superseded; overridable by admin
    // via assignSlotPrincipal without going through supersedeBundle (preventing front-running).
    mapping(bytes32 => address) private _slotPrincipals;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ANCHOR_ROLE, admin);
    }

    modifier onlyAnchorOrAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            _checkRole(ANCHOR_ROLE, msg.sender);
        }
        _;
    }

    /// @dev metadataURI is stored publicly on-chain. Do not include PII or sensitive content.
    /// @dev Caller must hold ANCHOR_ROLE at the time of the call.
    function anchorBundle(
        bytes32 bundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external onlyRole(ANCHOR_ROLE) {
        require(bundleHash != bytes32(0), "DocumentBundleAnchor: zero bundleHash");
        require(subjectId != bytes32(0), "DocumentBundleAnchor: zero subjectId");
        require(role != bytes32(0), "DocumentBundleAnchor: zero role");
        require(documentCount > 0, "DocumentBundleAnchor: zero documentCount");

        bytes32 tripleKey = _tripleKey(bundleHash, subjectId, role);
        require(_records[tripleKey].anchoredAt == 0, "DocumentBundleAnchor: already anchored");

        bytes32 slotKey = _slotKey(subjectId, role);
        require(_activeSlots[slotKey] == bytes32(0), "DocumentBundleAnchor: active slot occupied, use supersedeBundle");

        _anchor(bundleHash, subjectId, role, documentCount, metadataURI, tripleKey, slotKey);
    }

    /// @dev Requires the original anchorer to retain ANCHOR_ROLE, or DEFAULT_ADMIN_ROLE for recovery.
    function supersedeBundle(
        bytes32 oldBundleHash,
        bytes32 newBundleHash,
        bytes32 subjectId,
        bytes32 role,
        uint256 documentCount,
        string calldata metadataURI
    ) external onlyAnchorOrAdmin {
        require(newBundleHash != bytes32(0), "DocumentBundleAnchor: zero newBundleHash");
        require(subjectId != bytes32(0), "DocumentBundleAnchor: zero subjectId");
        require(role != bytes32(0), "DocumentBundleAnchor: zero role");
        require(documentCount > 0, "DocumentBundleAnchor: zero documentCount");

        bytes32 oldTripleKey = _tripleKey(oldBundleHash, subjectId, role);
        AnchorRecord storage old = _records[oldTripleKey];
        require(old.anchoredAt != 0, "DocumentBundleAnchor: old bundle not anchored");
        require(!old.superseded, "DocumentBundleAnchor: old bundle already superseded");

        bytes32 slotKey = _slotKey(subjectId, role);
        require(_activeSlots[slotKey] == oldBundleHash, "DocumentBundleAnchor: old bundle not active for given slot");

        require(
            _slotPrincipals[slotKey] == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "DocumentBundleAnchor: not authorized to supersede"
        );

        bytes32 newTripleKey = _tripleKey(newBundleHash, subjectId, role);
        require(_records[newTripleKey].anchoredAt == 0, "DocumentBundleAnchor: new bundle already anchored");

        old.superseded = true;
        old.supersededBy = newBundleHash;

        emit BundleSuperseded(oldBundleHash, newBundleHash, subjectId, role);

        _anchor(newBundleHash, subjectId, role, documentCount, metadataURI, newTripleKey, slotKey);
    }

    function getAnchor(bytes32 bundleHash, bytes32 subjectId, bytes32 role)
        external
        view
        returns (AnchorRecord memory)
    {
        bytes32 key = _tripleKey(bundleHash, subjectId, role);
        require(_records[key].anchoredAt != 0, "DocumentBundleAnchor: not anchored");
        return _records[key];
    }

    function isAnchored(bytes32 bundleHash, bytes32 subjectId, bytes32 role) external view returns (bool) {
        return _records[_tripleKey(bundleHash, subjectId, role)].anchoredAt != 0;
    }

    function activeBundle(bytes32 subjectId, bytes32 role) external view returns (bytes32) {
        return _activeSlots[_slotKey(subjectId, role)];
    }

    function slotPrincipal(bytes32 subjectId, bytes32 role) external view returns (address) {
        return _slotPrincipals[_slotKey(subjectId, role)];
    }

    function assignSlotPrincipal(bytes32 subjectId, bytes32 role, address principal)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(subjectId != bytes32(0), "DocumentBundleAnchor: zero subjectId");
        require(role != bytes32(0), "DocumentBundleAnchor: zero role");
        require(principal != address(0), "DocumentBundleAnchor: zero principal");
        bytes32 slotKey = _slotKey(subjectId, role);
        _slotPrincipals[slotKey] = principal;
        emit SlotPrincipalAssigned(subjectId, role, principal);
    }

    function _tripleKey(bytes32 bundleHash, bytes32 subjectId, bytes32 role) internal pure returns (bytes32) {
        return keccak256(abi.encode(bundleHash, subjectId, role));
    }

    function _slotKey(bytes32 subjectId, bytes32 role) internal pure returns (bytes32) {
        return keccak256(abi.encode(subjectId, role));
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDocumentBundleAnchor).interfaceId || super.supportsInterface(interfaceId);
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
        _activeSlots[slotKey] = bundleHash;
        _slotPrincipals[slotKey] = msg.sender;
        _records[tripleKey] = AnchorRecord({
            bundleHash: bundleHash,
            subjectId: subjectId,
            role: role,
            anchoredBy: msg.sender,
            anchoredAt: uint64(block.timestamp),
            documentCount: documentCount,
            metadataURI: metadataURI,
            superseded: false,
            supersededBy: bytes32(0)
        });
        emit BundleAnchored(bundleHash, subjectId, role, documentCount);
    }
}
