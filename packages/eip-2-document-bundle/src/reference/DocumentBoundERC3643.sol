// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDocumentBound} from "../interfaces/IDocumentBound.sol";
import {IDocumentBundleAnchor} from "../interfaces/IDocumentBundleAnchor.sol";

/// @title  DocumentBoundERC3643
/// @notice Reference T-REX (ERC-3643) security token with on-chain document
///         compliance via EIP-2. Combines the investor whitelist, freeze, and
///         pause controls of a regulated security token with a document compliance
///         layer -- all required document bundles must be active for transfers.
///
/// @dev    A production T-REX deployment additionally requires:
///           - On-chain Identity Registry (ONCHAINID / ERC-734/735)
///           - ClaimTopicsRegistry and TrustedIssuersRegistry
///           - Modular Compliance contract
///         This reference uses an address whitelist as a lightweight stand-in.
contract DocumentBoundERC3643 is ERC20, AccessControl, IDocumentBound {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT");

    IDocumentBundleAnchor private immutable _registry;
    bytes32               private immutable _subjectId;
    bytes32[]             private           _requiredRoles;

    // ── ERC-3643 compliance state ─────────────────────────────────────────
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
        address registry_,
        bytes32 subjectId_,
        bytes32[] memory requiredRoles_,
        address admin_
    ) ERC20(name_, symbol_) {
        require(registry_  != address(0), "DocumentBoundERC3643: zero registry");
        require(subjectId_ != bytes32(0), "DocumentBoundERC3643: zero subjectId");
        require(admin_     != address(0), "DocumentBoundERC3643: zero admin");
        require(requiredRoles_.length > 0, "DocumentBoundERC3643: no required roles");
        _registry      = IDocumentBundleAnchor(registry_);
        _subjectId     = subjectId_;
        _requiredRoles = requiredRoles_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(AGENT_ROLE, admin_);
    }

    // ── IDocumentBound ────────────────────────────────────────────────────

    /// @inheritdoc IDocumentBound
    function documentRegistry() external view override returns (address) {
        return address(_registry);
    }

    /// @inheritdoc IDocumentBound
    function documentSubjectId() external view override returns (bytes32) {
        return _subjectId;
    }

    /// @inheritdoc IDocumentBound
    function documentSubjectIdOf(uint256) external view override returns (bytes32) {
        revert("DocumentBoundERC3643: use documentSubjectId() -- whole-contract binding");
    }

    /// @inheritdoc IDocumentBound
    function isDocumentBound() external pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IDocumentBound
    function hasActiveDocumentBundle(bytes32 role) public view override returns (bool) {
        return _registry.activeBundle(_subjectId, role) != bytes32(0);
    }

    /// @inheritdoc IDocumentBound
    function hasActiveDocumentBundleFor(uint256, bytes32) external view override returns (bool) {
        revert("DocumentBoundERC3643: use hasActiveDocumentBundle(role) -- whole-contract binding");
    }

    function requiredRoles() external view returns (bytes32[] memory) {
        return _requiredRoles;
    }

    // ── ERC-3643 compliance: whitelist ────────────────────────────────────

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

    // ── ERC-3643 compliance: freeze ───────────────────────────────────────

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

    // ── ERC-3643 compliance: pause ────────────────────────────────────────

    function pause() external onlyRole(AGENT_ROLE) {
        require(!_paused, "DocumentBoundERC3643: already paused");
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(AGENT_ROLE) {
        require(_paused, "DocumentBoundERC3643: not paused");
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) { return _paused; }

    // ── Minting / burning ─────────────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyRole(AGENT_ROLE) {
        require(_whitelisted[to], "DocumentBoundERC3643: recipient not whitelisted");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(AGENT_ROLE) {
        _burn(from, amount);
    }

    // ── Transfer hook -- all compliance checks ────────────────────────────

    function _update(address from, address to, uint256 amount) internal override {
        bool isMint = from == address(0);
        bool isBurn = to   == address(0);

        if (!isMint && !isBurn) {
            require(!_paused,        "DocumentBoundERC3643: token paused");
            require(!_frozen[from],  "DocumentBoundERC3643: sender frozen");
            require(!_frozen[to],    "DocumentBoundERC3643: recipient frozen");
            require(_whitelisted[to], "DocumentBoundERC3643: recipient not whitelisted");

            for (uint256 i = 0; i < _requiredRoles.length; i++) {
                require(
                    _registry.activeBundle(_subjectId, _requiredRoles[i]) != bytes32(0),
                    "DocumentBoundERC3643: required document bundle not active"
                );
            }
        }
        super._update(from, to, amount);
    }

    // ── ERC-165 ───────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public view override returns (bool)
    {
        return interfaceId == type(IDocumentBound).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
