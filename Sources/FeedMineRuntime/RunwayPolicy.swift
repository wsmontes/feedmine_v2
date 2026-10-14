// Owns: pure coverage decisions from explicit measured facts and resource bounds.
import Foundation
import FeedMinePublication

public struct ConsumptionFacts: Hashable, Sendable {
    public let cardsPerSecond: Double?
    public let forwardIntent: Bool
    public let explicitTailApproach: Bool

    public init?(cardsPerSecond: Double?, forwardIntent: Bool, explicitTailApproach: Bool) {
        if let rate = cardsPerSecond, !rate.isFinite || rate < 0 { return nil }
        self.cardsPerSecond = cardsPerSecond
        self.forwardIntent = forwardIntent
        self.explicitTailApproach = explicitTailApproach
    }
}

public struct ReplenishmentFacts: Hashable, Sendable {
    public let p95Seconds: Double?
    public init?(p95Seconds: Double?) {
        if let seconds = p95Seconds, !seconds.isFinite || seconds <= 0 { return nil }
        self.p95Seconds = p95Seconds
    }
}

public struct RunwayPolicyInputs: Hashable, Sendable {
    public let safetyFactor: Double
    public let releaseMarginSeconds: Double
    /// Reserva mínima, em cartas apresentáveis, que o runway mantém à frente do leitor **independentemente** do
    /// alvo derivado de latência.
    ///
    /// A decisão do dono (2026-10-14): a fórmula `taxa × (p95 × fator + margem)` mede o *reabastecimento típico*,
    /// mas o leitor consome em tempo real e uma única oportunidade que demore mais que o p95 esgota a reserva — o
    /// feed chegava ao fim duro e só depois era repovoado. A V1 não tinha esse sintoma porque sempre manteve um
    /// buffer local profundo à frente do leitor. É um piso de **produto**, ajustável, não uma cota de aquisição:
    /// `nil` (default) deixa a fórmula sozinha, como antes.
    public let minimumReserveCards: Int?
    public init?(safetyFactor: Double, releaseMarginSeconds: Double, minimumReserveCards: Int? = nil) {
        guard safetyFactor.isFinite, safetyFactor >= 1,
            releaseMarginSeconds.isFinite, releaseMarginSeconds >= 0,
            minimumReserveCards.map({ $0 > 0 }) ?? true else { return nil }
        self.safetyFactor = safetyFactor
        self.releaseMarginSeconds = releaseMarginSeconds
        self.minimumReserveCards = minimumReserveCards
    }
}

public struct RunwayResourceFacts: Hashable, Sendable {
    public let localWorkAllowed: Bool
    public let examinedCandidateCapacity: Int
    public let readyProbeBound: Int
    public let readyProbeCeiling: Int
    public let forwardAdvanceProbeBound: Int
    /// Bootstrap coverage for a reader whose consumption/replenishment facts are not yet known.
    /// The host may supply its forward materialization capacity here. Once facts are measured,
    /// evaluate derives the reserve from them instead; a known zero rate disables this floor.
    /// Kept under the existing name for host compatibility. nil disables bootstrap coverage.
    public let reserveCards: Int?

    public init?(localWorkAllowed: Bool, examinedCandidateCapacity: Int, readyProbeBound: Int,
        readyProbeCeiling: Int, forwardAdvanceProbeBound: Int, reserveCards: Int? = nil) {
        guard examinedCandidateCapacity > 0, readyProbeBound > 0,
            readyProbeCeiling >= readyProbeBound, forwardAdvanceProbeBound > 0,
            reserveCards.map({ $0 > 0 && $0 <= readyProbeCeiling }) ?? true else { return nil }
        self.reserveCards = reserveCards
        self.localWorkAllowed = localWorkAllowed
        self.examinedCandidateCapacity = examinedCandidateCapacity
        self.readyProbeBound = readyProbeBound
        self.readyProbeCeiling = readyProbeCeiling
        self.forwardAdvanceProbeBound = forwardAdvanceProbeBound
    }
}

public enum RunwayCoverage: Hashable, Sendable {
    case healthy
    case pressured(requiredCards: Int)
    case logicalPressure
    case unknown
}

public enum RunwayPolicyAction: Hashable, Sendable {
    case hold
    case requestReadyProbe(Int)
    case requestLocalSlice
}

public struct RunwayPolicyEvaluation: Hashable, Sendable {
    public let coverage: RunwayCoverage
    public let action: RunwayPolicyAction
}

public struct RunwayFacts: Hashable, Sendable {
    public let consumption: ConsumptionFacts
    public let replenishment: ReplenishmentFacts
    public let readyAmount: ReadyAheadAmount?
    public let previouslyPressured: Bool
    public let localSliceInFlight: Bool
    public let unknownBootstrapAvailable: Bool

    public init(consumption: ConsumptionFacts, replenishment: ReplenishmentFacts,
        readyAmount: ReadyAheadAmount?, previouslyPressured: Bool,
        localSliceInFlight: Bool, unknownBootstrapAvailable: Bool) {
        self.consumption = consumption
        self.replenishment = replenishment
        self.readyAmount = readyAmount
        self.previouslyPressured = previouslyPressured
        self.localSliceInFlight = localSliceInFlight
        self.unknownBootstrapAvailable = unknownBootstrapAvailable
    }
}

public enum RunwayPolicy {
    public static func evaluate(facts: RunwayFacts, inputs: RunwayPolicyInputs,
        resources: RunwayResourceFacts) -> RunwayPolicyEvaluation {
        let consumption = facts.consumption
        let coverage: RunwayCoverage
        if consumption.cardsPerSecond == 0 {
            coverage = consumption.explicitTailApproach || (facts.readyAmount == .exact(0) && consumption.forwardIntent)
                ? .logicalPressure : .healthy
        } else if let rate = consumption.cardsPerSecond, let latency = facts.replenishment.p95Seconds {
            let duration = latency * inputs.safetyFactor + (facts.previouslyPressured ? inputs.releaseMarginSeconds : 0)
            let rawThreshold = ceil(rate * duration)
            // Out-of-representation measured coverage remains unknown, never clamped healthy.
            if rawThreshold.isFinite, let measured = Int(exactly: rawThreshold), measured >= 0 {
                // O piso de produto nunca é menor que o alvo medido: ele existe para o jitter de uma oportunidade
                // que demora mais que o p95, não para substituir a medição.
                let threshold = max(measured, inputs.minimumReserveCards ?? 0)
                switch facts.readyAmount {
                case .exact(let count):
                    coverage = count >= threshold ? .healthy : .pressured(requiredCards: threshold)
                case .atLeast(let bound):
                    if bound >= threshold { coverage = .healthy }
                    else {
                        let next = min(threshold, resources.readyProbeCeiling)
                        if next > bound {
                            return RunwayPolicyEvaluation(coverage: .unknown, action: .requestReadyProbe(next))
                        }
                        coverage = .unknown
                    }
                case nil: coverage = .unknown
                }
            } else { coverage = .unknown }
        } else {
            coverage = facts.readyAmount == .exact(0) && (consumption.forwardIntent || consumption.explicitTailApproach)
                ? .logicalPressure : .unknown
        }
        // The forward window protects bootstrap only. Measured demand replaces it, including
        // demand below that window and a known stationary reader. Invalid/overflowing measured
        // targets remain unknown rather than falling back to an unrelated bootstrap count.
        let needsBootstrap = consumption.cardsPerSecond == nil
            || (consumption.cardsPerSecond != 0 && facts.replenishment.p95Seconds == nil)
        var floored = coverage
        let bootstrapReserve = needsBootstrap
            ? [resources.reserveCards, inputs.minimumReserveCards].compactMap { $0 }.max() : nil
        if let reserve = bootstrapReserve {
            switch facts.readyAmount {
            case .exact(let count) where count < reserve:
                if case .pressured(let required) = floored { floored = .pressured(requiredCards: max(required, reserve)) }
                else if floored != .logicalPressure { floored = .pressured(requiredCards: reserve) }
            case .atLeast(let bound) where bound < reserve:
                if floored == .healthy || floored == .unknown {
                    return RunwayPolicyEvaluation(coverage: .unknown, action: .requestReadyProbe(reserve))
                }
            default: break
            }
        }
        let action: RunwayPolicyAction
        switch floored {
        case .healthy: action = .hold
        case .pressured, .logicalPressure:
            action = resources.localWorkAllowed && !facts.localSliceInFlight ? .requestLocalSlice : .hold
        case .unknown:
            action = facts.unknownBootstrapAvailable && resources.localWorkAllowed && !facts.localSliceInFlight
                && (consumption.forwardIntent || consumption.explicitTailApproach) ? .requestLocalSlice : .hold
        }
        return RunwayPolicyEvaluation(coverage: floored, action: action)
    }
}

/// Nearest-rank over the controller's bounded positive successful measurements.
func runwayP95(_ samples: [Double]) -> Double? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
    return sorted[rank - 1]
}
