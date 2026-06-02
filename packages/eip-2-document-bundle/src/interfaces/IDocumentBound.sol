// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IDocumentBound
/// @notice Interface for tokens that require on-chain document bundles for
///         compliance. A document-bound token declares the registry it reads
///         from and the subject ID under which its bundles are anchored.
///
/// @dev    Compliant tokens MUST:
///         - Return an immutable registry address from documentRegistry()
///         - Return an immutable subjectId from documentSubjectId()
///         - Gate transfers on the required document roles having active bundles
///
///         The subjectId is typically the EIP-1 anchorId of the underlying
///         real-world asset, creating a three-layer identity:
///           EIP-1 anchorId  →  asset registered
///           EIP-2 subjectId →  compliance docs anchored
///           EIP-2 token     →  tradeable representation
interface IDocumentBound {

    /// @notice The document bundle anchor registry this token reads from.
    /// @dev MUST be immutable after deployment.
    function documentRegistry() external view returns (address);

    /// @notice The subject ID used to look up this token's document bundles.
    /// @dev MUST be immutable after deployment.
    ///      For whole-contract tokens (ERC-20): one shared subjectId.
    ///      For per-token contracts (ERC-721): each tokenId has its own subjectId.
    function documentSubjectId() external view returns (bytes32);

    /// @notice Per-token subject ID for collections where each NFT is a separate asset.
    /// @dev MUST revert for whole-contract tokens. MUST revert for unbound tokenIds.
    function documentSubjectIdOf(uint256 tokenId) external view returns (bytes32);

    /// @notice Standard detection — returns true for all compliant tokens.
    function isDocumentBound() external pure returns (bool);

    /// @notice Check whether the required document bundle for a given role is active.
    /// @dev Returns false if no active bundle exists or if the bundle was superseded.
    function hasActiveDocumentBundle(bytes32 role) external view returns (bool);

    /// @notice Check a specific tokenId's document bundle status (per-token binding).
    function hasActiveDocumentBundleFor(uint256 tokenId, bytes32 role) external view returns (bool);
}
