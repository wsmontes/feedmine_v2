//
// File: MediaPreparationTrace.swift
// Module: FeedMineRuntime
//
// Responsibility:
// The evidence one run needs to answer what the supply media-preparation path did with every revision it
// **considered for publication**: what the feed declared, which outcome the preparation reached, and how long
// the revision took from first consideration to settlement. Also the fact a published card states — whether its
// revision declared an image and whether the card actually carries media.
//
// It reports through the existing `ReplenishmentTrace` port (the host already maps that to its line-oriented
// run trace); this file invents no second sink and writes no file. It reads nothing to choose anything: every
// value is stated after the decision that produced it.
//
// DEBUG only: a shipping build compiles no part of this file, and the host passes no trace. Cost when a trace
// exists is two bounded store reads per considered revision — supply preparation, not a per-frame path.
import Foundation

#if DEBUG
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication

/// What the feed's own document declared for a revision, as the store holds it. `unknown` is the absence of
/// evidence (the record could not be read), never a claim that the feed declared nothing.
enum DeclaredCardImage: String, Sendable {
    case declared = "true"
    case none = "false"
    case unknown = "unknown"
}

/// The facts the trace states about one revision, read once when the line is written.
struct MediaRevisionFacts: Sendable {
    let sources: [SourceID]
    let declaredImage: DeclaredCardImage

    /// The revision's declaration and memberships. A card image is what the feed declared as a **visible** card
    /// visual: a playback enclosure (audio/video) is not one, even though it is also a media candidate.
    static func read(_ revision: OriginRevisionID, in store: ContentStore) -> MediaRevisionFacts {
        let candidates: [MediaCandidate]? = (try? store.mediaCandidates(originRevisionID: revision)) ?? nil
        let declared: DeclaredCardImage
        if let candidates {
            declared = candidates.contains { $0.role == .cardVisual && $0.mediaClass == .image }
                ? .declared : .none
        } else {
            declared = .unknown
        }
        let record = ((try? store.originRevision(id: revision)) ?? nil)
        let sources = record.flatMap { (try? store.memberships(originRecordID: $0.originRecordID)) }?
            .map(\.sourceID) ?? []
        return MediaRevisionFacts(sources: sources, declaredImage: declared)
    }
}

/// The settlement line's vocabulary, mapped once from the outcomes the preparation owner already states. The
/// two transient outcomes (`failed`, `insufficientSpace`) are one fact for a reader of the trace — "try again" —
/// and are never reported as `unavailable`, which is definitive.
enum MediaSettlementOutcome: String, Sendable {
    case readyImage = "ready-image"
    case unavailable
    case transientFailed = "transient-failed"
    case deferred
    case textOnly = "text-only"

    init(_ outcome: MediaPreparationOutcome) {
        switch outcome {
        case .ready: self = .readyImage
        case .unavailable: self = .unavailable
        case .textOnly: self = .textOnly
        case .deferred: self = .deferred
        case .failed, .insufficientSpace: self = .transientFailed
        }
    }
}

/// One run's evidence for the supply media-preparation path.
///
/// The first instant a revision is handed to the path is remembered, so every later attempt reports the whole
/// wait, not just its own slice of it. A line is written when an attempt ends — including the attempts that end
/// without settling (`deferred`, `transient-failed`) — because silence there reads as "nothing happened" when
/// the truth is "the revision is still pending". A revision that settles is offered no work again, so its
/// terminal line exists once; a deferred or transient revision may earn a later line when it is retried.
final class MediaPreparationWitness: @unchecked Sendable {
    private let trace: ReplenishmentTrace
    private let clock: @Sendable () -> Double
    private let lock = NSLock()
    private var firstConsideration: [OriginRevisionID: Double] = [:]

    init(trace: ReplenishmentTrace, clock: @escaping @Sendable () -> Double) {
        self.trace = trace
        self.clock = clock
    }

    /// Every revision the path is handed is one it considers for publication. Only the earliest instant is
    /// kept: the elapsed time a run reads is the one the reader waited through.
    func consider(_ revisions: [OriginRevisionID]) {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        for revision in revisions where firstConsideration[revision] == nil {
            firstConsideration[revision] = now
        }
    }

    /// One line for this attempt's end: the revision, its source, what the feed declared, the outcome and the
    /// whole interval since first consideration.
    func settle(_ revision: OriginRevisionID, outcome: MediaPreparationOutcome, facts: MediaRevisionFacts) {
        lock.lock()
        let considered = firstConsideration[revision] ?? clock()
        let elapsed = max(0, clock() - considered)
        lock.unlock()
        trace.record(ReplenishmentEvent.mediaSettled, [
            "revision": revision.rawValue.uuidString,
            "source": facts.sources.isEmpty ? "none"
                : facts.sources.map(\.rawValue.uuidString).sorted().joined(separator: ","),
            "declared_image": facts.declaredImage.rawValue,
            "outcome": MediaSettlementOutcome(outcome).rawValue,
            "elapsed_ms": String(Int((elapsed * 1000).rounded()))
        ])
    }
}

/// The publication half: one line per card that reached history, stating the revision it froze, what that
/// revision's feed declared and whether the card actually carries media. Called only on a successful append, so
/// a line is a publication that happened — never an intention.
enum MediaPreparationTrace {
    static func recordPublished(_ drafts: [PublicationCardDraft], in store: ContentStore,
        to trace: ReplenishmentTrace?) {
        guard let trace else { return }
        for draft in drafts {
            let facts = MediaRevisionFacts.read(draft.origin.originRevisionID, in: store)
            trace.record(ReplenishmentEvent.mediaPublished, [
                "revision": draft.origin.originRevisionID.rawValue.uuidString,
                "source": draft.origin.sourceID?.rawValue.uuidString ?? "none",
                "declared_image": facts.declaredImage.rawValue,
                "media": draft.media.primary == nil ? "none" : "image",
                "layout": draft.renderContract.layout.rawValue
            ])
        }
    }
}
#endif
