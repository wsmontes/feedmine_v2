// Owns: memory-only observation, bounded measurements and one operational local intent.
import Foundation
import FeedMineDomain
import FeedMineEditorial
import FeedMinePublication
import FeedMineAcquisition

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
    case staleAcquisitionAcknowledgement
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
    /// Evidence, not identity: the correlation id of the replenishment attempt this decision opened. It travels
    /// inside the intent only so the executor that finishes the work can report the same operation at the arrival
    /// and at the destination — `==` below deliberately ignores it, because the decisions that compare intents
    /// (in-flight completion, acknowledgement) must keep exactly the meaning they had before it existed.
    public let operation: FeedReplenishmentOperationID
    /// This slice reviews a page of the durable skip pass and examines no structural supply: the walk has no work,
    /// but the authorized continuation still owes rows. It moves no cursor and completes no lane.
    public let reconsiderationOnly: Bool
    public init(scope: RunwayScope, lane: RunwayProductionLane, after: CandidateSupplyCursor?,
        examinedCapacity: Int, startedAt: RunwayMonotonicTime,
        operation: FeedReplenishmentOperationID = FeedReplenishmentOperationID(),
        reconsiderationOnly: Bool = false) {
        self.scope = scope
        self.lane = lane
        self.after = after
        self.examinedCapacity = examinedCapacity
        self.startedAt = startedAt
        self.operation = operation
        self.reconsiderationOnly = reconsiderationOnly
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.scope == right.scope && left.lane == right.lane && left.after == right.after
            && left.examinedCapacity == right.examinedCapacity && left.startedAt == right.startedAt
            && left.reconsiderationOnly == right.reconsiderationOnly
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(scope); hasher.combine(lane); hasher.combine(after)
        hasher.combine(examinedCapacity); hasher.combine(startedAt)
        hasher.combine(reconsiderationOnly)
    }
}

public struct RunwayAcquisitionIntent: Hashable, Sendable {
    public let scope: RunwayScope
    public let demand: AcquisitionDemand
    /// Evidence, not identity — see `RunwayLocalSliceIntent.operation`. The acknowledgement guards compare two
    /// intents for the **same demand**; a fresh correlation id must not make the same demand look like a new one.
    public let operation: FeedReplenishmentOperationID
    public init(scope: RunwayScope, demand: AcquisitionDemand,
        operation: FeedReplenishmentOperationID = FeedReplenishmentOperationID()) {
        self.scope = scope
        self.demand = demand
        self.operation = operation
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.scope == right.scope && left.demand == right.demand
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(scope); hasher.combine(demand)
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
    public let outstandingAcquisition: RunwayAcquisitionIntent?
    /// When a failed local slice becomes retryable without another signal (M7); nil when not scheduled.
    public let localRetryEligibleAt: RunwayMonotonicTime?
}

public struct RunwayControllerConfiguration: Hashable, Sendable {
    public let policyInputs: RunwayPolicyInputs
    public let consumptionSampleLimit: Int
    public let replenishmentSampleLimit: Int
    /// Review M7: after a failed local slice, a retry becomes eligible once this many seconds,
    /// doubled per consecutive failure, have passed. nil keeps the explicit-signal-only behavior.
    public let localRetryBaseSeconds: Double?
    public init?(policyInputs: RunwayPolicyInputs, consumptionSampleLimit: Int, replenishmentSampleLimit: Int,
        localRetryBaseSeconds: Double? = nil) {
        guard consumptionSampleLimit > 0, replenishmentSampleLimit > 0,
            localRetryBaseSeconds.map({ $0.isFinite && $0 > 0 }) ?? true else { return nil }
        self.policyInputs = policyInputs
        self.consumptionSampleLimit = consumptionSampleLimit
        self.replenishmentSampleLimit = replenishmentSampleLimit
        self.localRetryBaseSeconds = localRetryBaseSeconds
    }
}

public enum RunwayControllerAction: Hashable, Sendable {
    case none
    case measure(RunwayMeasurementRequest)
    case runLocalSlice(RunwayLocalSliceIntent)
    case requestAcquisition(RunwayAcquisitionIntent)
}

/// Serializes observation, measurement, supply signals and completions for one active scope.
public actor RunwayController {
    private struct Progress {
        var cursor: CandidateSupplyCursor?
        var exhausted = false
    }
    private let configuration: RunwayControllerConfiguration
    /// Optional evidence of the path a replenishment attempt walks. Never read to decide anything.
    private let trace: ReplenishmentTrace?
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
    /// One bounded local opportunity armed by an effective local supply/readiness change, consumed even when the
    /// policy would hold. It is separate from `pendingReset`: the latter belongs to the lane walk and is asserted
    /// by the acquisition cadence; this flag exists only to authorize one fresh local slice.
    private var freshSupplyOpportunity = false
    /// A page of the durable skip pass ended without a presentable revision while rows remained: the **same**
    /// authorization still owes the page behind it. It is not a new opportunity and not a second owner — the
    /// executor that took the slice keeps it, and a page that ends the pass clears it.
    private var reconsiderationOwed = false
    private var preferredLane: RunwayProductionLane = .episode
    private var bootstrapObservation: RunwayObservation?
    private var lastFailure: RunwayLocalFailure?
    private var lastFailureAt: RunwayMonotonicTime?
    private var consecutiveLocalFailures = 0
    private var lastCoverage: RunwayCoverage?
    private var previouslyPressured = false
    private var outstandingAcquisitionIntent: RunwayAcquisitionIntent?
    private var lastAcknowledgedAcquisitionIntent: RunwayAcquisitionIntent?

    private func invalidateAcquisitionDemand() {
        outstandingAcquisitionIntent = nil
        lastAcknowledgedAcquisitionIntent = nil
    }

    private var localSupplyExhausted: Bool {
        episode.exhausted && head == nil && !pendingReset
    }

    public func acknowledgeAcquisition(_ intent: RunwayAcquisitionIntent) throws {
        guard intent == outstandingAcquisitionIntent, intent.scope == scope else {
            throw RunwayControllerError.staleAcquisitionAcknowledgement
        }
        outstandingAcquisitionIntent = nil
        lastAcknowledgedAcquisitionIntent = intent
    }

    /// The network demand the reader's own continuation already justifies.
    ///
    /// It is read from the **measured deficit** the policy computed out of the reader's own facts
    /// (`RunwayPolicy.evaluate`) — never from the count ahead having been *proven* below the probe. Requiring an
    /// exact reading made the network's fate depend on the absence of a tail measurement: a saturated
    /// (`.atLeast`) reading was answered with a bounded larger probe and, at the resource ceiling, with a plain
    /// refusal, so "the reserve looks healthy" was standing in for a measurement. Local supply still comes first
    /// (INV-04: local order is ready stock → local supply → demand), so the demand is still emitted only once the
    /// bounded local walk cannot close the deficit: what changed is the trigger, which is the policy's own
    /// coverage verdict, not the shape of the reading.
    ///
    /// The demand carries the ready stock the deficit was measured against, as the probe established it; a
    /// saturated reading is a floor. On the **coverage-deficit** path `AcquisitionDemand` accepts the deficit only
    /// while it exceeds that stock, so there the demand cannot describe a shortage the reader does not have. The
    /// **logical-tail** path carries no count at all — by design, logical pressure introduces none — so its warrant
    /// is not arithmetic: it is the policy's verdict that a reader is at the tail with the local walk spent, and it
    /// is deliberately not blocked by a stock the probe could only bound (INV-04: wait for an exact N and the
    /// network is only asked at the end of the published prefix).
    private func acquisitionIntentIfEligible(coverage: RunwayCoverage) -> RunwayAcquisitionIntent? {
        guard let scope, let observation = latestObservation, let readyAhead,
            readyAhead.editionID == scope.editionID, readyAhead.anchorCardID == observation.anchorCardID,
            localSupplyExhausted, inFlight == nil, lastFailure == nil,
            let localSupply = Self.readySupply(readyAhead.amount) else { return nil }
        let pressure: AcquisitionPressure
        switch coverage {
        case .pressured(let required): pressure = .coverageDeficit(requiredCards: required)
        case .logicalPressure: pressure = .logicalTailPressure
        case .healthy, .unknown: return nil
        }
        guard let demand = AcquisitionDemand(contextKey: scope.contextKey,
            editorialRevisionID: scope.editorialRevisionID, purpose: .readerContinuation,
            pressure: pressure, localSupply: localSupply) else { return nil }
        return RunwayAcquisitionIntent(scope: scope, demand: demand)
    }

    /// The ready stock a measured deficit is stated against, as the bounded probe actually established it: an
    /// exact reading is that count, a saturated one is only a floor — and the demand states the floor, never a
    /// count the probe did not prove.
    private static func readySupply(_ amount: ReadyAheadAmount) -> ExhaustedLocalSupply? {
        switch amount {
        case .exact(let count): return ExhaustedLocalSupply(readyCards: count)
        case .atLeast(let bound): return ExhaustedLocalSupply(readyCards: bound)
        }
    }

    public init(configuration: RunwayControllerConfiguration, trace: ReplenishmentTrace? = nil) {
        self.configuration = configuration
        self.trace = trace
    }

    /// Activates the scope the runway works for. Re-activating the **same** scope is the foreground cadence
    /// re-entering the presentation it is already working for, not a scope change: the learned consumption and
    /// latency samples and the walk progress belong to the scope (the comment on `deactivate` says as much, and
    /// used to contradict the code one line above it). A cadence tick every 10 s that wiped them would put the
    /// reader back in bootstrap on every activation and disable F05-R2/R3 adaptation for good.
    ///
    /// A different edition, context or editorial revision is a genuine scope change and resets everything, because
    /// the measured walk describes one edition under one context at one revision.
    public func activate(_ scope: RunwayScope) {
        guard self.scope != scope else { return }
        deactivate()
        self.scope = scope
    }

    public func deactivate() {
        scope = nil
        markConsumptionInactive()
        // Learned consumption belongs to a scope, not to a foreground interval.
        consumptionSamples = []
        latencySamples = []
        inFlight = nil
        attemptStartedAt = nil
        episode = Progress()
        head = nil
        pendingReset = false
        freshSupplyOpportunity = false
        reconsiderationOwed = false
        preferredLane = .episode
        lastFailure = nil
        lastFailureAt = nil
        consecutiveLocalFailures = 0
        lastCoverage = nil
        previouslyPressured = false
    }

    public func markConsumptionInactive() {
        invalidateAcquisitionDemand()
        latestObservation = nil
        lastMeasuredObservation = nil
        readyAhead = nil
        highWater = nil
        bootstrapObservation = nil
    }

    public func submitObservation(_ observation: RunwayObservation) throws {
        guard let scope else { throw RunwayControllerError.noActiveScope }
        guard observation.editionID == scope.editionID else { throw RunwayControllerError.scopeMismatch }
        if let latestObservation, observation.sampledAt <= latestObservation.sampledAt {
            throw RunwayControllerError.nonMonotonicObservation
        }
        invalidateAcquisitionDemand()
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

    public func reconsider(resources: RunwayResourceFacts, at now: RunwayMonotonicTime,
        allowFreshSupply: Bool = true) throws -> RunwayControllerAction {
        guard let scope, let observation = latestObservation else { return .none }
        if lastFailure != nil, let eligible = retryEligibleAt, now >= eligible { lastFailure = nil }
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
        // A continuation is the same owner finishing the pass it was already authorized to review, so it does not
        // depend on `allowFreshSupply` (that guard keeps an *external* fact from authorizing a slice inside a caller
        // drive). It is bounded by the durable pass: a page that ends it reports no continuation.
        let owesContinuation = reconsiderationOwed || (allowFreshSupply && freshSupplyOpportunity)
        if owesContinuation, evaluation.action == .hold, resources.localWorkAllowed,
            let intent = takeLocalSlice(scope: scope, resources: resources, now: now,
                coverage: evaluation.coverage, observation: observation) {
            return .runLocalSlice(intent)
        }
        if let intent = acquisitionIntentIfEligible(coverage: evaluation.coverage) {
            guard intent != outstandingAcquisitionIntent, intent != lastAcknowledgedAcquisitionIntent else { return .none }
            outstandingAcquisitionIntent = intent
            if let trace {
                trace.record(ReplenishmentEvent.requested, Self.requestFields(intent, coverage: evaluation.coverage,
                    ready: readyAhead.amount))
            }
            return .requestAcquisition(intent)
        }
        switch evaluation.action {
        case .hold: return .none
        case .requestReadyProbe(let bound):
            return measurementRequest(observation, scope: scope, bound: bound, advanceBound: nil)
        case .requestLocalSlice:
            guard let intent = takeLocalSlice(scope: scope, resources: resources, now: now,
                coverage: evaluation.coverage, observation: observation) else { return .none }
            return .runLocalSlice(intent)
        }
    }

    private func takeLocalSlice(scope: RunwayScope, resources: RunwayResourceFacts, now: RunwayMonotonicTime,
        coverage: RunwayCoverage, observation: RunwayObservation) -> RunwayLocalSliceIntent? {
        // The fresh authorization belongs to the head reconsideration, even when fairness walks the episode lane
        // first. Consuming it on that older pass would let a healthy `.hold` strand the pending head.
        guard let readyAhead else { return nil }
        let lane = selectLane()
        // No lane has structural work left, but the authorized pass still owes pages: the page is taken as a
        // queue-only slice, which examines no supply and completes no lane.
        guard lane != nil || reconsiderationOwed else { return nil }
        let reconsiderationOnly = lane == nil
        // Read the reset state **after** `selectLane()`: its exhaustion branch clears `pendingReset` and consumes
        // the head reset on the same slice. Computing this before would preserve the authorization for a head that
        // no longer exists and grant one extra slice.
        let headPending = pendingReset || (head != nil && head?.exhausted == false)
        if reconsiderationOnly || lane == .headReconsideration || !headPending { freshSupplyOpportunity = false }
        let progress: Progress
        if reconsiderationOnly { progress = Progress() }
        else if lane == .episode { progress = episode }
        else { progress = head! }
        let intent = RunwayLocalSliceIntent(scope: scope, lane: lane ?? .episode,
            after: reconsiderationOnly ? nil : progress.cursor,
            examinedCapacity: resources.examinedCandidateCapacity, startedAt: now,
            reconsiderationOnly: reconsiderationOnly)
        inFlight = intent
        if attemptStartedAt == nil { attemptStartedAt = now }
        if coverage == .unknown { bootstrapObservation = observation }
        if let trace {
            trace.record(ReplenishmentEvent.requested, Self.requestFields(intent, coverage: coverage,
                ready: readyAhead.amount))
        }
        return intent
    }

    /// The facts the decision used, spelled once for both kinds of replenishment. Every value here was read to
    /// decide — nothing is reconstructed after the fact.
    private static func requestFields(operation: FeedReplenishmentOperationID, kind: String, scope: RunwayScope,
        coverage: RunwayCoverage, ready: ReadyAheadAmount?) -> [String: String] {
        var fields = ["op": operation.described, "kind": kind, "edition": scope.editionID.rawValue.uuidString,
            "surface": scope.contextKey.surfaceIdentity]
        switch coverage {
        case .healthy: fields["coverage"] = "healthy"
        case .pressured(let required): fields["coverage"] = "pressured"; fields["required_cards"] = String(required)
        case .logicalPressure: fields["coverage"] = "logical_pressure"
        case .unknown: fields["coverage"] = "unknown"
        }
        switch ready {
        case .exact(let count): fields["ready"] = "exact"; fields["ready_cards"] = String(count)
        case .atLeast(let bound): fields["ready"] = "at_least"; fields["ready_bound"] = String(bound)
        case nil: fields["ready"] = "unknown"
        }
        return fields
    }

    private static func requestFields(_ intent: RunwayLocalSliceIntent, coverage: RunwayCoverage,
        ready: ReadyAheadAmount?) -> [String: String] {
        var fields = requestFields(operation: intent.operation, kind: "local", scope: intent.scope,
            coverage: coverage, ready: ready)
        fields["lane"] = intent.lane == .episode ? "episode" : "head_reconsideration"
        fields["examined_capacity"] = String(intent.examinedCapacity)
        if intent.reconsiderationOnly { fields["reconsideration_only"] = "1" }
        return fields
    }

    private static func requestFields(_ intent: RunwayAcquisitionIntent, coverage: RunwayCoverage,
        ready: ReadyAheadAmount?) -> [String: String] {
        var fields = requestFields(operation: intent.operation, kind: "network", scope: intent.scope,
            coverage: coverage, ready: ready)
        switch intent.demand.pressure {
        case .coverageDeficit(let required):
            fields["pressure"] = "coverage_deficit"; fields["required_cards"] = String(required)
        case .logicalTailPressure: fields["pressure"] = "logical_tail_pressure"
        case .initialPublication: fields["pressure"] = "initial_publication"
        case .selectedSourceCoverage: fields["pressure"] = "selected_source_coverage"
        }
        if let localSupply = intent.demand.localSupply { fields["local_supply"] = String(localSupply.readyCards) }
        return fields
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
            case .forwardBeyondProbe(let bound):
                // Review M6: the fastest reader must not get the weakest signal. The probe proves
                // at least `bound` cards were passed, so bound/elapsed is a valid lower-bound rate.
                let rate = Double(bound) / elapsed
                guard bound > 0, rate.isFinite else { throw RunwayControllerError.invalidMeasurement }
                appendConsumption(rate)
                highWater = observation.anchorCardID
            }
        }
        if let readyAhead, readyAhead.amount != measurement.readyAhead.amount {
            invalidateAcquisitionDemand()
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
        invalidateAcquisitionDemand()
        consecutiveLocalFailures = 0
        lastFailureAt = nil
        if progress.exhausted { readyAhead = nil }
        // A queue-only slice examines no structural supply: it reports no progress and must not move a cursor.
        if !intent.reconsiderationOnly {
            let updated = Progress(cursor: progress.nextCursor, exhausted: progress.exhausted)
            if intent.lane == .episode { episode = updated }
            else if progress.exhausted { episode = updated; head = nil }
            else { head = updated }
        }
        // The pass owns the remaining work: the page behind this one is still owed to the same authorization, and
        // the page that ends the pass clears the obligation (the chain therefore terminates).
        reconsiderationOwed = progress.reconsiderationContinues
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
        // A failed slice did not advance the pass. The runway fences local work until a new supply fact anyway, and
        // a stale obligation must not authorize a page without that fact.
        reconsiderationOwed = false
        lastFailure = failure
        lastFailureAt = completedAt
        if failure == .failed { consecutiveLocalFailures += 1 }
    }

    public func noteLocalSupplyChanged(scope: RunwayScope) throws {
        guard let active = self.scope else { throw RunwayControllerError.noActiveScope }
        guard active == scope else { throw RunwayControllerError.scopeMismatch }
        invalidateAcquisitionDemand()
        lastFailure = nil
        bootstrapObservation = nil
        // A new supply/readiness fact starts a new pass: the obligation belongs to the pass that was interrupted by
        // this fact, and the caller resets the pass position itself.
        reconsiderationOwed = false
        if inFlight == nil, head == nil, episode.exhausted {
            episode = Progress()
            pendingReset = false
            preferredLane = .episode
            freshSupplyOpportunity = true
        } else if inFlight == nil, head == nil, episode.cursor == nil {
            // The primary lane is already at the fresh head; the change still gets its one bounded opportunity.
            freshSupplyOpportunity = true
        } else {
            if head == nil, !pendingReset { preferredLane = .headReconsideration }
            pendingReset = true
            freshSupplyOpportunity = true
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
            localSupplyExhausted: localSupplyExhausted, lastLocalFailure: lastFailure,
            outstandingAcquisition: outstandingAcquisitionIntent, localRetryEligibleAt: retryEligibleAt)
    }

    /// Time after which a failed local slice may be retried; doubles per consecutive failure.
    private var retryEligibleAt: RunwayMonotonicTime? {
        guard lastFailure == .failed, let base = configuration.localRetryBaseSeconds, let failedAt = lastFailureAt else { return nil }
        let delay = base * pow(2, Double(min(consecutiveLocalFailures - 1, 30)))
        return RunwayMonotonicTime(seconds: failedAt.seconds + delay)
    }
}
