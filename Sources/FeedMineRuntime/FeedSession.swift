// File: FeedSession.swift
// Module: FeedMineRuntime
// Owns: actor-isolated current local consumption state and logical window movement.
// Does not own: direct storage, publication, acquisition or UI layout.

import FeedMinePublication

public actor FeedSession {
    private let publicationHistory: PublicationHistory
    private var state: FeedSessionState?

    /// Composition-only exception: accepts the semantic Publication boundary.
    /// UI consumes Runtime presentation results without importing Publication.
    public init(publicationHistory: PublicationHistory) {
        self.publicationHistory = publicationHistory
    }

    public func currentPresentation() -> FeedPresentationSnapshot? {
        state?.presentation
    }

    /// Capacities are explicit finite materialization bounds, never a page/feed size.
    /// A failed read preserves existing state; no checkpoint clears local state.
    public func restoreLocalPresentation(
        backwardCapacity: Int,
        forwardCapacity: Int
    ) throws -> FeedPresentationSnapshot? {
        guard let restored = try publicationHistory.restore(
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity) else {
            state = nil
            return nil
        }
        let snapshot = FeedPresentationSnapshot(restoredPublication: restored)
        state = FeedSessionState(presentation: snapshot,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
        return snapshot
    }

    /// Observes a reading position in the current snapshot, using retained history only.
    public func submitViewport(_ observation: ViewportObservation) throws -> FeedPresentationSnapshot? {
        guard let current = state else { return nil }
        guard current.presentation.window.items.contains(where: { $0.id == observation.anchor.cardID }),
            observation.anchor != current.presentation.window.anchor else {
            return current.presentation
        }
        let placement: AnchorPlacement
        switch observation.anchor.placement {
        case .top: placement = .top
        case .center: placement = .center
        }
        let anchor = FeedWindowAnchor(cardID: observation.anchor.cardID, placement: placement)
        let window = try publicationHistory.window(editionID: current.presentation.editionID,
            around: anchor, backwardCapacity: current.backwardCapacity,
            forwardCapacity: current.forwardCapacity)
        let snapshot = FeedPresentationSnapshot(contextKey: current.presentation.contextKey,
            editionID: current.presentation.editionID, publishedWindow: window)
        let cursor = SessionCursor(editionID: current.presentation.editionID, anchor: anchor)
        try publicationHistory.saveCursor(cursor, updatedAt: observation.observedAt)
        state = FeedSessionState(presentation: snapshot,
            backwardCapacity: current.backwardCapacity, forwardCapacity: current.forwardCapacity)
        return snapshot
    }
}
