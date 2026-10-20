//
// File: PublishedMediaIdentity.swift
// Module: FeedMinePublication
//
// Responsibility:
//   State what an occurrence's media *is* (audio, video or none) and the one action its card may carry.
//
// Owns:
//   The D2 rule: a video card opens its origin and never offers an in-app player; an audio card keeps the
//   playable enclosure; an item with no enclosure states the absence instead of inventing a target.
//
// Does not own:
//   Reading feeds, MIME classification (`MediaCandidateClass.playback(forMIME:)` already did that at admission),
//   action execution, storage or rendering.
//
// Allowed dependencies:
//   Foundation value types and FeedMineDomain.
//

import Foundation
import FeedMineDomain

/// What the card's own payload is. Stored with the frozen card, so the identity survives a reload and an old
/// card that predates the fact reads as `nil` (unknown) instead of being guessed from its action kind.
public enum PublishedMediaIdentity: String, Hashable, Sendable {
    /// The occurrence declared no playable enclosure. A known absence, distinct from an unknown one.
    case none
    case audio
    case video
}

/// The identity and action one occurrence publishes with. Both come from the enclosure the feed declared,
/// translated to `MediaCandidateClass` by `MediaCandidateClass.playback(forMIME:)` at admission — never from a
/// source's `media_kind`.
public struct PublishedMediaDecision: Hashable, Sendable {
    public let identity: PublishedMediaIdentity
    public let primaryAction: PublishedPrimaryAction?

    public init(identity: PublishedMediaIdentity, primaryAction: PublishedPrimaryAction?) {
        self.identity = identity
        self.primaryAction = primaryAction
    }

    /// PD-2026-10-20 D2. Audio keeps today's behaviour exactly: the enclosure is what the card plays.
    /// A video item is identified as video and opens its own link in the browser — the in-app player is a bare
    /// `AVPlayer` and would play the sound of a video without an image. When the item has no link there is
    /// nothing to open: the identity is still recorded, and no playable target is invented in its place.
    public static func resolve(playback: MediaCandidate?, link: URL?) -> PublishedMediaDecision {
        switch playback?.mediaClass {
        case .audio?:
            guard let playback else { return PublishedMediaDecision(identity: .audio, primaryAction: nil) }
            return PublishedMediaDecision(identity: .audio, primaryAction: .mediaPlayback(playback.remoteURL))
        case .video?:
            return PublishedMediaDecision(identity: .video, primaryAction: link.map { .externalURL($0) })
        case .image?, nil:
            // An image is never a playback role (the store's own check says so); anything else is no payload.
            return PublishedMediaDecision(identity: .none, primaryAction: link.map { .externalURL($0) })
        }
    }
}
