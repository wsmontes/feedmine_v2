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

    /// Removes the given assets; returns the bytes reclaimed. Temporaries are left to their writer.
    @discardableResult
    public func evict(_ keys: [PublishedMediaKey]) -> Int64 {
        var reclaimed: Int64 = 0
        let sizes = Dictionary(inventory().map { ($0.key, $0.byteCount) }, uniquingKeysWith: { a, _ in a })
        for key in keys where key.rawValue.hasPrefix("sha256:") {
            let digest = String(key.rawValue.dropFirst(7))
            guard digest.count == 64 else { continue }
            if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(digest))) != nil {
                reclaimed += sizes[key] ?? 0
            }
        }
        return reclaimed
    }
}
