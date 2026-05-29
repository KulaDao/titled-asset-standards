// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IAssetBoundToken {

    /// @notice The anchor this token is bound to (whole-contract binding).
    /// @dev For ERC-20 tokens where the entire contract represents one asset.
    ///      MUST be immutable after contract deployment.
    function anchorId() external view returns (bytes32);

    /// @notice The anchor a specific tokenId is bound to (per-token binding).
    /// @dev For ERC-721/1155 tokens where each tokenId represents a separate asset.
    ///      MUST revert if tokenId is not bound.
    function anchorIdOf(uint256 tokenId) external view returns (bytes32);

    /// @notice The registry that holds the binding record.
    /// @dev MUST be immutable after contract deployment.
    function anchorRegistry() external view returns (address);

    /// @notice Standard detection — returns true for all compliant tokens.
    function isAssetBound() external pure returns (bool);

    /// @notice Check whether the bound anchor is still active (whole-contract binding).
    /// @dev Returns false when the anchor has expired OR been manually deactivated.
    ///      Manual deactivation takes precedence — a manually deactivated anchor
    ///      MUST NOT be restored by re-attestation.
    function isAnchorActive() external view returns (bool);

    /// @notice Check whether a specific tokenId's anchor is still active (per-token binding).
    function isAnchorActiveFor(uint256 tokenId) external view returns (bool);
}
