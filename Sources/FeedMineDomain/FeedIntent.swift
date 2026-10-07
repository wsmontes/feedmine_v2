//
// File: FeedIntent.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Describe feed-level user requests without prescribing Runtime execution.
//
// Owns:
//   FeedIntent.changeContext and FeedIntent.refresh.
//
// Does not own:
//   Execution strategy, networking, persistence, interactions, bookmark/read state or effects.
//
// Allowed dependencies:
//   Swift standard library and Foundation value types when needed; no other FeedMine module.
//
// Architectural invariants:
//   INV-02, INV-10; changing context reprioritizes future work without requiring destruction of reusable work.
//
// Planned public surface:
//   FeedIntent.changeContext and FeedIntent.refresh. No execution API is authorized in this phase.
//
// Status:
//   Phase 1B context and editorial revision value implementation.
//

/// FeedIntent describes what the user requested, not how Runtime executes the request.
/// A context change reprioritizes future work. It does not semantically require
/// destruction of reusable work from the previous context.
/// changeContext does not imply canceling network, destroying runway, fetching a URL
/// or reloading database. refresh does not imply clearing cache, restarting the app
/// or downloading all feeds. These decisions belong to Runtime and future policies.
public enum FeedIntent: Hashable, Codable, Sendable {
    case changeContext(FeedContext)
    case refresh
}
