// Owns the received local snapshot and caller-reported work condition for a future screen.
// Runtime remains the authority for every occurrence, Edition and logical anchor.
import FeedMineRuntime

public enum FeedPresentationStateError: Error, Equatable, Sendable {
    case presentationIdentityMismatch
}

public struct FeedPresentationState: Hashable, Sendable {
    public enum Work: Hashable, Sendable {
        case idle
        case pending
        case unavailable
        case deferred
        case failed(message: String)
    }

    public let presentation: FeedPresentationSnapshot?
    public let work: Work

    public init(presentation: FeedPresentationSnapshot?) {
        self.presentation = presentation
        work = .idle
    }

    private init(presentation: FeedPresentationSnapshot?, work: Work) {
        self.presentation = presentation
        self.work = work
    }

    /// Work reports never remove or modify an available local presentation.
    public func reporting(_ work: Work) -> Self {
        .init(presentation: presentation, work: work)
    }

    /// Accepts the first snapshot or an exact Runtime projection within the current identity.
    /// Receiving a projection does not imply that independently reported work has settled.
    public func receiving(_ snapshot: FeedPresentationSnapshot) throws -> Self {
        if let presentation {
            guard snapshot.editionID == presentation.editionID,
                snapshot.contextKey == presentation.contextKey else {
                throw FeedPresentationStateError.presentationIdentityMismatch
            }
        }
        return .init(presentation: snapshot, work: work)
    }
}
