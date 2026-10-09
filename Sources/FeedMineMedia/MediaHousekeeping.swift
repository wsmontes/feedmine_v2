// File: MediaHousekeeping.swift
// Module: FeedMineMedia
// Owns: inventory and deletion of local media bytes under the content-addressed asset root.
// Does not own: deciding what to keep (Runtime classifies; MediaRetention orders) or published history.
//
// Deleting bytes never rewrites a PublishedCard: a card whose bytes are gone renders the frozen
// RenderContract placeholder (MEDIA_DESIGN §8). Only valid `sha256:` files are touched.

import Foundation

public struct StoredMediaAsset: Hashable, Sendable {
    public let key: PublishedMediaKey
    public let byteCount: Int64
    /// File modification time: when the bytes were installed or last re-authenticated.
    public let storedAt: Date
}

public struct MediaHousekeeping: Sendable {
    private let directory: URL

    public init(assetDirectory: URL) {
        directory = assetDirectory.appendingPathComponent("sha256", isDirectory: true)
    }

    public func inventory() -> [StoredMediaAsset] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return [] }
        return files.compactMap { file in
            let name = file.lastPathComponent
            guard name.count == 64, name.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                let key = PublishedMediaKey(rawValue: "sha256:" + name) else { return nil }
            return StoredMediaAsset(key: key, byteCount: Int64(values.fileSize ?? 0),
                storedAt: values.contentModificationDate ?? .distantPast)
        }
    }

    public struct EvictionReport: Hashable, Sendable {
        public let removedKeys: Set<PublishedMediaKey>
        public let reclaimedBytes: Int64
    }

    /// Removes only inventoried regular assets and reports successful deletions precisely.
    public func evictReporting(_ keys: [PublishedMediaKey]) -> EvictionReport {
        var reclaimed: Int64 = 0
        var removed: Set<PublishedMediaKey> = []
        let sizes = Dictionary(inventory().map { ($0.key, $0.byteCount) }, uniquingKeysWith: { a, _ in a })
        for key in keys where sizes[key] != nil && !removed.contains(key) {
            let digest = String(key.rawValue.dropFirst(7))
            if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(digest))) != nil {
                reclaimed += sizes[key] ?? 0
                removed.insert(key)
            }
        }
        return EvictionReport(removedKeys: removed, reclaimedBytes: reclaimed)
    }

    @discardableResult
    public func evict(_ keys: [PublishedMediaKey]) -> Int64 { evictReporting(keys).reclaimedBytes }
}
