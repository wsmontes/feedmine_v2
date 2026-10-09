// Owns: actual image-container facts and exact-byte durable local materialization.
// No transformations or presentation objects; inspection never decodes a pixel buffer.

import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct LocalImageAsset: Hashable, Sendable {
    public let key: PublishedMediaKey
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let mimeType: String?
}

public struct ImageMaterializer: Sendable {
    private let store: AssetStore

    public init(assetDirectory: URL) {
        self.store = AssetStore(rootDirectory: assetDirectory)
    }

    public func materialize(_ bytes: Data) throws -> LocalImageAsset {
        let metadata = try Self.inspect(bytes)
        let key = try store.publish(bytes)
        return LocalImageAsset(key: key, pixelWidth: metadata.width,
            pixelHeight: metadata.height, mimeType: metadata.mimeType)
    }

    /// Exact authenticated local bytes for presentation decoding; nil when evicted or never stored.
    public func localBytes(for key: PublishedMediaKey) throws -> Data? {
        try store.bytes(for: key)
    }

    public func localAsset(for key: PublishedMediaKey) throws -> LocalImageAsset? {        guard let bytes = try store.bytes(for: key) else { return nil }
        let metadata: (width: Int, height: Int, mimeType: String?)
        do {
            metadata = try Self.inspect(bytes)
        } catch {
            throw LocalMediaAssetError.corruptStoredAsset(key)
        }
        return LocalImageAsset(key: key, pixelWidth: metadata.width,
            pixelHeight: metadata.height, mimeType: metadata.mimeType)
    }

    private static func inspect(_ bytes: Data) throws -> (width: Int, height: Int, mimeType: String?) {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
            CGImageSourceGetStatus(source) == .statusComplete,
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0 else {
            throw LocalMediaAssetError.invalidImage
        }
        let mimeType = CGImageSourceGetType(source).flatMap { UTType($0 as String)?.preferredMIMEType }
        return (width, height, mimeType)
    }
}
