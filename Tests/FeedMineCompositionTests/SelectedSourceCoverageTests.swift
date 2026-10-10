import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineComposition

private final class CoverageJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [AcquisitionTargetID] = []
    private var terminals: [AcquisitionTargetID] = []
    func enter(_ id: AcquisitionTargetID) { lock.withLock { entries.append(id) } }
    func settle(_ id: AcquisitionTargetID) { lock.withLock { terminals.append(id) } }
    var pulls: [AcquisitionTargetID] { lock.withLock { entries } }
    var outcomes: [AcquisitionTargetID] { lock.withLock { terminals } }
}
private enum CoverageResponse: Equatable, Sendable { case items, empty, upToDate, failure }
private final class CoverageGate: Sendable {
    let stream: AsyncStream<Void>
    let signal: AsyncStream<Void>.Continuation
    let entered: @Sendable () -> Void
    init(entered: @escaping @Sendable () -> Void) {
        (stream, signal) = AsyncStream.makeStream(); self.entered = entered
    }
    func wait() async { entered(); for await _ in stream { break } }
    func release() { signal.yield(()); signal.finish() }
}
private struct CoverageConnector: FeedConnector {
    let journal: CoverageJournal
    let sources: [SourceID]
    var response: CoverageResponse = .items
    var gate: CoverageGate? = nil
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        journal.enter(request.targetID)
        defer { journal.settle(request.targetID) }
        await gate?.wait()
        try Task.checkCancellation()
        if case .upToDate = response { return .upToDate }
        if case .failure = response { throw ConnectorOperationalFailure.transport }
        let observations = (0..<(response == .empty ? 0 : 20)).map { index in
            AcquisitionObservation(objectIdentity: .init(connectorKind: .syndication, namespace: request.targetID.rawValue.uuidString,
                value: "item-\(index)", role: .object), versionIdentity: nil, precedence: .makeCurrent,
                availability: .available, headline: "Item \(index)", summary: nil, bodyText: nil,
                authoredAt: Date(timeIntervalSince1970: Double(100 - index)), modifiedAt: nil,
                observedAt: Date(timeIntervalSince1970: 100), language: nil, primaryLink: nil,
                searchProjection: nil, providerID: nil, memberships: sources.map { .init(sourceID: $0, kind: .direct) }, mediaCandidates: [])!
        }
        return .batch(.init(targetID: request.targetID, targetGeneration: request.targetGeneration,
            expectedCheckpointRevision: request.checkpointRevision, observations: observations, nextCheckpoint: response == .empty ? .init(blob: Data([1]), serializationSchema: 1, connectorVersion: "coverage")! : nil)!, transportByteCount: 100)
    }
}
@MainActor
final class SelectedSourceCoverageTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let plan: FeedPlan
        let policy: ResolvedSelectionPolicy
        let session: FeedSession
        let snapshot: SyndicationAcquisitionSnapshot
        let coordinator: AcquisitionCoordinator
        let journal: CoverageJournal
        let targets: [AcquisitionTarget]
        let sources: [SourceID]
    }
    private func fixture(response: CoverageResponse = .items, shared: Bool = false, sourceContext: Bool = false,
        search: Bool = false, gate: CoverageGate? = nil, shuffledIDs: Bool = false) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let sources = (0..<4).map { _ in SourceID() }
        let sourceGroups = shared ? [[sources[0], sources[1]], [sources[2]], [sources[3]]] : sources.map { [$0] }
        let context = FeedContext(request: search ? .search(SearchContext(query: "Item")!) : sourceContext ? .source(sources[0]) : .main), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = FeedPlan(context: context, revision: revision)!
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyAlternatingSources, exposure: .excludePublishedRevisions)
        let targets = try sourceGroups.indices.map { index in
            try AcquisitionTargetAuthority(database: database).register(id: .init(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", (shuffledIDs ? [3, 1, 2, 4][index] : index + 1)))!),
                connectorKind: .syndication, authorizedSources: Set(sourceGroups[index]))
        }
        let registrations = targets.enumerated().map { index, target in
            let bindings = sourceGroups[index].map { source in SourceBinding(id: SourceBindingID(), sourceID: source,
                externalPrincipal: .init(connectorKind: .syndication, namespace: "coverage", value: source.rawValue.uuidString, role: .principal),
                aliases: [], generation: 1, state: .enabled)! }
            return SyndicationTargetRegistration(targetID: target.id, targetGeneration: 1,
                endpoint: URL(string: "https://coverage.test/\(index)")!, bindings: bindings)!
        }
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        let snapshot = try SyndicationAcquisitionSnapshot(database: database, registrations: registrations, session: transport, redirectCapacity: 0)
        let journal = CoverageJournal()
        let byTarget = Dictionary(uniqueKeysWithValues: zip(targets.map(\.id), sourceGroups))
        let coordinator = AcquisitionCoordinator(database: database, connectorForTarget: { target in
            CoverageConnector(journal: journal, sources: byTarget[target.id]!,
                response: targets.prefix(2).contains(where: { $0.id == target.id }) ? .items : response,
                gate: target.id == targets[2].id ? gate : nil)
        }, backoff: .init(baseSeconds: 30, ceilingSeconds: 60), concurrentTargetLimit: 2,
            monotonicSeconds: { 1 })
        return .init(database: database, plan: plan, policy: policy, session: FeedSession(publicationHistory: .init(database: database)),
            snapshot: snapshot, coordinator: coordinator, journal: journal, targets: targets, sources: sources)
    }
    nonisolated private static func prepare(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map { candidate in
            .init(origin: .init(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                sourceID: candidate.sourceIDs.first, providerID: nil, sourceDisplayName: "Fixture", providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }
    private func resources(targetCapacity: Int = 2, reserve: Int = 16) -> FeedRunwayDriverResources {
        .init(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 100, readyProbeBound: 64,
            readyProbeCeiling: 128, forwardAdvanceProbeBound: 64, reserveCards: reserve)!,
            acquisition: .init(targetWorkCapacity: targetCapacity, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 100, byteCapacityPerBatch: 100_000)!)
    }
    private func cold(_ f: Fixture) async throws -> FeedPresentationSnapshot {
        let cold = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy, acquisition: f.snapshot,
            coordinator: f.coordinator, prepare: Self.prepare)
        let identity = ColdFeedPublicationIdentity(editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1),
            selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 200), segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(timeIntervalSince1970: 201), anchorPlacement: .top, checkpointedAt: Date(timeIntervalSince1970: 202))!
        guard case .published(let snapshot) = try await cold.run(identity: identity,
            resources: .init(localExaminedCapacity: 100, acquisition: resources().acquisition)!, backwardCapacity: 0, forwardCapacity: 64)
        else { throw NSError(domain: "Expected publication", code: 1) }
        return snapshot
    }
    private func driver(_ f: Fixture) throws -> (FeedRunwayDriver, RunwayController) {
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 4, replenishmentSampleLimit: 4)!)
        return (try FeedRunwayDriver(session: f.session, runway: runway, plan: f.plan, policy: f.policy,
            acquisition: f.snapshot, coordinator: f.coordinator, monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 203))! },
            prepare: Self.prepare,
            selectedSourceCoverage: .init(selectedSourceCoverageFor: f.plan.context.key, editorialRevisionID: f.plan.revision.id)), runway)
    }
    func testP1StationaryHealthyRunwayStillExecutesRemainingSelectedTargets() async throws {
        let f = try fixture(), first = try await cold(f)
        XCTAssertEqual(Set(f.journal.pulls), Set(f.targets.prefix(2).map(\.id)))
        XCTAssertEqual(f.journal.outcomes.count, 2)
        let (driver, runway) = try driver(f)
        _ = try await driver.activateCurrentPresentation(resources: resources())
        try await runway.submitObservation(.init(editionID: first.editionID, anchorCardID: first.window.anchor.cardID,
            sampledAt: .init(seconds: ProcessInfo.processInfo.systemUptime)!, activity: .stationary))
        _ = try await driver.drive(resources: resources())
        let state = await runway.snapshot()
        XCTAssertEqual(state.lastCoverage, .healthy)
        let ready = try PublicationHistory(database: f.database).readyAhead(editionID: first.editionID,
            anchorCardID: first.window.anchor.cardID, probeBound: 64)
        if case .exact(let count) = ready.amount { XCTAssertGreaterThanOrEqual(count, 16) }
        else { XCTFail("Expected exact runway") }
        XCTAssertEqual(Set(f.journal.pulls), Set(f.targets.map(\.id)), "Healthy depth must not starve the other selected targets")
        XCTAssertEqual(f.journal.pulls.count, 4)
        XCTAssertEqual(f.journal.outcomes.count, 4)
    }
    func testP2SettledCoverageDoesNotChurnOrRewritePublishedHistory() async throws {
        let f = try fixture(), first = try await cold(f), (driver, _) = try driver(f)
        _ = try await driver.activateCurrentPresentation(resources: resources())
        let store = PublicationStore(database: f.database)
        let segments = try store.segments(editionID: first.editionID)
        let cards = try segments.flatMap { try $0.cardIDs.map { try XCTUnwrap(store.card(id: $0)) } }
        for _ in 0..<10 { _ = try await driver.drive(resources: resources()) }
        XCTAssertEqual(f.journal.pulls.count, 4); XCTAssertEqual(f.journal.outcomes.count, 4)
        XCTAssertEqual(try store.segments(editionID: first.editionID), segments)
        XCTAssertEqual(try segments.flatMap { try $0.cardIDs.map { try XCTUnwrap(store.card(id: $0)) } }, cards)
        XCTAssertEqual(cards.first?.id, first.window.anchor.cardID)
        for (a, b) in zip(cards, cards.dropFirst()) { XCTAssertNotEqual(a.sourceID, b.sourceID) }
    }
    func testP3UpToDateEmptyAndFailureSettleWithoutImmediateRetryOrFakeSupply() async throws {
        for response in [CoverageResponse.upToDate, .empty, .failure] {
            let f = try fixture(response: response), first = try await cold(f), (driver, runway) = try driver(f)
            _ = try await driver.activateCurrentPresentation(resources: resources(targetCapacity: 0))
            let scopeValue = await f.session.currentRunwayScope(), scope = try XCTUnwrap(scopeValue)
            let count = try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 100).records.count
            let outcome = try await RunwayAcquisitionCycle(runway: runway, coordinator: f.coordinator).runCoverage(
                .init(selectedSourceCoverageFor: f.plan.context.key, editorialRevisionID: f.plan.revision.id), scope: scope,
                eligibleTargets: f.snapshot.eligibleTargets(for: f.plan.context), resources: resources().acquisition)
            guard case .executed(let results) = outcome else { return XCTFail("Expected coverage execution") }
            XCTAssertEqual(results.count, 2); XCTAssertFalse(outcome.selectableSupplyChanged)
            for result in results {
                XCTAssertEqual(result.stop, response == .upToDate ? .upToDate : response == .empty ? .capacityReached : .operationalFailure(.transport))
            }
            for _ in 0..<5 { _ = try await driver.drive(resources: resources()) }
            XCTAssertEqual(f.journal.pulls.count, 4); XCTAssertEqual(f.journal.outcomes.count, 4)
            XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 100).records.count, count)
            let presentation = await f.session.currentPresentation(); XCTAssertEqual(presentation?.editionID, first.editionID)
            if response == .failure {
                let cooling = await f.coordinator.coolingTargetIDs()
                XCTAssertEqual(cooling, Set(f.targets.suffix(2).map(\.id)))
            }
        }
    }
    func testP3RepeatedPayloadSettlesWithoutFabricatedProgress() async throws {
        let f = try fixture()
        // Seed canonical observations without using this opportunity's coordinator or journal.
        for (target, source) in zip(f.targets, f.sources) {
            let request = FeedConnectorPull(targetID: target.id, targetGeneration: 1, checkpointRevision: 0,
                checkpoint: nil, observationCapacity: 100, byteCapacity: 100_000)!
            let event = try await CoverageConnector(journal: CoverageJournal(), sources: [source]).pull(request)
            guard case .batch(let batch, _) = event else { return XCTFail("Expected seed") }
            _ = try AdmissionPolicy(database: f.database).admit(batch)
        }
        let first = try await cold(f)
        XCTAssertTrue(f.journal.pulls.isEmpty, "Local-first initial publication does not wait for acquisition")
        let (driver, runway) = try driver(f)
        _ = try await driver.activateCurrentPresentation(resources: resources(targetCapacity: 0))
        let scopeValue = await f.session.currentRunwayScope(), scope = try XCTUnwrap(scopeValue)
        let outcome = try await RunwayAcquisitionCycle(runway: runway, coordinator: f.coordinator).runCoverage(
            .init(selectedSourceCoverageFor: f.plan.context.key, editorialRevisionID: f.plan.revision.id), scope: scope,
            eligibleTargets: f.snapshot.eligibleTargets(for: f.plan.context), resources: resources(targetCapacity: 4).acquisition)
        guard case .executed(let results) = outcome else { return XCTFail("Expected repeated payload execution") }
        XCTAssertEqual(results.count, 4); XCTAssertFalse(outcome.selectableSupplyChanged)
        XCTAssertTrue(results.allSatisfy { $0.stop == .capacityReached && !$0.selectableSupplyChanged })
        _ = try await driver.drive(resources: resources())
        XCTAssertEqual(f.journal.pulls.count, 4)
        XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 100).records.count, 80)
        let presentation = await f.session.currentPresentation(); XCTAssertEqual(presentation?.editionID, first.editionID)
    }
    func testP4SharedTargetRunsOnceAndRetainsDistinctSourceMemberships() async throws {
        let f = try fixture(shared: true), first = try await cold(f), (driver, _) = try driver(f)
        _ = try await driver.activateCurrentPresentation(resources: resources())
        XCTAssertEqual(f.journal.pulls.count, 3); XCTAssertEqual(Set(f.journal.pulls).count, 3)
        let candidates = try CandidateProvider(contentStore: .init(database: f.database)).candidates(for: f.plan, after: nil, examinedCapacity: 100).candidates
        XCTAssertTrue(candidates.contains { $0.sourceIDs == Set(f.sources.prefix(2)) })
        XCTAssertEqual(Set(candidates.flatMap(\.sourceIDs)), Set(f.sources))
        let segments = try PublicationStore(database: f.database).segments(editionID: first.editionID)
        let cards = try segments.flatMap { try $0.cardIDs.map { try XCTUnwrap(PublicationStore(database: f.database).card(id: $0)) } }
        for (a, b) in zip(cards, cards.dropFirst()) { XCTAssertNotEqual(a.sourceID, b.sourceID) }
    }
    func testP5DeniedResourcesResumePendingCoverageOnRecovery() async throws {
        let f = try fixture(), first = try await cold(f), (driver, _) = try driver(f)
        let denied = try await driver.activateCurrentPresentation(resources: resources(targetCapacity: 0))
        XCTAssertEqual(f.journal.pulls.count, 2); XCTAssertEqual(denied?.editionID, first.editionID)
        _ = try await driver.drive(resources: resources(targetCapacity: 0))
        XCTAssertEqual(f.journal.pulls.count, 2)
        _ = try await driver.drive(resources: resources(targetCapacity: 1))
        XCTAssertEqual(f.journal.pulls.count, 4); XCTAssertEqual(f.journal.outcomes.count, 4)
    }
    func testP6ScopeChangeAndCompetingDriveWhileConnectorSuspended() async throws {
        let entered = expectation(description: "Coverage connector entered")
        let gate = CoverageGate { entered.fulfill() }; defer { gate.release() }
        let f = try fixture(gate: gate), first = try await cold(f), (driver, runway) = try driver(f)
        let task = Task { try await driver.activateCurrentPresentation(resources: resources(targetCapacity: 1)) }
        let waited = await XCTWaiter.fulfillment(of: [entered], timeout: 5); XCTAssertEqual(waited, .completed)
        let old = await f.session.currentPresentation()
        let competing = try await driver.drive(resources: resources(targetCapacity: 1))
        XCTAssertEqual(competing, old); XCTAssertEqual(f.journal.pulls.count, 3)
        let oldSegments = try PublicationStore(database: f.database).segments(editionID: first.editionID)
        let otherContext = FeedContext(request: .source(f.sources[3])), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: otherContext.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let candidate = Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), headline: "B local",
            summary: nil, timestamp: .init(value: Date(timeIntervalSince1970: 1), kind: .observed), language: nil, providerID: nil, sourceIDs: [f.sources[3]])
        let selection = SelectionResult(editorialRevision: revision, orderedCandidates: [candidate], supplyReport: .init(examinedCount: 0, nextCursor: nil, exhausted: true))
        let prepared = Self.prepare(selection), otherEdition = FeedEditionID()
        _ = try PublicationCoordinator(database: f.database).createEdition(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs), editionID: otherEdition,
            publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 300),
            segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(timeIntervalSince1970: 301), cardIDs: prepared.cardIDs))
        try PublicationHistory(database: f.database).saveCursor(.init(editionID: otherEdition,
            anchor: .init(cardID: prepared.cardIDs[0], placement: .top)), updatedAt: Date(timeIntervalSince1970: 302))
        _ = try await f.session.restoreLocalPresentation(backwardCapacity: 0, forwardCapacity: 64)
        let newScopeValue = await f.session.currentRunwayScope(), newScope = try XCTUnwrap(newScopeValue)
        await runway.activate(newScope)
        let newPresentation = await f.session.currentPresentation(), checkpoint = try SessionStore(database: f.database).checkpoint()
        gate.release()
        do { _ = try await task.value; XCTFail("Old driver must reject a competing reconsideration in B") }
        catch { XCTAssertEqual(error as? FeedRunwayDriverError,
            .sessionContextMismatch(expected: f.plan.context.key, actual: otherContext.key)) }
        let settled = await f.session.currentPresentation()
        XCTAssertEqual(settled, newPresentation); XCTAssertEqual(f.journal.pulls.count, 3)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: first.editionID), oldSegments)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: otherEdition).count, 1)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        let acquired = try ContentStore(database: f.database).candidateWindow(sourceID: f.sources[2], after: nil, examinedCapacity: 100).records
        XCTAssertEqual(acquired.count, 20)
        XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id: f.targets[2].id)?.checkpointRevision, 0)
        XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id: f.targets[3].id)?.checkpointRevision, 0)
    }
    func testP7SingleSourceAndSearchIsolation() async throws {
        let f = try fixture(sourceContext: true), _ = try await cold(f), (driver, _) = try driver(f)
        _ = try await driver.activateCurrentPresentation(resources: resources())
        XCTAssertEqual(f.journal.pulls, [f.targets[0].id])
        let search = try fixture(search: true)
        // Supply from another authorized context stays locally searchable.
        let request = FeedConnectorPull(targetID: search.targets[0].id, targetGeneration: 1, checkpointRevision: 0,
            checkpoint: nil, observationCapacity: 100, byteCapacity: 100_000)!
        guard case .batch(let batch, _) = try await CoverageConnector(journal: CoverageJournal(), sources: [search.sources[0]]).pull(request)
        else { return XCTFail("Expected local seed") }
        _ = try AdmissionPolicy(database: search.database).admit(batch)
        _ = try await cold(search)
        let (searchDriver, _) = try self.driver(search)
        _ = try await searchDriver.activateCurrentPresentation(resources: resources())
        XCTAssertTrue(search.journal.pulls.isEmpty)
    }
    func testUnattemptedTargetsPrecedeReplayDuringDepthPressure() async throws {
        let f = try fixture(shuffledIDs: true), _ = try await cold(f), (driver, _) = try driver(f)
        _ = try await driver.activateCurrentPresentation(resources: resources(reserve: 64))
        XCTAssertEqual(f.journal.pulls.count, 4)
        XCTAssertEqual(Set(f.journal.pulls), Set(f.targets.map(\.id)))
    }

    func testP8DeactivationDuringCoveragePreservesHistoryAndCanonicalProvenance() async throws {
        let entered = expectation(description: "Coverage suspended before deactivation")
        let gate = CoverageGate { entered.fulfill() }; defer { gate.release() }
        let f = try fixture(gate: gate), first = try await cold(f), (driver, runway) = try driver(f)
        let task = Task { try await driver.activateCurrentPresentation(resources: resources(targetCapacity: 1)) }
        let waited = await XCTWaiter.fulfillment(of: [entered], timeout: 5); XCTAssertEqual(waited, .completed)
        let history = try PublicationStore(database: f.database).segments(editionID: first.editionID)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        await driver.deactivate(); gate.release(); _ = try await task.value
        let snapshot = await runway.snapshot(); XCTAssertNil(snapshot.scope)
        XCTAssertEqual(f.journal.pulls.count, 3)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: first.editionID), history)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertEqual(try ContentStore(database: f.database).candidateWindow(sourceID: f.sources[2], after: nil, examinedCapacity: 100).records.count, 20)
        let active = await f.coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
    }
    func testP8RevokedSelectedTargetDoesNotExecute() async throws {
        let f = try fixture(), _ = try await cold(f)
        _ = try AcquisitionTargetAuthority(database: f.database).revoke(id: f.targets[3].id, expectedGeneration: 1)
        let (driver, _) = try driver(f)
        do { _ = try await driver.activateCurrentPresentation(resources: resources()); XCTFail("Revoked configuration must be rejected") }
        catch { XCTAssertEqual(error as? SyndicationAcquisitionSnapshotError,
            .staleConfigurationGeneration(targetID: f.targets[3].id, configured: 1, durable: 2)) }
        XCTAssertEqual(f.journal.pulls.count, 2)
        XCTAssertFalse(f.journal.pulls.contains(f.targets[3].id))
        XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id: f.targets[3].id)?.checkpointRevision, 0)
    }

}
