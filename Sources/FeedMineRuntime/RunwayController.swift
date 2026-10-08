// Owns: memory-only observation, bounded measurements and one operational local intent.
import Foundation
import FeedMineDomain
import FeedMineEditorial
import FeedMinePublication

public struct RunwayMonotonicTime: Hashable, Sendable, Comparable {
    public let seconds: Double
    public init?(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        self.seconds = seconds
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.seconds < rhs.seconds }
}

public enum RunwayActivity: Hashable, Sendable {
    case forward, stationary, backward, explicitTailApproach
}
public enum RunwayProductionLane: Hashable, Sendable { case episode, headReconsideration }
public enum RunwayLocalFailure: Hashable, Sendable { case failed, cancelled }
public enum RunwayControllerError: Error, Equatable, Sendable {
    case noActiveScope, scopeMismatch, nonMonotonicObservation, staleMeasurement
    case invalidMeasurement, staleCompletion, invalidCompletionTime, completionScopeMismatch
}

public struct RunwayObservation: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let anchorCardID: PublicationCardID
    public let sampledAt: RunwayMonotonicTime
    public let activity: RunwayActivity
    public init(editionID: FeedEditionID, anchorCardID: PublicationCardID, sampledAt: RunwayMonotonicTime, activity: RunwayActivity) {
        self.editionID = editionID
        self.anchorCardID = anchorCardID
        self.sampledAt = sampledAt
        self.activity = activity
    }
}

public struct RunwayScope: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let contextKey: ContextKey
    public let editorialRevisionID: EditorialRevisionID
    public init(editionID: FeedEditionID, contextKey: ContextKey, editorialRevisionID: EditorialRevisionID) {
        self.editionID = editionID
        self.contextKey = contextKey
        self.editorialRevisionID = editorialRevisionID
    }
}

public struct RunwayAdvanceMeasurementRequest: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let fromCardID: PublicationCardID
    public let toCardID: PublicationCardID
    public let probeBound: Int
    public init(editionID: FeedEditionID, fromCardID: PublicationCardID, toCardID: PublicationCardID, probeBound: Int) {
        self.editionID = editionID
        self.fromCardID = fromCardID
        self.toCardID = toCardID
        self.probeBound = probeBound
    }
}

public struct RunwayMeasurementRequest: Hashable, Sendable {
    public let scope: RunwayScope
    public let observation: RunwayObservation
    public let readyProbeBound: Int
    public let advance: RunwayAdvanceMeasurementRequest?
    public init(scope: RunwayScope, observation: RunwayObservation, readyProbeBound: Int, advance: RunwayAdvanceMeasurementRequest?) {
        self.scope = scope
        self.observation = observation
        self.readyProbeBound = readyProbeBound
        self.advance = advance
    }
}

public struct RunwayMeasurement: Hashable, Sendable {
    public let observation: RunwayObservation
    public let readyAhead: ReadyAheadFacts
    public let advanceFromHighWater: PublicationAdvanceFacts?
    public init(observation: RunwayObservation, readyAhead: ReadyAheadFacts, advanceFromHighWater: PublicationAdvanceFacts?) {
        self.observation = observation
        self.readyAhead = readyAhead
        self.advanceFromHighWater = advanceFromHighWater
    }
}

public struct RunwayLocalSliceIntent: Hashable, Sendable {
    public let scope: RunwayScope
    public let lane: RunwayProductionLane
    public let after: CandidateSupplyCursor?
    public let examinedCapacity: Int
    public let startedAt: RunwayMonotonicTime
    public init(scope: RunwayScope, lane: RunwayProductionLane, after: CandidateSupplyCursor?, examinedCapacity: Int, startedAt: RunwayMonotonicTime) {
        self.scope = scope
        self.lane = lane
        self.after = after
        self.examinedCapacity = examinedCapacity
        self.startedAt = startedAt
    }
}

public struct RunwayControllerSnapshot: Hashable, Sendable {
    public let scope: RunwayScope?
    public let latestObservation: RunwayObservation?
    public let consumption: ConsumptionFacts
    public let replenishment: ReplenishmentFacts
    public let readyAhead: ReadyAheadFacts?
    public let lastCoverage: RunwayCoverage?
    public let localSliceInFlight: Bool
    public let pendingSupplyReset: Bool
    public let localSupplyExhausted: Bool
    public let lastLocalFailure: RunwayLocalFailure?
}

public struct RunwayControllerConfiguration: Hashable, Sendable {
    public let policyInputs: RunwayPolicyInputs
    public let consumptionSampleLimit: Int
    public let replenishmentSampleLimit: Int
    public init?(policyInputs: RunwayPolicyInputs, consumptionSampleLimit: Int, replenishmentSampleLimit: Int) {
        guard consumptionSampleLimit > 0, replenishmentSampleLimit > 0 else { return nil }
        self.policyInputs = policyInputs
        self.consumptionSampleLimit = consumptionSampleLimit
        self.replenishmentSampleLimit = replenishmentSampleLimit
    }
}

public enum RunwayControllerAction: Hashable, Sendable {
    case none
    case measure(RunwayMeasurementRequest)
    case runLocalSlice(RunwayLocalSliceIntent)
}

/// Serializes observation, measurement, supply signals and completions for one active scope.
public actor RunwayController {
    private struct Progress {
        var cursor: CandidateSupplyCursor?
        var exhausted = false
    }
    private let configuration: RunwayControllerConfiguration
    private var scope: RunwayScope?
    private var latestObservation: RunwayObservation?
    private var lastMeasuredObservation: RunwayObservation?
    private var highWater: PublicationCardID?
    private var readyAhead: ReadyAheadFacts?
    private var consumptionSamples: [Double] = []
    private var latencySamples: [Double] = []
    private var inFlight: RunwayLocalSliceIntent?
    private var attemptStartedAt: RunwayMonotonicTime?
    private var episode = Progress()
    private var head: Progress?
    private var pendingReset = false
    private var preferredLane: RunwayProductionLane = .episode
    private var bootstrapObservation: RunwayObservation?
    private var lastFailure: RunwayLocalFailure?
    private var lastCoverage: RunwayCoverage?
    private var previouslyPressured = false

    public init(configuration: RunwayControllerConfiguration) { self.configuration = configuration }

    public func activate(_ scope: RunwayScope) {
        deactivate()
        self.scope = scope
    }

    public func deactivate() {
        scope = nil
        markConsumptionInactive()
        latencySamples = []
        inFlight = nil
        attemptStartedAt = nil
        episode = Progress()
        head = nil
        pendingReset = false
        preferredLane = .episode
        lastFailure = nil
        lastCoverage = nil
        previouslyPressured = false
    }

    public func markConsumptionInactive() {
        latestObservation = nil
        lastMeasuredObservation = nil
        readyAhead = nil
        highWater = nil
        consumptionSamples = []
        bootstrapObservation = nil
    }

    public func submitObservation(_ observation: RunwayObservation) throws {
        guard let scope else { throw RunwayControllerError.noActiveScope }
        guard observation.editionID == scope.editionID else { throw RunwayControllerError.scopeMismatch }
        if let latestObservation, observation.sampledAt <= latestObservation.sampledAt {
            throw RunwayControllerError.nonMonotonicObservation
        }
        latestObservation = observation
        readyAhead = nil
        lastFailure = nil
    }

    private var consumption: ConsumptionFacts {
        ConsumptionFacts(cardsPerSecond: consumptionSamples.max(),
            forwardIntent: latestObservation?.activity == .forward,
            explicitTailApproach: latestObservation?.activity == .explicitTailApproach)!
    }

    private func measurementRequest(_ observation: RunwayObservation, scope: RunwayScope,
        bound: Int, advanceBound: Int?) -> RunwayControllerAction {
        let advance: RunwayAdvanceMeasurementRequest?
        if let highWater, let advanceBound, observation != lastMeasuredObservation {
            advance = RunwayAdvanceMeasurementRequest(editionID: scope.editionID,
                fromCardID: highWater, toCardID: observation.anchorCardID, probeBound: advanceBound)
        } else { advance = nil }
        return .measure(RunwayMeasurementRequest(scope: scope, observation: observation,
            readyProbeBound: bound, advance: advance))
    }

    public func reconsider(resources: RunwayResourceFacts, at now: RunwayMonotonicTime) throws -> RunwayControllerAction {
        guard let scope, let observation = latestObservation else { return .none }
        guard inFlight == nil, lastFailure == nil else { return .none }
        guard let readyAhead else {
            return measurementRequest(observation, scope: scope, bound: resources.readyProbeBound,
                advanceBound: resources.forwardAdvanceProbeBound)
        }
        let evaluation = RunwayPolicy.evaluate(facts: RunwayFacts(consumption: consumption,
            replenishment: ReplenishmentFacts(p95Seconds: runwayP95(latencySamples))!,
            readyAmount: readyAhead.amount, previouslyPressured: previouslyPressured,
            localSliceInFlight: false, unknownBootstrapAvailable: bootstrapObservation != observation),
            inputs: configuration.policyInputs, resources: resources)
        lastCoverage = evaluation.coverage
        switch evaluation.coverage {
        case .healthy: previouslyPressured = false
        case .pressured, .logicalPressure: previouslyPressured = true
        case .unknown: break
        }
        switch evaluation.action {
        case .hold: return .none
        case .requestReadyProbe(let bound):
            return measurementRequest(observation, scope: scope, bound: bound, advanceBound: nil)
        case .requestLocalSlice:
            guard let lane = selectLane() else { return .none }
            let progress = lane == .episode ? episode : head!
            let intent = RunwayLocalSliceIntent(scope: scope, lane: lane, after: progress.cursor,
                examinedCapacity: resources.examinedCandidateCapacity, startedAt: now)
            inFlight = intent
            if attemptStartedAt == nil { attemptStartedAt = now }
            if evaluation.coverage == .unknown { bootstrapObservation = observation }
            return .runLocalSlice(intent)
        }
    }

    public func acceptMeasurement(_ measurement: RunwayMeasurement) throws {
        guard let scope, measurement.observation == latestObservation else {
            throw RunwayControllerError.staleMeasurement
        }
        let observation = measurement.observation
        guard measurement.readyAhead.editionID == scope.editionID,
            measurement.readyAhead.anchorCardID == observation.anchorCardID else {
            throw RunwayControllerError.invalidMeasurement
        }
        if highWater == nil {
            guard measurement.advanceFromHighWater == nil else { throw RunwayControllerError.invalidMeasurement }
            highWater = observation.anchorCardID
        } else if observation != lastMeasuredObservation {
            guard let previous = lastMeasuredObservation, let advance = measurement.advanceFromHighWater,
                advance.editionID == scope.editionID, advance.fromCardID == highWater,
                advance.toCardID == observation.anchorCardID else { throw RunwayControllerError.invalidMeasurement }
            let elapsed = observation.sampledAt.seconds - previous.sampledAt.seconds
            guard elapsed > 0 else { throw RunwayControllerError.invalidMeasurement }
            switch advance.advance {
            case .same, .backward:
                appendConsumption(0)
            case .forwardExact(let count):
                let rate = Double(count) / elapsed
                guard count >= 0, rate.isFinite else { throw RunwayControllerError.invalidMeasurement }
                appendConsumption(rate)
                if count > 0 { highWater = observation.anchorCardID }
            case .forwardBeyondProbe:
                consumptionSamples = []
                highWater = observation.anchorCardID
            }
        }
        lastMeasuredObservation = observation
        readyAhead = measurement.readyAhead
    }

    private func appendConsumption(_ rate: Double) {
        consumptionSamples.append(rate)
        if consumptionSamples.count > configuration.consumptionSampleLimit { consumptionSamples.removeFirst() }
    }

    private func validateCompletion(_ intent: RunwayLocalSliceIntent, at time: RunwayMonotonicTime) throws {
        guard intent == inFlight, intent.scope == scope else { throw RunwayControllerError.staleCompletion }
        guard time > intent.startedAt else { throw RunwayControllerError.invalidCompletionTime }
    }

    public func completeLocalSlice(_ intent: RunwayLocalSliceIntent, outcome: LocalProductionSliceOutcome,
        at completedAt: RunwayMonotonicTime) throws {
        try validateCompletion(intent, at: completedAt)
        let progress: LocalProductionProgress
        let published: Bool
        switch outcome {
        case .advancedWithoutPublication(let value): progress = value; published = false
        case .published(let value, let receipt):
            guard receipt.editionID == scope?.editionID else { throw RunwayControllerError.completionScopeMismatch }
            progress = value; published = true
        }
        let latency = completedAt.seconds - (attemptStartedAt ?? intent.startedAt).seconds
        if published, latency <= 0 { throw RunwayControllerError.invalidCompletionTime }
        let updated = Progress(cursor: progress.nextCursor, exhausted: progress.exhausted)
        if intent.lane == .episode { episode = updated }
        else if progress.exhausted { episode = updated; head = nil }
        else { head = updated }
        inFlight = nil
        if published {
            latencySamples.append(latency)
            if latencySamples.count > configuration.replenishmentSampleLimit { latencySamples.removeFirst() }
            attemptStartedAt = nil
            readyAhead = nil
        } else if progress.exhausted { attemptStartedAt = nil }
    }

    public func failLocalSlice(_ intent: RunwayLocalSliceIntent, failure: RunwayLocalFailure,
        at completedAt: RunwayMonotonicTime) throws {
        try validateCompletion(intent, at: completedAt)
        inFlight = nil
        attemptStartedAt = nil
        lastFailure = failure
    }

    public func noteLocalSupplyChanged(scope: RunwayScope) throws {
        guard let active = self.scope else { throw RunwayControllerError.noActiveScope }
        guard active == scope else { throw RunwayControllerError.scopeMismatch }
        lastFailure = nil
        bootstrapObservation = nil
        if inFlight == nil, head == nil, episode.exhausted {
            episode = Progress()
            pendingReset = false
            preferredLane = .episode
        } else if inFlight == nil, head == nil, episode.cursor == nil {
            // The primary lane is already at the fresh head.
        } else {
            if head == nil, !pendingReset { preferredLane = .headReconsideration }
            pendingReset = true
        }
    }

    private func selectLane() -> RunwayProductionLane? {
        if episode.exhausted, head == nil, pendingReset {
            episode = Progress()
            pendingReset = false
            preferredLane = .episode
        }
        let headAvailable = pendingReset || (head != nil && head?.exhausted == false)
        let lane: RunwayProductionLane
        if preferredLane == .headReconsideration, headAvailable { lane = .headReconsideration }
        else if !episode.exhausted { lane = .episode }
        else if headAvailable { lane = .headReconsideration }
        else { return nil }
        if lane == .headReconsideration {
            if pendingReset { head = Progress(); pendingReset = false }
            preferredLane = .episode
        } else { preferredLane = .headReconsideration }
        return lane
    }

    public func snapshot() -> RunwayControllerSnapshot {
        RunwayControllerSnapshot(scope: scope, latestObservation: latestObservation, consumption: consumption,
            replenishment: ReplenishmentFacts(p95Seconds: runwayP95(latencySamples))!, readyAhead: readyAhead,
            lastCoverage: lastCoverage, localSliceInFlight: inFlight != nil, pendingSupplyReset: pendingReset,
            localSupplyExhausted: episode.exhausted && head == nil && !pendingReset, lastLocalFailure: lastFailure)
    }
}
