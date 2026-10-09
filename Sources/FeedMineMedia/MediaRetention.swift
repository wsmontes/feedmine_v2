// File: MediaRetention.swift
// Module: FeedMineMedia
// Owns: pure disk budget and eviction order for local media bytes (PD-6 rule 3).
// Does not own: deleting files, publication history or seen-state tracking.
//
// Evicting bytes never rewrites PublishedCard; a card whose bytes are gone falls back through its
// frozen RenderContract (MEDIA_DESIGN §8). Bookmarked media is never evicted.

import Foundation

public enum MediaRetentionClass: Int, Hashable, Sendable, Comparable {
    /// Prepared for runway far ahead of the reader; cheapest to lose (re-preparable).
    case farFutureUnseen = 0
    case seenLongAgo = 1
    case seenRecently = 2
    /// Next cards the reader will see; evicted only after everything older.
    case nearFutureUnseen = 3
    case bookmarked = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct RetainedMediaAsset: Hashable, Sendable {
    public let key: PublishedMediaKey
    public let byteCount: Int64
    public let retention: MediaRetentionClass
    /// Last time the asset mattered (seen, or prepared for runway); older goes first within a class.
    public let lastRelevantAt: Date

    public init?(key: PublishedMediaKey, byteCount: Int64, retention: MediaRetentionClass, lastRelevantAt: Date) {
        guard byteCount >= 0, lastRelevantAt.timeIntervalSince1970.isFinite else { return nil }
        self.key = key
        self.byteCount = byteCount
        self.retention = retention
        self.lastRelevantAt = lastRelevantAt
    }
}

public enum MediaRetention {
    /// Media may use a share of the free space that shrinks as the disk fills: with plenty of
    /// space the share is generous; near full it approaches zero so the user's device stays healthy.
    /// `currentUsageBytes` is what media already occupies (it counts as reclaimable space).
    public static func budgetBytes(freeStorageBytes: Int64, currentUsageBytes: Int64) -> Int64 {
        let free = max(0, freeStorageBytes), used = max(0, currentUsageBytes)
        let available = free + used
        guard available > 0 else { return 0 }
        // Share = free / (free + available): 1/2 of available when media is a small part of it,
        // falling toward 0 as free space runs out. Derived from the device's own state.
        let share = Double(free) / Double(free + available)
        return Int64((Double(available) * share).rounded(.down))
    }

    /// Keys to delete so the total fits `budgetBytes`, in eviction order. Bookmarked assets are
    /// never returned, even if the budget cannot be met without them.
    public static func evictions(_ assets: [RetainedMediaAsset], budgetBytes: Int64, protectedKeys: Set<PublishedMediaKey> = []) -> [PublishedMediaKey] {
        var total = assets.reduce(Int64(0)) { $0 + $1.byteCount }
        guard total > budgetBytes else { return [] }
        let order = assets.filter { $0.retention != .bookmarked && !protectedKeys.contains($0.key) }.sorted { a, b in
            if a.retention != b.retention { return a.retention < b.retention }
            if a.lastRelevantAt != b.lastRelevantAt { return a.lastRelevantAt < b.lastRelevantAt }
            return a.key.rawValue < b.key.rawValue
        }
        var evicted: [PublishedMediaKey] = []
        for asset in order where total > budgetBytes {
            evicted.append(asset.key)
            total -= asset.byteCount
        }
        return evicted
    }
}
