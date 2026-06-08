// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {INAVAggregation} from "../interfaces/INAVAggregation.sol";
import {INAVSnapshotOracle, NO_CORRECTION} from "../interfaces/INAVSnapshotOracle.sol";
import {PER_SHARE, PER_UNIT, TOTAL} from "../libraries/NAVConstants.sol";

contract NAVSnapshotOracle is INAVSnapshotOracle, INAVAggregation {
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    uint256 public constant MAX_PROVIDERS_PER_VALUATION = 64;

    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant PROVIDER_ROLE = keccak256("PROVIDER");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG");

    struct StalenessConfig {
        uint64 heartbeat;
        uint64 maxValuationAge;
    }

    struct AggregationConfig {
        uint256 quorum;
        uint256 deviationThresholdBps;
    }

    struct PublishParams {
        bytes32 subjectId;
        bytes32 currency;
        bytes32 navBasis;
        int256 nav;
        uint8 decimals;
        uint64 valuationTimestamp;
        bytes32 methodologyHash;
        string methodologyURI;
        uint256 correctsIndex;
    }

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    mapping(bytes32 => mapping(address => bool)) private _roles;
    mapping(bytes32 => NAVSnapshot[]) private _snapshots;
    mapping(bytes32 => mapping(address => uint256[])) private _providerSnapshotIndices;
    mapping(bytes32 => StalenessConfig) private _stalenessConfigs;
    mapping(bytes32 => AggregationConfig) private _aggregationConfigs;
    mapping(bytes32 => uint256) private _latestStreamSnapshotPlusOne;
    mapping(bytes32 => mapping(address => uint256)) private _latestProviderSnapshotPlusOne;

    mapping(bytes32 => uint64[]) private _valuationTimestamps;
    mapping(bytes32 => mapping(uint64 => bool)) private _valuationTimestampSeen;
    mapping(bytes32 => mapping(uint64 => address[])) private _timestampProviders;
    mapping(bytes32 => mapping(uint64 => mapping(address => bool))) private _timestampProviderSeen;
    mapping(bytes32 => mapping(uint64 => mapping(address => uint256))) private _providerTimestampSnapshotPlusOne;
    mapping(bytes32 => uint64) private _latestEligibleTimestamp;
    mapping(bytes32 => bool) private _latestEligibleTimestampSet;

    constructor(address admin) {
        require(admin != address(0), "NAVSnapshotOracle: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PROVIDER_ROLE, admin);
        _grantRole(CONFIG_ROLE, admin);
    }

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "NAVSnapshotOracle: missing role");
        _;
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

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
    ) external onlyRole(PROVIDER_ROLE) returns (uint256 snapshotIndex) {
        PublishParams memory params = PublishParams({
            subjectId: subjectId,
            currency: currency,
            navBasis: navBasis,
            nav: nav,
            decimals: decimals,
            valuationTimestamp: valuationTimestamp,
            methodologyHash: methodologyHash,
            methodologyURI: methodologyURI,
            correctsIndex: correctsIndex
        });

        return _publishNAV(params);
    }

    function _publishNAV(PublishParams memory params) internal returns (uint256 snapshotIndex) {
        require(_isKnownBasis(params.navBasis), "NAVSnapshotOracle: unknown navBasis");
        require(params.decimals <= 18, "NAVSnapshotOracle: decimals too high");
        require(params.nav != type(int256).min, "NAVSnapshotOracle: unsupported nav");
        require(_abs(params.nav) <= _maxSafeAbsNAV(params.decimals), "NAVSnapshotOracle: nav too large");
        require(params.valuationTimestamp <= block.timestamp, "NAVSnapshotOracle: future valuation");
        require(params.methodologyHash != bytes32(0), "NAVSnapshotOracle: zero methodologyHash");
        require(block.timestamp <= type(uint64).max, "NAVSnapshotOracle: timestamp overflow");

        bytes32 streamKey = _streamKey(params.subjectId, params.currency);
        snapshotIndex = _snapshots[streamKey].length;
        uint256 existingPlusOne = _providerTimestampSnapshotPlusOne[streamKey][params.valuationTimestamp][msg.sender];

        if (params.correctsIndex == NO_CORRECTION) {
            require(existingPlusOne == 0, "NAVSnapshotOracle: duplicate submission");
        } else {
            require(params.correctsIndex < snapshotIndex, "NAVSnapshotOracle: correctsIndex out of range");
            NAVSnapshot storage target = _snapshots[streamKey][params.correctsIndex];
            require(target.correctedByIndex == 0, "NAVSnapshotOracle: target already corrected");
            require(target.provider == msg.sender, "NAVSnapshotOracle: provider mismatch");
            require(target.valuationTimestamp == params.valuationTimestamp, "NAVSnapshotOracle: valuation mismatch");
            require(target.navBasis == params.navBasis, "NAVSnapshotOracle: navBasis mismatch");
            require(
                existingPlusOne != 0 && existingPlusOne - 1 == params.correctsIndex,
                "NAVSnapshotOracle: correctsIndex not latest"
            );
            target.correctedByIndex = snapshotIndex;
        }

        _snapshots[streamKey].push(
            NAVSnapshot({
                subjectId: params.subjectId,
                currency: params.currency,
                navBasis: params.navBasis,
                nav: params.nav,
                decimals: params.decimals,
                valuationTimestamp: params.valuationTimestamp,
                publishedAt: uint64(block.timestamp),
                provider: msg.sender,
                methodologyHash: params.methodologyHash,
                methodologyURI: params.methodologyURI,
                correctsIndex: params.correctsIndex,
                correctedByIndex: 0
            })
        );

        _providerSnapshotIndices[streamKey][msg.sender].push(snapshotIndex);
        _recordProviderTimestamp(streamKey, params.valuationTimestamp, msg.sender, snapshotIndex);
        _updateLatestPointers(streamKey, msg.sender, snapshotIndex);
        _updateLatestEligibleTimestamp(streamKey, params.valuationTimestamp);

        emit NAVPublished(
            params.subjectId,
            params.currency,
            msg.sender,
            snapshotIndex,
            params.nav,
            params.decimals,
            params.navBasis,
            params.valuationTimestamp,
            params.methodologyHash,
            params.correctsIndex
        );

        _emitDeviationIfNeeded(streamKey, params.subjectId, params.currency, params.valuationTimestamp);
    }

    function setStalenessConfig(bytes32 subjectId, bytes32 currency, uint64 heartbeat_, uint64 maxValuationAge_)
        external
        onlyRole(CONFIG_ROLE)
    {
        require(heartbeat_ != 0, "NAVSnapshotOracle: zero heartbeat");
        require(maxValuationAge_ != 0, "NAVSnapshotOracle: zero maxValuationAge");

        _stalenessConfigs[_streamKey(subjectId, currency)] =
            StalenessConfig({heartbeat: heartbeat_, maxValuationAge: maxValuationAge_});

        emit StalenessConfigUpdated(subjectId, currency, heartbeat_, maxValuationAge_);
    }

    function setAggregationConfig(bytes32 subjectId, bytes32 currency, uint256 quorum_, uint256 deviationThresholdBps_)
        external
        onlyRole(CONFIG_ROLE)
    {
        require(quorum_ != 0, "NAVSnapshotOracle: zero quorum");
        require(quorum_ <= MAX_PROVIDERS_PER_VALUATION, "NAVSnapshotOracle: quorum too high");
        require(deviationThresholdBps_ <= 10_000, "NAVSnapshotOracle: deviationThresholdBps too high");

        bytes32 streamKey = _streamKey(subjectId, currency);
        _aggregationConfigs[streamKey] =
            AggregationConfig({quorum: quorum_, deviationThresholdBps: deviationThresholdBps_});
        _recomputeLatestEligibleTimestamp(streamKey);

        emit AggregationConfigUpdated(subjectId, currency, quorum_, deviationThresholdBps_);
    }

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
        )
    {
        NAVSnapshot storage snap = _latestSnapshot(_streamKey(subjectId, currency));
        return (snap.nav, snap.decimals, snap.navBasis, snap.valuationTimestamp, snap.publishedAt, snap.provider);
    }

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
        )
    {
        bytes32 streamKey = _streamKey(subjectId, currency);
        NAVSnapshot storage snap = _latestSnapshot(streamKey);
        (isPublishStale, isValuationStale) = _stalenessStatus(streamKey, snap.publishedAt, snap.valuationTimestamp);
        return (
            snap.nav,
            snap.decimals,
            snap.navBasis,
            snap.valuationTimestamp,
            snap.publishedAt,
            snap.provider,
            isPublishStale,
            isValuationStale
        );
    }

    function getSnapshot(bytes32 subjectId, bytes32 currency, uint256 snapshotIndex)
        external
        view
        returns (NAVSnapshot memory)
    {
        bytes32 streamKey = _streamKey(subjectId, currency);
        require(snapshotIndex < _snapshots[streamKey].length, "NAVSnapshotOracle: snapshotIndex out of range");
        return _snapshots[streamKey][snapshotIndex];
    }

    function snapshotCount(bytes32 subjectId, bytes32 currency) external view returns (uint256) {
        return _snapshots[_streamKey(subjectId, currency)].length;
    }

    function latestNAVByProvider(bytes32 subjectId, bytes32 currency, address provider)
        external
        view
        returns (NAVSnapshot memory)
    {
        bytes32 streamKey = _streamKey(subjectId, currency);
        uint256 latestPlusOne = _latestProviderSnapshotPlusOne[streamKey][provider];
        require(latestPlusOne != 0, "NAVSnapshotOracle: no provider snapshot");
        return _snapshots[streamKey][latestPlusOne - 1];
    }

    function providerSnapshotCount(bytes32 subjectId, bytes32 currency, address provider)
        external
        view
        returns (uint256)
    {
        return _providerSnapshotIndices[_streamKey(subjectId, currency)][provider].length;
    }

    function providerSnapshotAt(bytes32 subjectId, bytes32 currency, address provider, uint256 ordinal)
        external
        view
        returns (uint256 snapshotIndex)
    {
        uint256[] storage indices = _providerSnapshotIndices[_streamKey(subjectId, currency)][provider];
        require(ordinal < indices.length, "NAVSnapshotOracle: ordinal out of range");
        return indices[ordinal];
    }

    function heartbeat(bytes32 subjectId, bytes32 currency) external view returns (uint64) {
        return _stalenessConfigs[_streamKey(subjectId, currency)].heartbeat;
    }

    function maxValuationAge(bytes32 subjectId, bytes32 currency) external view returns (uint64) {
        return _stalenessConfigs[_streamKey(subjectId, currency)].maxValuationAge;
    }

    function aggregatedNAV(bytes32 subjectId, bytes32 currency)
        external
        view
        returns (
            int256 nav,
            uint8 decimals,
            bytes32 navBasis,
            uint64 valuationTimestamp,
            uint256 providerCount,
            bool isPublishStale,
            bool isValuationStale
        )
    {
        bytes32 streamKey = _streamKey(subjectId, currency);
        AggregatedSet memory set = _aggregatedSet(streamKey);
        (isPublishStale, isValuationStale) = _stalenessStatus(streamKey, set.latestPublishedAt, set.valuationTimestamp);
        return (
            set.medianNav,
            set.decimals,
            set.navBasis,
            set.valuationTimestamp,
            set.providerCount,
            isPublishStale,
            isValuationStale
        );
    }

    function providerSubmissionCount(bytes32 subjectId, bytes32 currency) external view returns (uint256) {
        bytes32 streamKey = _streamKey(subjectId, currency);
        uint64 timestamp = _latestAggregationTimestamp(streamKey);
        return _eligibleProviderCount(streamKey, timestamp);
    }

    function providerSubmissionAt(bytes32 subjectId, bytes32 currency, uint256 index)
        external
        view
        returns (
            uint256 snapshotIndex,
            address provider,
            int256 nav,
            uint8 decimals,
            bytes32 navBasis,
            uint64 valuationTimestamp,
            uint64 publishedAt
        )
    {
        bytes32 streamKey = _streamKey(subjectId, currency);
        uint64 timestamp = _latestAggregationTimestamp(streamKey);
        uint256 seen;
        address[] storage providers = _timestampProviders[streamKey][timestamp];

        for (uint256 i = 0; i < providers.length; i++) {
            uint256 plusOne = _providerTimestampSnapshotPlusOne[streamKey][timestamp][providers[i]];
            if (plusOne == 0) continue;
            NAVSnapshot storage snap = _snapshots[streamKey][plusOne - 1];
            if (snap.correctedByIndex != 0) continue;
            if (seen == index) {
                return (
                    plusOne - 1,
                    snap.provider,
                    snap.nav,
                    snap.decimals,
                    snap.navBasis,
                    snap.valuationTimestamp,
                    snap.publishedAt
                );
            }
            seen++;
        }

        revert("NAVSnapshotOracle: submission index out of range");
    }

    function latestAggregationTimestamp(bytes32 subjectId, bytes32 currency) external view returns (uint64) {
        return _latestAggregationTimestamp(_streamKey(subjectId, currency));
    }

    function quorum(bytes32 subjectId, bytes32 currency) external view returns (uint256) {
        return _aggregationConfigs[_streamKey(subjectId, currency)].quorum;
    }

    function deviationThreshold(bytes32 subjectId, bytes32 currency) external view returns (uint256) {
        return _aggregationConfigs[_streamKey(subjectId, currency)].deviationThresholdBps;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC165 || interfaceId == type(INAVSnapshotOracle).interfaceId
            || interfaceId == type(INAVAggregation).interfaceId;
    }

    struct AggregatedSet {
        int256 medianNav;
        uint8 decimals;
        bytes32 navBasis;
        uint64 valuationTimestamp;
        uint64 latestPublishedAt;
        uint256 providerCount;
        int256 minNav;
        int256 maxNav;
    }

    function _grantRole(bytes32 role, address account) internal {
        require(account != address(0), "NAVSnapshotOracle: zero account");
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _streamKey(bytes32 subjectId, bytes32 currency) internal pure returns (bytes32) {
        return keccak256(abi.encode(subjectId, currency));
    }

    function _isKnownBasis(bytes32 navBasis) internal pure returns (bool) {
        return navBasis == PER_UNIT || navBasis == PER_SHARE || navBasis == TOTAL;
    }

    function _maxSafeAbsNAV(uint8 decimals) internal pure returns (uint256) {
        return uint256(type(int256).max) / (10 ** uint256(18 - decimals));
    }

    function _recordProviderTimestamp(
        bytes32 streamKey,
        uint64 valuationTimestamp,
        address provider,
        uint256 snapshotIndex
    ) internal {
        if (!_valuationTimestampSeen[streamKey][valuationTimestamp]) {
            _valuationTimestampSeen[streamKey][valuationTimestamp] = true;
            _valuationTimestamps[streamKey].push(valuationTimestamp);
        }

        if (!_timestampProviderSeen[streamKey][valuationTimestamp][provider]) {
            require(
                _timestampProviders[streamKey][valuationTimestamp].length < MAX_PROVIDERS_PER_VALUATION,
                "NAVSnapshotOracle: provider cap exceeded"
            );
            _timestampProviderSeen[streamKey][valuationTimestamp][provider] = true;
            _timestampProviders[streamKey][valuationTimestamp].push(provider);
        }

        _providerTimestampSnapshotPlusOne[streamKey][valuationTimestamp][provider] = snapshotIndex + 1;
    }

    function _updateLatestPointers(bytes32 streamKey, address provider, uint256 snapshotIndex) internal {
        if (_isPreferredLatest(streamKey, _latestStreamSnapshotPlusOne[streamKey], snapshotIndex)) {
            _latestStreamSnapshotPlusOne[streamKey] = snapshotIndex + 1;
        }

        if (_isPreferredLatest(streamKey, _latestProviderSnapshotPlusOne[streamKey][provider], snapshotIndex)) {
            _latestProviderSnapshotPlusOne[streamKey][provider] = snapshotIndex + 1;
        }
    }

    function _isPreferredLatest(bytes32 streamKey, uint256 currentPlusOne, uint256 candidateIndex)
        internal
        view
        returns (bool)
    {
        if (currentPlusOne == 0) return true;
        NAVSnapshot storage current = _snapshots[streamKey][currentPlusOne - 1];
        NAVSnapshot storage candidate = _snapshots[streamKey][candidateIndex];

        if (current.correctedByIndex != 0) return true;
        if (candidate.valuationTimestamp > current.valuationTimestamp) return true;
        return
            candidate.valuationTimestamp == current.valuationTimestamp && candidate.publishedAt >= current.publishedAt;
    }

    function _latestSnapshot(bytes32 streamKey) internal view returns (NAVSnapshot storage) {
        uint256 latestPlusOne = _latestStreamSnapshotPlusOne[streamKey];
        require(latestPlusOne != 0, "NAVSnapshotOracle: no snapshots");
        return _snapshots[streamKey][latestPlusOne - 1];
    }

    function _stalenessStatus(bytes32 streamKey, uint64 publishedAt, uint64 valuationTimestamp)
        internal
        view
        returns (bool isPublishStale, bool isValuationStale)
    {
        StalenessConfig memory config = _stalenessConfigs[streamKey];
        require(config.heartbeat != 0, "NAVSnapshotOracle: heartbeat unconfigured");
        require(config.maxValuationAge != 0, "NAVSnapshotOracle: maxValuationAge unconfigured");

        isPublishStale = block.timestamp > uint256(publishedAt) + uint256(config.heartbeat);
        isValuationStale = block.timestamp > uint256(valuationTimestamp) + uint256(config.maxValuationAge);
    }

    function _latestAggregationTimestamp(bytes32 streamKey) internal view returns (uint64) {
        AggregationConfig memory config = _aggregationConfigs[streamKey];
        require(config.quorum != 0, "NAVSnapshotOracle: quorum unconfigured");
        if (_latestEligibleTimestampSet[streamKey]) return _latestEligibleTimestamp[streamKey];
        revert("NAVSnapshotOracle: quorum not met");
    }

    function _updateLatestEligibleTimestamp(bytes32 streamKey, uint64 valuationTimestamp) internal {
        AggregationConfig memory config = _aggregationConfigs[streamKey];
        if (config.quorum == 0) return;
        if (_eligibleProviderCount(streamKey, valuationTimestamp) < config.quorum) return;
        if (!_latestEligibleTimestampSet[streamKey] || valuationTimestamp > _latestEligibleTimestamp[streamKey]) {
            _latestEligibleTimestampSet[streamKey] = true;
            _latestEligibleTimestamp[streamKey] = valuationTimestamp;
        }
    }

    function _recomputeLatestEligibleTimestamp(bytes32 streamKey) internal {
        uint64[] storage timestamps = _valuationTimestamps[streamKey];
        AggregationConfig memory config = _aggregationConfigs[streamKey];
        bool found;
        uint64 latestTimestamp;

        for (uint256 i = 0; i < timestamps.length; i++) {
            uint64 timestamp = timestamps[i];
            if (
                _eligibleProviderCount(streamKey, timestamp) >= config.quorum && (!found || timestamp > latestTimestamp)
            ) {
                found = true;
                latestTimestamp = timestamp;
            }
        }

        if (found) {
            _latestEligibleTimestampSet[streamKey] = true;
            _latestEligibleTimestamp[streamKey] = latestTimestamp;
        } else {
            _latestEligibleTimestampSet[streamKey] = false;
            _latestEligibleTimestamp[streamKey] = 0;
        }
    }

    function _eligibleProviderCount(bytes32 streamKey, uint64 valuationTimestamp)
        internal
        view
        returns (uint256 count)
    {
        address[] storage providers = _timestampProviders[streamKey][valuationTimestamp];
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 plusOne = _providerTimestampSnapshotPlusOne[streamKey][valuationTimestamp][providers[i]];
            if (plusOne == 0) continue;
            if (_snapshots[streamKey][plusOne - 1].correctedByIndex == 0) count++;
        }
    }

    function _aggregatedSet(bytes32 streamKey) internal view returns (AggregatedSet memory set) {
        set.valuationTimestamp = _latestAggregationTimestamp(streamKey);
        address[] storage providers = _timestampProviders[streamKey][set.valuationTimestamp];
        uint256 providerCount_ = _eligibleProviderCount(streamKey, set.valuationTimestamp);
        int256[] memory values = new int256[](providerCount_);

        uint8 maxDecimals;
        bytes32 commonBasis;
        uint256 used;
        uint64 latestPublishedAt_;

        for (uint256 i = 0; i < providers.length; i++) {
            uint256 plusOne = _providerTimestampSnapshotPlusOne[streamKey][set.valuationTimestamp][providers[i]];
            if (plusOne == 0) continue;

            NAVSnapshot storage snap = _snapshots[streamKey][plusOne - 1];
            if (snap.correctedByIndex != 0) continue;

            if (used == 0) {
                commonBasis = snap.navBasis;
            } else {
                require(snap.navBasis == commonBasis, "NAVSnapshotOracle: mixed navBasis");
            }

            if (snap.decimals > maxDecimals) maxDecimals = snap.decimals;
            if (snap.publishedAt > latestPublishedAt_) latestPublishedAt_ = snap.publishedAt;

            values[used] = snap.nav;
            used++;
        }

        for (uint256 i = 0; i < providers.length; i++) {
            uint256 plusOne = _providerTimestampSnapshotPlusOne[streamKey][set.valuationTimestamp][providers[i]];
            if (plusOne == 0) continue;

            NAVSnapshot storage snap = _snapshots[streamKey][plusOne - 1];
            if (snap.correctedByIndex != 0) continue;

            values[--used] = _normalize(snap.nav, snap.decimals, maxDecimals);
        }

        _sort(values);

        set.medianNav = values[(values.length - 1) / 2];
        set.decimals = maxDecimals;
        set.navBasis = commonBasis;
        set.latestPublishedAt = latestPublishedAt_;
        set.providerCount = values.length;
        set.minNav = values[0];
        set.maxNav = values[values.length - 1];
    }

    function _emitDeviationIfNeeded(bytes32 streamKey, bytes32 subjectId, bytes32 currency, uint64 valuationTimestamp)
        internal
    {
        AggregationConfig memory config = _aggregationConfigs[streamKey];
        if (config.quorum == 0) return;
        if (_eligibleProviderCount(streamKey, valuationTimestamp) < config.quorum) return;
        if (_hasMixedBasis(streamKey, valuationTimestamp)) return;

        AggregatedSet memory set = _aggregatedSetForTimestamp(streamKey, valuationTimestamp);
        uint256 deviationBps_ = _deviationBps(set.minNav, set.maxNav, set.medianNav);
        if (deviationBps_ > config.deviationThresholdBps) {
            emit NAVDeviationDetected(subjectId, currency, valuationTimestamp, set.minNav, set.maxNav, deviationBps_);
        }
    }

    function _aggregatedSetForTimestamp(bytes32 streamKey, uint64 valuationTimestamp)
        internal
        view
        returns (AggregatedSet memory set)
    {
        address[] storage providers = _timestampProviders[streamKey][valuationTimestamp];
        uint256 providerCount_ = _eligibleProviderCount(streamKey, valuationTimestamp);
        int256[] memory values = new int256[](providerCount_);

        uint8 maxDecimals;
        bytes32 commonBasis;
        uint256 used;

        for (uint256 i = 0; i < providers.length; i++) {
            uint256 plusOne = _providerTimestampSnapshotPlusOne[streamKey][valuationTimestamp][providers[i]];
            if (plusOne == 0) continue;

            NAVSnapshot storage snap = _snapshots[streamKey][plusOne - 1];
            if (snap.correctedByIndex != 0) continue;

            if (used == 0) commonBasis = snap.navBasis;
            else require(snap.navBasis == commonBasis, "NAVSnapshotOracle: mixed navBasis");

            if (snap.decimals > maxDecimals) maxDecimals = snap.decimals;
            used++;
        }

        used = 0;
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 plusOne = _providerTimestampSnapshotPlusOne[streamKey][valuationTimestamp][providers[i]];
            if (plusOne == 0) continue;

            NAVSnapshot storage snap = _snapshots[streamKey][plusOne - 1];
            if (snap.correctedByIndex != 0) continue;

            values[used] = _normalize(snap.nav, snap.decimals, maxDecimals);
            used++;
        }

        _sort(values);

        set.medianNav = values[(values.length - 1) / 2];
        set.decimals = maxDecimals;
        set.navBasis = commonBasis;
        set.valuationTimestamp = valuationTimestamp;
        set.providerCount = values.length;
        set.minNav = values[0];
        set.maxNav = values[values.length - 1];
    }

    function _hasMixedBasis(bytes32 streamKey, uint64 valuationTimestamp) internal view returns (bool) {
        address[] storage providers = _timestampProviders[streamKey][valuationTimestamp];
        bytes32 commonBasis;
        bool basisSet;

        for (uint256 i = 0; i < providers.length; i++) {
            uint256 plusOne = _providerTimestampSnapshotPlusOne[streamKey][valuationTimestamp][providers[i]];
            if (plusOne == 0) continue;

            NAVSnapshot storage snap = _snapshots[streamKey][plusOne - 1];
            if (snap.correctedByIndex != 0) continue;

            if (!basisSet) {
                basisSet = true;
                commonBasis = snap.navBasis;
            } else if (snap.navBasis != commonBasis) {
                return true;
            }
        }

        return false;
    }

    function _normalize(int256 nav, uint8 fromDecimals, uint8 toDecimals) internal pure returns (int256) {
        if (fromDecimals == toDecimals) return nav;
        return nav * int256(10 ** uint256(toDecimals - fromDecimals));
    }

    function _sort(int256[] memory values) internal pure {
        for (uint256 i = 1; i < values.length; i++) {
            int256 key = values[i];
            uint256 j = i;
            while (j > 0 && values[j - 1] > key) {
                values[j] = values[j - 1];
                j--;
            }
            values[j] = key;
        }
    }

    function _deviationBps(int256 minNav, int256 maxNav, int256 medianNav) internal pure returns (uint256) {
        uint256 spread = _spread(minNav, maxNav);
        if (spread == 0) return 0;

        uint256 denominator = _abs(medianNav);
        if (denominator == 0) return type(uint256).max;
        if (spread > type(uint256).max / 10_000) return type(uint256).max;

        return (spread * 10_000) / denominator;
    }

    function _spread(int256 minNav, int256 maxNav) internal pure returns (uint256) {
        uint256 absMin = _abs(minNav);
        uint256 absMax = _abs(maxNav);

        if (minNav >= 0) return absMax - absMin;
        if (maxNav <= 0) return absMin - absMax;
        return absMax + absMin;
    }

    function _abs(int256 value) internal pure returns (uint256) {
        return uint256(value < 0 ? -value : value);
    }
}
