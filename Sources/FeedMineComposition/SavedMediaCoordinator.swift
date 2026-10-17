//
// File: SavedMediaCoordinator.swift
// Module: FeedMineComposition
//
// Responsibility:
// The one path that turns a save into a durable reading unit: record what the link can actually open, and
// prepare the occurrence's media through the existing `MediaPrefetcher` when the bytes are not local.
//
// Does not own:
// Bookmarks (the reader's library), downloads (`MediaPrefetcher`), storage (`Media/` + `AssetStore`), the
// published occurrence (never rewritten) or any layout. A save is never deleted by a preparation outcome;
// a failure is recorded and remains retryable.
//
// Owner directive 2026-10-17 §2:
// * a saved occurrence is the immutable `published_cards` row — same media key, same render contract;
// * re-preparation fetches/stores bytes for that occurrence and changes only availability, never publication;
// * "saved" never simulates a preparation that did not happen, and a failure stays visible and recoverable;
// * decoded pixels in RAM are not durable data: the durable fact is the file in `Application Support/.../Media`,
//   which `MediaRetention` protects while a bookmark references it;
// * a saved image card whose bytes are missing is **not render-ready**, so the feed excludes it from the current
//   window (INV-17). It is never converted to a text card under the same identity — that fallback is forbidden;
//   the availability row is the honest statement, and retry is the recovery.
//
// Text-only decision: an occurrence published without media (`media_key IS NULL`) can **never** gain media here.
// Media is part of the frozen occurrence (`mediaLocator` states it: "a card's media is the media it was
// published with, whatever the origin says later"). Gaining media would require a new publication or mutating
// published history, both of which this contract forbids, so its availability is `textOnly` — final, and honest
// because the text *is* the whole published occurrence. The coordinator does not fetch and does not promise an
// image that will never come.

import Foundation
import FeedMineDomain
import FeedMineMedia
import FeedMinePersistence
import FeedMineRuntime

public actor SavedMediaCoordinator {
    private let publication: PublicationStore
    private let library: ReaderLibraryStore
    private let availability: SavedMediaAvailabilityStore
    private let prefetcher: MediaPrefetcher
    private let materializer: ImageMaterializer
    private let now: @Sendable () -> Date

    public init(database: RuntimeDatabase, assetDirectory: URL, prefetcher: MediaPrefetcher,
        now: @escaping @Sendable () -> Date = { Date() }) {
        publication = PublicationStore(database: database)
        library = ReaderLibraryStore(database: database)
        availability = SavedMediaAvailabilityStore(database: database)
        self.prefetcher = prefetcher
        materializer = ImageMaterializer(assetDirectory: assetDirectory)
        self.now = now
    }

    /// The save's own preparation, and the retry path for a saved card (they are the same operation: the reader
    /// asked for the content again).
    ///
    /// Records availability *before* the work as `pending`, so a long preparation is stated as pending rather
    /// than as an availability it does not have, then records the outcome. Nil means the card is not saved: the
    /// link was removed (possibly while the download was running, which wins), so there is nothing to promise and
    /// the recorded row is removed with it.
    @discardableResult
    public func prepareSavedMedia(cardID: PublicationCardID) async -> SavedMediaAvailability? {
        guard let card = try? publication.card(id: cardID) else { return nil }
        guard isSaved(cardID) else {
            try? availability.clear(cardID: cardID)
            return nil
        }
        // A publication without media is text-only for good: no bytes exist to fetch, and none may be invented.
        guard let key = card.mediaKey.flatMap(PublishedMediaKey.init(rawValue:)) else {
            try? availability.record(cardID: cardID, availability: .textOnly, at: now())
            return .textOnly
        }
        // Bytes already in the durable store: this is a durable unit right now.
        if localAsset(for: key) != nil {
            try? availability.record(cardID: cardID, availability: .ready, at: now())
            return .ready
        }
        try? availability.record(cardID: cardID, availability: .pending, at: now())
        let outcome = await prefetcher.prepareForSave(card.originRevisionID)
        // The link can disappear while the download runs. Availability belongs to a link; without one it is not
        // written back.
        guard isSaved(cardID) else {
            try? availability.clear(cardID: cardID)
            return nil
        }
        let state = resolved(outcome, publishedKey: key)
        try? availability.record(cardID: cardID, availability: state, at: now(), attempted: outcome.wasAttempted)
        return state
    }

    /// Resumes saved units whose content is not settled, bounded and sequential so a background pass never
    /// storms the download owner. `ready` rows are re-verified here: bytes lost behind the store's back are
    /// demoted and prepared again instead of being reported as available forever.
    public func resume(limit: Int = 8) async {
        guard let cards = try? availability.savedCardIDs(limit: limit) else { return }
        for cardID in cards { _ = await prepareSavedMedia(cardID: cardID) }
    }

    /// Removes availabilities whose link is gone. Called after a box change so an unsaved card leaves no claim
    /// behind; a card still in another box keeps its state.
    public func forgetUnsaved() {
        try? availability.clearUnsaved()
    }

    private func isSaved(_ cardID: PublicationCardID) -> Bool {
        ((try? library.bookmarkListIDs(forCard: cardID)) ?? []).isEmpty == false
    }

    private func localAsset(for key: PublishedMediaKey) -> LocalImageAsset? {
        // A corrupt stored asset is not "ready": it is a failure the retry path may repair or report again.
        (try? materializer.localAsset(for: key)) ?? nil
    }

    /// The published occurrence's own key is the only media this card may present. A fetch that stores different
    /// bytes (the origin changed what it serves) does not make the frozen occurrence available, so it is reported
    /// as a failure instead of a readiness the card cannot draw.
    private func resolved(_ outcome: MediaPreparationOutcome, publishedKey: PublishedMediaKey) -> SavedMediaAvailability {
        switch outcome {
        case .ready:
            return localAsset(for: publishedKey) != nil ? .ready : .failed
        case .unavailable, .textOnly:
            // The occurrence was published with media, so "no candidate could be prepared" is a real failure for
            // this unit — never a new text-only publication. The card is not render-ready, so the feed excludes it
            // from the current window (INV-17); this row keeps the failure visible and retryable.
            return .failed
        case .deferred:
            return .pending
        case .failed:
            return .failed
        case .insufficientSpace:
            return .insufficientSpace
        }
    }
}

private extension MediaPreparationOutcome {
    /// Whether the pipeline actually tried something (so the attempt counter reflects work, not a save).
    var wasAttempted: Bool {
        switch self {
        case .deferred: return false
        case .ready, .textOnly, .unavailable, .failed, .insufficientSpace: return true
        }
    }
}
