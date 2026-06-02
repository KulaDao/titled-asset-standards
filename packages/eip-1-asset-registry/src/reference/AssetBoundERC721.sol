// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAssetBoundToken} from "../interfaces/IAssetBoundToken.sol";
import {IAssetAnchorRegistry} from "../interfaces/IAssetAnchorRegistry.sol";

/// @title  AssetBoundERC721
/// @notice Reference ERC-721 implementation of IAssetBoundToken.
///         Each tokenId represents a distinct real-world asset and is bound
///         to its own anchor in the registry (per-token binding).
/// @dev    Workflow per asset:
///           1. registrar calls registry.registerAnchor(...) → anchorId
///           2. minter calls mint(to, tokenId, anchorId)
///           3. registrar calls registry.bindToken(anchorId, address(this), tokenId)
contract AssetBoundERC721 is ERC721, AccessControl, IAssetBoundToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    address private immutable _registry;

    mapping(uint256 => bytes32) private _anchorIds;
    mapping(bytes32 => bool)    private _anchorAssigned;

    event AnchorSet(uint256 indexed tokenId, bytes32 indexed anchorId);

    constructor(
        string memory name_,
        string memory symbol_,
        address registry_,
        address admin_
    ) ERC721(name_, symbol_) {
        require(registry_ != address(0), "AssetBoundERC721: zero registry");
        require(admin_    != address(0), "AssetBoundERC721: zero admin");
        _registry = registry_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
    }

    // ── IAssetBoundToken ──────────────────────────────────────────────────

    /// @inheritdoc IAssetBoundToken
    /// @dev ERC-721 uses per-token binding; whole-contract lookup is not applicable.
    function anchorId() external pure override returns (bytes32) {
        revert("AssetBoundERC721: use anchorIdOf(tokenId) -- per-token binding only");
    }

    /// @inheritdoc IAssetBoundToken
    function anchorIdOf(uint256 tokenId) external view override returns (bytes32) {
        bytes32 id = _anchorIds[tokenId];
        require(id != bytes32(0), "AssetBoundERC721: tokenId not bound");
        return id;
    }

    /// @inheritdoc IAssetBoundToken
    function anchorRegistry() external view override returns (address) {
        return _registry;
    }

    /// @inheritdoc IAssetBoundToken
    function isAssetBound() external pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IAssetBoundToken
    /// @dev ERC-721 uses per-token binding; whole-contract check is not applicable.
    function isAnchorActive() external pure override returns (bool) {
        revert("AssetBoundERC721: use isAnchorActiveFor(tokenId) -- per-token binding only");
    }

    /// @inheritdoc IAssetBoundToken
    function isAnchorActiveFor(uint256 tokenId) external view override returns (bool) {
        bytes32 id = _anchorIds[tokenId];
        require(id != bytes32(0), "AssetBoundERC721: tokenId not bound");
        return _isRegistryBound(id, tokenId) && IAssetAnchorRegistry(_registry).isActive(id);
    }

    // ── Minting ───────────────────────────────────────────────────────────

    /// @notice Mint a token and record its anchor in one step.
    /// @dev    Caller must still call registry.bindToken(anchorId, address(this), tokenId)
    ///         after minting to complete the binding on the registry side.
    function mint(address to, uint256 tokenId, bytes32 anchorId_)
        external onlyRole(MINTER_ROLE)
    {
        require(anchorId_ != bytes32(0),        "AssetBoundERC721: zero anchorId");
        require(_anchorIds[tokenId] == bytes32(0), "AssetBoundERC721: tokenId already bound");
        require(!_anchorAssigned[anchorId_], "AssetBoundERC721: anchor already assigned");

        IAssetAnchorRegistry registry = IAssetAnchorRegistry(_registry);
        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId_);
        require(rec.boundToken == address(0), "AssetBoundERC721: anchor already bound");
        require(registry.isActive(anchorId_), "AssetBoundERC721: anchor inactive");

        _anchorIds[tokenId] = anchorId_;
        _anchorAssigned[anchorId_] = true;
        _safeMint(to, tokenId);
        emit AnchorSet(tokenId, anchorId_);
    }

    // ── Transfer guard ────────────────────────────────────────────────────

    // OZ v5 ERC721._update signature: (address to, uint256 tokenId, address auth) returns (address from)
    function _update(address to, uint256 tokenId, address auth)
        internal override returns (address)
    {
        if (to != address(0)) {
            address from = _ownerOf(tokenId);
            if (from != address(0)) {
                bytes32 id = _anchorIds[tokenId];
                if (id != bytes32(0)) {
                    _requireBoundAnchorActive(id, tokenId);
                }
            }
        }
        return super._update(to, tokenId, auth);
    }

    function _requireBoundAnchorActive(bytes32 anchorId_, uint256 tokenId) internal view {
        IAssetAnchorRegistry registry = IAssetAnchorRegistry(_registry);
        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(anchorId_);
        require(
            rec.boundToken == address(this) && rec.boundTokenId == tokenId,
            "AssetBoundERC721: registry binding mismatch"
        );
        require(registry.isActive(anchorId_), "AssetBoundERC721: anchor inactive");
    }

    function _isRegistryBound(bytes32 anchorId_, uint256 tokenId) internal view returns (bool) {
        try IAssetAnchorRegistry(_registry).getAnchor(anchorId_)
            returns (IAssetAnchorRegistry.AnchorRecord memory rec)
        {
            return rec.boundToken == address(this) && rec.boundTokenId == tokenId;
        } catch {
            return false;
        }
    }

    // ── ERC-165 ───────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, AccessControl) returns (bool)
    {
        return interfaceId == type(IAssetBoundToken).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
