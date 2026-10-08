// File: FeedSessionState.swift
// Module: FeedMineRuntime
// Owns: minimal local session value and current finite materialization bounds.
// Does not own: duplicated context, Edition, anchor or persistence values.

import FeedMineDomain

struct FeedSessionState: Hashable, Sendable {
    let editorialRevisionID: EditorialRevisionID
    let presentation: FeedPresentationSnapshot
    let backwardCapacity: Int
    let forwardCapacity: Int
}
