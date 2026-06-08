// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {AnchorMetadataLib} from "../libraries/AnchorMetadataLib.sol";

interface IAssetAnchorRegistry {
    struct AnchorRecord {
        bytes32 anchorId;
        bytes32 legalHash;
        bytes32 evidenceHash;
        address boundToken;
        bytes32 bindingScope;
        uint256 boundTokenId;
        uint64 registeredAt;
        bool active;
    }

    event AnchorRegistered(bytes32 indexed anchorId, bytes32 legalHash, bytes32 evidenceHash);

    event TokenBound(bytes32 indexed anchorId, address indexed token, bytes32 indexed bindingScope, uint256 tokenId);

    event AnchorDeactivated(bytes32 indexed anchorId, string reason);

    event AnchorReattested(
        bytes32 indexed anchorId, uint64 oldExpiresAt, uint64 newExpiresAt, uint64 newAttestationDate
    );

    /// @notice Register a new anchor with dual hash references.
    /// @dev Reverts if the (legalHash, evidenceHash) pair is already registered in this registry.
    ///      Reverts if any required metadata field (assetClass, jurisdiction, attestationDate,
    ///      expiresAt, uri) is missing or empty.
    ///      The returned anchorId is suitable as a subjectId for any subject-keyed companion
    ///      standard, including document bundle anchoring (EIP-2), compliance event logging
    ///      (EIP-4), impact snapshot logging (EIP-5), and NAV oracle feeds (EIP-6).
    function registerAnchor(bytes32 legalHash, bytes32 evidenceHash, bytes calldata metadata)
        external
        returns (bytes32 anchorId);

    /// @notice Bind a token contract to an existing, unbound anchor.
    /// @dev Binding is permanent — reverts if the anchor is already bound.
    ///      Use the canonical contract binding scope for whole-contract binding and
    ///      the canonical token-ID binding scope for ERC-721/1155-style binding.
    ///      For contract scope, tokenId MUST be 0 as a canonical unused value.
    ///      For token-ID scope, tokenId 0 is a valid token-specific binding and
    ///      is not treated as a sentinel.
    function bindToken(bytes32 anchorId, address token, bytes32 bindingScope, uint256 tokenId) external;

    /// @notice Register and bind atomically to prevent front-running between
    ///         registration and binding.
    /// @dev Enforces the same uniqueness and binding rules as calling
    ///      registerAnchor + bindToken separately.
    function registerAndBind(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata,
        address token,
        bytes32 bindingScope,
        uint256 tokenId
    ) external returns (bytes32 anchorId);

    /// @notice Retrieve the full anchor record.
    /// @dev Reverts if anchorId does not exist in this registry.
    function getAnchor(bytes32 anchorId) external view returns (AnchorRecord memory);

    /// @notice Returns true whenever boundToken is non-zero, regardless of the active field.
    /// @dev isBound() returns true whenever boundToken is non-zero, regardless of the active
    ///      field. A deactivated anchor is still bound. Consumers checking operational status
    ///      SHOULD call isAnchorActive() on the token contract, not isBound() on the registry.
    function isBound(bytes32 anchorId) external view returns (bool);
}

interface IAssetAnchorRegistryLifecycle {
    /// @notice Returns the decoded metadata for an anchor.
    /// @dev Reverts if anchorId does not exist in this registry.
    function getMetadata(bytes32 anchorId) external view returns (AnchorMetadataLib.AnchorMetadata memory);

    /// @notice Returns the original registrar that created the anchor.
    /// @dev Reverts if anchorId does not exist in this registry.
    function registeredBy(bytes32 anchorId) external view returns (address);

    /// @notice Returns false if the anchor is manually deactivated or expired.
    /// @dev This reference lifecycle treats expiresAt as inclusive: an anchor is
    ///      active while block.timestamp <= expiresAt and expired when
    ///      block.timestamp > expiresAt.
    function isActive(bytes32 anchorId) external view returns (bool);

    /// @notice Permanently deactivates an anchor.
    /// @dev Manual deactivation MUST NOT be reversible by re-attestation.
    function deactivateAnchor(bytes32 anchorId, string calldata reason) external;

    /// @notice Updates the attestation date and expiry for an active anchor.
    /// @dev Reverts for manually deactivated anchors.
    function reattest(bytes32 anchorId, uint64 newExpiresAt, uint64 newAttestationDate) external;
}
