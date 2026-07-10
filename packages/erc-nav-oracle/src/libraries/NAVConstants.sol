// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

bytes32 constant PER_UNIT = keccak256("ERC-8330:NAV_BASIS:PER_UNIT");
bytes32 constant PER_SHARE = keccak256("ERC-8330:NAV_BASIS:PER_SHARE");
bytes32 constant TOTAL = keccak256("ERC-8330:NAV_BASIS:TOTAL");

bytes32 constant USD = keccak256("ERC-8330:CURRENCY:USD");
bytes32 constant EUR = keccak256("ERC-8330:CURRENCY:EUR");
bytes32 constant GBP = keccak256("ERC-8330:CURRENCY:GBP");
bytes32 constant KES = keccak256("ERC-8330:CURRENCY:KES");
bytes32 constant ZMW = keccak256("ERC-8330:CURRENCY:ZMW");

function deriveTokenCurrency(uint256 chainId, address tokenAddress) pure returns (bytes32) {
    return keccak256(abi.encodePacked("ERC-8330:CURRENCY:TOKEN", chainId, tokenAddress));
}
