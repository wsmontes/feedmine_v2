// File: PresentationImage.swift
// Module: FeedMineRuntime
// Owns: decoding of already-local published media into immutable, slot-sized presentation images.
// Does not own: downloading, asset storage, eviction or SwiftUI.
//
// v1 lessons (03-media.md): decode with ImageIO thumbnailing at the slot size (never full-size
// rasters), never let a late image change a visible card, and render missing bytes through the
// frozen RenderContract placeholder. Decoding happens inside FeedSession while it projects a
// window, so the UI only receives ready values (INV-01) and performs no I/O.

import CoreGraphics
import Foundation
import ImageIO
import FeedMineMedia

/// Immutable decoded image. CGImage is immutable, hence the checked unchecked-Sendable wrapper.
/// Equality is the published key plus decoded size, so re-projection of the same media is equal.
public struct PresentationImage: Hashable, @unchecked Sendable {
    public let key: String
    public let cgImage: CGImage

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.cgImage.width == rhs.cgImage.width && lhs.cgImage.height == rhs.cgImage.height
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(cgImage.width)
        hasher.combine(cgImage.height)
    }
}

/// Decodes local assets for a projected window. Pixel targets come from the device's measured
/// slot sizes (PD-6), supplied by composition.
public struct PresentationImageDecoder: Sendable {
    private let onDecode: @Sendable () -> Void
    private let materializer: ImageMaterializer
    public let heroMaxPixel: Int
    public let thumbnailMaxPixel: Int

    public init?(assetDirectory: URL, heroMaxPixel: Int, thumbnailMaxPixel: Int, onDecode: @escaping @Sendable () -> Void = {}) {
        guard heroMaxPixel > 0, thumbnailMaxPixel > 0 else { return nil }
        self.onDecode = onDecode
        materializer = ImageMaterializer(assetDirectory: assetDirectory)
        self.heroMaxPixel = heroMaxPixel
        self.thumbnailMaxPixel = thumbnailMaxPixel
    }

    /// nil when bytes are absent, corrupt or undecodable: the card keeps its frozen placeholder.
    func image(key: PublishedMediaKey, layout: PresentationCardLayout) -> PresentationImage? {
        let maxPixel: Int
        switch layout {
        case .hero: maxPixel = heroMaxPixel
        case .thumbnail: maxPixel = thumbnailMaxPixel
        case .textOnly: return nil
        }
        onDecode()
        guard let bytes = try? materializer.localBytes(for: key),
            let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return PresentationImage(key: key.rawValue, cgImage: image)
    }
}
