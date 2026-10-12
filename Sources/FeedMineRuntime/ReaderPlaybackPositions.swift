//
// File: ReaderPlaybackPositions.swift
// Module: FeedMineRuntime
//
// Responsibility:
// Where the reader stopped listening, as the player needs it: one position per card, read before playback starts
// and written while it runs. V1 kept this in `UserDefaults` and the rules it applied live here as the contract —
// the threshold below is V1's (`restorePositionIfNeeded`, `savedTime > 5`), so a client cannot invent a
// different idea of "worth resuming".
//
// The protocol is synchronous and small on purpose: it is called from the player's own time observer, often, and
// a value the caller must be able to read before it can seek. Storage (Persistence) and the platform adapter
// (the app) are the two sides; neither knows about the other.
//
// Does not own: playing anything (the adapter), durability (Persistence) or the surfaces (the app).
import Foundation
import FeedMineDomain

@MainActor
public protocol ReaderPlaybackPositions: AnyObject {
    /// The position this card was left at, or nil when there is none worth restoring.
    func position(for cardID: PublicationCardID) -> TimeInterval?
    func save(position: TimeInterval, duration: TimeInterval?, for cardID: PublicationCardID)
    /// Forgets a card's position: what reaching the end and starting over both mean.
    func clear(cardID: PublicationCardID)
}

public enum ReaderPlaybackPositionRules {
    /// V1 restored a saved position only when it was more than five seconds in (`AudioPlayerManager`): a listener
    /// two seconds into an episode wants it from the start, not from two seconds.
    public static let resumeThreshold: TimeInterval = 5

    /// V1 persisted every ~5 seconds of playback (`lastSavedAt`), and on the way out of the app.
    public static let saveInterval: TimeInterval = 5

    /// True when a saved position is worth resuming from.
    public static func isResumable(_ position: TimeInterval?) -> Bool {
        guard let position else { return false }
        return position > resumeThreshold
    }

    /// The position within an item that counts as "finished": V1 cleared its marker when a seek landed at least
    /// half a second before the end (`completedItemID`), so seeking back into the last seconds resumes playback
    /// instead of staying finished.
    public static let completionTolerance: TimeInterval = 0.5
}
