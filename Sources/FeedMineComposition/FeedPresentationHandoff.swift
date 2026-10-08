// Stateless composition of existing outcomes into the sole screen presentation value.
// Every execution opportunity remains an explicit caller operation.
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
        case .localWorkRemaining, .noPublicationAfterAcquisition:
            return state.reporting(.idle)
        case .unavailable:
            return state.reporting(.unavailable)
        case .deferred:
            return state.reporting(.deferred)
        }
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

    /// Forwards exact semantic inputs once and receives the driver's projection unchanged.
    /// Errors propagate; the caller retains its prior state and chooses any failure report.
    public static func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity,
        resources: FeedRunwayDriverResources, driver: FeedRunwayDriver,
        into state: FeedPresentationState) async throws -> FeedPresentationState {
        let snapshot = try await driver.submitViewport(observation, activity: activity, resources: resources)
        return try receive(snapshot: snapshot, into: state)
    }
}
