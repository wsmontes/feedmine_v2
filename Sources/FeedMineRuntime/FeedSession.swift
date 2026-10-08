// File: FeedSession.swift
// Module: FeedMineRuntime
// Owns: current local state, memory-local viewport movement and explicit checkpoints.
// Does not own: direct storage, publication, acquisition or UI layout.

import Foundation
import FeedMineDomain
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

    public func currentRunwayScope() -> RunwayScope? {
        guard let current = state else { return nil }
        return RunwayScope(editionID: current.presentation.editionID, contextKey: current.presentation.contextKey,
            editorialRevisionID: current.editorialRevisionID)
    }

    /// Rematerializes committed history at the same memory-local position; no milestone is written.
    public func refreshCurrentPresentation() throws -> FeedPresentationSnapshot? {
        guard let current = state else { return nil }
        let placement: AnchorPlacement
        switch current.presentation.window.anchor.placement {
        case .top: placement = .top
        case .center: placement = .center
        }
        let anchor = FeedWindowAnchor(cardID: current.presentation.window.anchor.cardID, placement: placement)
        let window = try publicationHistory.window(editionID: current.presentation.editionID, around: anchor,
            backwardCapacity: current.backwardCapacity, forwardCapacity: current.forwardCapacity)
        let snapshot = FeedPresentationSnapshot(contextKey: current.presentation.contextKey,
            editionID: current.presentation.editionID, publishedWindow: window)
        state = FeedSessionState(editorialRevisionID: current.editorialRevisionID, presentation: snapshot,
            backwardCapacity: current.backwardCapacity, forwardCapacity: current.forwardCapacity)
        return snapshot
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
        state = FeedSessionState(editorialRevisionID: restored.edition.editorialRevision.id, presentation: snapshot,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
        return snapshot
    }

    /// Makes the existing logical position durable without changing current presentation.
    /// The caller decides when a milestone occurs; date validation belongs to Persistence.
    public func checkpointCurrentPosition(at date: Date) throws -> Bool {
        guard let current = state else { return false }
        let placement: AnchorPlacement
        switch current.presentation.window.anchor.placement {
        case .top: placement = .top
        case .center: placement = .center
        }
        let anchor = FeedWindowAnchor(cardID: current.presentation.window.anchor.cardID, placement: placement)
        let cursor = SessionCursor(editionID: current.presentation.editionID, anchor: anchor)
        try publicationHistory.saveCursor(cursor, updatedAt: date)
        return true
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
        state = FeedSessionState(editorialRevisionID: current.editorialRevisionID, presentation: snapshot,
            backwardCapacity: current.backwardCapacity, forwardCapacity: current.forwardCapacity)
        return snapshot
    }
}
