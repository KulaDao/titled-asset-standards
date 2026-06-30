// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

uint256 constant NO_CORRECTION = type(uint256).max;
uint256 constant NO_CORRECTED_BY = 0;

interface INAVSnapshotOracle {
    struct NAVSnapshot {
        bytes32 subjectId;
        bytes32 currency;
        bytes32 navBasis;
        int256 nav;
        uint8 decimals;
        uint64 valuationTimestamp;
        uint64 publishedAt;
        address provider;
        bytes32 methodologyHash;
        string methodologyURI;
        uint256 correctsIndex; // NO_CORRECTION means original/non-correction snapshot.
        uint256 correctedByIndex; // NO_CORRECTED_BY means this snapshot has no successor correction.
    }

    event NAVPublished(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        address indexed provider,
        uint256 snapshotIndex,
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        uint256 correctsIndex
    );

    event StalenessConfigUpdated(
        bytes32 indexed subjectId, bytes32 indexed currency, uint64 heartbeat, uint64 maxValuationAge
    );

    event NAVBasisConfigured(bytes32 indexed subjectId, bytes32 indexed currency, bytes32 navBasis);

    event NAVSnapshotInvalidated(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        address indexed provider,
        uint256 snapshotIndex,
        address invalidatedBy,
        bytes32 reasonHash
    );

    /// @dev MUST reject methodologyHash == bytes32(0). methodologyURI MAY be empty
    ///      only if the implementation documents how verifiers retrieve the methodology.
    ///      MUST reject if the stream NAV basis is unconfigured or if navBasis does
    ///      not match the stream's configured NAV basis.
    function publishNAV(
        bytes32 subjectId,
        bytes32 currency,
        bytes32 navBasis,
        int256 nav,
        uint8 decimals,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        string calldata methodologyURI,
        uint256 correctsIndex
    ) external returns (uint256 snapshotIndex);

    function setNAVBasis(bytes32 subjectId, bytes32 currency, bytes32 navBasis) external;

    /// @notice Administratively invalidate a terminal snapshot without rewriting history.
    /// @dev Implementations MUST exclude invalidated snapshots from latest-value and
    ///      aggregation queries and MUST preserve the original snapshot record.
    function invalidateSnapshot(bytes32 subjectId, bytes32 currency, uint256 snapshotIndex, bytes32 reasonHash) external;

    function isSnapshotInvalidated(bytes32 subjectId, bytes32 currency, uint256 snapshotIndex)
        external
        view
        returns (bool);

    function setStalenessConfig(bytes32 subjectId, bytes32 currency, uint64 heartbeat, uint64 maxValuationAge) external;

    function streamNAVBasis(bytes32 subjectId, bytes32 currency) external view returns (bytes32 navBasis);

    function latestNAV(bytes32 subjectId, bytes32 currency)
        external
        view
        returns (
            int256 nav,
            uint8 decimals,
            bytes32 navBasis,
            uint64 valuationTimestamp,
            uint64 publishedAt,
            address provider
        );

    function latestNAVStatus(bytes32 subjectId, bytes32 currency)
        external
        view
        returns (
            int256 nav,
            uint8 decimals,
            bytes32 navBasis,
            uint64 valuationTimestamp,
            uint64 publishedAt,
            address provider,
            bool isPublishStale,
            bool isValuationStale
        );

    function getSnapshot(bytes32 subjectId, bytes32 currency, uint256 snapshotIndex)
        external
        view
        returns (NAVSnapshot memory);

    /// @notice Resolve the terminal snapshot in a correction chain.
    /// @dev MUST revert if snapshotIndex >= snapshotCount or the resolved terminal
    ///      snapshot has been invalidated and no current terminal remains.
    ///      Follows correctedByIndex until it reaches NO_CORRECTED_BY.
    function currentSnapshotIndex(bytes32 subjectId, bytes32 currency, uint256 snapshotIndex)
        external
        view
        returns (uint256);

    /// @notice Return true when snapshotIndex is terminal and has not been invalidated.
    /// @dev MUST revert if snapshotIndex >= snapshotCount.
    function isSnapshotCurrent(bytes32 subjectId, bytes32 currency, uint256 snapshotIndex) external view returns (bool);

    function snapshotCount(bytes32 subjectId, bytes32 currency) external view returns (uint256);

    function latestNAVByProvider(bytes32 subjectId, bytes32 currency, address provider)
        external
        view
        returns (NAVSnapshot memory);

    function providerSnapshotCount(bytes32 subjectId, bytes32 currency, address provider)
        external
        view
        returns (uint256);

    function providerSnapshotAt(bytes32 subjectId, bytes32 currency, address provider, uint256 ordinal)
        external
        view
        returns (uint256 snapshotIndex);

    function heartbeat(bytes32 subjectId, bytes32 currency) external view returns (uint64);

    function maxValuationAge(bytes32 subjectId, bytes32 currency) external view returns (uint64);
}
