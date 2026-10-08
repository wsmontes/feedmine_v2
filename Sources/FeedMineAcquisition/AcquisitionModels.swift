// Semantic need for canonical supply; external execution is owned downstream.
import FeedMineDomain

public enum AcquisitionPurpose: Hashable, Sendable {
    case readerContinuation
}

public enum AcquisitionPressure: Hashable, Sendable {
    case coverageDeficit(requiredCards: Int)
    case logicalTailPressure
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
    public let localSupply: ExhaustedLocalSupply

    public init?(contextKey: ContextKey, editorialRevisionID: EditorialRevisionID,
        purpose: AcquisitionPurpose, pressure: AcquisitionPressure, localSupply: ExhaustedLocalSupply) {
        if case .coverageDeficit(let required) = pressure {
            guard required > 0, required > localSupply.readyCards else { return nil }
        }
        self.contextKey = contextKey
        self.editorialRevisionID = editorialRevisionID
        self.purpose = purpose
        self.pressure = pressure
        self.localSupply = localSupply
    }
}
