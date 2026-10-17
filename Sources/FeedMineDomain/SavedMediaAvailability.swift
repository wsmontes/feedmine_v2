//
// File: SavedMediaAvailability.swift
// Module: FeedMineDomain
//
// Responsibility:
// The availability of a saved occurrence's content, as a durable fact — never inferred at render time.
//
// Owns:
// The closed vocabulary that separates the durable **link** (a bookmark membership) from whether the
// content behind it is local, pending, or failed, and which of those states a retry can change.
//
// Does not own:
// Storage, downloads, decoding or presentation. A save that cannot hold its media must be able to say so
// (`insufficientSpace`) instead of reading as completed offline availability.

import Foundation

/// What a saved occurrence's content is, right now, as a persisted fact.
///
/// "Saved" is the link (`reader_bookmark_memberships`). This value says what the link can actually open:
/// a text-only unit is complete without media; a media-bearing unit may still be waiting for its bytes,
/// may hold them durably, or may have failed to hold them. The states are persisted so a relaunch reports
/// what happened rather than what a renderer guesses.
public enum SavedMediaAvailability: String, Hashable, Codable, Sendable, CaseIterable {
    /// The occurrence was published without media: its text **is** the whole frozen occurrence. Final.
    case textOnly
    /// The link is saved and the bytes it needs are neither stored nor known-unobtainable yet. Recoverable.
    case pending
    /// The bytes are in the durable media store; a local admission can decode them. Recoverable only if lost.
    case ready
    /// Preparation was attempted and did not produce bytes (network, unreadable store, unusable remote media).
    /// The save remains; the reader sees an honest unavailable state and can retry.
    case failed
    /// The durable media store could not hold the bytes (a full disk). Nothing was promised and nothing was
    /// deleted; the save remains and a retry can succeed once space exists.
    case insufficientSpace

    /// Whether the saved unit is complete offline as it stands. `pending`, `failed` and `insufficientSpace`
    /// never read as availability they did not have.
    public var isAvailableOffline: Bool {
        switch self {
        case .textOnly, .ready: return true
        case .pending, .failed, .insufficientSpace: return false
        }
    }

    /// Whether preparing again can change this state. `textOnly` is a property of the published occurrence and
    /// `ready` only changes by loss, so neither is offered as a retry.
    public var isRecoverable: Bool {
        switch self {
        case .pending, .failed, .insufficientSpace: return true
        case .textOnly, .ready: return false
        }
    }
}
