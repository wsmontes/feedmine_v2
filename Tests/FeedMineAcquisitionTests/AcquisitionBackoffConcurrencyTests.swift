import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition

/// H2: per-target cooling after consecutive operational failures, and sliding-window execution.
final class AcquisitionBackoffConcurrencyTests: XCTestCase {
    private final class Time: @unchecked Sendable { var now = 0.0 }

    private struct FailingConnector: FeedConnector {
        func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent { throw ConnectorOperationalFailure.transport }
    }
    private struct FinishedConnector: FeedConnector {
        func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent { .finished }
    }
    private actor Gate: FeedConnector {
        private var started = 0, peak = 0, running = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private let onStarted: @Sendable (Int) -> Void
        private var opened = false
        init(onStarted: @escaping @Sendable (Int) -> Void) { self.onStarted = onStarted }
        func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
            started += 1; running += 1; peak = max(peak, running)
            onStarted(started)
            if !opened { await withCheckedContinuation { waiters.append($0) } }
            running -= 1
            return .finished
        }
        func releaseOne() { if !waiters.isEmpty { waiters.removeFirst().resume() } }
        func open() { opened = true; let all = waiters; waiters = []; all.forEach { $0.resume() } }
        func counts() -> (started: Int, peak: Int) { (started, peak) }
    }

    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: .init(directory: root))
    }
    private func targets(_ count: Int, in db: RuntimeDatabase) throws -> [AcquisitionTarget] {
        try (0..<count).map { _ in
            try AcquisitionTargetAuthority(database: db).register(id: AcquisitionTargetID(), connectorKind: .syndication,
                authorizedSources: [SourceID()])
        }
    }
    private static func start(_ target: AcquisitionTarget) -> AcquisitionPlannedWork {
        .start(target: target, bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 1, byteCapacityPerBatch: 10)!)
    }

    func testBackoffDelayDoublesAndCaps() throws {
        let policy = try XCTUnwrap(AcquisitionBackoffPolicy(baseSeconds: 10, ceilingSeconds: 35))
        XCTAssertEqual(policy.delay(afterConsecutiveFailures: 0), 0)
        XCTAssertEqual(policy.delay(afterConsecutiveFailures: 1), 10)
        XCTAssertEqual(policy.delay(afterConsecutiveFailures: 2), 20)
        XCTAssertEqual(policy.delay(afterConsecutiveFailures: 3), 35)
        XCTAssertEqual(policy.delay(afterConsecutiveFailures: 500), 35)
        XCTAssertNil(AcquisitionBackoffPolicy(baseSeconds: 0, ceilingSeconds: 1))
        XCTAssertNil(AcquisitionBackoffPolicy(baseSeconds: 5, ceilingSeconds: 1))
    }

    func testFailingTargetCoolsDownThenReturnsAndSuccessClearsHistory() async throws {
        let db = try database(), target = try targets(1, in: db)[0], time = Time()
        final class Switch: @unchecked Sendable { var fail = true }
        let mode = Switch()
        let coordinator = AcquisitionCoordinator(database: db, connectorForTarget: { _ in
            mode.fail ? FailingConnector() as any FeedConnector : FinishedConnector() },
            backoff: AcquisitionBackoffPolicy(baseSeconds: 10, ceilingSeconds: 100), monotonicSeconds: { time.now })
        let first = try await coordinator.execute(Self.start(target))
        XCTAssertEqual(first.stop, .operationalFailure(.transport))
        var cooling = await coordinator.coolingTargetIDs(); XCTAssertEqual(cooling, [target.id])
        time.now = 10; cooling = await coordinator.coolingTargetIDs(); XCTAssertTrue(cooling.isEmpty)
        _ = try await coordinator.execute(Self.start(target))           // second consecutive failure at t=10
        time.now = 29; cooling = await coordinator.coolingTargetIDs(); XCTAssertEqual(cooling, [target.id])
        time.now = 30; cooling = await coordinator.coolingTargetIDs(); XCTAssertTrue(cooling.isEmpty)
        mode.fail = false
        _ = try await coordinator.execute(Self.start(target))
        mode.fail = true
        _ = try await coordinator.execute(Self.start(target))           // history cleared: back to base delay
        time.now = 39; cooling = await coordinator.coolingTargetIDs(); XCTAssertEqual(cooling, [target.id])
        time.now = 40; cooling = await coordinator.coolingTargetIDs(); XCTAssertTrue(cooling.isEmpty)
    }

    func testPlanningSkipsCoolingTargetsAtomically() async throws {
        let db = try database(), all = try targets(2, in: db), time = Time()
        let coordinator = AcquisitionCoordinator(database: db, connectorForTarget: { $0.id == all[0].id ? FailingConnector() as any FeedConnector : FinishedConnector() },
            backoff: AcquisitionBackoffPolicy(baseSeconds: 60, ceilingSeconds: 60), monotonicSeconds: { time.now })
        _ = try await coordinator.execute(Self.start(all[0]))
        let demand = try XCTUnwrap(AcquisitionDemand(contextKey: .init(request: .main), editorialRevisionID: EditorialRevisionID(),
            purpose: .initialPublication, pressure: .initialPublication, localSupply: XCTUnwrap(ExhaustedLocalSupply(readyCards: 0))))
        let resources = try XCTUnwrap(AcquisitionPlanningResources(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
            observationCapacityPerBatch: 1, byteCapacityPerBatch: 10))
        let planning = try await coordinator.selectionOpportunity { position, active, cooling in
            try AcquisitionPlanner.plan(demand: demand, eligibleTargets: all.filter { !cooling.contains($0.id) },
                activeExecutions: active, resources: resources, selectionAfter: position)
        }
        guard case .planned(let plan) = planning else { return XCTFail("Expected a plan for the healthy target") }
        XCTAssertEqual(plan.work.map { work -> AcquisitionTargetID in
            switch work { case .start(let t, _), .joinActive(let t): return t.id }
        }, [all[1].id])
    }

    func testSlidingWindowNeverExceedsLimitAndReturnsPlanOrder() async throws {
        let waves = (2...5).map { XCTestExpectation(description: "Started \($0) requests") }
        let gate = Gate { started in
            if (2...5).contains(started) { waves[started - 2].fulfill() }
        }
        let db = try database(), all = try targets(5, in: db)
        let coordinator = AcquisitionCoordinator(database: db, connectorForTarget: { _ in gate }, concurrentTargetLimit: 2)
        let work = all.map(Self.start)
        let execution = Task { try await coordinator.executeConcurrently(work) { _ in } }
        for wave in waves {
            let result = await XCTWaiter.fulfillment(of: [wave], timeout: 5)
            guard result == .completed else {
                await gate.open()
                _ = try await execution.value
                return XCTFail("Sliding window did not refill after a completion")
            }
            let counts = await gate.counts()
            XCTAssertLessThanOrEqual(counts.peak, 2)
            await gate.releaseOne()
        }
        await gate.open()
        let results = try await execution.value
        XCTAssertEqual(results.map(\.targetID), all.map(\.id))
        let counts = await gate.counts()
        XCTAssertEqual(counts.started, 5)
        XCTAssertEqual(counts.peak, 2)
    }

    func testDefaultLimitIsSequential() async throws {
        let db = try database()
        let coordinator = AcquisitionCoordinator(database: db, connectorForTarget: { _ in FinishedConnector() })
        XCTAssertEqual(coordinator.concurrentTargetLimit, 1)
        let results = try await coordinator.executeConcurrently(try targets(3, in: db).map(Self.start)) { _ in }
        XCTAssertEqual(results.count, 3); XCTAssertTrue(results.allSatisfy { $0.stop == .finished })
    }
}
