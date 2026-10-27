//
// File: ReaderMedia.swift
// Module: FeedMineRuntime
//
// Responsibility:
// What the reader's own playback state *is*, and what the composition asks of a player it does not own.
// V1 read a global `AudioPlayerManager.shared`; V2 states the same facts as values and keeps AVFoundation in a
// platform adapter, so no renderer and no package target links a media framework.
//
// Does not own: playback (a platform adapter), the surfaces (the app) or the card's action (Composition).
import CoreGraphics
import Foundation
import ImageIO
import FeedMineDomain
import FeedMineMedia

/// One playable occurrence as the reader sees it.
public struct ReaderMediaItem: Hashable, Sendable, Identifiable {
    public let cardID: PublicationCardID
    public let url: URL
    public let title: String?
    /// What the card says it is (`audio/mpeg`, `video/mp4`). Nil when the card did not declare one.
    public let mimeType: String?
    /// The program the episode belongs to, as the card froze it. V1 stated it on the lock screen as the artist.
    public let source: String?
    /// The pixels the playing card was already admitted with, when the surface had them. This is a value the
    /// presentation layer decoded for the visible slot — never a download and never a second decoding pipeline:
    /// the player only publishes what the feed already prepared. Nil is honest: the card carried no prepared
    /// image, and the surfaces draw V1's waveform instead of an invented cover.
    public let artwork: PresentationImage?

    public init(cardID: PublicationCardID, url: URL, title: String?, mimeType: String?,
        source: String? = nil, artwork: PresentationImage? = nil) {
        self.cardID = cardID; self.url = url; self.title = title; self.mimeType = mimeType
        self.source = source; self.artwork = artwork
    }

    public var id: PublicationCardID { cardID }
}

public struct ReaderMediaState: Hashable, Sendable {
    public let item: ReaderMediaItem?
    public let isPlaying: Bool
    /// Where the reader is, and how long the item is. `duration` is nil until the player knows it, which is a
    /// real state V1 showed as an indeterminate bar rather than as zero.
    public let position: TimeInterval
    public let duration: TimeInterval?
    public let error: String?

    public static let idle = ReaderMediaState(item: nil, isPlaying: false, position: 0, duration: nil, error: nil)

    public init(item: ReaderMediaItem?, isPlaying: Bool, position: TimeInterval, duration: TimeInterval?,
        error: String?) {
        self.item = item; self.isPlaying = isPlaying; self.position = position; self.duration = duration
        self.error = error
    }

    /// 0…1 when the length is known, nil when it is not (the bar draws its own indeterminate state). A non-finite
    /// clock is not a length: reporting it as a fraction would state a position the player never proved.
    public var progress: Double? {
        guard let duration, duration.isFinite, duration > 0, position.isFinite else { return nil }
        return min(1, max(0, position / duration))
    }

    /// A **playback fact** update: where the player is, how long the item is, whether it is running. It is not a
    /// resolution of a refusal, so a stated reason survives it — the reader who was told "nothing to play" keeps
    /// being told that while the player reports its own state (measured: pausing on a refusal produced exactly one
    /// tick, which used to wipe the sentence the bar was showing). A new install constructs a fresh state and is
    /// what clears a reason; a retry states it again until it succeeds.
    public func reporting(position: TimeInterval, duration: TimeInterval?, isPlaying: Bool) -> Self {
        .init(item: item, isPlaying: isPlaying, position: position, duration: duration, error: error)
    }

    /// The same facts with the reason resolved. A refusal is cleared only by the fact that answers it — playback
    /// actually starting, or a new item being installed — never by a position tick.
    public func clearingError() -> Self {
        .init(item: item, isPlaying: isPlaying, position: position, duration: duration, error: nil)
    }

    public func failing(_ message: String) -> Self {
        .init(item: item, isPlaying: isPlaying, position: position, duration: duration, error: message)
    }
}

/// What the composition asks of a player. Implemented by a platform adapter (the app), so the package never
/// imports AVFoundation and a test can drive the state machine without a sound card.
@MainActor
public protocol ReaderMediaPlaying: AnyObject {
    var state: ReaderMediaState { get }
    /// Starts (or resumes) the item. Throws when the player cannot take it — a missing file, an unreachable
    /// host, a container it does not support — and the state says so instead of appearing to play.
    func play(_ item: ReaderMediaItem) async throws
    func pause() async
    func resume() async
    /// V1's own two skips, and the scrub a dragged bar performs.
    func skip(by seconds: TimeInterval) async
    func seek(to seconds: TimeInterval) async
    func stop() async
    /// The coordinator's own refusal (a card with nothing to play, a missing occurrence, a payload the player
    /// refused) is stated *by the player*, which owns the state — V1's `lastPlaybackError` was the same fact in
    /// the same place. `item` is the occurrence that could not play: F15 R4 keeps its reference so the surface
    /// can name what failed instead of showing a reason with nothing attached. Nil when the card carries no
    /// playable payload at all.
    func reportUnavailable(_ message: String, item: ReaderMediaItem?) async
}

/// A dragged scrubber's own rule, stated once so the surface and its test agree: the position on screen is a
/// **draft** until the reader lets go, and only a draft belonging to the item that is still playing may commit.
public enum ReaderMediaScrub {
    /// The seek the release commits, or nil when there is nothing to commit. A draft from another episode — the
    /// reader moved on while dragging — is discarded instead of seeking the new item to the old one's timeline.
    /// A finite duration bounds the target; an unknown duration only rules out non-finite values.
    public static func target(draft: TimeInterval?, draftedCard: PublicationCardID?,
        playingCard: PublicationCardID?, duration: TimeInterval?) -> TimeInterval? {
        guard let draft, draft.isFinite, let draftedCard, draftedCard == playingCard else { return nil }
        guard let duration, duration.isFinite, duration > 0 else { return max(0, draft) }
        return min(max(0, draft), duration)
    }
}

public extension PresentationImage {
    /// A decoded image the caller already holds — the pixels of a prepared card, or a test's own drawing. The
    /// presentation layer is the only decoder; this factory exists so a played occurrence can carry the image the
    /// card was admitted with across the Runtime boundary without a new image type.
    static func decoded(key: String, cgImage: CGImage) -> PresentationImage {
        PresentationImage(key: key, cgImage: cgImage)
    }
}

/// Reads the artwork of a played card from the bytes the media pipeline already materialized. One call per
/// play — never per clock tick, never from a view, never a network fetch. Nil when the asset was evicted or its
/// bytes do not decode, which the surfaces state honestly as V1's waveform.
public struct ReaderMediaArtworkDecoder: Sendable {
    private let materializer: ImageMaterializer
    public let maxPixel: Int

    public init?(assetDirectory: URL, maxPixel: Int = 600) {
        guard maxPixel > 0 else { return nil }
        materializer = ImageMaterializer(assetDirectory: assetDirectory)
        self.maxPixel = maxPixel
    }

    public func artwork(forMediaKey rawKey: String) -> PresentationImage? {
        guard let key = PublishedMediaKey(rawValue: rawKey),
            let bytes = try? materializer.localBytes(for: key),
            let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return PresentationImage.decoded(key: key.rawValue, cgImage: image)
    }
}
