// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDocumentBound} from "../interfaces/IDocumentBound.sol";
import {IDocumentBundleAnchor} from "../interfaces/IDocumentBundleAnchor.sol";

/// @title  DocumentBoundERC721
/// @notice Reference ERC-721 collection where each token represents a distinct
///         real-world asset with its own subject ID and independent document
///         compliance requirements.
///
/// @dev    Workflow per token:
///           1. Minter calls mint(to, tokenId, subjectId)
///           2. Anchorer calls registry.anchorBundle(bundleHash, subjectId, role, ...)
///           3. Once required bundles are active, the token becomes transferable
contract DocumentBoundERC721 is ERC721, AccessControl, IDocumentBound {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    IDocumentBundleAnchor private immutable _registry;
    bytes32[]             private           _requiredRoles;

    mapping(uint256 => bytes32) private _subjectIds;

    event SubjectIdSet(uint256 indexed tokenId, bytes32 indexed subjectId);

    constructor(
        string memory name_,
        string memory symbol_,
        address registry_,
        bytes32[] memory requiredRoles_,
        address admin_
    ) ERC721(name_, symbol_) {
        require(registry_  != address(0), "DocumentBoundERC721: zero registry");
        require(admin_     != address(0), "DocumentBoundERC721: zero admin");
        require(requiredRoles_.length > 0, "DocumentBoundERC721: no required roles");
        _registry      = IDocumentBundleAnchor(registry_);
        _requiredRoles = requiredRoles_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
    }

    // ── IDocumentBound ────────────────────────────────────────────────────

    /// @inheritdoc IDocumentBound
    function documentRegistry() external view override returns (address) {
        return address(_registry);
    }

    /// @inheritdoc IDocumentBound
    function documentSubjectId() external pure override returns (bytes32) {
        revert("DocumentBoundERC721: use documentSubjectIdOf(tokenId) -- per-token binding");
    }

    /// @inheritdoc IDocumentBound
    function documentSubjectIdOf(uint256 tokenId) public view override returns (bytes32) {
        bytes32 sid = _subjectIds[tokenId];
        require(sid != bytes32(0), "DocumentBoundERC721: tokenId not bound");
        return sid;
    }

    /// @inheritdoc IDocumentBound
    function isDocumentBound() external pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IDocumentBound
    function hasActiveDocumentBundle(bytes32) external pure override returns (bool) {
        revert("DocumentBoundERC721: use hasActiveDocumentBundleFor(tokenId, role) -- per-token binding");
    }

    /// @inheritdoc IDocumentBound
    function hasActiveDocumentBundleFor(uint256 tokenId, bytes32 role)
        public view override returns (bool)
    {
        bytes32 sid = _subjectIds[tokenId];
        if (sid == bytes32(0)) return false;
        return _registry.activeBundle(sid, role) != bytes32(0);
    }

    /// @notice Returns the list of document roles required for all transfers.
    function requiredRoles() external view returns (bytes32[] memory) {
        return _requiredRoles;
    }

    // ── Minting ───────────────────────────────────────────────────────────

    /// @notice Mint a token and bind it to a subject ID in one step.
    /// @dev    Anchoring document bundles must be done separately via the registry.
    function mint(address to, uint256 tokenId, bytes32 subjectId_)
        external onlyRole(MINTER_ROLE)
    {
        require(subjectId_ != bytes32(0),        "DocumentBoundERC721: zero subjectId");
        require(_subjectIds[tokenId] == bytes32(0), "DocumentBoundERC721: tokenId already bound");
        _subjectIds[tokenId] = subjectId_;
        _safeMint(to, tokenId);
        emit SubjectIdSet(tokenId, subjectId_);
    }

    // ── Transfer guard ────────────────────────────────────────────────────

    function _update(address to, uint256 tokenId, address auth)
        internal override returns (address)
    {
        if (to != address(0)) {
            address from = _ownerOf(tokenId);
            if (from != address(0)) {
                bytes32 sid = _subjectIds[tokenId];
                if (sid != bytes32(0)) {
                    for (uint256 i = 0; i < _requiredRoles.length; i++) {
                        require(
                            _registry.activeBundle(sid, _requiredRoles[i]) != bytes32(0),
                            "DocumentBoundERC721: required document bundle not active"
                        );
                    }
                }
            }
        }
        return super._update(to, tokenId, auth);
    }

    // ── ERC-165 ───────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, AccessControl) returns (bool)
    {
        return interfaceId == type(IDocumentBound).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
