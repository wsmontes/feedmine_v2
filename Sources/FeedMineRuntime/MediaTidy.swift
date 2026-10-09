// File: MediaTidy.swift
// Module: FeedMineRuntime
// Owns: the "tidy the house" pass that runs only while the app is not visible (PD-5).
// Does not own: published history (never rewritten), downloads or scheduling of the pass.
//
// PD-5: if an image arrives after a card was published, the visible screen does not change; when
// the app loses focus or is closed the program may tidy up quickly. What is safe here:
//   1. prepare media for the supply head, so the *next* cards are complete (future occurrences);
//   2. bring local media under the device-derived disk budget (PD-6 rule 3).
// Re-preparing already-published unseen cards would rewrite history and needs a successor-tail
// mechanism in Publication; it is deliberately not done here (see docs/v1-study/PORT_LOG.md).

import Foundation
import FeedMineDomain
import FeedMineMedia

public struct MediaTidy: Sendable {
    private let housekeeping: MediaHousekeeping
    private let prefetcher: MediaPrefetcher
    private let freeStorageBytes: @Sendable () -> Int64?

    public init(assetDirectory: URL, prefetcher: MediaPrefetcher, freeStorageBytes: @escaping @Sendable () -> Int64?) {
        housekeeping = MediaHousekeeping(assetDirectory: assetDirectory)
        self.prefetcher = prefetcher
        self.freeStorageBytes = freeStorageBytes
    }

    public struct Report: Hashable, Sendable {
        public let evictedAssets: Int
        public let reclaimedBytes: Int64
        public let budgetBytes: Int64
    }

    /// `visibleKeys` are media keys of the reader's current window (seen recently or next up);
    /// they are evicted last. Everything else is ordered by age.
    public func run(visibleKeys: Set<String>, supplyHeadLimit: Int, deadline: Double?) async -> Report {
        await prefetcher.prefetchSupplyHead(limit: supplyHeadLimit, deadline: deadline)
        let inventory = housekeeping.inventory()
        let used = inventory.reduce(Int64(0)) { $0 + $1.byteCount }
        guard let free = freeStorageBytes() else { return Report(evictedAssets: 0, reclaimedBytes: 0, budgetBytes: used) }
        let budget = MediaRetention.budgetBytes(freeStorageBytes: free, currentUsageBytes: used)
        let newest = inventory.map(\.storedAt).max() ?? .distantPast
        let assets = inventory.compactMap { asset -> RetainedMediaAsset? in
            let retention: MediaRetentionClass
            if visibleKeys.contains(asset.key.rawValue) { retention = .nearFutureUnseen }
            // Installed within a day of the newest asset: belongs to the current runway era.
            else if newest.timeIntervalSince(asset.storedAt) < 86_400 { retention = .seenRecently }
            else { retention = .seenLongAgo }
            return RetainedMediaAsset(key: asset.key, byteCount: asset.byteCount, retention: retention, lastRelevantAt: asset.storedAt)
        }
        let evictions = MediaRetention.evictions(assets, budgetBytes: budget)
        let reclaimed = housekeeping.evict(evictions)
        return Report(evictedAssets: evictions.count, reclaimedBytes: reclaimed, budgetBytes: budget)
    }
}
