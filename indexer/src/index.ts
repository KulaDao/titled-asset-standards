import { ponder } from "ponder:registry";

import * as schema from "../ponder.schema";

type LogEvent = {
  log: { logIndex: number };
  block: { number: bigint; timestamp: bigint };
  transaction: { hash: `0x${string}` };
};

const logMeta = (event: LogEvent) => ({
  blockNumber: event.block.number,
  blockTimestamp: event.block.timestamp,
  transactionHash: event.transaction.hash,
  logIndex: event.log.logIndex,
});

// --- eip-1: AssetAnchorRegistry ---

ponder.on("AssetAnchorRegistry:AnchorRegistered", async ({ event, context }) => {
  await context.db.insert(schema.anchorRegistered).values({
    id: event.id,
    anchorId: event.args.anchorId,
    legalHash: event.args.legalHash,
    evidenceHash: event.args.evidenceHash,
    ...logMeta(event),
  });
});

ponder.on("AssetAnchorRegistry:TokenBound", async ({ event, context }) => {
  await context.db.insert(schema.tokenBound).values({
    id: event.id,
    anchorId: event.args.anchorId,
    token: event.args.token,
    tokenId: event.args.tokenId,
    ...logMeta(event),
  });
});

ponder.on("AssetAnchorRegistry:AnchorDeactivated", async ({ event, context }) => {
  await context.db.insert(schema.anchorDeactivated).values({
    id: event.id,
    anchorId: event.args.anchorId,
    reason: event.args.reason,
    ...logMeta(event),
  });
});

ponder.on("AssetAnchorRegistry:AnchorReattested", async ({ event, context }) => {
  await context.db.insert(schema.anchorReattested).values({
    id: event.id,
    anchorId: event.args.anchorId,
    oldExpiresAt: event.args.oldExpiresAt,
    newExpiresAt: event.args.newExpiresAt,
    newAttestationDate: event.args.newAttestationDate,
    ...logMeta(event),
  });
});

// --- eip-2: DocumentBundleAnchor ---

ponder.on("DocumentBundleAnchor:BundleAnchored", async ({ event, context }) => {
  await context.db.insert(schema.bundleAnchored).values({
    id: event.id,
    bundleHash: event.args.bundleHash,
    subjectId: event.args.subjectId,
    role: event.args.role,
    documentCount: event.args.documentCount,
    ...logMeta(event),
  });
});

ponder.on("DocumentBundleAnchor:BundleSuperseded", async ({ event, context }) => {
  await context.db.insert(schema.bundleSuperseded).values({
    id: event.id,
    oldBundleHash: event.args.oldBundleHash,
    newBundleHash: event.args.newBundleHash,
    subjectId: event.args.subjectId,
    role: event.args.role,
    ...logMeta(event),
  });
});

// --- eip-3: TransferDomainRegistry / GracefulTransferDomainRegistry ---

ponder.on("TransferDomainRegistry:RouteSet", async ({ event, context }) => {
  await context.db.insert(schema.routeSet).values({
    id: event.id,
    sourceDomain: event.args.sourceDomain,
    destinationDomain: event.args.destinationDomain,
    assetClass: event.args.assetClass,
    permissionEvidenceHash: event.args.permissionEvidenceHash,
    effectiveAt: event.args.effectiveAt,
    ...logMeta(event),
  });
});

ponder.on("TransferDomainRegistry:RouteRevoked", async ({ event, context }) => {
  await context.db.insert(schema.routeRevoked).values({
    id: event.id,
    sourceDomain: event.args.sourceDomain,
    destinationDomain: event.args.destinationDomain,
    assetClass: event.args.assetClass,
    revocationEvidenceHash: event.args.revocationEvidenceHash,
    effectiveAt: event.args.effectiveAt,
    ...logMeta(event),
  });
});

ponder.on("GracefulTransferDomainRegistry:RouteRevocationInitiated", async ({ event, context }) => {
  await context.db.insert(schema.routeRevocationInitiated).values({
    id: event.id,
    sourceDomain: event.args.sourceDomain,
    destinationDomain: event.args.destinationDomain,
    assetClass: event.args.assetClass,
    revocationEvidenceHash: event.args.revocationEvidenceHash,
    initiatedAt: event.args.initiatedAt,
    effectiveAt: event.args.effectiveAt,
    ...logMeta(event),
  });
});

ponder.on("GracefulTransferDomainRegistry:RouteRevocationCancelled", async ({ event, context }) => {
  await context.db.insert(schema.routeRevocationCancelled).values({
    id: event.id,
    sourceDomain: event.args.sourceDomain,
    destinationDomain: event.args.destinationDomain,
    assetClass: event.args.assetClass,
    cancellationEvidenceHash: event.args.cancellationEvidenceHash,
    ...logMeta(event),
  });
});

// --- eip-4: ComplianceEventLog ---

ponder.on("ComplianceEventLog:ComplianceEventRecorded", async ({ event, context }) => {
  await context.db.insert(schema.complianceEventRecorded).values({
    id: event.id,
    subjectId: event.args.subjectId,
    eventType: event.args.eventType,
    actor: event.args.actor,
    eventIndex: event.args.eventIndex,
    outcome: event.args.outcome,
    authority: event.args.authority,
    occurredAt: event.args.occurredAt,
    correctsIndex: event.args.correctsIndex,
    ...logMeta(event),
  });
});

// --- eip-5: ImpactSnapshotLog ---

ponder.on("ImpactSnapshotLog:SnapshotRecorded", async ({ event, context }) => {
  await context.db.insert(schema.snapshotRecorded).values({
    id: event.id,
    subjectId: event.args.subjectId,
    indicatorId: event.args.indicatorId,
    snapshotIndex: event.args.snapshotIndex,
    value: event.args.value,
    decimals: event.args.decimals,
    unit: event.args.unit,
    periodStart: event.args.periodStart,
    periodEnd: event.args.periodEnd,
    methodologyHash: event.args.methodologyHash,
    correctsIndex: event.args.correctsIndex,
    reportedBy: event.args.reportedBy,
    ...logMeta(event),
  });
});

ponder.on("ImpactSnapshotLog:SnapshotAttested", async ({ event, context }) => {
  await context.db.insert(schema.snapshotAttested).values({
    id: event.id,
    subjectId: event.args.subjectId,
    snapshotIndex: event.args.snapshotIndex,
    attestor: event.args.attestor,
    endorsed: event.args.endorsed,
    evidenceHash: event.args.evidenceHash,
    attestationIndex: event.args.attestationIndex,
    ...logMeta(event),
  });
});

ponder.on("ImpactSnapshotLog:MethodologySuperseded", async ({ event, context }) => {
  await context.db.insert(schema.methodologySuperseded).values({
    id: event.id,
    subjectId: event.args.subjectId,
    indicatorId: event.args.indicatorId,
    oldMethodologyHash: event.args.oldMethodologyHash,
    newMethodologyHash: event.args.newMethodologyHash,
    effectiveFromOrdinal: event.args.effectiveFromOrdinal,
    ...logMeta(event),
  });
});

// --- eip-6: NAVSnapshotOracle ---

ponder.on("NAVSnapshotOracle:NAVPublished", async ({ event, context }) => {
  await context.db.insert(schema.navPublished).values({
    id: event.id,
    subjectId: event.args.subjectId,
    currency: event.args.currency,
    provider: event.args.provider,
    snapshotIndex: event.args.snapshotIndex,
    nav: event.args.nav,
    decimals: event.args.decimals,
    navBasis: event.args.navBasis,
    valuationTimestamp: event.args.valuationTimestamp,
    methodologyHash: event.args.methodologyHash,
    correctsIndex: event.args.correctsIndex,
    ...logMeta(event),
  });
});

ponder.on("NAVSnapshotOracle:NAVDeviationDetected", async ({ event, context }) => {
  await context.db.insert(schema.navDeviationDetected).values({
    id: event.id,
    subjectId: event.args.subjectId,
    currency: event.args.currency,
    valuationTimestamp: event.args.valuationTimestamp,
    minNav: event.args.minNav,
    maxNav: event.args.maxNav,
    deviationBps: event.args.deviationBps,
    ...logMeta(event),
  });
});

ponder.on("NAVSnapshotOracle:StalenessConfigUpdated", async ({ event, context }) => {
  await context.db.insert(schema.stalenessConfigUpdated).values({
    id: event.id,
    subjectId: event.args.subjectId,
    currency: event.args.currency,
    heartbeat: event.args.heartbeat,
    maxValuationAge: event.args.maxValuationAge,
    ...logMeta(event),
  });
});

ponder.on("NAVSnapshotOracle:AggregationConfigUpdated", async ({ event, context }) => {
  await context.db.insert(schema.aggregationConfigUpdated).values({
    id: event.id,
    subjectId: event.args.subjectId,
    currency: event.args.currency,
    quorum: event.args.quorum,
    deviationThresholdBps: event.args.deviationThresholdBps,
    ...logMeta(event),
  });
});
