// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IAssetAnchorRegistry {

    struct AnchorRecord {
        bytes32 anchorId;
        bytes32 legalHash;
        bytes32 evidenceHash;
        address boundToken;
        uint256 boundTokenId;
        uint64  registeredAt;
        bool    active;
    }

    event AnchorRegistered(
        bytes32 indexed anchorId,
        bytes32 legalHash,
        bytes32 evidenceHash
    );

    event TokenBound(
        bytes32 indexed anchorId,
        address indexed token,
        uint256 tokenId
    );

    event AnchorDeactivated(
        bytes32 indexed anchorId,
        string reason
    );

    /// @notice Register a new anchor with dual hash references.
    /// @dev Reverts if the (legalHash, evidenceHash) pair is already registered in this registry.
    ///      Reverts if any required metadata field (assetClass, jurisdiction, attestationDate,
    ///      expiresAt, uri) is missing or empty.
    ///      The returned anchorId is suitable as a subjectId for any subject-keyed companion
    ///      standard, including document bundle anchoring (EIP-3), impact snapshot logging
    ///      (EIP-4), NAV oracle feeds (EIP-5), and compliance event logging (EIP-6).
    function registerAnchor(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata
    ) external returns (bytes32 anchorId);

    /// @notice Bind a token contract to an existing, unbound anchor.
    /// @dev Binding is permanent — reverts if the anchor is already bound.
    ///      For whole-contract binding (ERC-20), pass tokenId = 0.
    function bindToken(
        bytes32 anchorId,
        address token,
        uint256 tokenId
    ) external;

    /// @notice Register and bind atomically to prevent front-running between
    ///         registration and binding.
    /// @dev Enforces the same uniqueness and binding rules as calling
    ///      registerAnchor + bindToken separately.
    function registerAndBind(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata,
        address token,
        uint256 tokenId
    ) external returns (bytes32 anchorId);

    /// @notice Retrieve the full anchor record.
    /// @dev Reverts if anchorId does not exist in this registry.
    function getAnchor(bytes32 anchorId)
        external view returns (AnchorRecord memory);

    /// @notice Returns true whenever boundToken is non-zero, regardless of the active field.
    /// @dev isBound() returns true whenever boundToken is non-zero, regardless of the active
    ///      field. A deactivated anchor is still bound. Consumers checking operational status
    ///      SHOULD call isAnchorActive() on the token contract, not isBound() on the registry.
    function isBound(bytes32 anchorId) external view returns (bool);
}
