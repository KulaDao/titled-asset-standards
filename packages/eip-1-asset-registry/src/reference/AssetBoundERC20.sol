// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAssetBoundToken} from "../interfaces/IAssetBoundToken.sol";
import {IAssetAnchorRegistry} from "../interfaces/IAssetAnchorRegistry.sol";

/// @title  AssetBoundERC20
/// @notice Reference ERC-20 implementation of IAssetBoundToken.
///         The entire token contract represents one real-world asset --
///         all transfers are blocked when the bound anchor becomes inactive.
/// @dev    Deploy this contract, then call registry.bindToken(anchorId, address(this), 0)
///         (tokenId = 0 for whole-contract ERC-20 binding).
contract AssetBoundERC20 is ERC20, AccessControl, IAssetBoundToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    bytes32 private immutable _anchorId;
    address private immutable _registry;

    constructor(
        string memory name_,
        string memory symbol_,
        bytes32 anchorId_,
        address registry_,
        address admin_
    ) ERC20(name_, symbol_) {
        require(anchorId_ != bytes32(0), "AssetBoundERC20: zero anchorId");
        require(registry_ != address(0), "AssetBoundERC20: zero registry");
        require(admin_    != address(0), "AssetBoundERC20: zero admin");
        _anchorId = anchorId_;
        _registry = registry_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
    }

    // ── IAssetBoundToken ──────────────────────────────────────────────────

    /// @inheritdoc IAssetBoundToken
    function anchorId() external view override returns (bytes32) {
        return _anchorId;
    }

    /// @inheritdoc IAssetBoundToken
    /// @dev ERC-20 uses whole-contract binding; per-token lookup is not applicable.
    function anchorIdOf(uint256) external view override returns (bytes32) {
        revert("AssetBoundERC20: use anchorId() -- whole-contract binding only");
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
    function isAnchorActive() external view override returns (bool) {
        return IAssetAnchorRegistry(_registry).isActive(_anchorId);
    }

    /// @inheritdoc IAssetBoundToken
    /// @dev ERC-20 uses whole-contract binding; per-token check is not applicable.
    function isAnchorActiveFor(uint256) external view override returns (bool) {
        revert("AssetBoundERC20: use isAnchorActive() -- whole-contract binding only");
    }

    // ── Minting ───────────────────────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ── Transfer guard ────────────────────────────────────────────────────

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            require(
                IAssetAnchorRegistry(_registry).isActive(_anchorId),
                "AssetBoundERC20: anchor inactive"
            );
        }
        super._update(from, to, amount);
    }

    // ── ERC-165 ───────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public view override returns (bool)
    {
        return interfaceId == type(IAssetBoundToken).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
