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
import Foundation
import FeedMineDomain

/// One playable occurrence as the reader sees it.
public struct ReaderMediaItem: Hashable, Sendable, Identifiable {
    public let cardID: PublicationCardID
    public let url: URL
    public let title: String?
    /// What the card says it is (`audio/mpeg`, `video/mp4`). Nil when the card did not declare one.
    public let mimeType: String?
    /// The program the episode belongs to, as the card froze it. V1 stated it on the lock screen as the artist.
    public let source: String?
    /// The card's own prepared image (`PublishedMediaKey` raw value): V1's player and lock screen showed the
    /// episode's art. Only a local image is ever drawn from it — the player never downloads one.
    public let artworkKey: String?
    /// The card's own text, which V1 published on the lock screen as the episode's comments.
    public let summary: String?
    /// The length the feed declared (`itunes:duration`), stated until the player measures the real one.
    public let declaredDuration: TimeInterval?

    public init(cardID: PublicationCardID, url: URL, title: String?, mimeType: String?,
        source: String? = nil, artworkKey: String? = nil, summary: String? = nil,
        declaredDuration: TimeInterval? = nil) {
        self.cardID = cardID; self.url = url; self.title = title; self.mimeType = mimeType; self.source = source
        self.artworkKey = artworkKey; self.summary = summary
        self.declaredDuration = declaredDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
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

    /// 0…1 when the length is known, nil when it is not (the bar draws its own indeterminate state).
    public var progress: Double? {
        guard let duration, duration > 0 else { return nil }
        return min(1, max(0, position / duration))
    }

    public func reporting(position: TimeInterval, duration: TimeInterval?, isPlaying: Bool) -> Self {
        .init(item: item, isPlaying: isPlaying, position: position, duration: duration, error: nil)
    }

    public func failing(_ message: String) -> Self {
        .init(item: item, isPlaying: false, position: position, duration: duration, error: message)
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
