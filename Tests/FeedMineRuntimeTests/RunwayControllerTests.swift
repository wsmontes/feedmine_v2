import Foundation
import XCTest
import FeedMineDomain
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
        let stopped = try await sut.reconsider(resources: resources(),at: time(13)); XCTAssertEqual(stopped,.none)
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

}
