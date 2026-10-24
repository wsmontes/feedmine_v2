// Stateless composition of existing outcomes into the sole screen presentation value.
// Every execution opportunity remains an explicit caller operation.
import FeedMineAcquisition
import FeedMineRuntime
import FeedMineUI

public enum FeedPresentationHandoff {
    /// A missing new projection never removes existing presentation or settles work implicitly.
    public static func receive(snapshot: FeedPresentationSnapshot?,
        into state: FeedPresentationState) throws -> FeedPresentationState {
        guard let snapshot else { return state }
        return try state.receiving(snapshot)
    }

    /// Maps a settled finite cold opportunity without inventing visual success from supply alone.
    public static func receive(coldOutcome: ColdFeedBootstrapOutcome,
        into state: FeedPresentationState) throws -> FeedPresentationState {
        switch coldOutcome {
        case .published(let snapshot):
            return try state.receiving(snapshot).reporting(.idle)
        case .localWorkRemaining:
            return state.reporting(.idle)
        case .noPublicationAfterAcquisition(_, let results):
            // R5/PO: the acquisition attempt finished without eligible stories. That is the reader's whole
            // situation only when there is no presentation to preserve; with cards on screen the same fact
            // stays quiet, so a working feed never acquires a "no stories" chip.
            // F-UX-2: finishing without eligible stories is not the only way an attempt ends without one, and an
            // absence caused by a transport that could not connect is not the absence of stories. The transports
            // that settled are the evidence for the difference; supply absence alone never is. The reader is
            // told the connection failed and offered only the action that can act on it.
            guard state.presentation == nil else { return state.reporting(.idle) }
            return state.reporting(transportFailed(results) ? .unreachable : .unavailable)
        case .unavailable:
            return state.reporting(.unavailable)
        case .deferred:
            return state.reporting(.deferred)
        }
    }

    /// The one fact that separates "the source could not be reached" from "the source had nothing to give": the
    /// transport failure the connector itself stated. `remoteResponse` and `remoteContent` are the source answering
    /// badly or unreadably — not connectivity — so they keep the absence state.
    private static func transportFailed(_ results: [AcquisitionExecutionResult]) -> Bool {
        results.contains { $0.stop == .operationalFailure(.transport) }
    }

    /// Acquisition settlement changes a work fact only; it supplies no published projection.
    public static func receive(acquisitionOutcome: RunwayAcquisitionCycleOutcome,
        into state: FeedPresentationState) -> FeedPresentationState {
        switch acquisitionOutcome {
        case .executed:
            return state.reporting(.idle)
        case .acceptedUnavailable:
            return state.reporting(.unavailable)
        case .deferred:
            return state.reporting(.deferred)
        }
    }

    /// The external consumer reports actual pending work, completion or a chosen failure message.
    public static func report(_ work: FeedPresentationState.Work,
        into state: FeedPresentationState) -> FeedPresentationState {
        state.reporting(work)
    }

    /// PO 2026-10-14: the end of the reader's eligible offer is decided here, and only from the full settled
    /// evidence. A provisional report is kept provisional: an empty local window, a finished acquisition round
    /// and an unavailable source each keep their own state, and none of them is the end.
    public static func work(settledEligibleOffer settlement: FeedEligibleOfferSettlement) -> FeedPresentationState.Work {
        guard settlement.isEligibleOfferExhausted else {
            switch settlement.acquisition {
            case .executed: return .idle
            case .deferred: return .deferred
            case .acceptedUnavailable: return .unavailable
            }
        }
        return .endOfContent
    }

    public static func receive(settledEligibleOffer settlement: FeedEligibleOfferSettlement,
        into state: FeedPresentationState) -> FeedPresentationState {
        state.reporting(work(settledEligibleOffer: settlement))
    }

    /// Forwards exact semantic inputs once and receives the driver's projection unchanged.
    /// Errors propagate; the caller retains its prior state and chooses any failure report.
    public static func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity,
        resources: FeedRunwayDriverResources, driver: FeedRunwayDriver,
        into state: FeedPresentationState, evidence: RenderedViewportEvidence? = nil,
        sampledAt: RunwayMonotonicTime? = nil,
        onCommitted: (@Sendable (FeedPresentationSnapshot) async -> Void)? = nil) async throws -> FeedPresentationState {
        let snapshot: FeedPresentationSnapshot?
        if let evidence {
            snapshot = try await driver.submitViewport(evidence, activity: activity,
                resources: resources, sampledAt: sampledAt, onCommitted: onCommitted)
        } else {
            snapshot = try await driver.submitViewport(observation, activity: activity,
                resources: resources, sampledAt: sampledAt, onCommitted: onCommitted)
        }
        return try receive(snapshot: snapshot, into: state)
    }
}
