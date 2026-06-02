// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
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
    error EmptyRoleSet();
    error DuplicateRole(bytes32 role);
    error TooManyRoles(uint256 count);

    constructor(address registry_) {
        require(registry_ != address(0), "BundleAnchorVerifier: zero registry");
        require(registry_.code.length > 0, "BundleAnchorVerifier: registry not contract");

        (bool ok, bytes memory data) = registry_.staticcall(
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IDocumentBundleAnchor).interfaceId)
        );
        if (ok) {
            require(
                data.length == 32 && abi.decode(data, (bool)),
                "BundleAnchorVerifier: unsupported registry"
            );
        }

        _registry = IDocumentBundleAnchor(registry_);
    }

    // ── Read helpers ──────────────────────────────────────────────────────

    /// @notice The registry this verifier reads from.
    function bundleRegistry() external view returns (address) {
        return address(_registry);
    }

    /// @notice Returns true if subjectId has a current (non-zero) active bundle for role.
    function hasActiveBundle(bytes32 subjectId, bytes32 role) public view returns (bool) {
        (bool current,,) = _activeRecord(subjectId, role);
        return current;
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
        (bool current, bytes32 active,) = _activeRecord(subjectId, role);
        return current && active == bundleHash;
    }

    /// @notice Returns true only if ALL roles have an active bundle for subjectId.
    /// @dev Reverts for empty, duplicate, or more-than-256 role sets.
    function hasActiveBundlesForAllRoles(bytes32 subjectId, bytes32[] calldata roles)
        public view returns (bool)
    {
        _validateRoles(roles);
        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasActiveBundle(subjectId, roles[i])) return false;
        }
        return true;
    }

    /// @notice Returns a bitmap indicating which roles have active bundles.
    ///         Bit i is set if roles[i] has an active bundle. Max 256 roles.
    function activeBundleBitmap(bytes32 subjectId, bytes32[] calldata roles)
        public view returns (uint256 bitmap)
    {
        _validateRoles(roles);
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasActiveBundle(subjectId, roles[i])) {
                bitmap |= (uint256(1) << i);
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
        IDocumentBundleAnchor.AnchorRecord memory record;
        try _registry.getAnchor(bundleHash, subjectId, role) returns (IDocumentBundleAnchor.AnchorRecord memory fetched) {
            record = fetched;
        } catch {
            revert BundleNotCurrent(bundleHash, subjectId, role);
        }

        if (!_isCurrentRecord(record, bundleHash, subjectId, role)) {
            revert BundleNotCurrent(bundleHash, subjectId, role);
        }
        return record;
    }

    // ── Guard functions ───────────────────────────────────────────────────

    /// @notice Reverts if subjectId has no active bundle for role.
    ///         Use in business logic as a compliance pre-check.
    function requireActiveBundle(bytes32 subjectId, bytes32 role) public view {
        if (!hasActiveBundle(subjectId, role)) {
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
    /// @dev Reverts for empty, duplicate, or more-than-256 role sets.
    function requireActiveBundlesForAllRoles(bytes32 subjectId, bytes32[] calldata roles) public view {
        _validateRoles(roles);
        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasActiveBundle(subjectId, roles[i])) {
                revert NoBundleActive(subjectId, roles[i]);
            }
        }
    }

    function _activeRecord(bytes32 subjectId, bytes32 role)
        internal view returns (
            bool current,
            bytes32 active,
            IDocumentBundleAnchor.AnchorRecord memory record
        )
    {
        active = _registry.activeBundle(subjectId, role);
        if (active == bytes32(0)) return (false, active, record);

        try _registry.getAnchor(active, subjectId, role) returns (IDocumentBundleAnchor.AnchorRecord memory fetched) {
            record = fetched;
            current = _isCurrentRecord(record, active, subjectId, role);
        } catch {
            current = false;
        }
    }

    function _isCurrentRecord(
        IDocumentBundleAnchor.AnchorRecord memory record,
        bytes32 bundleHash,
        bytes32 subjectId,
        bytes32 role
    ) internal pure returns (bool) {
        return record.bundleHash == bundleHash
            && record.subjectId == subjectId
            && record.role == role
            && record.anchoredAt != 0
            && record.documentCount > 0
            && !record.superseded;
    }

    function _validateRoles(bytes32[] calldata roles) internal pure {
        if (roles.length == 0) revert EmptyRoleSet();
        if (roles.length > 256) revert TooManyRoles(roles.length);

        for (uint256 i = 0; i < roles.length; i++) {
            for (uint256 j = i + 1; j < roles.length; j++) {
                if (roles[i] == roles[j]) revert DuplicateRole(roles[i]);
            }
        }
    }
}
