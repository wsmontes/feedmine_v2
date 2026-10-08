// Observable screen value and explicit semantic input forwarding.
// External composition supplies state and owns every execution opportunity.
import Observation
import FeedMineRuntime

@MainActor
@Observable
public final class FeedScreenStore {
    public private(set) var state: FeedPresentationState
    @ObservationIgnored
    private let onViewport: @MainActor (ViewportObservation, RunwayActivity) -> Void

    public init(onViewport: @escaping @MainActor (ViewportObservation, RunwayActivity) -> Void) {
        state = FeedPresentationState(presentation: nil)
        self.onViewport = onViewport
    }

    /// Receives the value computed by external composition using the existing handoff.
    /// Reception delegates identity rules to the state contract; absence retains visible content.
    /// A rejected snapshot leaves the entire observable value unchanged.
    public func install(_ received: FeedPresentationState) throws {
        let presentationState: FeedPresentationState
        if let snapshot = received.presentation {
            presentationState = try state.receiving(snapshot)
        } else {
            presentationState = state
        }
        state = presentationState.reporting(received.work)
    }

    /// Emits one explicit user observation. The external consumer decides how to execute it.
    public func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity) {
        onViewport(observation, activity)
    }
}
