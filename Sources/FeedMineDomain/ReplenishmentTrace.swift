//
// File: ReplenishmentTrace.swift
// Module: FeedMineDomain
//
// Responsibility:
// The optional evidence port the replenishment chain reports through: when supply was **requested**, when the data
// **arrived**, and what destination **concluded** the attempt. One vocabulary instead of four spellings, so the
// owners of the three points (Runtime, Editorial, Acquisition, Publication) say the same thing — and so a host can
// hand the same value to all of them.
//
// Does not own: any decision, any storage, any clock and any I/O. Nothing here is consulted before a decision: a
// trace that can change what it measures is not evidence. A `nil` trace is the default everywhere, and the
// behavior without one is exactly the behavior this module had before the port existed.
import Foundation

/// One logical replenishment attempt: from the decision that asked for supply to the destination that concluded it.
///
/// It exists to make the three intervals of one attempt comparable — requested → arrived → admitted/published —
/// without attributing them to an Edition or to a gesture. It is minted where the attempt is decided and carried
/// inside the intent the decision produced, so the executor that finishes the work still knows which attempt it
/// belongs to.
public struct FeedReplenishmentOperationID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
    /// The spelling a reader of the trace sees.
    public var described: String { rawValue.uuidString }
}

/// The optional sink. `record` is called **synchronously at the measured instant** and must not block: the host's
/// implementation buffers in memory and writes off the caller's thread, because a trace that puts I/O on the path
/// it measures changes what it measures (measured: a B03 run died on a UI query timeout when it did).
public struct ReplenishmentTrace: Sendable {
    private let sink: @Sendable (String, [String: String]) -> Void
    public init(_ sink: @escaping @Sendable (String, [String: String]) -> Void) { self.sink = sink }
    public func record(_ event: String, _ fields: [String: String] = [:]) { sink(event, fields) }
}

/// The three events, declared once. Field names are the contract the trace documents; each producer states what it
/// knows at its own point and never fabricates a fact it did not observe.
public enum ReplenishmentEvent {
    /// The decision that asked for supply: `RunwayController.reconsider` choosing a local slice or a network
    /// acquisition, with the kind and the coverage facts it decided on. Fields: `op`, `kind` (`local`/`network`),
    /// `edition`, `surface`, `coverage`, `ready` (+ `ready_cards`/`ready_bound`).
    public static let requested = "replenishment_requested"
    /// The return of the local consult or of the network pull, with quantity and result — **including empty,
    /// failure and cancellation**, because those are outcomes, not silence. Fields: `op`, `kind`, `result`, and the
    /// quantities the owner has (`candidates`/`examined`/`exhausted` locally, `observations`/`bytes`/`failure` for
    /// a pull).
    public static let arrived = "replenishment_arrived"
    /// The destination that concluded the attempt, stated explicitly: `destination` is `pool_admission` (durable
    /// supply exists; nothing is offered to the reader yet) or `segment_publication` (a segment is frozen into
    /// history; the host still has to install it, which is what `admitted` records).
    public static let concluded = "replenishment_concluded"

    /// One origin revision the supply media-preparation path **considered for publication**, at the moment an
    /// attempt ended: `revision`, `source`, `declared_image` (`true`/`false`/`unknown`), `outcome`
    /// (`ready-image`/`unavailable`/`transient-failed`/`deferred`/`text-only`) and `elapsed_ms` since the first
    /// consideration. `transient-failed` is a retry, never the definitive `unavailable`.
    public static let mediaSettled = "media_preparation_settled"
    /// One card that reached history: `revision`, `source`, `declared_image`, `media` (`image`/`none`) and
    /// `layout`. Written only after the append succeeded, so the line is a publication, not an intention.
    public static let mediaPublished = "media_card_published"

    /// The trace's own record that it **lost** events — the ceiling, a failed encoding, a write that never landed.
    /// Without it a run whose evidence was discarded looks exactly like a run where nothing happened.
    public static let truncated = "trace_truncated"
}
