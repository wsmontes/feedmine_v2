// File: FeedSessionState.swift
// Module: FeedMineRuntime
// Owns: minimal local session value and current finite materialization bounds.
// Does not own: duplicated context, Edition, anchor or persistence values.

struct FeedSessionState: Hashable, Sendable {
    let presentation: FeedPresentationSnapshot
    let backwardCapacity: Int
    let forwardCapacity: Int
}
