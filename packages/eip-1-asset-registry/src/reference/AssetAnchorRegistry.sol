// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAssetAnchorRegistry} from "../interfaces/IAssetAnchorRegistry.sol";
import {AnchorMetadataLib} from "../libraries/AnchorMetadataLib.sol";

contract AssetAnchorRegistry is IAssetAnchorRegistry, AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR");

    mapping(bytes32 => AnchorRecord)                     private _records;
    mapping(bytes32 => AnchorMetadataLib.AnchorMetadata) private _metadata;
    mapping(bytes32 => address)                          private _registeredBy;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function registerAnchor(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata
    ) external onlyRole(REGISTRAR_ROLE) returns (bytes32 anchorId) {
        return _register(legalHash, evidenceHash, metadata);
    }

    function bindToken(
        bytes32 anchorId,
        address token,
        uint256 tokenId
    ) external {
        AnchorRecord storage rec = _records[anchorId];
        require(rec.registeredAt != 0,        "AssetAnchorRegistry: anchor not found");
        require(rec.boundToken == address(0),  "AssetAnchorRegistry: already bound");
        require(token != address(0),           "AssetAnchorRegistry: zero token address");
        require(
            _registeredBy[anchorId] == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "AssetAnchorRegistry: not authorized to bind"
        );

        rec.boundToken   = token;
        rec.boundTokenId = tokenId;

        emit TokenBound(anchorId, token, tokenId);
    }

    function registerAndBind(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata,
        address token,
        uint256 tokenId
    ) external onlyRole(REGISTRAR_ROLE) returns (bytes32 anchorId) {
        require(token != address(0), "AssetAnchorRegistry: zero token address");

        anchorId = _register(legalHash, evidenceHash, metadata);
        AnchorRecord storage rec = _records[anchorId];
        rec.boundToken   = token;
        rec.boundTokenId = tokenId;

        emit TokenBound(anchorId, token, tokenId);
    }

    function getAnchor(bytes32 anchorId)
        external view returns (AnchorRecord memory)
    {
        require(_records[anchorId].registeredAt != 0, "AssetAnchorRegistry: anchor not found");
        return _records[anchorId];
    }

    function isBound(bytes32 anchorId) external view returns (bool) {
        return _records[anchorId].boundToken != address(0);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override returns (bool)
    {
        return interfaceId == type(IAssetAnchorRegistry).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _register(
        bytes32 legalHash,
        bytes32 evidenceHash,
        bytes calldata metadata
    ) internal returns (bytes32 anchorId) {
        anchorId = keccak256(abi.encode(legalHash, evidenceHash));
        require(_records[anchorId].registeredAt == 0, "AssetAnchorRegistry: duplicate anchor");

        AnchorMetadataLib.AnchorMetadata memory meta = AnchorMetadataLib.decode(metadata);
        AnchorMetadataLib.validate(meta);

        _records[anchorId] = AnchorRecord({
            anchorId:     anchorId,
            legalHash:    legalHash,
            evidenceHash: evidenceHash,
            boundToken:   address(0),
            boundTokenId: 0,
            registeredAt: uint64(block.timestamp),
            active:       true
        });
        _metadata[anchorId]     = meta;
        _registeredBy[anchorId] = msg.sender;

        emit AnchorRegistered(anchorId, legalHash, evidenceHash);
    }
}
