// File: FeedSession.swift
// Module: FeedMineRuntime
// Owns: synchronous read-only warm restore into immutable presentation snapshots.
// Does not own: direct storage, mutable session state, network or coordination yet.

import FeedMinePublication

public final class FeedSession: Sendable {
    private let publicationHistory: PublicationHistory

    /// Composition-only exception: accepts the semantic Publication read boundary.
    /// UI consumes Runtime presentation results without importing Publication.
    public init(publicationHistory: PublicationHistory) {
        self.publicationHistory = publicationHistory
    }

    /// Capacities are explicit finite materialization bounds, never a page/feed size.
    /// Nil means no saved checkpoint. Errors propagate without fallback state.
    public func restoreLocalPresentation(
        backwardCapacity: Int,
        forwardCapacity: Int
    ) throws -> FeedPresentationSnapshot? {
        try publicationHistory.restore(backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
            .map(FeedPresentationSnapshot.init(restoredPublication:))
    }
}
