// File: FeedSession.swift
// Module: FeedMineRuntime
// Owns: current local state, memory-local viewport movement and explicit checkpoints.
// Does not own: direct storage, publication, acquisition or UI layout.

import Foundation
import FeedMineDomain
import FeedMinePublication

public actor FeedSession {
    private let publicationHistory: PublicationHistory
    private let imageDecoder: PresentationImageDecoder?
    private var state: FeedSessionState?
    private let projectionSequenceID = UUID()
    private var projectionPosition: UInt64 = 0

    /// Composition-only exception: accepts the semantic Publication boundary.
    /// UI consumes Runtime presentation results without importing Publication.
    /// With a decoder, projected cards carry slot-sized local images; without one they render placeholders.
    public init(publicationHistory: PublicationHistory, imageDecoder: PresentationImageDecoder? = nil) {
        self.publicationHistory = publicationHistory
        self.imageDecoder = imageDecoder
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
        let snapshot = try project(contextKey: current.presentation.contextKey,
            editionID: current.presentation.editionID, publishedWindow: window)
        state = FeedSessionState(editorialRevisionID: current.editorialRevisionID, presentation: snapshot,
            backwardCapacity: current.backwardCapacity, forwardCapacity: current.forwardCapacity)
        return snapshot
    }

    /// Capacities are explicit finite materialization bounds, never a page/feed size.
    /// A failed read preserves existing state; no checkpoint clears local state.
    public func restoreLocalPresentation(
        backwardCapacity: Int,
        forwardCapacity: Int,
        contextKey: ContextKey? = nil
    ) throws -> FeedPresentationSnapshot? {
        guard let restored = try publicationHistory.restore(
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity, contextKey: contextKey) else {
            state = nil
            return nil
        }
        try publicationHistory.markSeen(editionID: restored.edition.id, cardID: restored.cursor.anchor.cardID)
        let snapshot = try project(contextKey: restored.edition.contextKey, editionID: restored.edition.id, publishedWindow: restored.window)
        state = FeedSessionState(editorialRevisionID: restored.edition.editorialRevision.id, presentation: snapshot,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
        return snapshot
    }

    /// Allocate only after a successful read, alongside the actor's synchronous state transition.
    /// An unchanged effective projection retains its exact provenance, even after another read.
    private func project(contextKey: ContextKey, editionID: FeedEditionID,
        publishedWindow: FeedWindow) throws -> FeedPresentationSnapshot {
        let current = state?.presentation
        let reusable = current.flatMap { snapshot in
            snapshot.contextKey == contextKey && snapshot.editionID == editionID
                ? Dictionary(uniqueKeysWithValues: snapshot.window.items.map { ($0.id, $0) }) : nil
        } ?? [:]
        let window = FeedWindowSnapshot(publishedWindow: publishedWindow, decoder: imageDecoder, reusable: reusable)
        if let current = state?.presentation, current.contextKey == contextKey,
            current.editionID == editionID, current.window == window { return current }
        let next = try FeedProjectionProvenance.nextPosition(after: projectionPosition)
        let snapshot = FeedPresentationSnapshot(contextKey: contextKey, editionID: editionID,
            window: window,
            provenance: .init(sequenceID: projectionSequenceID, position: next))
        projectionPosition = next
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
        guard current.presentation.window.items.contains(where: { $0.id == observation.anchor.cardID }) else { return current.presentation }
        try publicationHistory.markSeen(editionID: current.presentation.editionID, cardID: observation.anchor.cardID)
        guard observation.anchor != current.presentation.window.anchor else { return current.presentation }
        let placement: AnchorPlacement
        switch observation.anchor.placement {
        case .top: placement = .top
        case .center: placement = .center
        }
        let anchor = FeedWindowAnchor(cardID: observation.anchor.cardID, placement: placement)
        let window = try publicationHistory.window(editionID: current.presentation.editionID,
            around: anchor, backwardCapacity: current.backwardCapacity,
            forwardCapacity: current.forwardCapacity)
        let snapshot = try project(contextKey: current.presentation.contextKey,
            editionID: current.presentation.editionID, publishedWindow: window)
        state = FeedSessionState(editorialRevisionID: current.editorialRevisionID, presentation: snapshot,
            backwardCapacity: current.backwardCapacity, forwardCapacity: current.forwardCapacity)
        return snapshot
    }
}
