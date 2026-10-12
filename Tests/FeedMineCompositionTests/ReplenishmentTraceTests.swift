import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
@testable import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineComposition

/// What the chain reported, in order, with the thread-safety the port promises. It stands in for the host's trace:
/// the modules only know a `ReplenishmentTrace`, and these tests are the reader of what they said.
private final class TraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(event: String, fields: [String: String])] = []

    var trace: ReplenishmentTrace { ReplenishmentTrace { [self] event, fields in record(event, fields) } }

    func record(_ event: String, _ fields: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        storage.append((event, fields))
    }
    var events: [(event: String, fields: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    /// Every payload reported under one event name, in the order it was reported.
    func fields(_ event: String) -> [[String: String]] { events.filter { $0.event == event }.map(\.fields) }
}

/// One scripted answer per pull, so an arrival and the absence of one are both expressible.
private actor ScriptedConnector: FeedConnector {
    enum Outcome: Sendable {
        case batch(Int, bytes: Int)
        case upToDate
        case cancelled
        case operationalFailure
    }
    private let outcome: Outcome
    private let source: SourceID
    private(set) var pulls = 0

    init(_ outcome: Outcome, source: SourceID) {
        self.outcome = outcome
        self.source = source
    }

    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        pulls += 1
        switch outcome {
        case .batch(let count, let bytes):
            let observations = (0..<count).map { index in
                AcquisitionObservation(objectIdentity: ExternalIdentity(connectorKind: .syndication,
                    namespace: "objects", value: "external-\(index)", role: .object),
                    versionIdentity: nil, precedence: .makeCurrent, availability: .available,
                    headline: "Headline \(index)", summary: nil, bodyText: nil, authoredAt: nil, modifiedAt: nil,
                    observedAt: Date(timeIntervalSince1970: Double(index + 1)), language: nil, primaryLink: nil,
                    searchProjection: nil, providerID: nil,
                    memberships: [.init(sourceID: source, kind: .direct)], mediaCandidates: [])!
            }
            return .batch(AcquisitionBatch(targetID: request.targetID,
                targetGeneration: request.targetGeneration,
                expectedCheckpointRevision: request.checkpointRevision, observations: observations,
                nextCheckpoint: nil)!, transportByteCount: bytes)
        case .upToDate: return .upToDate
        case .cancelled: return .cancelled
        case .operationalFailure: throw ConnectorOperationalFailure.transport
        }
    }
}

@MainActor
final class ReplenishmentTraceTests: XCTestCase {
    // MARK: - shared fixture pieces

    private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))! }
    private func scope(_ n: Int = 1) -> RunwayScope {
        RunwayScope(editionID: FeedEditionID(rawValue: uuid(n)), contextKey: ContextKey(request: .main),
            editorialRevisionID: EditorialRevisionID(rawValue: uuid(100 + n)))
    }
    private func time(_ seconds: Double) -> RunwayMonotonicTime { RunwayMonotonicTime(seconds: seconds)! }
    private func observation(_ card: Int, _ seconds: Double, activity: RunwayActivity = .forward,
        scope: RunwayScope? = nil) -> RunwayObservation {
        RunwayObservation(editionID: (scope ?? self.scope()).editionID,
            anchorCardID: PublicationCardID(rawValue: uuid(1000 + card)), sampledAt: time(seconds), activity: activity)
    }
    private func resources() -> RunwayResourceFacts {
        RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 7, readyProbeBound: 5,
            readyProbeCeiling: 100, forwardAdvanceProbeBound: 20)!
    }
    private func measurement(_ o: RunwayObservation, amount: ReadyAheadAmount = .exact(0)) -> RunwayMeasurement {
        RunwayMeasurement(observation: o, readyAhead: ReadyAheadFacts(editionID: o.editionID,
            anchorCardID: o.anchorCardID, observedTailCardID: PublicationCardID(rawValue: uuid(9999)), amount: amount),
            advanceFromHighWater: nil)
    }
    private func workBounds() -> AcquisitionWorkBounds {
        AcquisitionWorkBounds(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100)!
    }

    // MARK: - the request

    /// The decision names the operation, the kind and the facts it decided on — and the id it minted reaches the
    /// executor inside the intent, which is the only thing that can carry it there.
    func testTheDecisionReportsTheOperationItsKindAndTheCoverageFactsItUsed() async throws {
        let recorder = TraceRecorder()
        let sut = RunwayController(configuration: RunwayControllerConfiguration(
            policyInputs: RunwayPolicyInputs(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 2, replenishmentSampleLimit: 2)!, trace: recorder.trace)
        await sut.activate(scope())
        let first = observation(1, 0)
        try await sut.submitObservation(first)
        try await sut.acceptMeasurement(measurement(first))

        guard case .runLocalSlice(let local) = try await sut.reconsider(resources: resources(), at: time(1))
        else { return XCTFail("Expected a local slice") }
        let requests = recorder.fields(ReplenishmentEvent.requested)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0]["op"], local.operation.described)
        XCTAssertEqual(requests[0]["kind"], "local")
        XCTAssertEqual(requests[0]["lane"], "episode")
        XCTAssertEqual(requests[0]["examined_capacity"], "7")
        XCTAssertEqual(requests[0]["ready"], "exact")
        XCTAssertEqual(requests[0]["ready_cards"], "0")
        XCTAssertEqual(requests[0]["edition"], scope().editionID.rawValue.uuidString)
        XCTAssertEqual(requests[0]["surface"], "main")
        XCTAssertTrue(["healthy", "pressured", "logical_pressure", "unknown"].contains(requests[0]["coverage"] ?? ""))

        // The slice exhausts the local supply, and the next decision asks the network — under its own operation.
        try await sut.completeLocalSlice(local, outcome: .advancedWithoutPublication(
            LocalProductionProgress(examinedCount: 7, nextCursor: nil, exhausted: true)), at: time(2))
        try await sut.acceptMeasurement(measurement(first))
        guard case .requestAcquisition(let network) = try await sut.reconsider(resources: resources(), at: time(3))
        else { return XCTFail("Expected a network acquisition") }
        let all = recorder.fields(ReplenishmentEvent.requested)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1]["op"], network.operation.described)
        XCTAssertEqual(all[1]["kind"], "network")
        XCTAssertEqual(all[1]["pressure"], "logical_tail_pressure")
        XCTAssertNotEqual(network.operation, local.operation)
    }

    /// The correlation id is evidence, not identity: the decisions compare intents exactly as they did before it
    /// existed, so minting one can never make the same demand look like a new one.
    func testTheOperationIDIsNotPartOfWhatADecisionCompares() throws {
        let target = scope()
        let demand = AcquisitionDemand(contextKey: target.contextKey,
            editorialRevisionID: target.editorialRevisionID, purpose: .readerContinuation,
            pressure: .logicalTailPressure, localSupply: ExhaustedLocalSupply(readyCards: 0)!)!
        let one = RunwayAcquisitionIntent(scope: target, demand: demand)
        let two = RunwayAcquisitionIntent(scope: target, demand: demand)
        XCTAssertNotEqual(one.operation, two.operation)
        XCTAssertEqual(one, two)
        XCTAssertEqual(one.hashValue, two.hashValue)

        let local = RunwayLocalSliceIntent(scope: target, lane: .episode, after: nil, examinedCapacity: 7,
            startedAt: time(1))
        let same = RunwayLocalSliceIntent(scope: target, lane: .episode, after: nil, examinedCapacity: 7,
            startedAt: time(1))
        XCTAssertNotEqual(local.operation, same.operation)
        XCTAssertEqual(local, same)
        XCTAssertEqual(local.hashValue, same.hashValue)
    }

    // MARK: - the arrival (network) and the pool admission

    private func networkFixture() throws -> (database: RuntimeDatabase, target: AcquisitionTarget, source: SourceID, recorder: TraceRecorder) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let source = SourceID()
        let target = try AcquisitionTargetAuthority(database: database).register(id: AcquisitionTargetID(),
            connectorKind: .syndication, authorizedSources: [source])
        return (database, target, source, TraceRecorder())
    }

    func testTheNetworkArrivalAndThePoolAdmissionReportTheSameOperation() async throws {
        let (database, target, source, recorder) = try networkFixture()
        let connector = ScriptedConnector(.batch(2, bytes: 42), source: source)
        let coordinator = AcquisitionCoordinator(database: database, connectorForTarget: { _ in connector })
        let operation = FeedReplenishmentOperationID()

        let result = try await coordinator.execute(.start(target: target, bounds: workBounds()),
            operation: operation, trace: recorder.trace)
        XCTAssertEqual(result.stop, .capacityReached)
        let arrived = recorder.fields(ReplenishmentEvent.arrived)
        XCTAssertEqual(arrived.count, 1)
        XCTAssertEqual(arrived[0]["op"], operation.described)
        XCTAssertEqual(arrived[0]["kind"], "network")
        XCTAssertEqual(arrived[0]["result"], "batch")
        XCTAssertEqual(arrived[0]["observations"], "2")
        XCTAssertEqual(arrived[0]["bytes"], "42")
        XCTAssertEqual(arrived[0]["attempt"], "1")

        let concluded = recorder.fields(ReplenishmentEvent.concluded)
        XCTAssertEqual(concluded.count, 1)
        XCTAssertEqual(concluded[0]["op"], operation.described)
        XCTAssertEqual(concluded[0]["destination"], "pool_admission")
        XCTAssertEqual(concluded[0]["observations"], "2")
        XCTAssertEqual(concluded[0]["selectable_supply_changed"], "true")
        XCTAssertEqual(concluded[0]["checkpoint_advanced"], "false")
    }

    /// Empty, failure and cancellation are outcomes of a pull. Each is reported as an arrival, and none of them
    /// claims a destination it never reached.
    func testAnUnproductivePullIsReportedAsAnArrivalWithNoAdmission() async throws {
        for (outcome, expected) in [(ScriptedConnector.Outcome.upToDate, "up_to_date"),
            (.cancelled, "cancelled"), (.operationalFailure, "failure")] {
            let (database, target, source, recorder) = try networkFixture()
            let coordinator = AcquisitionCoordinator(database: database,
                connectorForTarget: { _ in ScriptedConnector(outcome, source: source) })
            let operation = FeedReplenishmentOperationID()
            _ = try? await coordinator.execute(.start(target: target, bounds: workBounds()),
                operation: operation, trace: recorder.trace)
            let arrived = recorder.fields(ReplenishmentEvent.arrived)
            XCTAssertEqual(arrived.count, 1, expected)
            XCTAssertEqual(arrived[0]["result"], expected)
            XCTAssertEqual(arrived[0]["op"], operation.described)
            XCTAssertTrue(recorder.fields(ReplenishmentEvent.concluded).isEmpty, expected)
        }
    }

    // MARK: - the arrival (local) and the published segment

    private func localFixture() throws -> (database: RuntimeDatabase, slice: LocalProductionSlice, request: LocalProductionSlice.Request, recorder: TraceRecorder) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let context = FeedContext(request: .main), version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(rawValue: uuid(40000)), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version, sequencingPolicyVersion: version,
            exposurePolicyVersion: version, selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: revision.contextKey, userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version, sequencingPolicyVersion: version,
            exposurePolicyVersion: version, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending,
            exposure: .excludePublishedRevisions)
        let edition = FeedEditionID(rawValue: uuid(41000))
        let source = SourceID(rawValue: uuid(43000))
        let anchor = Self.originRevision(900)
        try Self.admit(anchor, database: database, source: source)
        let anchorSelection = SelectionResult(editorialRevision: revision,
            orderedCandidates: [Self.candidate(anchor)],
            supplyReport: SelectionSupplyReport(examinedCount: 0, nextCursor: nil, exhausted: true))
        let anchorPrepared = Self.prepared(anchorSelection)
        _ = try PublicationCoordinator(database: database).createEdition(.init(selection: anchorSelection,
            drafts: PublicationPreparation.drafts(selection: anchorSelection, inputs: anchorPrepared.inputs),
            editionID: edition, publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1), selectionSeed: 7,
            editionCreatedAt: Date(timeIntervalSince1970: 10), segmentID: FeedSegmentID(rawValue: uuid(42000)),
            segmentSeed: 8, segmentCreatedAt: Date(timeIntervalSince1970: 11), cardIDs: anchorPrepared.cardIDs))
        let fresh = Self.originRevision(901)
        try Self.admit(fresh, database: database, source: source)
        let recorder = TraceRecorder()
        let request = LocalProductionSlice.Request(plan: plan, policy: policy, editionID: edition, after: nil,
            examinedCapacity: 8, segmentID: FeedSegmentID(rawValue: uuid(44000)), segmentSeed: 9,
            segmentCreatedAt: Date(timeIntervalSince1970: 12))
        return (database, LocalProductionSlice(database: database, trace: recorder.trace), request, recorder)
    }

    /// The consult and the segment are separated by selection, preparation and the append — measuring both is the
    /// point of recording the arrival on the local path instead of presuming it collapses into publication.
    func testTheLocalConsultAndThePublishedSegmentReportTheSameOperation() throws {
        let (database, slice, base, recorder) = try localFixture()
        let operation = FeedReplenishmentOperationID()
        // The consult reports the **structural** window — both origins, the published anchor included — while the
        // segment publishes one. That gap is the reason the arrival is measured before selection rather than
        // inferred from the publication.
        XCTAssertEqual(try CandidateProvider(contentStore: ContentStore(database: database))
            .candidates(for: base.plan, after: nil, examinedCapacity: 8).candidates.count, 2)
        let request = LocalProductionSlice.Request(plan: base.plan, policy: base.policy, editionID: base.editionID,
            after: base.after, examinedCapacity: base.examinedCapacity, segmentID: base.segmentID,
            segmentSeed: base.segmentSeed, segmentCreatedAt: base.segmentCreatedAt, operation: operation)
        let outcome = try slice.run(request) { Self.prepared($0) }
        guard case .published(_, let receipt) = outcome else { return XCTFail("Expected a published segment") }

        let arrived = recorder.fields(ReplenishmentEvent.arrived)
        XCTAssertEqual(arrived.count, 1)
        XCTAssertEqual(arrived[0]["op"], operation.described)
        XCTAssertEqual(arrived[0]["kind"], "local")
        XCTAssertEqual(arrived[0]["consult"], "slice")
        XCTAssertEqual(arrived[0]["result"], "window")
        XCTAssertEqual(arrived[0]["candidates"], "2")
        XCTAssertEqual(arrived[0]["exhausted"], "true")

        let concluded = recorder.fields(ReplenishmentEvent.concluded)
        XCTAssertEqual(concluded.count, 1)
        XCTAssertEqual(concluded[0]["op"], operation.described)
        XCTAssertEqual(concluded[0]["destination"], "segment_publication")
        XCTAssertEqual(concluded[0]["edition"], receipt.editionID.rawValue.uuidString)
        XCTAssertEqual(concluded[0]["segment"], receipt.segmentID.rawValue.uuidString)
        XCTAssertEqual(concluded[0]["ordinal"], String(receipt.segmentOrdinal))
        XCTAssertEqual(concluded[0]["cards"], "1")
        XCTAssertEqual(concluded[0]["head"], receipt.cardIDs[0].rawValue.uuidString)
        XCTAssertEqual(concluded[0]["tail"], receipt.cardIDs[0].rawValue.uuidString)
    }

    /// Without an operation nothing is reported: the same call, the same work, and the trace stays as silent as it
    /// was before the port existed.
    func testWorkThatIsNotAReplenishmentReportsNothing() throws {
        let (database, slice, base, recorder) = try localFixture()
        let outcome = try slice.run(base) { Self.prepared($0) }
        guard case .published = outcome else { return XCTFail("Expected a published segment") }
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(try CandidateProvider(contentStore: ContentStore(database: database))
            .candidates(for: base.plan, after: nil, examinedCapacity: 8).candidates.count, 2)
    }

    // MARK: - tiny local fixture pieces (mirrors the shape the slice tests already use)

    nonisolated private static func originRevision(_ n: Int) -> OriginRevision {
        OriginRevision(id: OriginRevisionID(rawValue: LocalIDs.uuid(1000 + n)),
            originRecordID: OriginRecordID(rawValue: LocalIDs.uuid(n)), externalVersionIdentity: nil,
            headline: "Headline \(n)", summary: "Summary \(n)", bodyText: nil,
            authoredAt: Date(timeIntervalSince1970: Double(n)), modifiedAt: nil,
            observedAt: Date(timeIntervalSince1970: 999), language: nil, primaryLink: nil, searchProjection: nil,
            providerID: nil)
    }
    nonisolated private static func candidate(_ revision: OriginRevision) -> Candidate {
        Candidate(originRecordID: revision.originRecordID, originRevisionID: revision.id,
            headline: revision.headline, summary: revision.summary,
            timestamp: CandidateTimestamp(value: revision.authoredAt ?? revision.observedAt,
                kind: revision.authoredAt == nil ? .observed : .authored),
            language: revision.language, providerID: revision.providerID)
    }
    nonisolated private static func prepared(_ selection: SelectionResult) -> LocalPreparedPublication {
        LocalPreparedPublication(inputs: selection.orderedCandidates.map { candidate in
            PublicationPreparationInput(origin: PublishedOrigin(originRecordID: candidate.originRecordID,
                originRevisionID: candidate.originRevisionID, sourceID: nil, providerID: candidate.providerID,
                sourceDisplayName: "Test Source", providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail,
                presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }
    nonisolated private static func admit(_ revision: OriginRevision, database: RuntimeDatabase, source: SourceID) throws {
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: revision.originRecordID,
            externalObjectIdentity: ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),
                namespace: "objects", value: revision.originRecordID.rawValue.uuidString, role: .object),
            revision: revision, mediaCandidates: [], availability: .available, observedAt: revision.observedAt,
            expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: revision.observedAt)]))
    }
}

private enum LocalIDs {
    static func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))! }
}
