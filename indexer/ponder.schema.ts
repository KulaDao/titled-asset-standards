import { onchainTable } from "ponder";

// --- eip-1: AssetAnchorRegistry ---

export const anchorRegistered = onchainTable("anchor_registered", (t) => ({
  id: t.text().primaryKey(),
  anchorId: t.hex().notNull(),
  legalHash: t.hex().notNull(),
  evidenceHash: t.hex().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const tokenBound = onchainTable("token_bound", (t) => ({
  id: t.text().primaryKey(),
  anchorId: t.hex().notNull(),
  token: t.hex().notNull(),
  tokenId: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const anchorDeactivated = onchainTable("anchor_deactivated", (t) => ({
  id: t.text().primaryKey(),
  anchorId: t.hex().notNull(),
  reason: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const anchorReattested = onchainTable("anchor_reattested", (t) => ({
  id: t.text().primaryKey(),
  anchorId: t.hex().notNull(),
  oldExpiresAt: t.bigint().notNull(),
  newExpiresAt: t.bigint().notNull(),
  newAttestationDate: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

// --- eip-2: DocumentBundleAnchor ---

export const bundleAnchored = onchainTable("bundle_anchored", (t) => ({
  id: t.text().primaryKey(),
  bundleHash: t.hex().notNull(),
  subjectId: t.hex().notNull(),
  role: t.hex().notNull(),
  documentCount: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const bundleSuperseded = onchainTable("bundle_superseded", (t) => ({
  id: t.text().primaryKey(),
  oldBundleHash: t.hex().notNull(),
  newBundleHash: t.hex().notNull(),
  subjectId: t.hex().notNull(),
  role: t.hex().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

// --- eip-3: TransferDomainRegistry / GracefulTransferDomainRegistry ---

export const routeSet = onchainTable("route_set", (t) => ({
  id: t.text().primaryKey(),
  sourceDomain: t.hex().notNull(),
  destinationDomain: t.hex().notNull(),
  assetClass: t.hex().notNull(),
  permissionEvidenceHash: t.hex().notNull(),
  effectiveAt: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const routeRevoked = onchainTable("route_revoked", (t) => ({
  id: t.text().primaryKey(),
  sourceDomain: t.hex().notNull(),
  destinationDomain: t.hex().notNull(),
  assetClass: t.hex().notNull(),
  revocationEvidenceHash: t.hex().notNull(),
  effectiveAt: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const routeRevocationInitiated = onchainTable("route_revocation_initiated", (t) => ({
  id: t.text().primaryKey(),
  sourceDomain: t.hex().notNull(),
  destinationDomain: t.hex().notNull(),
  assetClass: t.hex().notNull(),
  revocationEvidenceHash: t.hex().notNull(),
  initiatedAt: t.bigint().notNull(),
  effectiveAt: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const routeRevocationCancelled = onchainTable("route_revocation_cancelled", (t) => ({
  id: t.text().primaryKey(),
  sourceDomain: t.hex().notNull(),
  destinationDomain: t.hex().notNull(),
  assetClass: t.hex().notNull(),
  cancellationEvidenceHash: t.hex().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

// --- eip-4: ComplianceEventLog ---

export const complianceEventRecorded = onchainTable("compliance_event_recorded", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  eventType: t.hex().notNull(),
  actor: t.hex().notNull(),
  eventIndex: t.bigint().notNull(),
  outcome: t.hex().notNull(),
  authority: t.hex().notNull(),
  occurredAt: t.bigint().notNull(),
  correctsIndex: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

// --- eip-5: ImpactSnapshotLog ---

export const snapshotRecorded = onchainTable("snapshot_recorded", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  indicatorId: t.hex().notNull(),
  snapshotIndex: t.bigint().notNull(),
  value: t.bigint().notNull(),
  decimals: t.integer().notNull(),
  unit: t.hex().notNull(),
  periodStart: t.bigint().notNull(),
  periodEnd: t.bigint().notNull(),
  methodologyHash: t.hex().notNull(),
  correctsIndex: t.bigint().notNull(),
  reportedBy: t.hex().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const snapshotAttested = onchainTable("snapshot_attested", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  snapshotIndex: t.bigint().notNull(),
  attestor: t.hex().notNull(),
  endorsed: t.boolean().notNull(),
  evidenceHash: t.hex().notNull(),
  attestationIndex: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const methodologySuperseded = onchainTable("methodology_superseded", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  indicatorId: t.hex().notNull(),
  oldMethodologyHash: t.hex().notNull(),
  newMethodologyHash: t.hex().notNull(),
  effectiveFromOrdinal: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

// --- eip-6: NAVSnapshotOracle ---

export const navPublished = onchainTable("nav_published", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  currency: t.hex().notNull(),
  provider: t.hex().notNull(),
  snapshotIndex: t.bigint().notNull(),
  nav: t.bigint().notNull(),
  decimals: t.integer().notNull(),
  navBasis: t.hex().notNull(),
  valuationTimestamp: t.bigint().notNull(),
  methodologyHash: t.hex().notNull(),
  correctsIndex: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const navDeviationDetected = onchainTable("nav_deviation_detected", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  currency: t.hex().notNull(),
  valuationTimestamp: t.bigint().notNull(),
  minNav: t.bigint().notNull(),
  maxNav: t.bigint().notNull(),
  deviationBps: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const stalenessConfigUpdated = onchainTable("staleness_config_updated", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  currency: t.hex().notNull(),
  heartbeat: t.bigint().notNull(),
  maxValuationAge: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));

export const aggregationConfigUpdated = onchainTable("aggregation_config_updated", (t) => ({
  id: t.text().primaryKey(),
  subjectId: t.hex().notNull(),
  currency: t.hex().notNull(),
  quorum: t.bigint().notNull(),
  deviationThresholdBps: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  blockTimestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
  logIndex: t.integer().notNull(),
}));
