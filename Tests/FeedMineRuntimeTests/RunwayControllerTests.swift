import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition
import FeedMineEditorial
@testable import FeedMinePublication
@testable import FeedMineRuntime

@MainActor
final class RunwayControllerTests: XCTestCase {
    private enum FixtureError: Error { case expectedIntent }
    private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x",n))! }
    private func scope(_ n: Int = 1) -> RunwayScope {
        RunwayScope(editionID: FeedEditionID(rawValue: uuid(n)),contextKey: ContextKey(request: .main),editorialRevisionID: EditorialRevisionID(rawValue: uuid(100+n)))
    }
    private func time(_ seconds: Double) -> RunwayMonotonicTime { RunwayMonotonicTime(seconds: seconds)! }
    private func observation(_ card: Int, _ seconds: Double, activity: RunwayActivity = .forward, scope: RunwayScope? = nil) -> RunwayObservation {
        RunwayObservation(editionID: (scope ?? self.scope()).editionID,anchorCardID: PublicationCardID(rawValue: uuid(1000+card)),sampledAt: time(seconds),activity: activity)
    }
    private func resources(allowed: Bool = true, bound: Int = 5, ceiling: Int = 100) -> RunwayResourceFacts {
        RunwayResourceFacts(localWorkAllowed: allowed,examinedCandidateCapacity: 7,readyProbeBound: bound,readyProbeCeiling: ceiling,forwardAdvanceProbeBound: 20)!
    }
    private func controller(consumption: Int = 2, replenishment: Int = 2) -> RunwayController {
        RunwayController(configuration: RunwayControllerConfiguration(policyInputs: RunwayPolicyInputs(safetyFactor: 1,releaseMarginSeconds: 0)!,consumptionSampleLimit: consumption,replenishmentSampleLimit: replenishment)!)
    }
    private func facts(_ o: RunwayObservation, amount: ReadyAheadAmount = .exact(0), from: PublicationCardID? = nil, advance: PublicationAdvance = .same) -> RunwayMeasurement {
        RunwayMeasurement(observation: o,readyAhead: ReadyAheadFacts(editionID: o.editionID,anchorCardID: o.anchorCardID,observedTailCardID: PublicationCardID(rawValue: uuid(9999)),amount: amount),
            advanceFromHighWater: from.map { PublicationAdvanceFacts(editionID: o.editionID,fromCardID: $0,toCardID: o.anchorCardID,advance: advance) })
    }
    private func cursor(_ n: Int) -> CandidateSupplyCursor {
        CandidateSupplyCursor(sortDate: Date(timeIntervalSince1970: Double(n)),originRecordID: OriginRecordID(rawValue: uuid(n)))
    }
    private func outcome(_ intent: RunwayLocalSliceIntent, after: CandidateSupplyCursor? = nil, exhausted: Bool = false, publish: Bool = false, edition: FeedEditionID? = nil) -> LocalProductionSliceOutcome {
        let progress = LocalProductionProgress(examinedCount: 7,nextCursor: after,exhausted: exhausted)
        if publish { return .published(progress,PublicationReceipt(editionID: edition ?? intent.scope.editionID,segmentID: FeedSegmentID(rawValue: uuid(2000)),segmentOrdinal: 1,cardIDs: [PublicationCardID(rawValue: uuid(3000))])) }
        return .advancedWithoutPublication(progress)
    }
    private func intent(_ sut: RunwayController, at: Double) async throws -> RunwayLocalSliceIntent {
        let action = try await sut.reconsider(resources: resources(),at: time(at))
        guard case .runLocalSlice(let intent) = action else { XCTFail("Expected local intent: \(action)"); throw FixtureError.expectedIntent }
        return intent
    }
    private func start(_ sut: RunwayController, o: RunwayObservation? = nil, amount: ReadyAheadAmount = .exact(0)) async throws -> RunwayObservation {
        let o = o ?? observation(1,0)
        await sut.activate(scope()); try await sut.submitObservation(o); try await sut.acceptMeasurement(facts(o,amount: amount)); return o
    }

    func testFirstObservationRequestsMeasurementWithoutStorageAndValidatesValues() async throws {
        XCTAssertNil(RunwayMonotonicTime(seconds: -.infinity)); XCTAssertNil(RunwayMonotonicTime(seconds: -1)); XCTAssertNil(RunwayMonotonicTime(seconds: .nan))
        XCTAssertNil(RunwayControllerConfiguration(policyInputs: RunwayPolicyInputs(safetyFactor: 1,releaseMarginSeconds: 0)!,consumptionSampleLimit: 0,replenishmentSampleLimit: 1))
        let sut = controller(), o = observation(1,1)
        do { try await sut.submitObservation(o); XCTFail("Missing scope") } catch { XCTAssertEqual(error as? RunwayControllerError,.noActiveScope) }
        await sut.activate(scope()); try await sut.submitObservation(o)
        let action = try await sut.reconsider(resources: resources(),at: time(2))
        guard case .measure(let request) = action else { return XCTFail("Expected measurement") }
        XCTAssertEqual(request.scope,scope()); XCTAssertEqual(request.observation,o); XCTAssertEqual(request.readyProbeBound,5); XCTAssertNil(request.advance)
        let snap = await sut.snapshot(); XCTAssertFalse(snap.localSliceInFlight)
    }

    func testForwardHighWaterReversalStationaryAndBoundedEviction() async throws {
        let sut = controller(), a = try await start(sut), b = observation(2,2)
        try await sut.submitObservation(b)
        let action = try await sut.reconsider(resources: resources(),at: time(3))
        guard case .measure(let request) = action else { return XCTFail("Expected advancement request") }
        XCTAssertEqual(request.advance?.fromCardID,a.anchorCardID); XCTAssertEqual(request.advance?.toCardID,b.anchorCardID); XCTAssertEqual(request.advance?.probeBound,20)
        try await sut.acceptMeasurement(facts(b,from: a.anchorCardID,advance: .forwardExact(4)))
        var snap = await sut.snapshot(); XCTAssertEqual(snap.consumption.cardsPerSecond,2)
        let back = observation(1,4,activity: .backward)
        try await sut.submitObservation(back); try await sut.acceptMeasurement(facts(back,from: b.anchorCardID,advance: .backward))
        snap = await sut.snapshot(); XCTAssertEqual(snap.consumption.cardsPerSecond,2)
        let again = observation(2,6,activity: .stationary)
        try await sut.submitObservation(again)
        let next = try await sut.reconsider(resources: resources(),at: time(7))
        guard case .measure(let reread) = next else { return XCTFail("Expected reread measurement") }
        XCTAssertEqual(reread.advance?.fromCardID,b.anchorCardID)
        try await sut.acceptMeasurement(facts(again,from: b.anchorCardID,advance: .same))
        snap = await sut.snapshot(); XCTAssertEqual(snap.consumption.cardsPerSecond,0)
        let far = observation(9,8)
        try await sut.submitObservation(far); try await sut.acceptMeasurement(facts(far,from: b.anchorCardID,advance: .forwardBeyondProbe(20)))
        snap = await sut.snapshot(); XCTAssertNil(snap.consumption.cardsPerSecond)
        let after = observation(10,10)
        try await sut.submitObservation(after)
        let probe = try await sut.reconsider(resources: resources(),at: time(11))
        guard case .measure(let moved) = probe else { return XCTFail("Expected high-water request") }
        XCTAssertEqual(moved.advance?.fromCardID,far.anchorCardID)
    }

    func testNonMonotonicStaleAndMisalignedMeasurementsLeaveStateUnchanged() async throws {
        let sut = controller(), a = try await start(sut,o: observation(1,2))
        let before = await sut.snapshot()
        for o in [observation(2,2),observation(2,1)] {
            do { try await sut.submitObservation(o); XCTFail("Expected monotonic error") } catch { XCTAssertEqual(error as? RunwayControllerError,.nonMonotonicObservation) }
        }
        var snap = await sut.snapshot(); XCTAssertEqual(snap,before)
        do { try await sut.submitObservation(observation(1,3,scope: scope(2))); XCTFail("Wrong scope") } catch { XCTAssertEqual(error as? RunwayControllerError,.scopeMismatch) }
        let b = observation(2,4); try await sut.submitObservation(b)
        do { try await sut.acceptMeasurement(facts(a)); XCTFail("Stale") } catch { XCTAssertEqual(error as? RunwayControllerError,.staleMeasurement) }
        let pending = await sut.snapshot()
        do { try await sut.acceptMeasurement(facts(b)); XCTFail("Missing advance") } catch { XCTAssertEqual(error as? RunwayControllerError,.invalidMeasurement) }
        do { try await sut.acceptMeasurement(facts(b,from: a.anchorCardID,advance: .forwardExact(-1))); XCTFail("Negative distance") } catch { XCTAssertEqual(error as? RunwayControllerError,.invalidMeasurement) }
        let wrong = RunwayMeasurement(observation: b,readyAhead: facts(a).readyAhead,advanceFromHighWater: nil)
        do { try await sut.acceptMeasurement(wrong); XCTFail("Wrong ready anchor") } catch { XCTAssertEqual(error as? RunwayControllerError,.invalidMeasurement) }
        snap = await sut.snapshot(); XCTAssertEqual(snap,pending)
    }

    func testReadyReprobeExpandsBoundWithoutDoubleCountingConsumption() async throws {
        let sut = controller(), a = try await start(sut)
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1),publish: true),at: time(13))
        let b = observation(2,2); try await sut.submitObservation(b)
        try await sut.acceptMeasurement(facts(b,amount: .atLeast(5),from: a.anchorCardID,advance: .forwardExact(4)))
        let action = try await sut.reconsider(resources: resources(),at: time(14))
        guard case .measure(let larger) = action else { return XCTFail("Expected larger probe") }
        XCTAssertEqual(larger.readyProbeBound,6); XCTAssertNil(larger.advance)
        try await sut.acceptMeasurement(facts(b,amount: .exact(6)))
        let snapshot = await sut.snapshot(); XCTAssertEqual(snapshot.consumption.cardsPerSecond,2); XCTAssertFalse(snapshot.localSliceInFlight)
        let healthy = try await sut.reconsider(resources: resources(),at: time(15)); XCTAssertEqual(healthy,.none)
    }

    func testOneInFlightCoalescesLatestAndPublicationPreservesAnchor() async throws {
        let sut = controller(), a = try await start(sut), first = try await intent(sut,at: 10)
        let duplicate = try await sut.reconsider(resources: resources(),at: time(11)); XCTAssertEqual(duplicate,.none)
        for n in 2...4 { try await sut.submitObservation(observation(n,Double(n))) }
        let still = try await sut.reconsider(resources: resources(),at: time(12)); XCTAssertEqual(still,.none)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1),publish: true),at: time(13))
        let snap = await sut.snapshot(); XCTAssertEqual(snap.latestObservation,observation(4,4)); XCTAssertNil(snap.readyAhead)
        let action = try await sut.reconsider(resources: resources(),at: time(14))
        guard case .measure(let req) = action else { return XCTFail("Expected current anchor measurement") }
        XCTAssertEqual(req.observation.anchorCardID,observation(4,4).anchorCardID); XCTAssertEqual(req.advance?.fromCardID,a.anchorCardID)
    }

    func testZeroYieldLatencyChainIncludesSchedulingAndRecentP95EvictsOldSamples() async throws {
        let sut = controller(), o = try await start(sut)
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1)),at: time(12))
        var snap = await sut.snapshot(); XCTAssertNil(snap.replenishment.p95Seconds)
        let second = try await intent(sut,at: 13); XCTAssertEqual(second.after,cursor(1))
        try await sut.completeLocalSlice(second,outcome: outcome(second,after: cursor(2),publish: true),at: time(16))
        snap = await sut.snapshot(); XCTAssertEqual(snap.replenishment.p95Seconds,6); XCTAssertEqual(snap.latestObservation,o); XCTAssertNil(snap.readyAhead)
        for (start,end) in [(20.0,22.0),(30.0,31.0)] {
            try await sut.acceptMeasurement(facts(o))
            let next = try await intent(sut,at: start)
            try await sut.completeLocalSlice(next,outcome: outcome(next,after: cursor(3),publish: true),at: time(end))
        }
        snap = await sut.snapshot(); XCTAssertEqual(snap.replenishment.p95Seconds,2)
    }

    func testExhaustedZeroHasNoLatencyAndSupplyChangeReopensAtHead() async throws {
        let sut = controller(); _ = try await start(sut)
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1),exhausted: true),at: time(12))
        var snap = await sut.snapshot(); XCTAssertTrue(snap.localSupplyExhausted); XCTAssertNil(snap.replenishment.p95Seconds)
        let stopped = try await sut.reconsider(resources: resources(),at: time(13))
        guard case .measure = stopped else { return XCTFail("Exhaustion must settle ready facts") }
        try await sut.acceptMeasurement(facts(observation(1,0)))
        try await sut.noteLocalSupplyChanged(scope: scope())
        snap = await sut.snapshot(); XCTAssertFalse(snap.localSupplyExhausted)
        let fresh = try await intent(sut,at: 14); XCTAssertNil(fresh.after)
    }

    func testFailureAndCancellationDoNotAdvanceOrRetryAndExplicitSignalsReopen() async throws {
        let sut = controller(); _ = try await start(sut)
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1)),at: time(11))
        let failed = try await intent(sut,at: 12)
        try await sut.failLocalSlice(failed,failure: .failed,at: time(13))
        var snap = await sut.snapshot(); XCTAssertEqual(snap.lastLocalFailure,.failed); XCTAssertNil(snap.replenishment.p95Seconds)
        let blocked = try await sut.reconsider(resources: resources(),at: time(14)); XCTAssertEqual(blocked,.none)
        let nextObservation = observation(1,1)
        try await sut.submitObservation(nextObservation); try await sut.acceptMeasurement(facts(nextObservation,from: observation(1,0).anchorCardID))
        let resumed = try await intent(sut,at: 15); XCTAssertEqual(resumed.after,cursor(1))
        try await sut.failLocalSlice(resumed,failure: .cancelled,at: time(16))
        try await sut.noteLocalSupplyChanged(scope: scope())
        snap = await sut.snapshot(); XCTAssertNil(snap.lastLocalFailure); XCTAssertNil(snap.replenishment.p95Seconds)
        let reopened = try await intent(sut,at: 17); XCTAssertNil(reopened.after)
    }

    func testStaleCompletionAndInvalidCompletionScopeTimeCannotMutateState() async throws {
        let sut = controller(); _ = try await start(sut)
        let first = try await intent(sut,at: 10), before = await sut.snapshot()
        do { try await sut.completeLocalSlice(first,outcome: outcome(first,publish: true),at: time(10)); XCTFail("Invalid completion time") } catch { XCTAssertEqual(error as? RunwayControllerError,.invalidCompletionTime) }
        do { try await sut.completeLocalSlice(first,outcome: outcome(first,publish: true,edition: scope(2).editionID),at: time(11)); XCTFail("Wrong receipt scope") } catch { XCTAssertEqual(error as? RunwayControllerError,.completionScopeMismatch) }
        var snap = await sut.snapshot(); XCTAssertEqual(snap,before)
        await sut.activate(scope(2)); let active = await sut.snapshot()
        do { try await sut.completeLocalSlice(first,outcome: outcome(first),at: time(12)); XCTFail("Stale completion") } catch { XCTAssertEqual(error as? RunwayControllerError,.staleCompletion) }
        snap = await sut.snapshot(); XCTAssertEqual(snap,active)
        await sut.deactivate(); snap = await sut.snapshot(); XCTAssertNil(snap.scope); XCTAssertFalse(snap.localSliceInFlight)
    }

    func testHeadFairnessCoalescesSignalsThenFreshHeadExhaustionSupersedesOlderWalk() async throws {
        let sut = controller(); _ = try await start(sut)
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1)),at: time(11))
        for _ in 0..<20 { try await sut.noteLocalSupplyChanged(scope: scope()) }
        let head = try await intent(sut,at: 12); XCTAssertEqual(head.lane,.headReconsideration); XCTAssertNil(head.after)
        try await sut.noteLocalSupplyChanged(scope: scope())
        try await sut.completeLocalSlice(head,outcome: outcome(head,after: cursor(10)),at: time(13))
        let older = try await intent(sut,at: 14); XCTAssertEqual(older.lane,.episode); XCTAssertEqual(older.after,cursor(1))
        try await sut.completeLocalSlice(older,outcome: outcome(older,after: cursor(2)),at: time(15))
        let resetHead = try await intent(sut,at: 16); XCTAssertEqual(resetHead.lane,.headReconsideration); XCTAssertNil(resetHead.after)
        try await sut.completeLocalSlice(resetHead,outcome: outcome(resetHead,after: cursor(20),exhausted: true),at: time(17))
        let snap = await sut.snapshot(); XCTAssertTrue(snap.localSupplyExhausted); XCTAssertFalse(snap.pendingSupplyReset)
    }

    func testUnknownBootstrapOnceAndExactZeroPressureCanContinueSeparateSlices() async throws {
        let sut = controller(), o = try await start(sut,amount: .exact(4))
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1)),at: time(11))
        let hold = try await sut.reconsider(resources: resources(),at: time(12)); XCTAssertEqual(hold,.none)
        try await sut.noteLocalSupplyChanged(scope: scope())
        let fresh = try await intent(sut,at: 13)
        try await sut.completeLocalSlice(fresh,outcome: outcome(fresh,after: cursor(2)),at: time(14))
        let again = try await sut.reconsider(resources: resources(),at: time(15)); XCTAssertEqual(again,.none)
        // Ready-only exact-zero evidence is logical pressure even without new observation.
        try await sut.acceptMeasurement(facts(o))
        let zero = try await intent(sut,at: 16)
        try await sut.completeLocalSlice(zero,outcome: outcome(zero,after: cursor(3)),at: time(17))
        _ = try await intent(sut,at: 18)
    }

    func testInactiveResetPreservesEpisodeAndLatencyButRestartsConsumptionMeasurement() async throws {
        let sut = controller(), o = try await start(sut)
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1),publish: true),at: time(12))
        await sut.markConsumptionInactive()
        let snap = await sut.snapshot(); XCTAssertEqual(snap.scope,scope()); XCTAssertNil(snap.latestObservation); XCTAssertNil(snap.consumption.cardsPerSecond); XCTAssertEqual(snap.replenishment.p95Seconds,2)
        let later = observation(2,100)
        try await sut.submitObservation(later)
        let action = try await sut.reconsider(resources: resources(),at: time(101))
        guard case .measure(let req) = action else { return XCTFail("Expected fresh measurement") }
        XCTAssertNil(req.advance)
        try await sut.acceptMeasurement(facts(later))
        let next = try await intent(sut,at: 102); XCTAssertEqual(next.after,cursor(1)); XCTAssertNotEqual(later.anchorCardID,o.anchorCardID)
    }
    func testPublicationReMeasuresSameAnchorWithoutAnotherConsumptionSample() async throws {
        let sut = controller(), o = try await start(sut)
        let first = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1),publish: true),at: time(12))
        let snap = await sut.snapshot()
        XCTAssertEqual(snap.latestObservation,o); XCTAssertNil(snap.readyAhead)
        let action = try await sut.reconsider(resources: resources(),at: time(13))
        guard case .measure(let request) = action else { return XCTFail("Expected ready measurement") }
        XCTAssertEqual(request.observation,o); XCTAssertNil(request.advance)
        try await sut.acceptMeasurement(facts(o))
        let measured = await sut.snapshot(); XCTAssertNil(measured.consumption.cardsPerSecond)
    }

    func testNewObservationReopensUnknownBootstrapAndSupplyAlreadyAtHeadDoesNotDuplicateLane() async throws {
        let sut = controller(), a = try await start(sut,amount: .exact(4))
        try await sut.noteLocalSupplyChanged(scope: scope())
        let first = try await intent(sut,at: 10)
        XCTAssertEqual(first.lane,.episode); XCTAssertNil(first.after)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(1)),at: time(11))
        let held = try await sut.reconsider(resources: resources(),at: time(12)); XCTAssertEqual(held,.none)
        let b = observation(2,2)
        try await sut.submitObservation(b)
        try await sut.acceptMeasurement(facts(b,amount: .exact(4),from: a.anchorCardID,advance: .forwardBeyondProbe(20)))
        let next = try await intent(sut,at: 13); XCTAssertEqual(next.after,cursor(1))
    }

    private func knownPressure(_ sut: RunwayController) async throws -> RunwayObservation {
        let a = try await start(sut)
        let seed = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(seed,outcome: outcome(seed,after: cursor(1),publish: true),at: time(13))
        let b = observation(2,2)
        try await sut.submitObservation(b)
        try await sut.acceptMeasurement(facts(b,amount: .exact(2),from: a.anchorCardID,advance: .forwardExact(4)))
        return b
    }

    private func exhausted(_ sut: RunwayController, known: Bool = true) async throws -> RunwayObservation {
        let o: RunwayObservation
        if known { o = try await knownPressure(sut) }
        else { o = try await start(sut) }
        let last = try await intent(sut,at: 20)
        try await sut.completeLocalSlice(last,outcome: outcome(last,after: cursor(2),exhausted: true),at: time(21))
        return o
    }

    private func demand(_ sut: RunwayController, at: Double = 22) async throws -> RunwayAcquisitionIntent {
        let action = try await sut.reconsider(resources: resources(),at: time(at))
        guard case .requestAcquisition(let value) = action else {
            XCTFail("Expected semantic demand: \(action)"); throw FixtureError.expectedIntent
        }
        return value
    }

    func testAcquisitionValuesValidateExactDeficitWithoutArtificialLogicalCount() {
        XCTAssertNil(ExhaustedLocalSupply(readyCards: -1))
        XCTAssertNotNil(ExhaustedLocalSupply(readyCards: 0))
        let local = ExhaustedLocalSupply(readyCards: 3)!
        func make(_ pressure: AcquisitionPressure) -> AcquisitionDemand? {
            AcquisitionDemand(contextKey: scope().contextKey,editorialRevisionID: scope().editorialRevisionID,
                purpose: .readerContinuation,pressure: pressure,localSupply: local)
        }
        XCTAssertNotNil(make(.coverageDeficit(requiredCards: 5)))
        for required in [-1,0,2,3] { XCTAssertNil(make(.coverageDeficit(requiredCards: required))) }
        XCTAssertNotNil(make(.logicalTailPressure))
    }

    func testNonexhaustedKnownPressureStaysLocalAndExhaustionForcesPostSettleMeasurement() async throws {
        let sut = controller(), o = try await knownPressure(sut)
        let first = try await intent(sut,at: 20)
        try await sut.completeLocalSlice(first,outcome: outcome(first,after: cursor(2)),at: time(21))
        let next = try await intent(sut,at: 22); XCTAssertEqual(next.after,cursor(2))
        try await sut.completeLocalSlice(next,outcome: outcome(next,after: cursor(3),exhausted: true),at: time(23))
        let snap = await sut.snapshot(); XCTAssertNil(snap.readyAhead); XCTAssertTrue(snap.localSupplyExhausted)
        let action = try await sut.reconsider(resources: resources(),at: time(24))
        guard case .measure(let request) = action else { return XCTFail("Post-settle measurement required") }
        XCTAssertEqual(request.observation,o); XCTAssertNil(request.advance)
        XCTAssertNil(snap.outstandingAcquisition)
    }

    func testCoverageDemandContentCoalescingAndAcknowledgementPreserveLocalFacts() async throws {
        let sut = controller(), o = try await exhausted(sut)
        try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
        let before = await sut.snapshot(), d = try await demand(sut)
        XCTAssertEqual(d.scope,scope()); XCTAssertEqual(d.demand.contextKey,scope().contextKey)
        XCTAssertEqual(d.demand.editorialRevisionID,scope().editorialRevisionID)
        XCTAssertEqual(d.demand.purpose,.readerContinuation)
        XCTAssertEqual(d.demand.pressure,.coverageDeficit(requiredCards: 6))
        XCTAssertEqual(d.demand.localSupply.readyCards,2)
        for n in 23...26 {
            let action = try await sut.reconsider(resources: resources(),at: time(Double(n)))
            XCTAssertEqual(action,.none)
        }
        var snap = await sut.snapshot(); XCTAssertEqual(snap.outstandingAcquisition,d)
        XCTAssertEqual(snap.readyAhead,before.readyAhead); XCTAssertEqual(snap.consumption,before.consumption)
        XCTAssertEqual(snap.replenishment,before.replenishment); XCTAssertTrue(snap.localSupplyExhausted)
        let wrong = RunwayAcquisitionIntent(scope: scope(2),demand: d.demand)
        do { try await sut.acknowledgeAcquisition(wrong); XCTFail("Exact acknowledgement required") }
        catch { XCTAssertEqual(error as? RunwayControllerError,.staleAcquisitionAcknowledgement) }
        try await sut.acknowledgeAcquisition(d)
        snap = await sut.snapshot(); XCTAssertNil(snap.outstandingAcquisition)
        XCTAssertEqual(snap.readyAhead,before.readyAhead); XCTAssertTrue(snap.localSupplyExhausted)
        let held = try await sut.reconsider(resources: resources(),at: time(27)); XCTAssertEqual(held,.none)
        do { try await sut.acknowledgeAcquisition(d); XCTFail("Already acknowledged") }
        catch { XCTAssertEqual(error as? RunwayControllerError,.staleAcquisitionAcknowledgement) }
        try await sut.noteLocalSupplyChanged(scope: scope())
        let reopened = try await intent(sut,at: 28); XCTAssertNil(reopened.after)
    }

    func testLogicalTailDemandHasNoFabricatedThreshold() async throws {
        let sut = controller(); await sut.activate(scope())
        let o = observation(1,0,activity: .explicitTailApproach)
        try await sut.submitObservation(o); try await sut.acceptMeasurement(facts(o))
        let last = try await intent(sut,at: 10)
        try await sut.completeLocalSlice(last,outcome: outcome(last,exhausted: true),at: time(11))
        try await sut.acceptMeasurement(facts(o))
        let d = try await demand(sut)
        XCTAssertEqual(d.demand.pressure,.logicalTailPressure); XCTAssertEqual(d.demand.localSupply.readyCards,0)
    }

    func testUnknownHealthyAndSaturatedStockNeverEscalate() async throws {
        let unknown = controller(), u = try await exhausted(unknown,known: false)
        try await unknown.acceptMeasurement(facts(u,amount: .exact(4)))
        let heldUnknown = try await unknown.reconsider(resources: resources(),at: time(22)); XCTAssertEqual(heldUnknown,.none)
        let known = controller(), k = try await exhausted(known)
        try await known.acceptMeasurement(facts(k,amount: .exact(6)))
        let healthy = try await known.reconsider(resources: resources(),at: time(22)); XCTAssertEqual(healthy,.none)
        try await known.acceptMeasurement(facts(k,amount: .atLeast(5)))
        let probe = try await known.reconsider(resources: resources(),at: time(23))
        guard case .measure(let larger) = probe else { return XCTFail("Bounded larger probe") }
        XCTAssertEqual(larger.readyProbeBound,6)
        // Logical pressure cannot use a saturated stock as shortage evidence either.
        let logical = controller(); await logical.activate(scope())
        let tail = observation(1,0,activity: .explicitTailApproach)
        try await logical.submitObservation(tail); try await logical.acceptMeasurement(facts(tail))
        let first = try await intent(logical,at: 10)
        try await logical.completeLocalSlice(first,outcome: outcome(first,exhausted: true),at: time(11))
        let later = observation(1,2,activity: .explicitTailApproach)
        try await logical.submitObservation(later)
        try await logical.acceptMeasurement(facts(later,amount: .atLeast(5),from: tail.anchorCardID))
        let action = try await logical.reconsider(resources: resources(),at: time(12))
        guard case .measure(let ceiling) = action else { return XCTFail("Exact tail evidence required") }
        XCTAssertEqual(ceiling.readyProbeBound,100); XCTAssertNil(ceiling.advance)
        try await logical.acceptMeasurement(facts(later,amount: .atLeast(100)))
        let saturated = try await logical.reconsider(resources: resources(),at: time(13)); XCTAssertEqual(saturated,.none)
        let snap = await logical.snapshot(); XCTAssertNil(snap.outstandingAcquisition)
    }

    func testFailedLocalExecutorDoesNotBecomeRemoteShortage() async throws {
        let sut = controller(), o = try await knownPressure(sut)
        let first = try await intent(sut,at: 20)
        // The same failure fact covers storage, preparation and publication failures.
        try await sut.failLocalSlice(first,failure: .failed,at: time(21))
        let held = try await sut.reconsider(resources: resources(),at: time(22)); XCTAssertEqual(held,.none)
        var snap = await sut.snapshot(); XCTAssertNil(snap.outstandingAcquisition); XCTAssertFalse(snap.localSupplyExhausted)
        let next = observation(2,4)
        try await sut.submitObservation(next); try await sut.acceptMeasurement(facts(next,from: o.anchorCardID))
        _ = try await intent(sut,at: 23)
        snap = await sut.snapshot(); XCTAssertNil(snap.outstandingAcquisition)
    }

    func testAdmissionClearsOutstandingMakesOldAckStaleAndReopensLocalHead() async throws {
        let sut = controller(), o = try await exhausted(sut)
        try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
        let d = try await demand(sut)
        try await sut.noteLocalSupplyChanged(scope: scope())
        let snap = await sut.snapshot(); XCTAssertNil(snap.outstandingAcquisition); XCTAssertFalse(snap.localSupplyExhausted)
        do { try await sut.acknowledgeAcquisition(d); XCTFail("Supply changed") }
        catch { XCTAssertEqual(error as? RunwayControllerError,.staleAcquisitionAcknowledgement) }
        let local = try await intent(sut,at: 23); XCTAssertNil(local.after)
    }

    func testNewObservationAfterAcknowledgementRequiresFactsBeforeNewDemand() async throws {
        let sut = controller(), o = try await exhausted(sut)
        try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
        let d = try await demand(sut); try await sut.acknowledgeAcquisition(d)
        let newer = observation(3,4)
        try await sut.submitObservation(newer)
        let action = try await sut.reconsider(resources: resources(),at: time(23))
        guard case .measure(let request) = action else { return XCTFail("Changed reader facts need measurement") }
        XCTAssertEqual(request.advance?.fromCardID,o.anchorCardID)
        try await sut.acceptMeasurement(facts(newer,amount: .exact(2),from: o.anchorCardID,advance: .forwardExact(4)))
        _ = try await demand(sut,at: 24)
    }

    func testScopeDeactivationAndInactiveConsumptionClearOwnershipAndRejectOldAck() async throws {
        for mode in 0...2 {
            let sut = controller(), o = try await exhausted(sut)
            try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
            let d = try await demand(sut)
            if mode == 0 { await sut.activate(scope(2)) }
            else if mode == 1 { await sut.deactivate() }
            else { await sut.markConsumptionInactive() }
            let before = await sut.snapshot(); XCTAssertNil(before.outstandingAcquisition)
            do { try await sut.acknowledgeAcquisition(d); XCTFail("Stale ownership") }
            catch { XCTAssertEqual(error as? RunwayControllerError,.staleAcquisitionAcknowledgement) }
            let after = await sut.snapshot(); XCTAssertEqual(before,after)
            if mode == 1 { XCTAssertNil(after.scope) }
            if mode == 2 { XCTAssertNil(after.latestObservation); XCTAssertTrue(after.localSupplyExhausted) }
        }
    }

    func testPendingSupplyResetAfterExhaustionKeepsHeadWorkAheadOfRemoteHandoff() async throws {
        let sut = controller(), o = try await knownPressure(sut)
        let last = try await intent(sut,at: 20)
        try await sut.noteLocalSupplyChanged(scope: scope())
        try await sut.completeLocalSlice(last,outcome: outcome(last,after: cursor(2),exhausted: true),at: time(21))
        var snap = await sut.snapshot(); XCTAssertTrue(snap.pendingSupplyReset); XCTAssertFalse(snap.localSupplyExhausted)
        try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
        let head = try await intent(sut,at: 22); XCTAssertNil(head.after)
        snap = await sut.snapshot(); XCTAssertNil(snap.outstandingAcquisition)
    }

    func testChangedExactShortageSupersedesRememberedDemandButUnchangedProbeDoesNot() async throws {
        let sut = controller(), o = try await exhausted(sut)
        try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
        let first = try await demand(sut)
        try await sut.acknowledgeAcquisition(first)
        try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
        let same = try await sut.reconsider(resources: resources(),at: time(23)); XCTAssertEqual(same,.none)
        try await sut.acceptMeasurement(facts(o,amount: .exact(1)))
        let changed = try await demand(sut,at: 24); XCTAssertNotEqual(changed,first)
        try await sut.acceptMeasurement(facts(o,amount: .exact(2)))
        let restored = try await demand(sut,at: 25); XCTAssertEqual(restored,first)
        do { try await sut.acknowledgeAcquisition(changed); XCTFail("Superseded evidence") }
        catch { XCTAssertEqual(error as? RunwayControllerError,.staleAcquisitionAcknowledgement) }
    }

}
