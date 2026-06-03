// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IMethodologyVersioning {
    event MethodologySuperseded(
        bytes32 indexed subjectId,
        bytes32 indexed indicatorId,
        bytes32 oldMethodologyHash,
        bytes32 newMethodologyHash,
        uint256 effectiveFromOrdinal
    );

    function supersedeMethodology(
        bytes32        subjectId,
        bytes32        indicatorId,
        bytes32        oldMethodologyHash,
        bytes32        newMethodologyHash,
        string calldata newMethodologyURI,
        uint256        effectiveFromOrdinal
    ) external;

    function activeMethodology(bytes32 subjectId, bytes32 indicatorId)
        external view returns (bytes32 methodologyHash, string memory methodologyURI);
}
