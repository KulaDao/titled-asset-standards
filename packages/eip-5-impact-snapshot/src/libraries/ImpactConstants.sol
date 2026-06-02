// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

// Indicator identifiers
bytes32 constant CARBON_OFFSET     = keccak256("EIP-XXXX:INDICATOR:CARBON_OFFSET");
bytes32 constant CARBON_EMITTED    = keccak256("EIP-XXXX:INDICATOR:CARBON_EMITTED");
bytes32 constant ENERGY_GENERATED  = keccak256("EIP-XXXX:INDICATOR:ENERGY_GENERATED");
bytes32 constant ENERGY_SAVED      = keccak256("EIP-XXXX:INDICATOR:ENERGY_SAVED");
bytes32 constant WATER_TREATED     = keccak256("EIP-XXXX:INDICATOR:WATER_TREATED");
bytes32 constant JOBS_CREATED      = keccak256("EIP-XXXX:INDICATOR:JOBS_CREATED");
bytes32 constant BENEFICIARIES     = keccak256("EIP-XXXX:INDICATOR:BENEFICIARIES");
bytes32 constant BIODIVERSITY_AREA = keccak256("EIP-XXXX:INDICATOR:BIODIVERSITY_AREA");
bytes32 constant WASTE_DIVERTED    = keccak256("EIP-XXXX:INDICATOR:WASTE_DIVERTED");

// Unit identifiers
bytes32 constant UNIT_TCO2E   = keccak256("tCO2e");
bytes32 constant UNIT_KWH     = keccak256("kWh");
bytes32 constant UNIT_M3      = keccak256("m3");
bytes32 constant UNIT_FTE     = keccak256("FTE");
bytes32 constant UNIT_PERSONS = keccak256("persons");
bytes32 constant UNIT_HECTARES = keccak256("hectares");
bytes32 constant UNIT_TONNES  = keccak256("tonnes");
