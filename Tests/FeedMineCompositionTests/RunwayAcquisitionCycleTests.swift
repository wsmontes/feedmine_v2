import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineComposition

// Test-only connector: one offered/scripted event per pull, at most one buffered event.
private actor CycleConnector: FeedConnector {
    enum Failure: Error, Equatable, Sendable { case expected, unexpectedPull }
    enum Step: Sendable {
        case batch([AcquisitionObservation], AcquisitionCheckpoint?)
        case finished
        case failure
        case operational(ConnectorOperationalFailure)
        case cancelled
        func event(_ request: FeedConnectorPull) throws -> FeedConnectorEvent {
            switch self {
            case .batch(let observations, let checkpoint):
                return .batch(AcquisitionBatch(targetID: request.targetID,targetGeneration: request.targetGeneration,
                    expectedCheckpointRevision: request.checkpointRevision,observations: observations,nextCheckpoint: checkpoint)!,transportByteCount: 1)
            case .finished: return .finished
            case .failure: throw Failure.expected
            case .operational(let failure): throw failure
            case .cancelled: return .cancelled
            }
        }
    }
    private var pending: Step?
    private var waiting: CheckedContinuation<Step, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private let onPull: (@Sendable (FeedConnectorPull) async throws -> Void)?
    private(set) var pulls: [FeedConnectorPull] = []
    init(_ step: Step? = nil, onPull: (@Sendable (FeedConnectorPull) async throws -> Void)? = nil) {
        pending = step
        self.onPull = onPull
    }
    func offer(_ step: Step) -> Bool {
        if let waiting { self.waiting = nil; waiting.resume(returning: step); return true }
        guard pending == nil else { return false }
        pending = step
        return true
    }
    func waitForPull() async {
        if !pulls.isEmpty { return }
        precondition(entered == nil)
        await withCheckedContinuation { entered = $0 }
    }
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        guard pulls.isEmpty else { throw Failure.unexpectedPull }
        pulls.append(request)
        let step: Step
        if let pending {
            self.pending = nil
            entered?.resume(); entered = nil
            try await onPull?(request)
            step = pending
        } else {
            step = await withCheckedContinuation { continuation in
                waiting = continuation
                entered?.resume(); entered = nil
            }
            try await onPull?(request)
        }
        return try step.event(request)
    }
}
private actor CycleJournal {
    private(set) var events: [String] = []
    func record(_ value: String) { events.append(value) }
}

@MainActor
final class RunwayAcquisitionCycleTests: XCTestCase {
    private enum FixtureError: Error { case unexpectedAction }
    private struct Fixture: Sendable {
        let database: RuntimeDatabase
        let plan: FeedPlan
        let policy: ResolvedSelectionPolicy
        let edition: FeedEditionID
        let anchor: PublicationCardID
        let source: SourceID
        let target: AcquisitionTarget
        let runway: RunwayController
        var scope: RunwayScope { .init(editionID: edition,contextKey: plan.context.key,editorialRevisionID: plan.revision.id) }
        var authority: AcquisitionTargetAuthority { .init(database: database) }
        var publication: PublicationStore { .init(database: database) }
        func coordinator(_ mapping: [AcquisitionTargetID: any FeedConnector]) -> AcquisitionCoordinator {
            AcquisitionCoordinator(database: database,connectorForTarget: { mapping[$0.id] })
        }
        func request(_ intent: RunwayLocalSliceIntent) -> LocalProductionSlice.Request {
            .init(plan: plan,policy: policy,editionID: intent.scope.editionID,after: intent.after,
                examinedCapacity: intent.examinedCapacity,segmentID: FeedSegmentID(),segmentSeed: 2,
                segmentCreatedAt: Date(timeIntervalSince1970: 20))
        }
        func candidates() throws -> [Candidate] {
            try CandidateProvider(contentStore: ContentStore(database: database)).candidates(for: plan,after: nil,examinedCapacity: 8).candidates
        }
    }
    nonisolated private static func observation(source: SourceID, object: String = "external", time: Double = 10) -> AcquisitionObservation {
        AcquisitionObservation(objectIdentity: ExternalIdentity(connectorKind: .syndication,namespace: "objects",value: object,role: .object),
            versionIdentity: nil,precedence: .makeCurrent,availability: .available,headline: object,summary: nil,bodyText: nil,
            authoredAt: nil,modifiedAt: nil,observedAt: Date(timeIntervalSince1970: time),language: nil,primaryLink: nil,
            searchProjection: nil,providerID: nil,memberships: [.init(sourceID: source,kind: .direct)],mediaCandidates: [])!
    }
    nonisolated private static func prepared(_ selection: SelectionResult) -> LocalPreparedPublication {
        LocalPreparedPublication(inputs: selection.orderedCandidates.map { candidate in
            PublicationPreparationInput(origin: PublishedOrigin(originRecordID: candidate.originRecordID,originRevisionID: candidate.originRevisionID,
                sourceID: nil,providerID: candidate.providerID,sourceDisplayName: "Test Source",providerDisplayName: nil),
                contentEntityID: nil,contentClusterID: nil,primaryAction: .localContentDetail,presentation: .textOnly)
        },cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }
    private func fixture(seedAnchor: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root)), source = SourceID()
        let target = try AcquisitionTargetAuthority(database: database).register(id: AcquisitionTargetID(),connectorKind: .syndication)
        let context = FeedContext(request: .main), version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(),contextKey: context.key,catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: version,eligibilityPolicyVersion: version,scoringPolicyVersion: version,sequencingPolicyVersion: version,
            exposurePolicyVersion: version,selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context,revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey,userSelectionVersion: version,eligibilityPolicyVersion: version,
            scoringPolicyVersion: version,sequencingPolicyVersion: version,exposurePolicyVersion: version,
            selectionSchemaVersion: revision.selectionSchemaVersion,eligibility: .structuralOnly,scoring: .equal,
            sequencing: .recencyDescending,exposure: .excludePublishedRevisions)
        let anchorCandidate: Candidate
        if seedAnchor {
            _ = try AdmissionPolicy(database: database).admit(AcquisitionBatch(targetID: target.id,targetGeneration: 1,expectedCheckpointRevision: 0,
                observations: [Self.observation(source: source,object: "anchor")],nextCheckpoint: nil)!)
            anchorCandidate = try CandidateProvider(contentStore: ContentStore(database: database)).candidates(for: plan,after: nil,examinedCapacity: 8).candidates[0]
        } else {
            anchorCandidate = Candidate(originRecordID: OriginRecordID(),originRevisionID: OriginRevisionID(),headline: "anchor",summary: nil,
                timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: 1),kind: .observed),language: nil,providerID: nil)
        }
        let selection = SelectionResult(editorialRevision: revision,orderedCandidates: [anchorCandidate],
            supplyReport: SelectionSupplyReport(examinedCount: 0,nextCursor: nil,exhausted: true))
        let prepared = Self.prepared(selection), edition = FeedEditionID()
        _ = try PublicationCoordinator(database: database).createEdition(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection,inputs: prepared.inputs),editionID: edition,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1),selectionSeed: 1,editionCreatedAt: Date(timeIntervalSince1970: 1),
            segmentID: FeedSegmentID(),segmentSeed: 1,segmentCreatedAt: Date(timeIntervalSince1970: 2),cardIDs: prepared.cardIDs))
        let runway = RunwayController(configuration: RunwayControllerConfiguration(policyInputs: RunwayPolicyInputs(safetyFactor: 1,releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2,replenishmentSampleLimit: 2)!)
        return Fixture(database: database,plan: plan,policy: policy,edition: edition,anchor: prepared.cardIDs[0],source: source,target: target,runway: runway)
    }
    nonisolated private static func localResources() -> RunwayResourceFacts {
        .init(localWorkAllowed: true,examinedCandidateCapacity: 8,readyProbeBound: 8,readyProbeCeiling: 16,forwardAdvanceProbeBound: 8)!
    }
    private func resources(_ targetCapacity: Int = 1) -> AcquisitionPlanningResources {
        .init(targetWorkCapacity: targetCapacity,batchCapacityPerNewExecution: 1,observationCapacityPerBatch: 8,byteCapacityPerBatch: 100)!
    }
    private func checkpoint() -> AcquisitionCheckpoint { .init(blob: Data([1]),serializationSchema: 1,connectorVersion: "test")! }
    private func time(_ value: Double) -> RunwayMonotonicTime { .init(seconds: value)! }
    private func intent(_ f: Fixture) async throws -> RunwayAcquisitionIntent {
        await f.runway.activate(f.scope)
        let observation = RunwayObservation(editionID: f.edition,anchorCardID: f.anchor,sampledAt: time(0),activity: .explicitTailApproach)
        try await f.runway.submitObservation(observation)
        for at in [1.0,4.0] {
            guard case .measure(let request) = try await f.runway.reconsider(resources: Self.localResources(),at: time(at)) else { throw FixtureError.unexpectedAction }
            let ready = try PublicationHistory(database: f.database).readyAhead(editionID: f.edition,anchorCardID: f.anchor,probeBound: request.readyProbeBound)
            XCTAssertEqual(ready.amount,.exact(0))
            try await f.runway.acceptMeasurement(.init(observation: observation,readyAhead: ready,advanceFromHighWater: nil))
            if at == 1 {
                guard case .runLocalSlice(let local) = try await f.runway.reconsider(resources: Self.localResources(),at: time(2)) else { throw FixtureError.unexpectedAction }
                let outcome = try LocalProductionSlice(database: f.database).run(f.request(local),prepare: Self.prepared)
                guard case .advancedWithoutPublication(let progress) = outcome else { throw FixtureError.unexpectedAction }
                XCTAssertTrue(progress.exhausted)
                try await f.runway.completeLocalSlice(local,outcome: outcome,at: time(3))
            }
        }
        guard case .requestAcquisition(let intent) = try await f.runway.reconsider(resources: Self.localResources(),at: time(5)) else { throw FixtureError.unexpectedAction }
        let snapshot = await f.runway.snapshot()
        XCTAssertTrue(snapshot.localSupplyExhausted); XCTAssertEqual(snapshot.outstandingAcquisition,intent)
        return intent
    }
    private func executed(_ outcome: RunwayAcquisitionCycleOutcome) throws -> [AcquisitionExecutionResult] {
        guard case .executed(let results) = outcome else { throw FixtureError.unexpectedAction }
        return results
    }

    func test01ExternalSupplyReopensLocalFirstAndPublishesSameEdition() async throws {
        let f = try fixture(), intent = try await intent(f)
        XCTAssertTrue(try f.candidates().isEmpty)
        let originalEdition = try f.publication.edition(id: f.edition), original = try f.publication.card(id: f.anchor)
        XCTAssertEqual(try f.publication.segments(editionID: f.edition).count,1)
        let fake = CycleConnector(.batch([Self.observation(source: f.source)],checkpoint()))
        let cycle = RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake]))
        let outcome = try await cycle.run(intent,eligibleTargets: [f.target],resources: resources())
        let results = try executed(outcome); XCTAssertEqual(results.count,1); XCTAssertTrue(outcome.selectableSupplyChanged)
        let admitted = try XCTUnwrap(f.candidates().first)
        XCTAssertEqual(try f.publication.segments(editionID: f.edition).count,1)
        let snapshot = await f.runway.snapshot(); XCTAssertNil(snapshot.outstandingAcquisition); XCTAssertFalse(snapshot.localSupplyExhausted)
        guard case .runLocalSlice(let local) = try await f.runway.reconsider(resources: Self.localResources(),at: time(6)) else { throw FixtureError.unexpectedAction }
        XCTAssertEqual(local.scope.editionID,f.edition); XCTAssertNil(local.after)
        let production = try LocalProductionSlice(database: f.database).run(f.request(local)) { selected in
            XCTAssertEqual(selected.orderedCandidates.map(\.originRevisionID),[admitted.originRevisionID])
            return Self.prepared(selected)
        }
        try await f.runway.completeLocalSlice(local,outcome: production,at: time(7))
        guard case .published(_,let receipt) = production else { throw FixtureError.unexpectedAction }
        XCTAssertEqual(receipt.editionID,f.edition); XCTAssertEqual(receipt.segmentOrdinal,1)
        let segments = try f.publication.segments(editionID: f.edition)
        XCTAssertEqual(segments.count,2); XCTAssertEqual(segments[0].cardIDs,[f.anchor]); XCTAssertEqual(segments[1].cardIDs,receipt.cardIDs)
        XCTAssertEqual(try f.publication.card(id: receipt.cardIDs[0])?.originRevisionID,admitted.originRevisionID)
        XCTAssertEqual(try f.publication.card(id: f.anchor),original); XCTAssertEqual(try f.publication.edition(id: f.edition),originalEdition)
        let history = try PublicationHistory(database: f.database).readyAhead(editionID: f.edition,anchorCardID: f.anchor,probeBound: 8)
        XCTAssertEqual(history.amount,.exact(1))
    }
    func test02AcknowledgementBeforeFirstPull() async throws {
        let f = try fixture(), intent = try await intent(f)
        let fake = CycleConnector(.finished,onPull: { _ in
            let snapshot = await f.runway.snapshot(); XCTAssertNil(snapshot.outstandingAcquisition)
        })
        _ = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake])).run(intent,eligibleTargets: [f.target],resources: resources())
        let pulls = await fake.pulls; XCTAssertEqual(pulls.count,1)
    }
    func test03NoEligibleTargetsAcknowledged() async throws {
        let f = try fixture(), intent = try await intent(f), fake = CycleConnector(.failure)
        let outcome = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake])).run(intent,eligibleTargets: [],resources: resources())
        XCTAssertEqual(outcome,.acceptedUnavailable(.noEligibleTargets)); XCTAssertFalse(outcome.selectableSupplyChanged)
        let snapshot = await f.runway.snapshot(); XCTAssertNil(snapshot.outstandingAcquisition)
        let action = try await f.runway.reconsider(resources: Self.localResources(),at: time(6)); XCTAssertEqual(action,.none)
        let pulls = await fake.pulls; XCTAssertTrue(pulls.isEmpty)
    }
    func test04ResourceDenialPreservesExactIntentUntilExplicitResourceChange() async throws {
        let f = try fixture(), intent = try await intent(f), fake = CycleConnector(.finished)
        let cycle = RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake]))
        let denied = try await cycle.run(intent,eligibleTargets: [f.target],resources: resources(0))
        XCTAssertEqual(denied,.deferred(.resourceDenied)); XCTAssertFalse(denied.selectableSupplyChanged)
        let snapshot = await f.runway.snapshot(); XCTAssertEqual(snapshot.outstandingAcquisition,intent)
        let pulls = await fake.pulls; XCTAssertTrue(pulls.isEmpty)
        let accepted = try await cycle.run(intent,eligibleTargets: [f.target],resources: resources())
        XCTAssertEqual(try executed(accepted).count,1)
    }
    func test05ActiveGenerationConflictPreservesIntent() async throws {
        let f = try fixture(), fake = CycleConnector(), coordinator = f.coordinator([f.target.id: fake])
        let bounds = AcquisitionWorkBounds(batchCapacity: 1,observationCapacityPerBatch: 8,byteCapacityPerBatch: 100)!
        let old = Task { try await coordinator.execute(.start(target: f.target,bounds: bounds)) }
        await fake.waitForPull()
        let current = try f.authority.reconfigure(id: f.target.id,expectedGeneration: 1,connectorKind: .syndication,checkpoint: .preserve)
        let intent = try await intent(f)
        let outcome = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: coordinator).run(intent,eligibleTargets: [current],resources: resources())
        XCTAssertEqual(outcome,.deferred(.activeGenerationConflict)); XCTAssertFalse(outcome.selectableSupplyChanged)
        let snapshot = await f.runway.snapshot(); XCTAssertEqual(snapshot.outstandingAcquisition,intent)
        let pulls = await fake.pulls; XCTAssertEqual(pulls.count,1)
        let offered = await fake.offer(.finished); XCTAssertTrue(offered)
        _ = try await old.value
        let active = await coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        let after = await f.runway.snapshot(); XCTAssertEqual(after.outstandingAcquisition,intent)
    }
    func test06StaleIntentRefusedBeforePlanningAndExecution() async throws {
        let f = try fixture(), intent = try await intent(f), fake = CycleConnector(.failure)
        try await f.runway.noteLocalSupplyChanged(scope: f.scope)
        // Inconsistent targets would throw Planner error if the stale gate did not run first.
        let inconsistent = AcquisitionTarget(id: f.target.id,connectorKind: .syndication,generation: 2,state: .enabled,checkpointRevision: 0,checkpoint: nil)!
        do { _ = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake])).run(intent,eligibleTargets: [f.target,inconsistent],resources: resources()); XCTFail("Expected stale intent") }
        catch { XCTAssertEqual(error as? RunwayAcquisitionCycleError,.staleIntent) }
        let pulls = await fake.pulls; XCTAssertTrue(pulls.isEmpty)
    }
    // Test 7 omitted as authorized: there is no deterministic insertion point between
    // the snapshot and acknowledgement without a production synchronization hook.
    func test08CheckpointOnlyDoesNotReopenWalk() async throws {
        let f = try fixture(), intent = try await intent(f), fake = CycleConnector(.batch([],checkpoint()))
        let outcome = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake])).run(intent,eligibleTargets: [f.target],resources: resources())
        XCTAssertFalse(outcome.selectableSupplyChanged)
        let snapshot = await f.runway.snapshot(); XCTAssertNil(snapshot.outstandingAcquisition); XCTAssertTrue(snapshot.localSupplyExhausted)
        let action = try await f.runway.reconsider(resources: Self.localResources(),at: time(6)); XCTAssertEqual(action,.none)
    }
    func test09ExactReplayDoesNotReopenWalk() async throws {
        let f = try fixture(seedAnchor: true), before = try XCTUnwrap(f.candidates().first), intent = try await intent(f)
        let fake = CycleConnector(.batch([Self.observation(source: f.source,object: "anchor",time: 20)],nil))
        let outcome = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake])).run(intent,eligibleTargets: [f.target],resources: resources())
        XCTAssertFalse(outcome.selectableSupplyChanged); XCTAssertEqual(try f.candidates().map(\.originRevisionID),[before.originRevisionID])
        let snapshot = await f.runway.snapshot(); XCTAssertTrue(snapshot.localSupplyExhausted); XCTAssertNil(snapshot.outstandingAcquisition)
        let action = try await f.runway.reconsider(resources: Self.localResources(),at: time(6)); XCTAssertEqual(action,.none)
    }
    func test10ExecutionErrorAfterAckDoesNotRedemand() async throws {
        let f = try fixture(), intent = try await intent(f), fake = CycleConnector(.failure)
        do { _ = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake])).run(intent,eligibleTargets: [f.target],resources: resources()); XCTFail("Expected connector error") }
        catch { XCTAssertEqual(error as? CycleConnector.Failure,.expected) }
        let snapshot = await f.runway.snapshot(); XCTAssertNil(snapshot.outstandingAcquisition)
        let action = try await f.runway.reconsider(resources: Self.localResources(),at: time(6)); XCTAssertEqual(action,.none)
        let pulls = await fake.pulls; XCTAssertEqual(pulls.count,1)
    }
    func test11PriorCommittedSupplyAndSignalSurviveLaterError() async throws {
        let f = try fixture(), intent = try await intent(f)
        let second = try f.authority.register(id: AcquisitionTargetID(),connectorKind: .syndication)
        let a = CycleConnector(.batch([Self.observation(source: f.source)],checkpoint())), b = CycleConnector(.failure)
        do { _ = try await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: a,second.id: b])).run(intent,eligibleTargets: [f.target,second],resources: resources(2)); XCTFail("Expected second error") }
        catch { XCTAssertEqual(error as? CycleConnector.Failure,.expected) }
        XCTAssertEqual(try f.candidates().count,1); XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpointRevision,1)
        let snapshot = await f.runway.snapshot(); XCTAssertFalse(snapshot.localSupplyExhausted); XCTAssertNil(snapshot.outstandingAcquisition)
        let aPulls = await a.pulls, bPulls = await b.pulls; XCTAssertEqual(aPulls.count,1); XCTAssertEqual(bPulls.count,1)
    }
    func test12ScopeSwitchDoesNotRollbackOrSignalUnrelatedScope() async throws {
        let f = try fixture(), intent = try await intent(f), fake = CycleConnector(), coordinator = f.coordinator([f.target.id: fake])
        let cycle = RunwayAcquisitionCycle(runway: f.runway,coordinator: coordinator)
        let execution = Task { try await cycle.run(intent,eligibleTargets: [f.target],resources: resources()) }
        await fake.waitForPull()
        let b = RunwayScope(editionID: FeedEditionID(),contextKey: ContextKey(request: .source(SourceID())),editorialRevisionID: EditorialRevisionID())
        await f.runway.activate(b)
        let before = await f.runway.snapshot()
        let offered = await fake.offer(.batch([Self.observation(source: f.source)],checkpoint())); XCTAssertTrue(offered)
        let outcome = try await execution.value; XCTAssertTrue(outcome.selectableSupplyChanged)
        XCTAssertEqual(try f.candidates().count,1)
        let after = await f.runway.snapshot(); XCTAssertEqual(after,before); XCTAssertEqual(after.scope,b)
    }
    func test13MultipleSupplyResultsSignalBeforeLaterWorkAndSeparately() async throws {
        let f = try fixture(), intent = try await intent(f)
        let second = try f.authority.register(id: AcquisitionTargetID(),connectorKind: .syndication)
        let a = CycleConnector(.batch([Self.observation(source: f.source,object: "A")],checkpoint()))
        let b = CycleConnector(.batch([Self.observation(source: f.source,object: "B")],checkpoint()),onPull: { _ in
            let before = await f.runway.snapshot(); XCTAssertFalse(before.localSupplyExhausted); XCTAssertFalse(before.pendingSupplyReset)
            // Test caller opens a real local opportunity between the two remote results.
            let action = try await f.runway.reconsider(resources: Self.localResources(),at: RunwayMonotonicTime(seconds: 6)!)
            guard case .runLocalSlice = action else { throw FixtureError.unexpectedAction }
        })
        let results = try executed(await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: a,second.id: b])).run(intent,eligibleTargets: [f.target,second],resources: resources(2)))
        XCTAssertEqual(results.map(\.targetID),[f.target.id,second.id]); XCTAssertTrue(results.allSatisfy(\.selectableSupplyChanged))
        let after = await f.runway.snapshot(); XCTAssertTrue(after.localSliceInFlight); XCTAssertTrue(after.pendingSupplyReset)
        XCTAssertEqual(try f.candidates().count,2)
    }
    func test14PlanOrderTraversedSequentially() async throws {
        let f = try fixture(), intent = try await intent(f), journal = CycleJournal()
        let second = try f.authority.register(id: AcquisitionTargetID(),connectorKind: .syndication)
        let a = CycleConnector(.batch([Self.observation(source: f.source,object: "A")],checkpoint()),onPull: { _ in await journal.record("A pull") })
        let b = CycleConnector(.batch([Self.observation(source: f.source,object: "B")],checkpoint()),onPull: { _ in
            XCTAssertEqual(try f.authority.target(id: f.target.id)?.checkpointRevision,1)
            XCTAssertEqual(try f.candidates().map(\.headline),["A"])
            await journal.record("A settled"); await journal.record("B pull")
        })
        let results = try executed(await RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: a,second.id: b])).run(intent,eligibleTargets: [f.target,second],resources: resources(2)))
        XCTAssertEqual(results.map(\.targetID),[f.target.id,second.id])
        let events = await journal.events; XCTAssertEqual(events,["A pull","A settled","B pull"])
    }
    func testDeactivationDuringExecutionKeepsCanonicalSupplyAndIgnoresOldNotification() async throws {
        let f = try fixture(), intent = try await intent(f), fake = CycleConnector()
        let cycle = RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: fake]))
        let execution = Task { try await cycle.run(intent,eligibleTargets: [f.target],resources: resources()) }
        await fake.waitForPull()
        await f.runway.deactivate()
        let before = await f.runway.snapshot()
        let offered = await fake.offer(.batch([Self.observation(source: f.source)],checkpoint())); XCTAssertTrue(offered)
        let outcome = try await execution.value; XCTAssertTrue(outcome.selectableSupplyChanged)
        XCTAssertEqual(try f.candidates().count,1)
        let after = await f.runway.snapshot(); XCTAssertNil(after.scope); XCTAssertEqual(after,before)
    }
}

extension RunwayAcquisitionCycleTests {
    func test3R2OperationalFailuresDoNotBlockSupplyAndAllResultsRemainVisible() async throws {
        for healthyFirst in [false, true] {
            let f = try fixture(), intent = try await intent(f)
            let b = try f.authority.register(id: AcquisitionTargetID(), connectorKind: .syndication)
            let c = try f.authority.register(id: AcquisitionTargetID(), connectorKind: .syndication)
            let aConnector = CycleConnector(healthyFirst ? .batch([Self.observation(source: f.source)], checkpoint()) : .operational(.remoteResponse))
            let bConnector = CycleConnector(.operational(.transport))
            let cConnector = CycleConnector(healthyFirst ? .operational(.remoteContent) : .batch([Self.observation(source: f.source)], checkpoint()))
            let cycle = RunwayAcquisitionCycle(runway: f.runway, coordinator: f.coordinator([f.target.id: aConnector, b.id: bConnector, c.id: cConnector]))
            let outcome = try await cycle.run(intent, eligibleTargets: [f.target,b,c], resources: resources(3))
            let results = try executed(outcome)
            XCTAssertEqual(results.map(\.targetID), [f.target.id,b.id,c.id])
            XCTAssertEqual(results[1].stop, .operationalFailure(.transport))
            XCTAssertTrue(outcome.selectableSupplyChanged); XCTAssertEqual(try f.candidates().count, 1)
            XCTAssertEqual(results.map { $0.receipts.count }, healthyFirst ? [1,0,0] : [0,0,1])
            let snapshot = await f.runway.snapshot(); XCTAssertFalse(snapshot.localSupplyExhausted)
            XCTAssertNil(snapshot.outstandingAcquisition)
            for connector in [aConnector,bConnector,cConnector] { let pulls = await connector.pulls; XCTAssertEqual(pulls.count, 1) }
        }
    }
    func test3R2EffectiveCancellationStopsRemainingTargets() async throws {
        let f = try fixture(), intent = try await intent(f)
        let b = try f.authority.register(id: AcquisitionTargetID(), connectorKind: .syndication)
        let aConnector = CycleConnector(.cancelled), bConnector = CycleConnector(.failure)
        let results = try executed(await RunwayAcquisitionCycle(runway: f.runway,
            coordinator: f.coordinator([f.target.id:aConnector,b.id:bConnector])).run(intent, eligibleTargets:[f.target,b], resources:resources(2)))
        XCTAssertEqual(results.count,1); XCTAssertEqual(results[0].stop,.cancelled)
        let pulls = await bConnector.pulls; XCTAssertTrue(pulls.isEmpty)
    }
}


extension RunwayAcquisitionCycleTests {
    func test3R6AllOperationalCategoriesContinueThreeTargetsAndSignalConfirmedSupply() async throws {
        for category in [ConnectorOperationalFailure.remoteContent,.remoteResponse,.transport] {
            let f = try fixture(), intent = try await intent(f)
            let b = try f.authority.register(id: AcquisitionTargetID(),connectorKind: .syndication)
            let c = try f.authority.register(id: AcquisitionTargetID(),connectorKind: .syndication)
            let aConnector = CycleConnector(.operational(category))
            let bConnector = CycleConnector(.batch([Self.observation(source: f.source)],checkpoint()))
            let cConnector = CycleConnector(.finished)
            let cycle = RunwayAcquisitionCycle(runway: f.runway,coordinator: f.coordinator([f.target.id: aConnector,b.id: bConnector,c.id: cConnector]))
            let outcome = try await cycle.run(intent,eligibleTargets: [f.target,b,c],resources: resources(3))
            let results = try executed(outcome)
            XCTAssertEqual(results.map(\.targetID),[f.target.id,b.id,c.id])
            XCTAssertEqual(results[0].stop,.operationalFailure(category))
            XCTAssertEqual(results.map { $0.receipts.count },[0,1,0])
            XCTAssertTrue(outcome.selectableSupplyChanged); XCTAssertEqual(try f.candidates().count,1)
            let snapshot = await f.runway.snapshot()
            XCTAssertFalse(snapshot.localSupplyExhausted); XCTAssertNil(snapshot.outstandingAcquisition)
            for connector in [aConnector,bConnector,cConnector] { let pulls = await connector.pulls; XCTAssertEqual(pulls.count,1) }
        }
    }
}
