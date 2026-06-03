// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TransferRouteLib {
    /// @notice Canonical storage key for a directional route.
    function routeKey(bytes32 sourceDomain, bytes32 destinationDomain, bytes32 assetClass)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(sourceDomain, destinationDomain, assetClass));
    }
}
