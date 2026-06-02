// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAssetBoundToken} from "../interfaces/IAssetBoundToken.sol";
import {IAssetAnchorRegistry} from "../interfaces/IAssetAnchorRegistry.sol";

/// @title  AssetBoundERC3643
/// @notice Reference ERC-3643 (T-REX) implementation of IAssetBoundToken.
///         Whole-contract binding (like ERC-20): the entire token contract
///         represents one real-world asset.
///
///         Key ERC-3643 properties implemented here:
///           - Investor whitelist enforced on every transfer and mint
///           - Per-account freeze (compliance hold)
///           - Global pause (emergency stop)
///           - Anchor-active guard: transfers revert when the bound anchor
///             is deactivated or expired
///           - Agent role for compliance operations
///
/// @dev    A production T-REX deployment additionally requires:
///           - On-chain Identity Registry (ONCHAINID / ERC-734/735)
///           - ClaimTopicsRegistry and TrustedIssuersRegistry
///           - Modular Compliance contract
///         This reference implementation uses an address whitelist as a
///         lightweight stand-in for the full identity layer.
contract AssetBoundERC3643 is ERC20, AccessControl, IAssetBoundToken {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT");

    bytes32 private immutable _anchorId;
    address private immutable _registry;

    // ── Compliance state ──────────────────────────────────────────────────
    mapping(address => bool) private _whitelisted;
    mapping(address => bool) private _frozen;
    bool private _paused;

    // ── Events ────────────────────────────────────────────────────────────
    event InvestorWhitelisted(address indexed investor);
    event InvestorRemoved(address indexed investor);
    event AddressFrozen(address indexed account, bool indexed frozen, address indexed agent);
    event Paused(address indexed agent);
    event Unpaused(address indexed agent);

    constructor(
        string memory name_,
        string memory symbol_,
        bytes32 anchorId_,
        address registry_,
        address admin_
    ) ERC20(name_, symbol_) {
        require(anchorId_ != bytes32(0), "AssetBoundERC3643: zero anchorId");
        require(registry_ != address(0), "AssetBoundERC3643: zero registry");
        require(admin_    != address(0), "AssetBoundERC3643: zero admin");
        _anchorId = anchorId_;
        _registry = registry_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(AGENT_ROLE, admin_);
    }

    // ── IAssetBoundToken ──────────────────────────────────────────────────

    /// @inheritdoc IAssetBoundToken
    function anchorId() external view override returns (bytes32) {
        return _anchorId;
    }

    /// @inheritdoc IAssetBoundToken
    function anchorIdOf(uint256) external pure override returns (bytes32) {
        revert("AssetBoundERC3643: use anchorId() -- whole-contract binding only");
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
        return _isRegistryBound() && IAssetAnchorRegistry(_registry).isActive(_anchorId);
    }

    /// @inheritdoc IAssetBoundToken
    function isAnchorActiveFor(uint256) external pure override returns (bool) {
        revert("AssetBoundERC3643: use isAnchorActive() -- whole-contract binding only");
    }

    // ── Compliance: whitelist ─────────────────────────────────────────────

    function addToWhitelist(address investor) external onlyRole(AGENT_ROLE) {
        _whitelisted[investor] = true;
        emit InvestorWhitelisted(investor);
    }

    function removeFromWhitelist(address investor) external onlyRole(AGENT_ROLE) {
        _whitelisted[investor] = false;
        emit InvestorRemoved(investor);
    }

    function isWhitelisted(address investor) external view returns (bool) {
        return _whitelisted[investor];
    }

    // ── Compliance: freeze ────────────────────────────────────────────────

    function freezeAddress(address account) external onlyRole(AGENT_ROLE) {
        _frozen[account] = true;
        emit AddressFrozen(account, true, msg.sender);
    }

    function unfreezeAddress(address account) external onlyRole(AGENT_ROLE) {
        _frozen[account] = false;
        emit AddressFrozen(account, false, msg.sender);
    }

    function isFrozen(address account) external view returns (bool) {
        return _frozen[account];
    }

    // ── Compliance: pause ─────────────────────────────────────────────────

    function pause() external onlyRole(AGENT_ROLE) {
        require(!_paused, "AssetBoundERC3643: already paused");
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(AGENT_ROLE) {
        require(_paused, "AssetBoundERC3643: not paused");
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    // ── Minting / burning ─────────────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyRole(AGENT_ROLE) {
        require(!_paused, "AssetBoundERC3643: token paused");
        require(_whitelisted[to], "AssetBoundERC3643: recipient not whitelisted");
        require(!_frozen[to], "AssetBoundERC3643: recipient frozen");
        _requireBoundAnchorActive();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(AGENT_ROLE) {
        require(!_paused, "AssetBoundERC3643: token paused");
        require(_whitelisted[from], "AssetBoundERC3643: holder not whitelisted");
        require(!_frozen[from], "AssetBoundERC3643: holder frozen");
        _requireBoundAnchorActive();
        _burn(from, amount);
    }

    // ── Transfer hook -- all compliance checks in one place ────────────────

    function _update(address from, address to, uint256 amount) internal override {
        bool isMint = from == address(0);
        bool isBurn = to   == address(0);

        if (!isMint && !isBurn) {
            require(!_paused,       "AssetBoundERC3643: token paused");
            require(!_frozen[from], "AssetBoundERC3643: sender frozen");
            require(!_frozen[to],   "AssetBoundERC3643: recipient frozen");
            require(_whitelisted[from], "AssetBoundERC3643: sender not whitelisted");
            require(_whitelisted[to], "AssetBoundERC3643: recipient not whitelisted");
            _requireBoundAnchorActive();
        }
        super._update(from, to, amount);
    }

    function _requireBoundAnchorActive() internal view {
        IAssetAnchorRegistry registry = IAssetAnchorRegistry(_registry);
        IAssetAnchorRegistry.AnchorRecord memory rec = registry.getAnchor(_anchorId);
        require(
            rec.boundToken == address(this) && rec.boundTokenId == 0,
            "AssetBoundERC3643: registry binding mismatch"
        );
        require(registry.isActive(_anchorId), "AssetBoundERC3643: anchor inactive");
    }

    function _isRegistryBound() internal view returns (bool) {
        try IAssetAnchorRegistry(_registry).getAnchor(_anchorId)
            returns (IAssetAnchorRegistry.AnchorRecord memory rec)
        {
            return rec.boundToken == address(this) && rec.boundTokenId == 0;
        } catch {
            return false;
        }
    }

    // ── ERC-165 ───────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public view override returns (bool)
    {
        return interfaceId == type(IAssetBoundToken).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
