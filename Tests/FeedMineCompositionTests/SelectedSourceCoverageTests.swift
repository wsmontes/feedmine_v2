import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
@testable import FeedMinePublication
@testable import FeedMineRuntime
@testable import FeedMineComposition

private final class CoverageJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [AcquisitionTargetID] = []
    private var terminals: [AcquisitionTargetID] = []
    func enter(_ id: AcquisitionTargetID) { lock.withLock { entries.append(id) } }
    func settle(_ id: AcquisitionTargetID) { lock.withLock { terminals.append(id) } }
    var pulls: [AcquisitionTargetID] { lock.withLock { entries } }
    var outcomes: [AcquisitionTargetID] { lock.withLock { terminals } }
}
private final class CompletionCount: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int?
    func set(_ value: Int) { lock.withLock { stored = value } }
    @discardableResult func increment() -> Int { lock.withLock { stored = (stored ?? 0) + 1; return stored! } }
    var value: Int? { lock.withLock { stored } }
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
    private func resources(targetCapacity: Int = 2, reserve: Int = 16,
        discovery: Int? = nil) -> FeedRunwayDriverResources {
        .init(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 100, readyProbeBound: 64,
            readyProbeCeiling: 128, forwardAdvanceProbeBound: 64, reserveCards: reserve)!,
            acquisition: .init(targetWorkCapacity: targetCapacity, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 100, byteCapacityPerBatch: 100_000)!,
            discoveryExaminedCapacity: discovery ?? 0)
    }
    /// The fixture alternates sources, so a late occurrence from the same source as the Edition's tail is held
    /// by the selection rule and never publishes. Pick a cold source that differs from the last admitted card.
    private func lateTargetAndSource(_ f: Fixture, editionID: FeedEditionID) throws
        -> (AcquisitionTargetID, SourceID) {
        let store = PublicationStore(database: f.database)
        let tailID = try store.segments(editionID: editionID).last?.cardIDs.last
        let tailSource = try tailID.flatMap { try store.card(id: $0)?.sourceID }
        for (target, source) in zip(f.targets.prefix(2), f.sources.prefix(2)) where source != tailSource {
            return (target.id, source)
        }
        return (f.targets[0].id, f.sources[0])
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
    nonisolated private static func admitLateLocal(_ database: RuntimeDatabase, target: AcquisitionTargetID,
        source: SourceID) throws -> OriginRevisionID {
        let observation = AcquisitionObservation(
            objectIdentity: .init(connectorKind: .syndication, namespace: "late", value: UUID().uuidString, role: .object),
            versionIdentity: nil, precedence: .makeCurrent, availability: .available, headline: "late", summary: nil,
            bodyText: nil, authoredAt: nil, modifiedAt: nil, observedAt: Date(timeIntervalSince1970: 200),
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil,
            memberships: [.init(sourceID: source, kind: .direct)], mediaCandidates: [])!
        let record = try XCTUnwrap(AcquisitionTargetAuthority(database: database).target(id: target))
        _ = try AdmissionPolicy(database: database).admit(.init(targetID: target, targetGeneration: record.generation,
            expectedCheckpointRevision: record.checkpointRevision, observations: [observation], nextCheckpoint: nil)!)
        let records = try ContentStore(database: database).candidateWindow(sourceID: nil, after: nil,
            examinedCapacity: 100).records
        return try XCTUnwrap(records.first { $0.headline == "late" }?.originRevisionID)
    }

    private func driver(_ f: Fixture, readiness: MediaReadiness? = nil,
        selectedSourceCoverage: Bool = true,
        onDiscoveryPage: (@Sendable ([LegacyCatalogEntry]) async -> Void)? = nil,
        makeMediaOpportunity: (@Sendable () async -> MediaPreparationOpportunity)? = nil)
        throws -> (FeedRunwayDriver, RunwayController) {
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 4, replenishmentSampleLimit: 4)!)
        return (try FeedRunwayDriver(session: f.session, runway: runway, plan: f.plan, policy: f.policy,
            acquisition: f.snapshot, coordinator: f.coordinator, monotonicNow: { .init(seconds: ProcessInfo.processInfo.systemUptime)! },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 203))! },
            prepare: Self.prepare,
            selectedSourceCoverage: selectedSourceCoverage
                ? .init(selectedSourceCoverageFor: f.plan.context.key, editorialRevisionID: f.plan.revision.id) : nil,
            readiness: readiness, onDiscoveryPage: onDiscoveryPage,
            makeMediaOpportunity: makeMediaOpportunity), runway)
    }

    private func waitUntil(_ seconds: Double, _ condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return await condition()
    }

    /// Starts the gated target through the coordinator, leaving it active and suspended while the driver runs.
    private func startSuspendedTarget(_ f: Fixture) -> Task<AcquisitionExecutionResult, Error> {
        let bounds = AcquisitionWorkBounds(batchCapacity: 1, observationCapacityPerBatch: 100,
            byteCapacityPerBatch: 100_000)!
        return Task { try await f.coordinator.execute(.start(target: f.targets[2], bounds: bounds)) }
    }

    /// Codex P1: with B suspended and A's late supply ready, the publication must conclude before B is released.
    /// Coverage starts B and returns; it never joins the active pull and never holds the driver's drain.
    func testP8LatePublicationConcludesWhileSelectedTargetIsSuspended() async throws {
        let entered = expectation(description: "suspended target entered")
        let gate = CoverageGate { entered.fulfill() }
        defer { gate.release() }
        let f = try fixture(gate: gate), first = try await cold(f), (driver, _) = try driver(f)
        let suspended = startSuspendedTarget(f)
        defer { _ = try? suspended }
        await XCTWaiter.fulfillment(of: [entered], timeout: 5)
        _ = try await driver.activateCurrentPresentation(resources: resources())

        let before = try PublicationStore(database: f.database).segments(editionID: first.editionID).count
        let late = try lateTargetAndSource(f, editionID: first.editionID)
        // A reader intent that asks the existing local slice for content; the late fact arrives afterwards.
        _ = try await driver.submitViewport(.init(anchor: first.window.anchor), activity: .explicitTailApproach,
            resources: resources())
        _ = try Self.admitLateLocal(f.database, target: late.0, source: late.1)
        await driver.noteLateDurableFact()
        let published = await waitUntil(5) {
            (try? PublicationStore(database: f.database).segments(editionID: first.editionID).count) ?? before > before
        }
        XCTAssertTrue(published, "late A publishes while B is still suspended")
    }

    /// Codex P1: a late callback after background cannot use the foreground resources to start new coverage.
    /// The authorized pull keeps running; the door to a new opportunity is closed until a foreground activation.
    func testP9LateCallbackAfterBackgroundDoesNotStartNewCoverage() async throws {
        let entered = expectation(description: "suspended target entered")
        let gate = CoverageGate { entered.fulfill() }
        defer { gate.release() }
        let f = try fixture(gate: gate), first = try await cold(f), (driver, _) = try driver(f)
        let suspended = startSuspendedTarget(f)
        defer { _ = try? suspended }
        await XCTWaiter.fulfillment(of: [entered], timeout: 5)
        _ = try await driver.activateCurrentPresentation(resources: resources(targetCapacity: 0))
        await driver.suspendForBackground()
        let pulls = f.journal.pulls.count
        let segments = try PublicationStore(database: f.database).segments(editionID: first.editionID).count

        _ = try Self.admitLateLocal(f.database, target: f.targets[0].id, source: f.sources[0])
        await driver.noteLateDurableFact()
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(f.journal.pulls.count, pulls, "a late callback starts no new coverage")
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: first.editionID).count,
            segments, "a late callback publishes nothing while the screen is gone")

        // Foreground registers resources again and the same durable fact publishes through the one executor.
        _ = try await driver.activateCurrentPresentation(resources: resources())
        _ = try await driver.submitViewport(.init(anchor: first.window.anchor), activity: .explicitTailApproach,
            resources: resources())
        let published = await waitUntil(5) {
            (try? PublicationStore(database: f.database).segments(editionID: first.editionID).count) ?? segments > segments
        }
        XCTAssertTrue(published, "the resumed foreground opportunity publishes the pending local fact")
    }
    /// P1: coverage never joins an execution another owner already has in flight. A direct coverage call while
    /// the target is suspended must return; joining it would block the caller for the target's transport.
    func testP10CoverageDoesNotJoinAnActiveSuspendedExecution() async throws {
        let entered = expectation(description: "suspended target entered")
        let gate = CoverageGate { entered.fulfill() }
        defer { gate.release() }
        let f = try fixture(gate: gate), _ = try await cold(f), (driver, runway) = try driver(f)
        let suspended = startSuspendedTarget(f)
        defer { _ = try? suspended }
        await XCTWaiter.fulfillment(of: [entered], timeout: 5)
        _ = try await driver.activateCurrentPresentation(resources: resources())
        let scopeValue = await f.session.currentRunwayScope(), scope = try XCTUnwrap(scopeValue)
        let cycle = RunwayAcquisitionCycle(runway: runway, coordinator: f.coordinator)
        let demand = AcquisitionDemand(selectedSourceCoverageFor: f.plan.context.key,
            editorialRevisionID: f.plan.revision.id)
        let returned = expectation(description: "coverage returns without the suspended target")
        Task {
            _ = try? await cycle.runCoverage(demand, scope: scope,
                eligibleTargets: f.snapshot.eligibleTargets(for: f.plan.context),
                resources: resources().acquisition)
            returned.fulfill()
        }
        await XCTWaiter.fulfillment(of: [returned], timeout: 2)
    }

    /// Codex P1.1: the coverage opportunity itself starts the slow target. B is suspended by coverage's own
    /// `executeConcurrently`; A's late supply must still publish before B is released.
    func testP11CoverageStartedSuspendedTargetDoesNotHoldLatePublication() async throws {
        let gate = CoverageGate {}
        defer { gate.release() }
        let readiness = MediaReadiness()
        let f = try fixture(gate: gate), first = try await cold(f)
        // The cold slice can only publish a reserve if its readiness decisions exist; the benchmark's local
        // supply is text, so every existing revision is declared text before the runway decides.
        for record in try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil,
            examinedCapacity: 100).records {
            readiness.record(record.originRevisionID, nil, textDeclared: true)
        }
        let (driver, runway) = try driver(f, readiness: readiness)
        _ = try await driver.activateCurrentPresentation(resources: resources(reserve: 1))
        let startedIDs = await driver.coverageStartedTargetIDs
        XCTAssertTrue(startedIDs.contains(f.targets[2].id),
            "selected-source coverage owns the start of the suspended target")
        let started = await waitUntil(5) { f.journal.pulls.contains(f.targets[2].id) }
        XCTAssertTrue(started, "coverage starts the selected target")
        let current = await f.session.currentPresentation()
        let before = try PublicationStore(database: f.database).segments(editionID: first.editionID).count
        let late = try lateTargetAndSource(f, editionID: first.editionID)
        let revision = try Self.admitLateLocal(f.database, target: late.0, source: late.1)
        readiness.record(revision, nil, textDeclared: true)
        await driver.noteMediaReadinessChanged()
        let forwardID = current?.window.items.dropFirst().first?.id ?? first.window.anchor.cardID
        _ = try await driver.submitViewport(.init(anchor: .init(cardID: forwardID, placement: .top)),
            activity: .forward, resources: resources(reserve: 1))
        let noticed = await waitUntil(5) {
            let snapshot = await runway.snapshot()
            if case .exact(0)? = snapshot.readyAhead?.amount { return snapshot.localSupplyExhausted == false }
            return true
        }
        XCTAssertTrue(noticed, "the runway observes the readiness transition")
        let published = await waitUntil(10) {
            (try? PublicationStore(database: f.database).segments(editionID: first.editionID).count) ?? before > before
        }
        XCTAssertTrue(published, "A publishes while the target coverage itself started is still suspended")
        let publishedCards = try PublicationStore(database: f.database).segments(editionID: first.editionID)
            .flatMap { segment in try segment.cardIDs.compactMap { try PublicationStore(database: f.database).card(id: $0) } }
        XCTAssertTrue(publishedCards.contains { $0.originRevisionID == revision },
            "the published segment carries A's late revision before B is released")
    }

    /// Codex P1.1 (second interleaving): a late fact that arrives while a **caller** execution is suspended must
    /// carry its own fresh authorization. The execution was started by a foreground opportunity, but the fact is
    /// late; publishing A cannot wait for another gesture or for B to be released.
    func testP11LateFactCoalescedIntoCallerExecutionPublishesBeforeSuspendedTargetReleases() async throws {
        let gate = CoverageGate {}
        defer { gate.release() }
        let mediaEntered = CompletionCount()
        let mediaGate = CoverageGate { if mediaEntered.value == nil { mediaEntered.set(1) } }
        defer { mediaGate.release() }
        let readiness = MediaReadiness()
        let f = try fixture(gate: gate), first = try await cold(f)
        for record in try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil,
            examinedCapacity: 100).records {
            readiness.record(record.originRevisionID, nil, textDeclared: true)
        }
        let (driver, runway) = try driver(f, readiness: readiness, selectedSourceCoverage: false,
            makeMediaOpportunity: {
            await mediaGate.wait()
            return MediaPreparationOpportunity(waitSeconds: 0, startedAt: 0, prepare: { _, _ in })
        })
        let suspended = startSuspendedTarget(f)
        defer { _ = try? suspended }
        let scopeValue = await f.session.currentRunwayScope()
        let scope = try XCTUnwrap(scopeValue)
        await runway.activate(scope)
        let prime = RunwayObservation(editionID: first.editionID,
            anchorCardID: first.window.anchor.cardID,
            sampledAt: .init(seconds: ProcessInfo.processInfo.systemUptime)!, activity: .stationary)
        try await runway.submitObservation(prime)
        try await runway.acceptMeasurement(RunwayMeasurement(observation: prime,
            readyAhead: ReadyAheadFacts(editionID: first.editionID, anchorCardID: prime.anchorCardID,
                observedTailCardID: prime.anchorCardID, amount: .exact(64)),
            advanceFromHighWater: nil))
        let before = try PublicationStore(database: f.database).segments(editionID: first.editionID).count
        let activation = Task {
            try await driver.activateCurrentPresentation(resources: resources(reserve: 1))
        }
        let reachedMedia = await waitUntil(5) { mediaEntered.value != nil }
        XCTAssertTrue(reachedMedia, "the caller execution reached its media barrier")

        let late = try lateTargetAndSource(f, editionID: first.editionID)
        let revision = try Self.admitLateLocal(f.database, target: late.0, source: late.1)
        readiness.record(revision, nil, textDeclared: true)
        // Coalesces into the caller execution already in flight; no new gesture follows.
        await driver.noteMediaReadinessChanged()
        mediaGate.release()
        _ = try await activation.value

        // No new gesture: the deferred late drive is the only opportunity after the caller releases ownership.
        let published = await waitUntil(5) {
            (try? PublicationStore(database: f.database).segments(editionID: first.editionID).count) ?? before > before
        }
        XCTAssertTrue(published,
            "the coalesced late fact publishes after the caller releases ownership, without a new gesture")
        let cards = try PublicationStore(database: f.database).segments(editionID: first.editionID)
            .flatMap { try $0.cardIDs.compactMap { try PublicationStore(database: f.database).card(id: $0) } }
        XCTAssertTrue(cards.contains { $0.originRevisionID == revision },
            "the segment carries A's late revision while the selected target is still suspended")
    }

    /// Codex P1.1 (durable path): `RunwayAcquisitionCycle` arms the fresh supply through `noteLocalSupplyChanged`
    /// and then coalesces the result through `noteLateDurableFact`. That fact must survive the caller execution too.
    func testP11DurableFactCoalescedIntoCallerExecutionPublishesWithoutNewGesture() async throws {
        let gate = CoverageGate {}
        defer { gate.release() }
        let mediaEntered = CompletionCount()
        let mediaGate = CoverageGate { if mediaEntered.value == nil { mediaEntered.set(1) } }
        defer { mediaGate.release() }
        let readiness = MediaReadiness()
        let f = try fixture(gate: gate), first = try await cold(f)
        for record in try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil,
            examinedCapacity: 100).records {
            readiness.record(record.originRevisionID, nil, textDeclared: true)
        }
        let (driver, runway) = try driver(f, readiness: readiness, selectedSourceCoverage: false,
            makeMediaOpportunity: {
            await mediaGate.wait()
            return MediaPreparationOpportunity(waitSeconds: 0, startedAt: 0, prepare: { _, _ in })
        })
        let suspended = startSuspendedTarget(f)
        defer { _ = try? suspended }
        let scopeValue = await f.session.currentRunwayScope()
        let scope = try XCTUnwrap(scopeValue)
        await runway.activate(scope)
        let prime = RunwayObservation(editionID: first.editionID,
            anchorCardID: first.window.anchor.cardID,
            sampledAt: .init(seconds: ProcessInfo.processInfo.systemUptime)!, activity: .stationary)
        try await runway.submitObservation(prime)
        try await runway.acceptMeasurement(RunwayMeasurement(observation: prime,
            readyAhead: ReadyAheadFacts(editionID: first.editionID, anchorCardID: prime.anchorCardID,
                observedTailCardID: prime.anchorCardID, amount: .exact(64)),
            advanceFromHighWater: nil))
        let before = try PublicationStore(database: f.database).segments(editionID: first.editionID).count
        let activation = Task {
            try await driver.activateCurrentPresentation(resources: resources(reserve: 1))
        }
        let reachedMedia = await waitUntil(5) { mediaEntered.value != nil }
        XCTAssertTrue(reachedMedia, "the caller execution reached its media barrier")

        let late = try lateTargetAndSource(f, editionID: first.editionID)
        let revision = try Self.admitLateLocal(f.database, target: late.0, source: late.1)
        readiness.record(revision, nil, textDeclared: true)
        // The acquisition cycle's durable path: note the local supply, then coalesce the result into the caller.
        try await runway.noteLocalSupplyChanged(scope: scope)
        await driver.noteLateDurableFact()
        mediaGate.release()
        _ = try await activation.value

        let published = await waitUntil(5) {
            (try? PublicationStore(database: f.database).segments(editionID: first.editionID).count) ?? before > before
        }
        XCTAssertTrue(published, "the durable fact publishes after the caller releases ownership")
        let cards = try PublicationStore(database: f.database).segments(editionID: first.editionID)
            .flatMap { try $0.cardIDs.compactMap { try PublicationStore(database: f.database).card(id: $0) } }
        XCTAssertTrue(cards.contains { $0.originRevisionID == revision })
    }

    /// Codex review: a coalesced caller whose media budget is still being created must not lose its page when the
    /// owner finishes first, and the late budget must not be installed into the next execution.
    func testCoalescedCallerBudgetReturningAfterOwnerDoesNotContaminateTheNextExecution() async throws {
        let f = try fixture(), first = try await cold(f)
        let mediaCalls = CompletionCount()
        let ownerGate = CoverageGate {}
        defer { ownerGate.release() }
        let refreshGate = CoverageGate {}
        defer { refreshGate.release() }
        let (driver, _) = try driver(f, selectedSourceCoverage: false,
            makeMediaOpportunity: {
                let call = mediaCalls.increment()
                if call == 1 { await ownerGate.wait() }
                else if call == 2 { await refreshGate.wait() }
                return MediaPreparationOpportunity(waitSeconds: 0, startedAt: 0, prepare: { _, _ in })
            })
        let owner = Task { try await driver.activateCurrentPresentation(resources: resources(discovery: 3)) }
        let ownerStarted = await waitUntil(5) { mediaCalls.value == 1 }
        XCTAssertTrue(ownerStarted, "the owner creates its media budget")

        let caller = Task {
            try await driver.submitViewport(.init(anchor: first.window.anchor), activity: .forward,
                resources: resources(discovery: 3))
        }
        _ = try? await caller.value
        ownerGate.release()
        let refreshStarted = await waitUntil(5) { mediaCalls.value == 2 }
        XCTAssertTrue(refreshStarted, "the coalesced caller's budget is created off the owner loop")

        // The owner finishes while that budget creation is still suspended.
        _ = try await owner.value
        // A new execution claims the same scope before the stale budget returns.
        let next = Task {
            try await driver.submitViewport(.init(anchor: first.window.anchor), activity: .forward,
                resources: resources(discovery: 3))
        }
        let nextBudget = await waitUntil(5) { (mediaCalls.value ?? 0) >= 3 }
        XCTAssertTrue(nextBudget, "the next execution creates its own budget")
        refreshGate.release()
        try? await Task.sleep(for: .milliseconds(100))
        _ = try? await next.value
        XCTAssertEqual(mediaCalls.value ?? 0, 3, "the stale budget returning late cannot replace the new one")
    }

    /// Codex P1.2: background during an executor already in flight. The executor was started by a caller, is
    /// suspended at its barrier, and must not start new coverage with the resources it captured after background.
    func testP12BackgroundDuringInFlightExecutorStartsNoNewWork() async throws {
        let entered = expectation(description: "in-flight executor reached its media barrier")
        let gate = CoverageGate { entered.fulfill() }
        defer { gate.release() }
        let f = try fixture(), first = try await cold(f)
        let (driver, _) = try driver(f, makeMediaOpportunity: {
            await gate.wait()
            return MediaPreparationOpportunity(waitSeconds: 0, startedAt: 0, prepare: { _, _ in })
        })
        let activation = Task { try await driver.activateCurrentPresentation(resources: resources()) }
        await XCTWaiter.fulfillment(of: [entered], timeout: 5)
        let pulls = f.journal.pulls.count

        // A durable fact asks the in-flight executor for another pass; background revokes the door.
        _ = try Self.admitLateLocal(f.database, target: f.targets[0].id, source: f.sources[0])
        await driver.noteLateDurableFact()
        await driver.suspendForBackground()
        gate.release()
        _ = try? await activation.value
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(f.journal.pulls.count, pulls,
            "an executor already in flight does not start new coverage after background")
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
        _ = await waitUntil(5) { f.journal.pulls.count >= 3 }
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
        _ = await waitUntil(5) { f.journal.pulls.count >= 4 }
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
        // The other context is a separate association with its own session and presentation (T2).
        let otherSession = FeedSession(publicationHistory: .init(database: f.database))
        let otherValue = try await otherSession.admitPresentation(.restore(.init(backwardCapacity: 0,
            forwardCapacity: 64, contextKey: otherContext.key)))
        let otherPresentation = try XCTUnwrap(otherValue)
        XCTAssertEqual(otherPresentation.editionID, otherEdition)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        gate.release()
        let result = try await task.value
        // The suspended coverage opportunity belongs to its own session: it neither replaces the other
        // context's presentation nor rewrites its checkpoint.
        let settled = await f.session.currentPresentation()
        XCTAssertEqual(result, settled)
        let otherSettled = await otherSession.currentPresentation()
        XCTAssertEqual(otherSettled, otherPresentation)
        XCTAssertGreaterThanOrEqual(f.journal.pulls.count, 3)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: otherEdition).count, 1)
        _ = await waitUntil(5) {
            (try? ContentStore(database: f.database).candidateWindow(sourceID: f.sources[2], after: nil,
                examinedCapacity: 100).records.count) ?? 0 >= 20
        }
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
        _ = await waitUntil(5) { f.journal.pulls.count >= 4 }
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
        _ = await waitUntil(5) { f.journal.pulls.count >= 3 }
        XCTAssertEqual(f.journal.pulls.count, 3)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: first.editionID), history)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        _ = await waitUntil(5) {
            (try? ContentStore(database: f.database).candidateWindow(sourceID: f.sources[2], after: nil,
                examinedCapacity: 100).records.count) ?? 0 >= 20
        }
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
