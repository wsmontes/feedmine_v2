import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition

// Executes on the coordinator actor so the test barrier proves that a second caller
// reaches execute before the actor can remove ownership for the first caller.
private extension AcquisitionCoordinator {
    func enteredExecute(_ work: AcquisitionPlannedWork, entered: CheckedContinuation<Void, Never>) async throws -> AcquisitionExecutionResult {
        entered.resume()
        return try await execute(work)
    }
}

final class AcquisitionCoordinatorTests: XCTestCase {
    private struct Fixture: Sendable {
        let database: RuntimeDatabase
        let target: AcquisitionTarget
        let source: SourceID
        var authority: AcquisitionTargetAuthority { .init(database: database) }
        var content: ContentStore { .init(database: database) }
        func coordinator(_ connector: any FeedConnector) -> AcquisitionCoordinator {
            let mapping: [AcquisitionTargetID: any FeedConnector] = [target.id: connector]
            return AcquisitionCoordinator(database: database,connectorForTarget: { mapping[$0.id] })
        }
    }
    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let target = try AcquisitionTargetAuthority(database: db).register(id: AcquisitionTargetID(),connectorKind: .syndication)
        return Fixture(database: db,target: target,source: SourceID())
    }
    private func checkpoint(_ byte: UInt8) -> AcquisitionCheckpoint {
        .init(blob: Data([byte]),serializationSchema: 1,connectorVersion: " test ")!
    }
    private func observation(_ f: Fixture, object: String = "A", time: Double = 10) -> AcquisitionObservation {
        let identity = ExternalIdentity(connectorKind: .syndication,namespace: "objects",value: object,role: .object)
        return AcquisitionObservation(objectIdentity: identity,versionIdentity: nil,precedence: .makeCurrent,availability: .available,
            headline: object,summary: nil,bodyText: nil,authoredAt: nil,modifiedAt: nil,observedAt: Date(timeIntervalSince1970: time),
            language: nil,primaryLink: nil,searchProjection: nil,providerID: nil,
            memberships: [.init(sourceID: f.source,kind: .direct)],mediaCandidates: [])!
    }
    private func bounds(_ batches: Int = 3, observations: Int = 2, bytes: Int = 100) -> AcquisitionWorkBounds {
        .init(batchCapacity: batches,observationCapacityPerBatch: observations,byteCapacityPerBatch: bytes)!
    }
    private func start(_ f: Fixture, bounds: AcquisitionWorkBounds? = nil) -> AcquisitionPlannedWork {
        .start(target: f.target,bounds: bounds ?? self.bounds())
    }
    private func assertNoSupply(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(try f.content.candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.isEmpty,file: file,line: line)
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpointRevision,0,file: file,line: line)
        XCTAssertNil(try f.authority.target(id: f.target.id)?.checkpoint,file: file,line: line)
    }
    private func enter(_ coordinator: AcquisitionCoordinator, _ work: AcquisitionPlannedWork) async -> Task<AcquisitionExecutionResult, Error> {
        var task: Task<AcquisitionExecutionResult, Error>!
        await withCheckedContinuation { entered in
            task = Task { try await coordinator.enteredExecute(work,entered: entered) }
        }
        return task
    }

    func test01FiniteCheckpointChain() async throws {
        let f = try fixture(), cp1 = checkpoint(1), cp2 = checkpoint(2)
        let fake = FakeFiniteConnector([.batch(observations: [observation(f)],checkpoint: cp1,bytes: 10),
            .batch(observations: [observation(f,object: "B")],checkpoint: cp2,bytes: 10),.finished])
        let coordinator = f.coordinator(fake), result = try await coordinator.execute(start(f))
        XCTAssertEqual(result.stop,.finished); XCTAssertEqual(result.receipts.count,2)
        XCTAssertEqual(result.targetID,f.target.id); XCTAssertEqual(result.generation,1)
        let pulls = await fake.receivedPulls
        XCTAssertEqual(pulls.map(\.checkpointRevision),[0,1,2]); XCTAssertEqual(pulls.map(\.checkpoint),[nil,cp1,cp2])
        XCTAssertTrue(pulls.allSatisfy { $0.observationCapacity == 2 && $0.byteCapacity == 100 && $0.targetID == f.target.id && $0.targetGeneration == 1 })
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpoint,cp2)
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
    }
    func test02CapacityReached() async throws {
        let f = try fixture()
        let fake = FakeFiniteConnector([.batch(observations: [observation(f)],checkpoint: nil,bytes: 0),
            .batch(observations: [observation(f,time: 20)],checkpoint: nil,bytes: 0),
            .batch(observations: [observation(f,object: "C")],checkpoint: nil,bytes: 0)])
        let result = try await f.coordinator(fake).execute(start(f,bounds: bounds(2)))
        XCTAssertEqual(result.stop,.capacityReached); XCTAssertEqual(result.receipts.count,2)
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,2)
    }
    func test03UpToDate() async throws { try await terminal(.upToDate,expected: .upToDate) }
    func test04Disconnected() async throws { try await terminal(.disconnected,expected: .disconnected) }
    func test05CancelledEvent() async throws { try await terminal(.cancelled,expected: .cancelled) }
    func test06CancellationError() async throws { try await terminal(.cancellationError,expected: .cancelled) }
    private func terminal(_ step: FakeFiniteConnector.Step, expected: AcquisitionExecutionStop) async throws {
        let f = try fixture(), fake = FakeFiniteConnector([step,.failure])
        let coordinator = f.coordinator(fake), result = try await coordinator.execute(start(f))
        XCTAssertEqual(result.stop,expected); XCTAssertTrue(result.receipts.isEmpty); XCTAssertFalse(result.selectableSupplyChanged)
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,1)
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        try assertNoSupply(f)
    }
    func test07OtherConnectorError() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.failure,.finished]), coordinator = f.coordinator(fake)
        do { _ = try await coordinator.execute(start(f)); XCTFail("Expected error") }
        catch { XCTAssertEqual(error as? FakeFiniteConnector.Failure,.expected) }
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,1)
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        try assertNoSupply(f)
    }
    private func rejected(_ f: Fixture, event: FeedConnectorEvent, expected: AcquisitionCoordinatorError,
        bounds: AcquisitionWorkBounds? = nil) async throws {
        let fake = FakeFiniteConnector([.raw(event),.failure]), coordinator = f.coordinator(fake)
        do { _ = try await coordinator.execute(start(f,bounds: bounds)); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? AcquisitionCoordinatorError,expected) }
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,1)
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        try assertNoSupply(f)
        for record in try f.content.candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records {
            XCTFail("Unexpected canonical origin \(record.originRecordID)")
        }
    }
    private func batch(_ f: Fixture, id: AcquisitionTargetID? = nil, generation: UInt64 = 1, revision: UInt64 = 0,
        observations: [AcquisitionObservation]? = nil) -> AcquisitionBatch {
        .init(targetID: id ?? f.target.id,targetGeneration: generation,expectedCheckpointRevision: revision,
            observations: observations ?? [observation(f)],nextCheckpoint: checkpoint(1))!
    }
    func test08ObservationBound() async throws {
        let f = try fixture()
        try await rejected(f,event: .batch(batch(f,observations: [observation(f),observation(f,object: "B")]),transportByteCount: 1),
            expected: .observationCapacityExceeded(limit: 1,actual: 2),bounds: bounds(observations: 1))
    }
    func test09ByteBound() async throws {
        let f = try fixture()
        try await rejected(f,event: .batch(batch(f),transportByteCount: 11),expected: .byteCapacityExceeded(limit: 10,actual: 11),bounds: bounds(bytes: 10))
    }
    func test10NegativeByteFact() async throws {
        let f = try fixture()
        try await rejected(f,event: .batch(batch(f),transportByteCount: -1),expected: .invalidTransportByteCount(-1))
    }
    func test11BatchTargetMismatch() async throws {
        let f = try fixture(), other = AcquisitionTargetID()
        try await rejected(f,event: .batch(batch(f,id: other),transportByteCount: 1),expected: .batchTargetMismatch(expected: f.target.id,actual: other))
    }
    func test12BatchGenerationMismatch() async throws {
        let f = try fixture()
        try await rejected(f,event: .batch(batch(f,generation: 2),transportByteCount: 1),expected: .batchGenerationMismatch(expected: 1,actual: 2))
    }
    func test13CheckpointRevisionMismatch() async throws {
        let f = try fixture()
        try await rejected(f,event: .batch(batch(f,revision: 1),transportByteCount: 1),expected: .batchCheckpointRevisionMismatch(expected: 0,actual: 1))
    }
    func test14CheckpointOnlyBatchCounts() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.batch(observations: [],checkpoint: checkpoint(1),bytes: 0),.failure])
        let result = try await f.coordinator(fake).execute(start(f,bounds: bounds(1)))
        XCTAssertEqual(result.stop,.capacityReached); XCTAssertEqual(result.receipts.count,1)
        XCTAssertTrue(result.receipts[0].checkpointAdvanced); XCTAssertFalse(result.selectableSupplyChanged)
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpointRevision,1)
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,1)
    }
    func test15SameGenerationConcurrentStartCoalesces() async throws {
        let f = try fixture(), fake = FakeContinuousConnector(), coordinator = f.coordinator(fake)
        let first = await enter(coordinator,start(f,bounds: bounds(1)))
        await fake.waitForWaitingPull()
        // Joining with larger bounds must not expand the original execution.
        let second = await enter(coordinator,start(f,bounds: bounds(10)))
        let active = await coordinator.activeExecutions(); XCTAssertEqual(active,[AcquisitionActiveExecution(targetID: f.target.id,generation: 1)!])
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,1)
        let offered = await fake.offer(.batch(observations: [],checkpoint: checkpoint(1),bytes: 0)); XCTAssertTrue(offered)
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a,b); XCTAssertEqual(a.stop,.capacityReached)
        let finalPulls = await fake.receivedPulls; XCTAssertEqual(finalPulls.count,1)
    }
    func test16JoinActiveShares() async throws {
        let f = try fixture(), fake = FakeContinuousConnector(), coordinator = f.coordinator(fake)
        let first = await enter(coordinator,start(f)); await fake.waitForWaitingPull()
        let second = await enter(coordinator,.joinActive(target: f.target))
        let offered = await fake.offer(.finished); XCTAssertTrue(offered)
        let a = try await first.value, b = try await second.value; XCTAssertEqual(a,b)
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,1)
    }
    func test17JoinWithoutActiveTypedFailure() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.failure]), coordinator = f.coordinator(fake)
        do { _ = try await coordinator.execute(.joinActive(target: f.target)); XCTFail("Expected missing active") }
        catch { XCTAssertEqual(error as? AcquisitionCoordinatorError,.missingActiveExecution(f.target.id)) }
        let pulls = await fake.receivedPulls; XCTAssertTrue(pulls.isEmpty)
    }
    func test18DifferentGenerationBlocked() async throws { try await lateWork(replacement: false) }
    func test19LateOldResultRefused() async throws { try await lateWork(replacement: false) }
    func test20ReplacementAfterSettlement() async throws { try await lateWork(replacement: true) }
    private func lateWork(replacement: Bool) async throws {
        let f = try fixture(), fake = FakeContinuousConnector(), coordinator = f.coordinator(fake)
        let old = await enter(coordinator,start(f)); await fake.waitForWaitingPull()
        let current = try f.authority.reconfigure(id: f.target.id,expectedGeneration: 1,connectorKind: .syndication,checkpoint: .preserve)
        for work in [AcquisitionPlannedWork.start(target: current,bounds: bounds()),.joinActive(target: current)] {
            do { _ = try await coordinator.execute(work); XCTFail("Expected conflict") }
            catch { XCTAssertEqual(error as? AcquisitionCoordinatorError,.activeGenerationConflict(targetID: current.id,activeGeneration: 1,requestedGeneration: 2)) }
        }
        let offered = await fake.offer(.batch(observations: [observation(f)],checkpoint: checkpoint(1),bytes: 1)); XCTAssertTrue(offered)
        do { _ = try await old.value; XCTFail("Expected durable refusal") }
        catch { XCTAssertEqual(error as? AcquisitionTargetStoreError,.staleGeneration(expected: 1,actual: 2)) }
        try assertNoSupply(f)
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,1)
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        if replacement {
            let offered = await fake.offer(.finished); XCTAssertTrue(offered)
            let result = try await coordinator.execute(.start(target: current,bounds: bounds()))
            XCTAssertEqual(result.generation,2); XCTAssertEqual(result.stop,.finished)
            let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.map(\.targetGeneration),[1,2])
        }
    }
    func test21StalePlanBeforeFirstPull() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.failure])
        _ = try f.authority.reconfigure(id: f.target.id,expectedGeneration: 1,connectorKind: .syndication,checkpoint: .preserve)
        try await beforePull(f,fake: fake,work: start(f),expected: .stalePlannedGeneration(targetID: f.target.id,planned: 1,actual: 2))
    }
    func test22RevokedBeforePull() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.failure])
        _ = try f.authority.revoke(id: f.target.id,expectedGeneration: 1)
        try await beforePull(f,fake: fake,work: start(f),expected: .targetRevoked(f.target.id))
    }
    func test23MissingTarget() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.failure])
        let missing = AcquisitionTarget(id: AcquisitionTargetID(),connectorKind: .syndication,generation: 1,state: .enabled,checkpointRevision: 0,checkpoint: nil)!
        let coordinator = AcquisitionCoordinator(database: f.database,connectorForTarget: { _ in fake })
        do { _ = try await coordinator.execute(.start(target: missing,bounds: bounds())); XCTFail("Expected missing target") }
        catch { XCTAssertEqual(error as? AcquisitionCoordinatorError,.targetMissing(missing.id)) }
        let pulls = await fake.receivedPulls; XCTAssertTrue(pulls.isEmpty)
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
    }
    func test24MissingConnector() async throws {
        let f = try fixture(), coordinator = AcquisitionCoordinator(database: f.database,connectorForTarget: { _ in nil })
        do { _ = try await coordinator.execute(start(f)); XCTFail("Expected missing connector") }
        catch { XCTAssertEqual(error as? AcquisitionCoordinatorError,.missingConnector(f.target.id)) }
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
    }
    func test25ConnectorKindSnapshotMismatch() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.failure])
        let fabricated = AcquisitionTarget(id: f.target.id,connectorKind: ConnectorKind(rawValue: "SYNDICATION"),generation: 1,state: .enabled,checkpointRevision: 0,checkpoint: nil)!
        try await beforePull(f,fake: fake,work: .start(target: fabricated,bounds: bounds()),expected: .targetConnectorMismatch(f.target.id))
    }
    private func beforePull(_ f: Fixture, fake: FakeFiniteConnector, work: AcquisitionPlannedWork,
        expected: AcquisitionCoordinatorError) async throws {
        let coordinator = f.coordinator(fake)
        do { _ = try await coordinator.execute(work); XCTFail("Expected refusal") }
        catch { XCTAssertEqual(error as? AcquisitionCoordinatorError,expected) }
        let pulls = await fake.receivedPulls; XCTAssertTrue(pulls.isEmpty)
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
    }
    func test26ContinuousOneSlotBackpressure() async throws {
        let f = try fixture(), fake = FakeContinuousConnector()
        let request = FeedConnectorPull(targetID: f.target.id,targetGeneration: 1,checkpointRevision: 0,checkpoint: nil,observationCapacity: 1,byteCapacity: 1)!
        let a = await fake.offer(.upToDate), b = await fake.offer(.disconnected)
        XCTAssertTrue(a); XCTAssertFalse(b)
        let buffered = await fake.bufferedCount; XCTAssertEqual(buffered,1)
        let event = try await fake.pull(request); XCTAssertEqual(event,.upToDate)
        let next = await fake.offer(.disconnected); XCTAssertTrue(next)
        let event2 = try await fake.pull(request); XCTAssertEqual(event2,.disconnected)
        let empty = await fake.bufferedCount; XCTAssertEqual(empty,0)
    }
    func test27ContinuousPullWaitsForExplicitEvent() async throws {
        let f = try fixture(), fake = FakeContinuousConnector()
        let request = FeedConnectorPull(targetID: f.target.id,targetGeneration: 1,checkpointRevision: 0,checkpoint: nil,observationCapacity: 1,byteCapacity: 1)!
        let task = Task { try await fake.pull(request) }
        await fake.waitForWaitingPull()
        let waiting = await fake.waitingPullCount; XCTAssertEqual(waiting,1)
        let offered = await fake.offer(.upToDate); XCTAssertTrue(offered)
        let event = try await task.value; XCTAssertEqual(event,.upToDate)
    }
    func test28AdmissionFailureStopsNextPull() async throws { try await lateWork(replacement: false) }
    func test29SelectableSupplyAggregation() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.batch(observations: [],checkpoint: checkpoint(1),bytes: 0),
            .batch(observations: [observation(f)],checkpoint: checkpoint(2),bytes: 1),.finished])
        let result = try await f.coordinator(fake).execute(start(f))
        XCTAssertEqual(result.receipts.map(\.selectableSupplyChanged),[false,true]); XCTAssertTrue(result.selectableSupplyChanged)
        XCTAssertTrue(result.receipts.allSatisfy { $0.checkpointAdvanced })
    }
    func test30NoSupplyChange() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.batch(observations: [],checkpoint: checkpoint(1),bytes: 0),
            .batch(observations: [],checkpoint: checkpoint(2),bytes: 0),.finished])
        let result = try await f.coordinator(fake).execute(start(f))
        XCTAssertEqual(result.receipts.map(\.selectableSupplyChanged),[false,false]); XCTAssertFalse(result.selectableSupplyChanged)
    }
    func testPullValueValidationAndExactCheckpointEnvelope() throws {
        let f = try fixture(), cp = checkpoint(1)
        func pull(generation: UInt64 = 1, observations: Int = 1, bytes: Int = 1) -> FeedConnectorPull? {
            FeedConnectorPull(targetID: f.target.id,targetGeneration: generation,checkpointRevision: .max,
                checkpoint: cp,observationCapacity: observations,byteCapacity: bytes)
        }
        XCTAssertNil(pull(generation: 0)); XCTAssertNil(pull(observations: 0)); XCTAssertNil(pull(observations: -1))
        XCTAssertNil(pull(bytes: 0)); XCTAssertNil(pull(bytes: -1))
        let valid = try XCTUnwrap(pull())
        XCTAssertEqual(valid.checkpointRevision,.max); XCTAssertEqual(valid.checkpoint,cp)
        XCTAssertEqual(valid.targetID,f.target.id); XCTAssertEqual(valid.targetGeneration,1)
    }
    func testCancellationErrorPreservesPreviouslyCommittedReceipts() async throws {
        let f = try fixture(), fake = FakeFiniteConnector([.batch(observations: [observation(f)],checkpoint: checkpoint(1),bytes: 1),
            .cancellationError,.failure])
        let result = try await f.coordinator(fake).execute(start(f))
        XCTAssertEqual(result.stop,.cancelled); XCTAssertEqual(result.receipts.count,1)
        XCTAssertTrue(result.receipts[0].checkpointAdvanced); XCTAssertTrue(result.selectableSupplyChanged)
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpoint,checkpoint(1))
        let pulls = await fake.receivedPulls; XCTAssertEqual(pulls.count,2)
        XCTAssertEqual(pulls[1].checkpointRevision,1)
    }
}

private actor SettlementConnector: FeedConnector {
    enum Step: Sendable {
        case batch([AcquisitionObservation], AcquisitionCheckpoint?)
        case operational(ConnectorOperationalFailure)
        case invalidBatch
    }
    var steps: [Step]
    private(set) var pulls: [FeedConnectorPull] = []
    init(_ steps: [Step]) { self.steps = steps }
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        pulls.append(request)
        switch steps.removeFirst() {
        case .operational(let reason): throw reason
        case .invalidBatch:
            return .batch(.init(targetID: request.targetID, targetGeneration: request.targetGeneration + 1,
                expectedCheckpointRevision: request.checkpointRevision, observations: [], nextCheckpoint: .init(blob: Data([99]), serializationSchema: 1, connectorVersion: "test"))!, transportByteCount: 0)
        case .batch(let observations, let checkpoint):
            return .batch(.init(targetID: request.targetID, targetGeneration: request.targetGeneration,
                expectedCheckpointRevision: request.checkpointRevision, observations: observations, nextCheckpoint: checkpoint)!, transportByteCount: 1)
        }
    }
}
private actor FairOpportunityConnector: FeedConnector {
    let broken: AcquisitionTargetID
    private(set) var targets: [AcquisitionTargetID] = []
    init(broken: AcquisitionTargetID) { self.broken = broken }
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        targets.append(request.targetID)
        if request.targetID == broken { throw ConnectorOperationalFailure.remoteResponse }
        return .upToDate
    }
}
extension AcquisitionCoordinatorTests {
    func test3R2FirstOperationalPullHasNoInventedReceipts() async throws {
        let f = try fixture()
        for reason in [ConnectorOperationalFailure.transport, .remoteResponse, .remoteContent] {
            let connector = SettlementConnector([.operational(reason)])
            let result = try await f.coordinator(connector).execute(start(f))
            XCTAssertEqual(result.stop, .operationalFailure(reason))
            XCTAssertTrue(result.receipts.isEmpty); XCTAssertFalse(result.selectableSupplyChanged)
            let pulls = await connector.pulls; XCTAssertEqual(pulls.count, 1)
        }
        try assertNoSupply(f)
    }
    func test3R2TenItemsSurviveOperationalFailureAfterAdmission() async throws {
        let f = try fixture()
        let connector = SettlementConnector([.batch((0..<10).map { observation(f, object: "item-\($0)") }, checkpoint(1)), .operational(.transport)])
        let result = try await f.coordinator(connector).execute(start(f, bounds: bounds(2, observations: 10)))
        XCTAssertEqual(result.stop, .operationalFailure(.transport)); XCTAssertEqual(result.receipts.count, 1)
        XCTAssertTrue(result.receipts[0].checkpointAdvanced); XCTAssertTrue(result.selectableSupplyChanged)
        XCTAssertEqual(try f.content.candidateWindow(sourceID: f.source, after: nil, examinedCapacity: 20).records.count, 10)
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpoint, checkpoint(1))
        let pulls = await connector.pulls; XCTAssertEqual(pulls.map(\.checkpointRevision), [0, 1])
    }
    func test3R2MultipleReceiptsRemainOrderedAndNoSupplyIsFactual() async throws {
        let f = try fixture()
        let connector = SettlementConnector([.batch([], checkpoint(1)), .batch([observation(f)], checkpoint(2)), .operational(.remoteContent)])
        let result = try await f.coordinator(connector).execute(start(f))
        XCTAssertEqual(result.stop, .operationalFailure(.remoteContent))
        XCTAssertEqual(result.receipts.map(\.selectableSupplyChanged), [false, true])
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpoint, checkpoint(2))
        let noSupply = SettlementConnector([.batch([], checkpoint(3)), .operational(.transport)])
        let current = try XCTUnwrap(f.authority.target(id: f.target.id))
        let second = try await f.coordinator(noSupply).execute(.start(target: current, bounds: bounds()))
        XCTAssertEqual(second.receipts.count, 1); XCTAssertFalse(second.selectableSupplyChanged)
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpoint, checkpoint(3))
    }
    func test3R2StructuralFailureAfterAdmissionRemainsThrown() async throws {
        let f = try fixture(), connector = SettlementConnector([.batch([observation(f)], checkpoint(1)), .invalidBatch])
        do { _ = try await f.coordinator(connector).execute(start(f)); XCTFail("Expected generation fence") }
        catch { XCTAssertEqual(error as? AcquisitionCoordinatorError, .batchGenerationMismatch(expected: 1, actual: 2)) }
        XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpointRevision, 1)
        XCTAssertEqual(try f.content.candidateWindow(sourceID: nil, after: nil, examinedCapacity: 10).records.count, 1)
    }
    func test3R2SharedFairnessExecutesBrokenAndNoSupplyTargetsWithoutCheckpointProgress() async throws {
        let f = try fixture()
        let b = try f.authority.register(id: AcquisitionTargetID(), connectorKind: .syndication)
        let c = try f.authority.register(id: AcquisitionTargetID(), connectorKind: .syndication)
        let connector = FairOpportunityConnector(broken: f.target.id)
        let coordinator = AcquisitionCoordinator(database: f.database, connectorForTarget: { _ in connector })
        let targets = [f.target, b, c]
        let demand = AcquisitionDemand(contextKey: ContextKey(request: .main), editorialRevisionID: EditorialRevisionID(),
            purpose: .readerContinuation, pressure: .logicalTailPressure, localSupply: ExhaustedLocalSupply(readyCards: 0)!)!
        let resources = AcquisitionPlanningResources(targetWorkCapacity: 1, batchCapacityPerNewExecution: 1,
            observationCapacityPerBatch: 1, byteCapacityPerBatch: 1)!
        for _ in 0..<6 {
            let planning = try await coordinator.selectionOpportunity { position, active in
                try AcquisitionPlanner.plan(demand: demand, eligibleTargets: targets, activeExecutions: active,
                    resources: resources, selectionAfter: position)
            }
            guard case .planned(let plan) = planning else { return XCTFail("Expected finite opportunity") }
            XCTAssertEqual(plan.work.count, 1)
            let result = try await coordinator.execute(plan.work[0])
            XCTAssertFalse(result.selectableSupplyChanged)
            XCTAssertEqual(result.stop, result.targetID == f.target.id ? .operationalFailure(.remoteResponse) : .upToDate)
        }
        let actual = await connector.targets; XCTAssertEqual(Set(actual.prefix(3)), Set(targets.map(\.id)))
        XCTAssertEqual(Array(actual.prefix(3)), Array(actual.suffix(3)))
        for target in targets { XCTAssertEqual(try f.authority.target(id: target.id)?.checkpointRevision, 0) }
        // Remove the marker's target, disable another and add a new target: remaining opportunities still progress.
        _ = try f.authority.revoke(id: b.id, expectedGeneration: 1)
        let disabled = try XCTUnwrap(f.authority.target(id: b.id))
        let d = try f.authority.register(id: AcquisitionTargetID(), connectorKind: .syndication)
        let changed = [f.target, disabled, d]
        for _ in 0..<4 {
            guard case .planned(let plan) = try await coordinator.selectionOpportunity({ position, active in
                try AcquisitionPlanner.plan(demand: demand, eligibleTargets: changed, activeExecutions: active,
                    resources: resources, selectionAfter: position)
            }) else { return XCTFail("Expected remaining target") }
            _ = try await coordinator.execute(plan.work[0])
        }
        let changedActual = await connector.targets
        XCTAssertEqual(Set(changedActual.suffix(4)), Set([f.target.id, d.id]))
        XCTAssertNotEqual(changedActual[6], changedActual[7]); XCTAssertEqual(changedActual[6], changedActual[8])
    }
}
