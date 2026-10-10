// File: FeedSessionState.swift
// Module: FeedMineRuntime
// Owns: minimal local session value (editorial revision, admitted presentation, frozen bounds).
// Does not own: duplicated context, Edition, anchor or persistence values.

import FeedMineDomain

struct FeedSessionState: Hashable, Sendable {
    let editorialRevisionID: EditorialRevisionID
    let presentation: FeedPresentationSnapshot
    /// Bounds captured when the presentation was installed; never re-derived from a later caller.
    let bounds: FeedPresentationBounds
}
