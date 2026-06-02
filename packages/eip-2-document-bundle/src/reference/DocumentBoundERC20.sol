// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDocumentBound} from "../interfaces/IDocumentBound.sol";
import {IDocumentBundleAnchor} from "../interfaces/IDocumentBundleAnchor.sol";

/// @title  DocumentBoundERC20
/// @notice Reference ERC-20 that enforces on-chain document compliance via EIP-2.
///         The entire token contract maps to one subject ID. All required document
///         roles must have active bundles before any transfer can settle.
///
/// @dev    Deploy this contract, then call registry.anchorBundle(...) with
///         subjectId = documentSubjectId() for each required role.
///         Transfers are blocked until all required bundles are active.
contract DocumentBoundERC20 is ERC20, AccessControl, IDocumentBound {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    IDocumentBundleAnchor private immutable _registry;
    bytes32               private immutable _subjectId;
    bytes32[]             private           _requiredRoles;

    constructor(
        string memory name_,
        string memory symbol_,
        address registry_,
        bytes32 subjectId_,
        bytes32[] memory requiredRoles_,
        address admin_
    ) ERC20(name_, symbol_) {
        require(registry_  != address(0), "DocumentBoundERC20: zero registry");
        require(subjectId_ != bytes32(0), "DocumentBoundERC20: zero subjectId");
        require(admin_     != address(0), "DocumentBoundERC20: zero admin");
        require(requiredRoles_.length > 0, "DocumentBoundERC20: no required roles");
        _registry       = IDocumentBundleAnchor(registry_);
        _subjectId      = subjectId_;
        _requiredRoles  = requiredRoles_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
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
        revert("DocumentBoundERC20: use documentSubjectId() -- whole-contract binding");
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
        revert("DocumentBoundERC20: use hasActiveDocumentBundle(role) -- whole-contract binding");
    }

    /// @notice Returns the list of roles that must have active bundles for transfers.
    function requiredRoles() external view returns (bytes32[] memory) {
        return _requiredRoles;
    }

    // ── Minting ───────────────────────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ── Transfer guard ────────────────────────────────────────────────────

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < _requiredRoles.length; i++) {
                require(
                    _registry.activeBundle(_subjectId, _requiredRoles[i]) != bytes32(0),
                    "DocumentBoundERC20: required document bundle not active"
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
