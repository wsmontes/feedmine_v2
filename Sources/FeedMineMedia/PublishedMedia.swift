//
// File: PublishedMedia.swift
// Module: FeedMineMedia
//
// Responsibility:
//   Freeze self-contained semantic values for deterministic local published presentation.
//
// Owns:
//   Opaque local media identity, validated reference metadata and primary-only media set.
//
// Does not own:
//   Preparation, downloads, paths, remote resolution, storage or alternate media variants.
//
// Allowed dependencies:
//   Foundation value types and FeedMineDomain; PublishedCard also uses FeedMineMedia.
//
// Architectural invariants:
//   INV-08, INV-12; published history survives canonical eviction without live joins.
//
// Public surface:
//   Phase 2C immutable semantic values; no Codable storage blobs or execution API.
//
// Status:
//   Phase 2C frozen PublishedCard baseline implemented.
//

/// Opaque stable local asset identity understood by FeedMineMedia.
/// Not a filesystem path or remote URL; future AssetStore resolves it to local materialization.
public struct PublishedMediaKey: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

/// A reference may survive byte eviction; the published render contract supplies fallback.
public struct PublishedMediaRef: Hashable, Sendable {
    public let key: PublishedMediaKey
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let mimeType: String?

    public var aspectRatio: Double? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    public init?(key: PublishedMediaKey, pixelWidth: Int?, pixelHeight: Int?, mimeType: String?) {
        switch (pixelWidth, pixelHeight) {
        case (nil, nil):
            break
        case let (.some(width), .some(height)) where width > 0 && height > 0:
            break
        default:
            return nil
        }
        self.key = key
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.mimeType = mimeType
    }
}

public struct PublishedMediaSet: Hashable, Sendable {
    public let primary: PublishedMediaRef?

    public init(primary: PublishedMediaRef?) {
        self.primary = primary
    }

    public static let none = PublishedMediaSet(primary: nil)
}
