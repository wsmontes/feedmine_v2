// File: PreparedFeedInstallation.swift
// Module: FeedMineComposition
//
// Responsibility:
// The one value an installation needs, prepared by its owner **before** the main actor installs it. Installation
// only validates and assigns values — it never reads storage, opens a database or awaits a preparation.
//
// The bookmark half carries the revision of confirmed mutations it was read under, so a package prepared before a
// reader's own save/remove cannot overwrite the set that save/remove confirmed.
//
// It lives beside the handoff, not inside it: `FeedPresentationHandoff` is pinned by its own architecture test as a
// stateless bridge with no `init`/`var`/`actor`, and a value type with a public initializer would break that fence.
//
// Does not own: reading, preparation, ordering, publication or any UI state.
import Foundation
import FeedMineDomain
import FeedMineRuntime
import FeedMineUI

public struct PreparedFeedInstallation: Sendable {
    public struct Bookmarks: Sendable, Hashable {
        public let ids: Set<PublicationCardID>
        /// The confirmed-mutation revision observed when this read started.
        public let base: UInt64
        public init(ids: Set<PublicationCardID>, base: UInt64) {
            self.ids = ids
            self.base = base
        }
    }

    public let state: FeedPresentationState
    /// Nil is a work-only report or an installation whose window did not change: the bookmarks already prepared stay
    /// as they are and no storage is consulted.
    public let bookmarks: Bookmarks?

    public init(state: FeedPresentationState, bookmarks: Bookmarks? = nil) {
        self.state = state
        self.bookmarks = bookmarks
    }
}
