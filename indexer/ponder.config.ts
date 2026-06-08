import { createConfig } from "ponder";

import { AssetAnchorRegistryAbi } from "./abis/AssetAnchorRegistryAbi";
import { ComplianceEventLogAbi } from "./abis/ComplianceEventLogAbi";
import { DocumentBundleAnchorAbi } from "./abis/DocumentBundleAnchorAbi";
import { GracefulTransferDomainRegistryAbi } from "./abis/GracefulTransferDomainRegistryAbi";
import { ImpactSnapshotLogAbi } from "./abis/ImpactSnapshotLogAbi";
import { NAVSnapshotOracleAbi } from "./abis/NAVSnapshotOracleAbi";
import { TransferDomainRegistryAbi } from "./abis/TransferDomainRegistryAbi";

export default createConfig({
  chains: {
    sepolia: {
      id: 11155111,
      rpc: process.env.PONDER_RPC_URL_SEPOLIA!,
    },
  },
  contracts: {
    AssetAnchorRegistry: {
      chain: "sepolia",
      abi: AssetAnchorRegistryAbi,
      address: "0x2b0578497ced999000518e3786d4a5ac16fdf00e",
      startBlock: 10940573,
    },
    DocumentBundleAnchor: {
      chain: "sepolia",
      abi: DocumentBundleAnchorAbi,
      address: "0xae867f34603D64fFdF65c7341CACcca6331A9f93",
      startBlock: 11017179,
    },
    TransferDomainRegistry: {
      chain: "sepolia",
      abi: TransferDomainRegistryAbi,
      address: "0x55c4eD8ed404CC42165f6d47962184f47Cb89B91",
      startBlock: 11017207,
    },
    GracefulTransferDomainRegistry: {
      chain: "sepolia",
      abi: GracefulTransferDomainRegistryAbi,
      address: "0x53F9c30FF7Eb7089B22f6E44937a075cA80b92E9",
      startBlock: 11017207,
    },
    ComplianceEventLog: {
      chain: "sepolia",
      abi: ComplianceEventLogAbi,
      address: "0x8276024a0e738FA25D40Fb6e232b36446a68b1C6",
      startBlock: 11017210,
    },
    ImpactSnapshotLog: {
      chain: "sepolia",
      abi: ImpactSnapshotLogAbi,
      address: "0x0e3266c4Ce3CAb97430677288B1E8Ae9D9ab41C6",
      startBlock: 11017427,
    },
    NAVSnapshotOracle: {
      chain: "sepolia",
      abi: NAVSnapshotOracleAbi,
      address: "0x7F0640Fc6a7d7bDDA4E865C4076Bb20841Eb256e",
      startBlock: 11017219,
    },
  },
});
