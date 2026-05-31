// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDocumentBundleAnchor} from "../interfaces/IDocumentBundleAnchor.sol";

/// @title  BundleAnchorVerifier
/// @notice Read-only consumer of IDocumentBundleAnchor.
///         Downstream contracts inherit or compose this to enforce
///         "subject must have an active, non-superseded document bundle
///         for a given role" before executing sensitive operations.
///
/// @dev    Typical usage — inherit and call requireActiveBundle() as a guard:
///
///         contract MyProtocol is BundleAnchorVerifier {
///             constructor(address registry) BundleAnchorVerifier(registry) {}
///
///             function executeOperation(bytes32 subjectId, bytes32 role, ...) external {
///                 requireActiveBundle(subjectId, role);
///                 // safe to proceed
///             }
///         }
contract BundleAnchorVerifier {
    IDocumentBundleAnchor private immutable _registry;

    error NoBundleActive(bytes32 subjectId, bytes32 role);
    error BundleNotCurrent(bytes32 bundleHash, bytes32 subjectId, bytes32 role);

    constructor(address registry_) {
        require(registry_ != address(0), "BundleAnchorVerifier: zero registry");
        _registry = IDocumentBundleAnchor(registry_);
    }

    // ── Read helpers ──────────────────────────────────────────────────────

    /// @notice The registry this verifier reads from.
    function bundleRegistry() external view returns (address) {
        return address(_registry);
    }

    /// @notice Returns true if subjectId has a current (non-zero) active bundle for role.
    function hasActiveBundle(bytes32 subjectId, bytes32 role) public view returns (bool) {
        return _registry.activeBundle(subjectId, role) != bytes32(0);
    }

    /// @notice Returns the active bundle hash, or bytes32(0) if none exists.
    function activeBundleFor(bytes32 subjectId, bytes32 role) public view returns (bytes32) {
        return _registry.activeBundle(subjectId, role);
    }

    /// @notice Returns true if bundleHash is the currently active bundle for (subjectId, role)
    ///         and has not been superseded.
    function isBundleCurrent(bytes32 bundleHash, bytes32 subjectId, bytes32 role)
        public view returns (bool)
    {
        bytes32 active = _registry.activeBundle(subjectId, role);
        return active != bytes32(0) && active == bundleHash;
    }

    /// @notice Returns true only if ALL roles have an active bundle for subjectId.
    function hasActiveBundlesForAllRoles(bytes32 subjectId, bytes32[] calldata roles)
        public view returns (bool)
    {
        for (uint256 i = 0; i < roles.length; i++) {
            if (_registry.activeBundle(subjectId, roles[i]) == bytes32(0)) return false;
        }
        return true;
    }

    /// @notice Returns a bitmap indicating which roles have active bundles.
    ///         Bit i is set if roles[i] has an active bundle. Max 256 roles.
    function activeBundleBitmap(bytes32 subjectId, bytes32[] calldata roles)
        public view returns (uint256 bitmap)
    {
        require(roles.length <= 256, "BundleAnchorVerifier: too many roles");
        for (uint256 i = 0; i < roles.length; i++) {
            if (_registry.activeBundle(subjectId, roles[i]) != bytes32(0)) {
                bitmap |= (1 << i);
            }
        }
    }

    /// @notice Retrieves the full AnchorRecord for the active bundle of (subjectId, role).
    ///         Reverts if no active bundle exists.
    function getActiveBundleRecord(bytes32 subjectId, bytes32 role)
        public view returns (IDocumentBundleAnchor.AnchorRecord memory)
    {
        bytes32 bundleHash = _registry.activeBundle(subjectId, role);
        if (bundleHash == bytes32(0)) revert NoBundleActive(subjectId, role);
        return _registry.getAnchor(bundleHash, subjectId, role);
    }

    // ── Guard functions ───────────────────────────────────────────────────

    /// @notice Reverts if subjectId has no active bundle for role.
    ///         Use in business logic as a compliance pre-check.
    function requireActiveBundle(bytes32 subjectId, bytes32 role) public view {
        if (_registry.activeBundle(subjectId, role) == bytes32(0)) {
            revert NoBundleActive(subjectId, role);
        }
    }

    /// @notice Reverts if bundleHash is not the current active bundle for (subjectId, role).
    function requireBundleIsCurrent(bytes32 bundleHash, bytes32 subjectId, bytes32 role) public view {
        if (!isBundleCurrent(bundleHash, subjectId, role)) {
            revert BundleNotCurrent(bundleHash, subjectId, role);
        }
    }

    /// @notice Reverts unless ALL roles have an active bundle for subjectId.
    function requireActiveBundlesForAllRoles(bytes32 subjectId, bytes32[] calldata roles) public view {
        for (uint256 i = 0; i < roles.length; i++) {
            if (_registry.activeBundle(subjectId, roles[i]) == bytes32(0)) {
                revert NoBundleActive(subjectId, roles[i]);
            }
        }
    }
}
