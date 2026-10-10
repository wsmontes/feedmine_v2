// Semantic need for canonical supply; external execution is owned downstream.
import FeedMineDomain

public enum AcquisitionPurpose: Hashable, Sendable {
    case readerContinuation
    case initialPublication
}

public enum AcquisitionPressure: Hashable, Sendable {
    case coverageDeficit(requiredCards: Int)
    case logicalTailPressure
    case initialPublication
    case selectedSourceCoverage
}

/// Construction asserts that the relevant bounded local structural walk completed.
public struct ExhaustedLocalSupply: Hashable, Sendable {
    public let readyCards: Int
    public init?(readyCards: Int) {
        guard readyCards >= 0 else { return nil }
        self.readyCards = readyCards
    }
}

public struct AcquisitionDemand: Hashable, Sendable {
    public let contextKey: ContextKey
    public let editorialRevisionID: EditorialRevisionID
    public let purpose: AcquisitionPurpose
    public let pressure: AcquisitionPressure
    public let localSupply: ExhaustedLocalSupply?

    /// A finite opportunity for selected targets, independent of published depth. No local
    /// exhaustion assertion is made: local presentation may already be fully covered.
    public init(selectedSourceCoverageFor contextKey: ContextKey, editorialRevisionID: EditorialRevisionID) {
        self.contextKey = contextKey
        self.editorialRevisionID = editorialRevisionID
        purpose = .readerContinuation
        pressure = .selectedSourceCoverage
        localSupply = nil
    }

    public init?(contextKey: ContextKey, editorialRevisionID: EditorialRevisionID,
        purpose: AcquisitionPurpose, pressure: AcquisitionPressure, localSupply: ExhaustedLocalSupply) {
        switch (purpose, pressure) {
        case (.readerContinuation, .coverageDeficit(let required)):
            guard required > 0, required > localSupply.readyCards else { return nil }
        case (.readerContinuation, .logicalTailPressure):
            break
        case (.initialPublication, .initialPublication):
            guard localSupply.readyCards == 0 else { return nil }
        default:
            return nil
        }
        self.contextKey = contextKey
        self.editorialRevisionID = editorialRevisionID
        self.purpose = purpose
        self.pressure = pressure
        self.localSupply = localSupply
    }
}
