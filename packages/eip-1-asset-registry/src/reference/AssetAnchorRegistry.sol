// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAssetAnchorRegistry, IAssetAnchorRegistryLifecycle} from "../interfaces/IAssetAnchorRegistry.sol";
import {AssetRegistryConstants} from "../libraries/AssetRegistryConstants.sol";
import {AnchorMetadataLib} from "../libraries/AnchorMetadataLib.sol";

contract AssetAnchorRegistry is IAssetAnchorRegistry, IAssetAnchorRegistryLifecycle, AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR");

    mapping(bytes32 => AnchorRecord) private _records;
    mapping(bytes32 => AnchorMetadataLib.AnchorMetadata) private _metadata;
    mapping(bytes32 => address) private _registeredBy;
    mapping(bytes32 => bytes32) private _boundAnchorByTokenBinding;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function registerAnchor(bytes32 legalHash, bytes32 evidenceHash, bytes calldata metadata)
        external
        onlyRole(REGISTRAR_ROLE)
        returns (bytes32 anchorId)
    {
        return _register(legalHash, evidenceHash, metadata);
    }

    function bindToken(bytes32 anchorId, address token, bytes32 bindingScope, uint256 tokenId) external {
        AnchorRecord storage rec = _records[anchorId];
        require(rec.registeredAt != 0, "AssetAnchorRegistry: anchor not found");
        require(rec.boundToken == address(0), "AssetAnchorRegistry: already bound");
        require(token != address(0), "AssetAnchorRegistry: zero token address");
        _requireValidBindingScope(bindingScope, tokenId);
        require(rec.active, "AssetAnchorRegistry: anchor inactive");
        require(block.timestamp <= _metadata[anchorId].expiresAt, "AssetAnchorRegistry: anchor expired");
        require(
            _registeredBy[anchorId] == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "AssetAnchorRegistry: not authorized to bind"
        );
        _requireTokenRegistryAgreement(token);

        _bind(rec, anchorId, token, bindingScope, tokenId);
    }

    function registerAndBind(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata,
        address token,
        bytes32 bindingScope,
        uint256 tokenId
    ) external onlyRole(REGISTRAR_ROLE) returns (bytes32 anchorId) {
        require(token != address(0), "AssetAnchorRegistry: zero token address");
        _requireValidBindingScope(bindingScope, tokenId);
        _requireTokenRegistryAgreement(token);

        anchorId = _register(legalHash, evidenceHash, metadata);
        AnchorRecord storage rec = _records[anchorId];
        _bind(rec, anchorId, token, bindingScope, tokenId);
    }

    function getAnchor(bytes32 anchorId) external view returns (AnchorRecord memory) {
        require(_records[anchorId].registeredAt != 0, "AssetAnchorRegistry: anchor not found");
        return _records[anchorId];
    }

    function isBound(bytes32 anchorId) external view returns (bool) {
        return _records[anchorId].boundToken != address(0);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAssetAnchorRegistry).interfaceId
            || interfaceId == type(IAssetAnchorRegistryLifecycle).interfaceId || super.supportsInterface(interfaceId);
    }

    function _bind(AnchorRecord storage rec, bytes32 anchorId, address token, bytes32 bindingScope, uint256 tokenId)
        internal
    {
        bytes32 bindingKey = _tokenBindingKey(token, bindingScope, tokenId);
        require(
            _boundAnchorByTokenBinding[bindingKey] == bytes32(0), "AssetAnchorRegistry: token binding already bound"
        );

        rec.boundToken = token;
        rec.bindingScope = bindingScope;
        rec.boundTokenId = tokenId;
        _boundAnchorByTokenBinding[bindingKey] = anchorId;

        emit TokenBound(anchorId, token, bindingScope, tokenId);
    }

    function _requireValidBindingScope(bytes32 bindingScope, uint256 tokenId) internal pure {
        if (bindingScope == AssetRegistryConstants.BINDING_SCOPE_CONTRACT) {
            require(tokenId == 0, "AssetAnchorRegistry: contract scope tokenId must be 0");
            return;
        }

        if (bindingScope == AssetRegistryConstants.BINDING_SCOPE_TOKEN_ID) {
            return;
        }

        revert("AssetAnchorRegistry: invalid binding scope");
    }

    function _tokenBindingKey(address token, bytes32 bindingScope, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(token, bindingScope, tokenId));
    }

    /// @dev If the token declares anchorRegistry(), it must point back to this
    ///      registry. Plain ERC-20/721 tokens that don't implement the interface are allowed.
    function _requireTokenRegistryAgreement(address token) internal view {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("anchorRegistry()"));
        if (ok && data.length == 32) {
            address declared = abi.decode(data, (address));
            require(declared == address(this), "AssetAnchorRegistry: token registry mismatch");
        }
    }

    function _register(bytes32 legalHash, bytes32 evidenceHash, bytes calldata metadata)
        internal
        returns (bytes32 anchorId)
    {
        require(legalHash != bytes32(0), "AssetAnchorRegistry: zero legalHash");
        require(evidenceHash != bytes32(0), "AssetAnchorRegistry: zero evidenceHash");

        anchorId = keccak256(abi.encode(legalHash, evidenceHash));
        require(_records[anchorId].registeredAt == 0, "AssetAnchorRegistry: duplicate anchor");

        AnchorMetadataLib.AnchorMetadata memory meta = AnchorMetadataLib.decode(metadata);
        AnchorMetadataLib.validate(meta);

        require(meta.attestationDate <= block.timestamp, "AssetAnchorRegistry: future attestation date");
        require(meta.attestationDate < meta.expiresAt, "AssetAnchorRegistry: expiresAt not after attestationDate");
        require(block.timestamp <= meta.expiresAt, "AssetAnchorRegistry: metadata already expired");

        _records[anchorId] = AnchorRecord({
            anchorId: anchorId,
            legalHash: legalHash,
            evidenceHash: evidenceHash,
            boundToken: address(0),
            bindingScope: bytes32(0),
            boundTokenId: 0,
            registeredAt: uint64(block.timestamp),
            active: true
        });
        _metadata[anchorId] = meta;
        _registeredBy[anchorId] = msg.sender;

        emit AnchorRegistered(anchorId, legalHash, evidenceHash);
    }

    /// @notice Permanently deactivates an anchor. Cannot be reversed by re-attestation.
    function deactivateAnchor(bytes32 anchorId, string calldata reason) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AnchorRecord storage rec = _records[anchorId];
        require(rec.registeredAt != 0, "AssetAnchorRegistry: anchor not found");
        require(rec.active, "AssetAnchorRegistry: already deactivated");

        rec.active = false;
        emit AnchorDeactivated(anchorId, reason);
    }

    /// @notice Update expiresAt for re-attestation. Reverts if the anchor is manually deactivated.
    function reattest(bytes32 anchorId, uint64 newExpiresAt, uint64 newAttestationDate) external {
        AnchorRecord storage rec = _records[anchorId];
        require(rec.registeredAt != 0, "AssetAnchorRegistry: anchor not found");
        require(rec.active, "AssetAnchorRegistry: manually deactivated");
        require(
            _registeredBy[anchorId] == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "AssetAnchorRegistry: not authorized to reattest"
        );
        require(newExpiresAt > block.timestamp, "AssetAnchorRegistry: expiresAt must be future");
        require(newAttestationDate != 0, "AssetAnchorRegistry: zero attestation date");
        require(newAttestationDate <= block.timestamp, "AssetAnchorRegistry: future attestation date");
        require(newAttestationDate < newExpiresAt, "AssetAnchorRegistry: expiresAt not after attestationDate");

        AnchorMetadataLib.AnchorMetadata storage meta = _metadata[anchorId];
        uint64 oldExpiresAt = meta.expiresAt;
        meta.expiresAt = newExpiresAt;
        meta.attestationDate = newAttestationDate;

        emit AnchorReattested(anchorId, oldExpiresAt, newExpiresAt, newAttestationDate);
    }

    /// @notice Returns the decoded metadata for an anchor.
    function getMetadata(bytes32 anchorId) external view returns (AnchorMetadataLib.AnchorMetadata memory) {
        require(_records[anchorId].registeredAt != 0, "AssetAnchorRegistry: anchor not found");
        return _metadata[anchorId];
    }

    /// @notice Returns the original registrar that created the anchor.
    function registeredBy(bytes32 anchorId) external view returns (address) {
        require(_records[anchorId].registeredAt != 0, "AssetAnchorRegistry: anchor not found");
        return _registeredBy[anchorId];
    }

    /// @notice Returns false if active == false (manual deactivation) OR block.timestamp > expiresAt.
    ///         Manual deactivation takes precedence — reattest() reverts on a deactivated anchor.
    function isActive(bytes32 anchorId) external view returns (bool) {
        AnchorRecord storage rec = _records[anchorId];
        if (!rec.active) return false;
        return block.timestamp <= _metadata[anchorId].expiresAt;
    }
}
