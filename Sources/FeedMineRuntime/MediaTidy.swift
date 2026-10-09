// File: MediaTidy.swift
// Module: FeedMineRuntime
// Owns: the "tidy the house" pass that runs only while the app is not visible (PD-5).
// Does not own: published history (never rewritten), downloads or scheduling of the pass.
//
// PD-5: this pass prepares media; Publication's fenced successor operation owns unseen changes.
// PD-6: reader-window keys and bookmarks are protected; eviction uses durable reading facts.

import Foundation
import FeedMineDomain
import FeedMineMedia
import FeedMinePersistence

public struct MediaTidy: Sendable {
    private let housekeeping: MediaHousekeeping
    private let prefetcher: MediaPrefetcher
    private let usage: @Sendable () throws -> [String: PublicationStore.MediaUsage]
    private let now: @Sendable () -> Date
    private let freeStorageBytes: @Sendable () -> Int64?

    public init(assetDirectory: URL, prefetcher: MediaPrefetcher, freeStorageBytes: @escaping @Sendable () -> Int64?,
        usage: @escaping @Sendable () throws -> [String: PublicationStore.MediaUsage] = { [:] }, now: @escaping @Sendable () -> Date = { Date() }) {
        housekeeping = MediaHousekeeping(assetDirectory: assetDirectory)
        self.prefetcher = prefetcher
        self.freeStorageBytes = freeStorageBytes
        self.usage = usage
        self.now = now
    }

    public struct Report: Hashable, Sendable {
        public let evictedAssets: Int
        public let reclaimedBytes: Int64
        public let budgetBytes: Int64
    }

    /// Reader-window keys are protected. Other assets use durable reading/bookmark facts;
    /// a failed fact read retains all bytes.
    public func run(visibleKeys: Set<String>, supplyHeadLimit: Int, deadline: Double?) async -> Report {
        await prefetcher.prefetchSupplyHead(limit: supplyHeadLimit, deadline: deadline)
        let inventory = housekeeping.inventory()
        let used = inventory.reduce(Int64(0)) { $0 + $1.byteCount }
        guard let free = freeStorageBytes() else { return Report(evictedAssets: 0, reclaimedBytes: 0, budgetBytes: used) }
        let budget = MediaRetention.budgetBytes(freeStorageBytes: free, currentUsageBytes: used)
        guard let facts = try? usage() else { return Report(evictedAssets: 0, reclaimedBytes: 0, budgetBytes: budget) }
        let recent = now().addingTimeInterval(-7 * 86_400)
        let assets = inventory.compactMap { asset -> RetainedMediaAsset? in
            let retention: MediaRetentionClass
            let fact = facts[asset.key.rawValue]
            if fact?.bookmarked == true { retention = .bookmarked }
            else if visibleKeys.contains(asset.key.rawValue) { retention = .nearFutureUnseen }
            else if let seen = fact?.lastSeenAt { retention = seen >= recent ? .seenRecently : .seenLongAgo }
            else { retention = .farFutureUnseen }
            return RetainedMediaAsset(key: asset.key, byteCount: asset.byteCount, retention: retention, lastRelevantAt: fact?.lastSeenAt ?? asset.storedAt)
        }
        let protected = Set(visibleKeys.compactMap(PublishedMediaKey.init(rawValue:)))
        let evictions = MediaRetention.evictions(assets, budgetBytes: budget, protectedKeys: protected)
        let result = housekeeping.evictReporting(evictions)
        return Report(evictedAssets: result.removedKeys.count, reclaimedBytes: result.reclaimedBytes, budgetBytes: budget)
    }
}
