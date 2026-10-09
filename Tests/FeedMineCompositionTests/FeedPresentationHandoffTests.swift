import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMineUI
import FeedMineComposition

private final class HandoffClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double = 0
    func next() -> RunwayMonotonicTime { lock.withLock { seconds += 1; return .init(seconds: seconds)! } }
}

@MainActor
final class FeedPresentationHandoffTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let session: FeedSession
        let bootstrap: ColdFeedBootstrap
        let driver: FeedRunwayDriver
        let coordinator: AcquisitionCoordinator
        let target: AcquisitionTarget
        let editionID: FeedEditionID
        let cardIDs: [PublicationCardID]
        let http: HandoffHTTPFixture
    }
    nonisolated private static func prepared(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map {
            .init(origin: .init(originRecordID: $0.originRecordID, originRevisionID: $0.originRevisionID,
                sourceID: nil, providerID: $0.providerID, sourceDisplayName: "Source", providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }
    private func fixture(history: Int = 4, registered: Bool = true, paused: Bool = false,
        error: URLError? = nil, remoteItems: Int = 2, context: FeedContext = .init(request: .main),
        structuralConnector: (any FeedConnector)? = nil,
        editionID: FeedEditionID = FeedEditionID()) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory)), version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: version, eligibilityPolicyVersion: version, scoringPolicyVersion: version,
            sequencingPolicyVersion: version, exposurePolicyVersion: version, selectionSchemaVersion: .init(rawValue: 1))
        let plan = FeedPlan(context: context, revision: revision)!
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version, sequencingPolicyVersion: version,
            exposurePolicyVersion: version, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedRevisions)
        let candidates = (0..<history).map { index in
            Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), headline: "Saved \(index)",
                summary: nil, timestamp: .init(value: Date(timeIntervalSince1970: 1), kind: .observed), language: nil, providerID: nil)
        }
        let selection = SelectionResult(editorialRevision: revision, orderedCandidates: candidates,
            supplyReport: .init(examinedCount: 0, nextCursor: nil, exhausted: true))
        let prepared = Self.prepared(selection)
        let publicationHistory = PublicationHistory(database: database)
        if history > 0 {
            _ = try PublicationCoordinator(database: database).createEdition(.init(selection: selection,
                drafts: PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs), editionID: editionID,
                publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 1),
                segmentID: FeedSegmentID(), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 2), cardIDs: prepared.cardIDs))
            try publicationHistory.saveCursor(.init(editionID: editionID, anchor: .init(cardID: prepared.cardIDs[0], placement: .top)),
                updatedAt: Date(timeIntervalSince1970: 3))
        }
        let source: SourceID
        if case .source(let id) = context.request { source = id } else { source = SourceID() }
        let target = try AcquisitionTargetAuthority(database: database).register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [source])
        let http = HandoffHTTPFixture(paused: paused, error: error, items: remoteItems)
        addTeardownBlock { http.release(); http.remove() }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [HandoffURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        addTeardownBlock { transport.invalidateAndCancel() }
        let binding = SourceBinding(id: SourceBindingID(), sourceID: source,
            externalPrincipal: .init(connectorKind: .syndication, namespace: "p", value: "source", role: .principal),
            aliases: [], generation: 1, state: .enabled)!
        let registration = SyndicationTargetRegistration(targetID: target.id, targetGeneration: target.generation,
            endpoint: http.url, bindings: [binding])!
        let acquisition = try SyndicationAcquisitionSnapshot(database: database, registrations: registered ? [registration] : [],
            session: transport, redirectCapacity: 0, now: { Date(timeIntervalSince1970: 5) })
        let coordinator: AcquisitionCoordinator
        if let structuralConnector {
            coordinator = AcquisitionCoordinator(database: database, connectorForTarget: { _ in structuralConnector })
        } else { coordinator = acquisition.makeCoordinator() }
        let session = FeedSession(publicationHistory: publicationHistory), clock = HandoffClock()
        let runway = RunwayController(configuration: .init(policyInputs: .init(safetyFactor: 1, releaseMarginSeconds: 0)!,
            consumptionSampleLimit: 4, replenishmentSampleLimit: 4)!)
        let bootstrap = try ColdFeedBootstrap(session: session, plan: plan, policy: policy, acquisition: acquisition,
            coordinator: coordinator, prepare: Self.prepared)
        let driver = try FeedRunwayDriver(session: session, runway: runway, plan: plan, policy: policy,
            acquisition: acquisition, coordinator: coordinator, monotonicNow: { clock.next() },
            makeSegmentIdentity: { .init(segmentID: FeedSegmentID(), segmentSeed: 3, segmentCreatedAt: Date(timeIntervalSince1970: 6))! },
            prepare: Self.prepared)
        return .init(database: database, session: session, bootstrap: bootstrap, driver: driver, coordinator: coordinator,
            target: target, editionID: editionID, cardIDs: prepared.cardIDs, http: http)
    }
    private func resources(targets: Int = 1) -> FeedRunwayDriverResources {
        .init(runway: .init(localWorkAllowed: true, examinedCandidateCapacity: 8, readyProbeBound: 8,
            readyProbeCeiling: 64, forwardAdvanceProbeBound: 64)!,
            acquisition: .init(targetWorkCapacity: targets, batchCapacityPerNewExecution: 1,
                observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)
    }
    private func identity() -> ColdFeedPublicationIdentity {
        .init(editionID: FeedEditionID(), publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1,
            editionCreatedAt: Date(timeIntervalSince1970: 10), segmentID: FeedSegmentID(), segmentSeed: 2,
            segmentCreatedAt: Date(timeIntervalSince1970: 11), anchorPlacement: .center, checkpointedAt: Date(timeIntervalSince1970: 12))!
    }
    private func cold(_ fixture: Fixture, targets: Int = 1, local: Int = 8) async throws -> ColdFeedBootstrapOutcome {
        try await fixture.bootstrap.run(identity: identity(), resources: .init(localExaminedCapacity: local, acquisition: resources(targets: targets).acquisition)!,
            backwardCapacity: 0, forwardCapacity: 3)
    }
    private func warm(_ fixture: Fixture) async throws -> FeedPresentationState {
        let snapshot = try await fixture.driver.restoreAndActivate(backwardCapacity: 1, forwardCapacity: 1, resources: resources())
        let state = try FeedPresentationHandoff.receive(snapshot: snapshot, into: .init(presentation: nil))
        XCTAssertNotNil(state.presentation)
        return state
    }
    func testH1WarmRestoreHandoffWithoutAcquisition() async throws {
        let f = try fixture(), checkpoint = try SessionStore(database: f.database).checkpoint()
        let state = try await warm(f), current = await f.session.currentPresentation()
        XCTAssertEqual(state.presentation, current); XCTAssertEqual(state.presentation?.editionID, f.editionID)
        XCTAssertEqual(state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(2)))
        XCTAssertEqual(f.http.calls, 0); XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
    }
    func testH2RealColdPublicationHandoff() async throws {
        let f = try fixture(history: 0)
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
        let pending = FeedPresentationHandoff.report(.pending, into: .init(presentation: nil))
        let outcome = try await cold(f)
        guard case .published(let snapshot) = outcome else { return XCTFail("Expected cold publication") }
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let state = try FeedPresentationHandoff.receive(coldOutcome: outcome, into: pending)
        XCTAssertEqual(state.presentation, snapshot); XCTAssertEqual(state.work, .idle)
        let current = await f.session.currentPresentation(); XCTAssertEqual(state.presentation, current)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
    }
    func testH3PendingKeepsVisibleContentDuringRealDriverAcquisition() async throws {
        let f = try fixture(history: 1, paused: true), visible = try await warm(f)
        let pending = FeedPresentationHandoff.report(.pending, into: visible)
        let observation = ViewportObservation(anchor: try XCTUnwrap(visible.presentation).window.anchor)
        let bounds = resources(), driver = f.driver
        let task = Task { try await FeedPresentationHandoff.submitViewport(observation, activity: .explicitTailApproach,
            resources: bounds, driver: driver, into: pending) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        XCTAssertEqual(pending.presentation, visible.presentation); XCTAssertEqual(pending.work, .pending)
        let active = await f.coordinator.activeExecutions()
        XCTAssertEqual(active, [AcquisitionActiveExecution(targetID: f.target.id, generation: 1)!])
        let current = await f.session.currentPresentation(); XCTAssertEqual(current, visible.presentation)
        f.http.release()
        let updated = try await task.value
        XCTAssertEqual(updated.presentation?.editionID, f.editionID)
        XCTAssertEqual(updated.presentation?.window.anchor, observation.anchor)
        XCTAssertEqual(updated.work, .pending)
        XCTAssertEqual(updated.presentation?.window.items.count, 2)
        XCTAssertEqual(FeedPresentationHandoff.report(.idle, into: updated).work, .idle)
    }
    func testH4RealDeferredAndUnavailableKeepPresentationDistinct() async throws {
        let warmFixture = try fixture(), visible = try await warm(warmFixture)
        let unavailableFixture = try fixture(history: 0, registered: false), deferredFixture = try fixture(history: 0)
        let unavailableOutcome = try await cold(unavailableFixture), deferredOutcome = try await cold(deferredFixture, targets: 0)
        guard case .unavailable = unavailableOutcome, case .deferred(_, .resourceDenied) = deferredOutcome else {
            return XCTFail("Expected actual finite cold dispositions")
        }
        let pending = FeedPresentationHandoff.report(.pending, into: visible)
        let unavailable = try FeedPresentationHandoff.receive(coldOutcome: unavailableOutcome, into: pending)
        let deferred = try FeedPresentationHandoff.receive(coldOutcome: deferredOutcome, into: pending)
        XCTAssertEqual(unavailable.presentation, visible.presentation); XCTAssertEqual(unavailable.work, .unavailable)
        XCTAssertEqual(deferred.presentation, visible.presentation); XCTAssertEqual(deferred.work, .deferred)
        XCTAssertNotEqual(unavailable, deferred)
        XCTAssertEqual(unavailableFixture.http.calls, 0); XCTAssertEqual(deferredFixture.http.calls, 0)
    }
    func testH5OperationErrorPropagatesAndCanBeReportedWithoutLosingPresentation() async throws {
        let wrongID = AcquisitionTargetID(), connector = HandoffWrongTargetConnector(wrongID: wrongID)
        let f = try fixture(history: 1, structuralConnector: connector), visible = try await warm(f)
        let history = PublicationStore(database: f.database)
        let cardsBefore = try f.cardIDs.map { try history.card(id: $0) }
        let editionBefore = try history.edition(id: f.editionID)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        var state = FeedPresentationHandoff.report(.pending, into: visible)
        do {
            state = try await FeedPresentationHandoff.submitViewport(.init(anchor: try XCTUnwrap(visible.presentation).window.anchor),
                activity: .explicitTailApproach, resources: resources(), driver: f.driver, into: state)
            XCTFail("Expected unchanged driver error")
        } catch {
            XCTAssertEqual(error as? AcquisitionCoordinatorError, .batchTargetMismatch(expected: f.target.id, actual: wrongID))
            XCTAssertFalse(error is ConnectorOperationalFailure)
            state = FeedPresentationHandoff.report(.failed(message: "Invalid acquisition batch"), into: state)
        }
        XCTAssertEqual(state.presentation, visible.presentation); XCTAssertEqual(state.work, .failed(message: "Invalid acquisition batch"))
        let pulls = await connector.pulls; XCTAssertEqual(pulls, 1); XCTAssertEqual(f.http.calls, 0)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertEqual(try history.segments(editionID: f.editionID).count, 1)
        XCTAssertEqual(try history.edition(id: f.editionID), editionBefore)
        XCTAssertEqual(try f.cardIDs.map { try history.card(id: $0) }, cardsBefore)
        XCTAssertEqual(state.presentation?.window.anchor, visible.presentation?.window.anchor)
        XCTAssertTrue(try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 8).records.isEmpty)
    }
    func testH6ViewportForwardingUsesDriverSnapshotAndExactIdentity() async throws {
        let f = try fixture(), state = try await warm(f)
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        let updated = try await FeedPresentationHandoff.submitViewport(observation, activity: .stationary,
            resources: resources(), driver: f.driver, into: state)
        let current = await f.session.currentPresentation()
        XCTAssertEqual(updated.presentation, current)
        XCTAssertEqual(updated.presentation?.window.anchor, observation.anchor)
        XCTAssertEqual(updated.presentation?.editionID, f.editionID)
        XCTAssertEqual(updated.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(3)))
        XCTAssertEqual(f.http.calls, 0)
    }
    func testH7NoImplicitEditionOrContextSwap() async throws {
        let f = try fixture(), state = try await warm(f)
        let other = try fixture(), otherState = try await warm(other)
        XCTAssertThrowsError(try FeedPresentationHandoff.receive(snapshot: otherState.presentation, into: state)) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertThrowsError(try FeedPresentationHandoff.receive(coldOutcome: .published(XCTUnwrap(otherState.presentation)), into: state)) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        let otherContext = try fixture(context: .init(request: .source(SourceID())), editionID: f.editionID)
        let contextState = try await warm(otherContext)
        XCTAssertThrowsError(try FeedPresentationHandoff.receive(snapshot: contextState.presentation, into: state)) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(state.presentation?.editionID, f.editionID)
        XCTAssertEqual(f.http.calls, 0); XCTAssertEqual(other.http.calls, 0)
    }
    func testH8MaterializedWindowEndDoesNotDeclareGlobalExhaustion() async throws {
        let f = try fixture(), state = try await warm(f)
        let last = try XCTUnwrap(state.presentation?.window.items.last)
        let updated = try await FeedPresentationHandoff.submitViewport(.init(anchor: .init(cardID: last.id, placement: .top)),
            activity: .stationary, resources: resources(), driver: f.driver, into: state)
        XCTAssertEqual(updated.work, .idle)
        XCTAssertEqual(updated.presentation?.window.items.last?.id, f.cardIDs[2])
        XCTAssertEqual(updated.presentation?.editionID, f.editionID); XCTAssertEqual(f.http.calls, 0)
    }
    func testH9SharedCoordinatorRemainsExternallyOwnedThroughHandoff() async throws {
        let f = try fixture(history: 0, paused: true)
        let id = identity(), bounds = ColdFeedBootstrapResources(localExaminedCapacity: 8, acquisition: resources().acquisition)!
        let bootstrap = f.bootstrap
        let task = Task { try await bootstrap.run(identity: id, resources: bounds, backwardCapacity: 0, forwardCapacity: 2) }
        defer { f.http.release() }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let active = await f.coordinator.activeExecutions()
        XCTAssertEqual(active, [AcquisitionActiveExecution(targetID: f.target.id, generation: 1)!])
        f.http.release()
        let outcome = try await task.value
        let first = try FeedPresentationHandoff.receive(coldOutcome: outcome, into: .init(presentation: nil))
        let restored = try await f.driver.restoreAndActivate(backwardCapacity: 0, forwardCapacity: 2, resources: resources())
        let continuous = try FeedPresentationHandoff.receive(snapshot: restored, into: first)
        XCTAssertEqual(continuous.presentation?.editionID, id.editionID)
        XCTAssertEqual(first.presentation, continuous.presentation); XCTAssertEqual(f.http.calls, 1)
        let settled = await f.coordinator.activeExecutions(); XCTAssertTrue(settled.isEmpty)
    }
    func testH10SnapshotHandoffAndViewportDoNotWriteAnotherCheckpoint() async throws {
        let f = try fixture(), checkpoint = try SessionStore(database: f.database).checkpoint()
        let state = try await warm(f)
        let same = try FeedPresentationHandoff.receive(snapshot: state.presentation, into: state)
        let updated = try await FeedPresentationHandoff.submitViewport(.init(anchor: .init(cardID: f.cardIDs[1], placement: .center)),
            activity: .stationary, resources: resources(), driver: f.driver, into: same)
        XCTAssertNotEqual(updated.presentation?.window.anchor.cardID, checkpoint?.cardID)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID).count, 1)
    }
    func testH11PureReceivingAndReportingStartNoHiddenWork() async throws {
        let f = try fixture(), visible = try await warm(f)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let segments = try PublicationStore(database: f.database).segments(editionID: f.editionID)
        let pending = FeedPresentationHandoff.report(.pending, into: visible)
        let received = try FeedPresentationHandoff.receive(snapshot: visible.presentation, into: pending)
        let unchanged = try FeedPresentationHandoff.receive(snapshot: nil, into: received)
        XCTAssertEqual(unchanged, pending)
        let idle = FeedPresentationHandoff.receive(acquisitionOutcome: .executed([]), into: unchanged)
        XCTAssertEqual(idle.presentation, visible.presentation); XCTAssertEqual(idle.work, .idle)
        XCTAssertEqual(f.http.calls, 0)
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID), segments)
        let active = await f.coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
    }
    func testAcquisitionSettlementWithoutPublicationDoesNotCreateVisualSuccess() async throws {
        let f = try fixture(history: 0)
        let result = try await f.coordinator.execute(.start(target: f.target,
            bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!))
        XCTAssertTrue(result.selectableSupplyChanged)
        let pending = FeedPresentationHandoff.report(.pending, into: .init(presentation: nil))
        let settled = FeedPresentationHandoff.receive(acquisitionOutcome: .executed([result]), into: pending)
        XCTAssertNil(settled.presentation); XCTAssertEqual(settled.work, .idle)
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
        let unavailable = FeedPresentationHandoff.receive(acquisitionOutcome: .acceptedUnavailable(.noEligibleTargets), into: settled)
        let deferred = FeedPresentationHandoff.receive(acquisitionOutcome: .deferred(.resourceDenied), into: settled)
        XCTAssertEqual(unavailable.work, .unavailable); XCTAssertEqual(deferred.work, .deferred)
        XCTAssertNil(unavailable.presentation); XCTAssertNil(deferred.presentation)
    }
    func testRealColdNoPublicationAfterAcquisitionPreservesVisiblePresentation() async throws {
        let f = try fixture(), visible = try await warm(f), coldFixture = try fixture(history: 0, remoteItems: 0)
        let outcome = try await cold(coldFixture)
        guard case .noPublicationAfterAcquisition = outcome else { return XCTFail("Expected checkpoint-only acquisition") }
        let updated = try FeedPresentationHandoff.receive(coldOutcome: outcome, into: FeedPresentationHandoff.report(.pending, into: visible))
        XCTAssertEqual(updated.presentation, visible.presentation); XCTAssertEqual(updated.work, .idle)
        XCTAssertEqual(coldFixture.http.calls, 1)
        XCTAssertNil(try SessionStore(database: coldFixture.database).checkpoint())
    }
    func testLocalWorkRemainingDoesNotMeanExhaustion() async throws {
        let f = try fixture(), state = try await warm(f)
        let coldFixture = try fixture(history: 0, context: .init(request: .source(SourceID())))
        let unrelatedSource = SourceID()
        let unrelatedTarget = try AcquisitionTargetAuthority(database: coldFixture.database).register(
            id: AcquisitionTargetID(),connectorKind: .syndication,authorizedSources: [unrelatedSource])
        let observations = (0..<3).map { index in
            AcquisitionObservation(objectIdentity: .init(connectorKind: .syndication, namespace: "local", value: "unrelated-\(index)", role: .object),
                versionIdentity: nil, precedence: .makeCurrent, availability: .available, headline: "Unrelated", summary: nil,
                bodyText: nil, authoredAt: nil, modifiedAt: nil, observedAt: Date(timeIntervalSince1970: Double(index)), language: nil,
                primaryLink: nil, searchProjection: nil, providerID: nil, memberships: [.init(sourceID: unrelatedSource, kind: .direct)], mediaCandidates: [])!
        }
        _ = try AdmissionPolicy(database: coldFixture.database).admit(.init(targetID: unrelatedTarget.id, targetGeneration: 1,
            expectedCheckpointRevision: 0, observations: observations, nextCheckpoint: nil)!)
        let outcome = try await cold(coldFixture, local: 1)
        guard case .localWorkRemaining(let progress) = outcome else { return XCTFail("Expected actual bounded local miss") }
        XCTAssertFalse(progress.exhausted); XCTAssertEqual(progress.examinedCount, 1)
        XCTAssertEqual(coldFixture.http.calls, 0)
        let updated = try FeedPresentationHandoff.receive(coldOutcome: outcome, into: FeedPresentationHandoff.report(.pending, into: state))
        XCTAssertEqual(updated.presentation, state.presentation); XCTAssertEqual(updated.work, .idle)
        let absent = try FeedPresentationHandoff.receive(coldOutcome: outcome, into: .init(presentation: nil))
        XCTAssertNil(absent.presentation); XCTAssertEqual(absent.work, .idle)
        XCTAssertEqual(f.http.calls, 0)
    }
    func testNilDriverResultDoesNotErasePresentationOrWorkFact() async throws {
        let visibleFixture = try fixture(), visible = try await warm(visibleFixture)
        let empty = try fixture(history: 0)
        let pending = FeedPresentationHandoff.report(.pending, into: visible)
        let result = try await FeedPresentationHandoff.submitViewport(.init(anchor: try XCTUnwrap(visible.presentation).window.anchor),
            activity: .stationary, resources: resources(), driver: empty.driver, into: pending)
        XCTAssertEqual(result, pending); XCTAssertEqual(empty.http.calls, 0)
    }
    func testStaticBridgeHasNoParallelAuthorityOrAutomaticExecution() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineComposition/FeedPresentationHandoff.swift"), encoding: .utf8)
        for forbidden in ["AcquisitionCoordinator", "ContentStore", "PublicationStore", "FeedEdition(", "FeedSegment(",
            "Task", "Timer", "sleep", "retry", "backoff", "cache", "checkpoint", "[PresentationCard]", "[PublicationCardID]",
            "RunwayController", "UUID(", "Date("] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        XCTAssertNil(source.range(of: #"\b(actor|var|init)\b"#, options: .regularExpression))
        XCTAssertEqual(source.components(separatedBy: "driver.submitViewport(").count - 1, 1)
    }
}

private final class HandoffHTTPFixture: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: HandoffHTTPFixture] = [:]
    let url = URL(string: "https://handoff-" + UUID().uuidString.lowercased() + ".test/feed")!
    let body: Data
    let paused: Bool
    let error: URLError?
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var count = 0
    private var pending: HandoffURLProtocol?
    private var released = false
    init(paused: Bool, error: URLError?, items: Int) {
        self.paused = paused; self.error = error
        body = Data(("<rss version=\"2.0\"><channel><title>Feed</title>" + (0..<items).map {
            "<item><guid>remote-\($0)</guid><title>Remote \($0)</title></item>"
        }.joined() + "</channel></rss>").utf8)
        (started, signal) = AsyncStream.makeStream()
        Self.registryLock.withLock { Self.registry[url.host!] = self }
    }
    static func find(_ url: URL?) -> HandoffHTTPFixture? { registryLock.withLock { registry[url?.host ?? ""] } }
    func remove() { _ = Self.registryLock.withLock { Self.registry.removeValue(forKey: url.host!) } }
    var calls: Int { lock.withLock { count } }
    func start(_ loader: HandoffURLProtocol) {
        let wait = lock.withLock { count += 1; if paused && !released { pending = loader; return true }; return false }
        signal.yield(()); if !wait { respond(loader) }
    }
    func release() {
        let loader = lock.withLock { released = true; let value = pending; pending = nil; return value }
        if let loader { respond(loader) }
    }
    private func respond(_ loader: HandoffURLProtocol) {
        if let error { loader.client?.urlProtocol(loader, didFailWithError: error); return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/rss+xml"])!
        loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
        loader.client?.urlProtocol(loader, didLoad: body)
        loader.client?.urlProtocolDidFinishLoading(loader)
    }
}
private final class HandoffURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = HandoffHTTPFixture.find(request.url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        fixture.start(self)
    }
    override func stopLoading() {}
}

private actor HandoffWrongTargetConnector: FeedConnector {
    let wrongID: AcquisitionTargetID
    private(set) var pulls = 0
    init(wrongID: AcquisitionTargetID) { self.wrongID = wrongID }
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        pulls += 1
        return .batch(.init(targetID: wrongID, targetGeneration: request.targetGeneration,
            expectedCheckpointRevision: request.checkpointRevision, observations: [],
            nextCheckpoint: .init(blob: Data([1]), serializationSchema: 1, connectorVersion: "test")!)!, transportByteCount: 1)
    }
}
