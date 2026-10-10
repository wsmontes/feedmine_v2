// Owns the received local snapshot and caller-reported work condition for a future screen.
// Runtime remains the authority for every occurrence, Edition and logical anchor.
import FeedMineRuntime

public enum FeedPresentationStateError: Error, Equatable, Sendable {
    case presentationIdentityMismatch
    case staleProjection
    case projectionSequenceMismatch
    case inconsistentProjectionOrder
}

public extension FeedPresentationState.Work {
    /// The short status the reader's chip states. It describes receiving work only; it never claims
    /// content that is not there (INV-06) and never implies the feed changed.
    var shortDescription: String {
        switch self {
        case .idle: ""
        case .pending: String(localized: "Buscando novidades")
        case .preparing: String(localized: "Preparando")
        case .unavailable: String(localized: "Sem conexão")
        case .deferred: String(localized: "Aguardando")
        case .failed(let message): message
        }
    }
}

public struct FeedPresentationState: Hashable, Sendable {
    public enum Work: Hashable, Sendable {
        case idle
        case pending
        case unavailable
        case deferred
        case failed(message: String)
        /// PD-3: first-launch preparation with real evidence of content arriving.
        case preparing(PreparationProgress)
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
            guard snapshot.provenance.sequenceID == presentation.provenance.sequenceID else {
                throw FeedPresentationStateError.projectionSequenceMismatch
            }
            guard snapshot.provenance.position >= presentation.provenance.position else {
                throw FeedPresentationStateError.staleProjection
            }
            if snapshot.provenance.position == presentation.provenance.position {
                guard snapshot == presentation else { throw FeedPresentationStateError.inconsistentProjectionOrder }
                return self
            }
        }
        return .init(presentation: snapshot, work: work)
    }
}
