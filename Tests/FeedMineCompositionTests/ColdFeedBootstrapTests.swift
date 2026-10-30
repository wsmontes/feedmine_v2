import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineComposition
import FeedMineUI

private final class ColdJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var values: [String] { lock.withLock { entries } }
}

/// States, from the media side, every window the bootstrap asked it to prepare. `MediaPreparationOpportunity`
/// requests in its own task, so the test settles on this log instead of on wall-clock time.
private final class ColdMediaLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    private var revisions: [OriginRevisionID] = []
    func record(_ revisions: [OriginRevisionID]) { lock.lock(); requests += 1; self.revisions += revisions; lock.unlock() }
    var count: Int { lock.withLock { requests } }
    var requested: [OriginRevisionID] { lock.withLock { revisions } }
}

private final class ColdHTTPFixture: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: ColdHTTPFixture] = [:]
    let url = URL(string: "https://cold-" + UUID().uuidString.lowercased() + ".test/feed")!
    let body: Data
    let status: Int
    let error: URLError?
    let laterError: URLError?
    let paused: Bool
    let journal: ColdJournal
    let label: String
    let onStart: @Sendable () -> Void
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var pending: ColdURLProtocol?
    private var count = 0
    private var released = false
    init(items: Int = 1, status: Int = 200, error: URLError? = nil, laterError: URLError? = nil, paused: Bool = false,
        journal: ColdJournal = ColdJournal(), label: String = "A", onStart: @escaping @Sendable () -> Void = {}) {
        self.body = Data(("<rss version=\"2.0\"><channel><title>Feed</title>" + (0..<items).map {
            "<item><guid>\(label)-\($0)</guid><title>Remote \($0)</title></item>"
        }.joined() + "</channel></rss>").utf8)
        self.status = status; self.error = error; self.laterError = laterError; self.paused = paused
        self.journal = journal; self.label = label; self.onStart = onStart
        (started, signal) = AsyncStream.makeStream()
        Self.registryLock.withLock { Self.registry[url.host!] = self }
    }
    static func find(_ url: URL?) -> ColdHTTPFixture? { registryLock.withLock { registry[url?.host ?? ""] } }
    func remove() { _ = Self.registryLock.withLock { Self.registry.removeValue(forKey: url.host!) } }
    var calls: Int { lock.withLock { count } }
    func start(_ loader: ColdURLProtocol) {
        let wait = lock.withLock { count += 1; if paused && !released { pending = loader; return true }; return false }
        journal.append(label + " start"); onStart(); signal.yield(())
        if !wait { respond(loader) }
    }
    func release() {
        let loader = lock.withLock { released = true; let value = pending; pending = nil; return value }
        if let loader { respond(loader) }
    }
    private func respond(_ loader: ColdURLProtocol) {
        journal.append(label + " response")
        if let error = calls > 1 ? (laterError ?? error) : error { loader.client?.urlProtocol(loader, didFailWithError: error); return }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/rss+xml", "ETag": "cold-etag"])!
        loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status == 200 { loader.client?.urlProtocol(loader, didLoad: body) }
        loader.client?.urlProtocolDidFinishLoading(loader)
    }
}
private final class ColdURLProtocol: URLProtocol, @unchecked Sendable {
    // Intercept every request; an unregistered endpoint fails locally instead of reaching the internet.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = ColdHTTPFixture.find(request.url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        fixture.start(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ColdFeedBootstrapTests: XCTestCase {
    private enum Failure: Error, Equatable { case preparation }
    private struct Fixture {
        let database: RuntimeDatabase
        let plan: FeedPlan
        let policy: ResolvedSelectionPolicy
        let source: SourceID
        let target: AcquisitionTarget
        let session: FeedSession
        let acquisition: SyndicationAcquisitionSnapshot
        let coordinator: AcquisitionCoordinator
        let http: ColdHTTPFixture
        let journal: ColdJournal
    }
    private func transport() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ColdURLProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel() }
        return session
    }
    private func registration(_ target: AcquisitionTarget, source: SourceID, http: ColdHTTPFixture) -> SyndicationTargetRegistration {
        let binding = SourceBinding(id: SourceBindingID(), sourceID: source,
            externalPrincipal: .init(connectorKind: .syndication, namespace: "p", value: "principal", role: .principal),
            aliases: [], generation: 1, state: .enabled)!
        return .init(targetID: target.id, targetGeneration: target.generation, endpoint: http.url, bindings: [binding])!
    }
    private func snapshot(_ db: RuntimeDatabase, _ regs: [SyndicationTargetRegistration]) throws -> SyndicationAcquisitionSnapshot {
        try .init(database: db, registrations: regs, session: transport(), redirectCapacity: 0,
            now: { Date(timeIntervalSince1970: 50) })
    }
    private func fixture(sourceContext: Bool = false, search: Bool = false, registrations: Bool = true,
        items: Int = 1, status: Int = 200, error: URLError? = nil, laterError: URLError? = nil, paused: Bool = false,
        filter: ReaderFilter = .unrestricted) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: .init(directory: root)), source = SourceID()
        let context = FeedContext(request: search ? .search(SearchContext(query: "cold")!) : sourceContext ? .source(source) : .main,
            filter: filter)
        let v = PolicyVersion(rawValue: 1)
        let r = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = FeedPlan(context: context, revision: r)!
        let policy = ResolvedSelectionPolicy(contextKey: r.contextKey, userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: r.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedRevisions)
        let target = try AcquisitionTargetAuthority(database: db).register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [source])
        let journal = ColdJournal()
        let http = ColdHTTPFixture(items: items, status: status, error: error, laterError: laterError, paused: paused, journal: journal)
        addTeardownBlock { http.release(); http.remove() }
        let acquisition = try snapshot(db, registrations ? [registration(target, source: source, http: http)] : [])
        return .init(database: db, plan: plan, policy: policy, source: source, target: target,
            session: FeedSession(publicationHistory: .init(database: db)), acquisition: acquisition,
            coordinator: acquisition.makeCoordinator(), http: http, journal: journal)
    }
    private func planningResources(targets: Int = 1) -> AcquisitionPlanningResources {
        .init(targetWorkCapacity: targets, batchCapacityPerNewExecution: 1, observationCapacityPerBatch: 8,
            byteCapacityPerBatch: 100_000)!
    }
    private func work(_ target: AcquisitionTarget) -> AcquisitionPlannedWork {
        .start(target: target, bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)
    }
    func testClosedBootstrapCannotPublishAfterSuspendedPreparation() async throws {
        let f = try fixture(), id = identity(), bounds = resources()
        let announced = expectation(description: "Media preparation announced, bootstrap suspended")
        let suspended = expectation(description: "Media composition suspended while the run is revoked")
        let (release, signal) = AsyncStream<Void>.makeStream()
        addTeardownBlock { signal.finish() }
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            evidence: { event in
                guard case .preparingMedia = event else { return }
                announced.fulfill()
                for await _ in release { break }
            },
            makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in
                    // The same barrier the legacy closure held: the composition never completes, and the
                    // revoked bootstrap still refuses to publish what it acquired.
                    suspended.fulfill()
                    XCTAssertFalse(revisions.isEmpty)
                    for await _ in release { break }
                }
            })
        let task = Task { try await bootstrap.run(identity: id, resources: bounds, backwardCapacity: 0, forwardCapacity: 2) }
        let waited = await XCTWaiter.fulfillment(of: [announced], timeout: 5)
        XCTAssertEqual(waited, .completed)
        bootstrap.cancel()
        signal.yield(()); signal.finish()
        do { _ = try await task.value; XCTFail("Closed bootstrap published") }
        catch { XCTAssertEqual(error as? ColdFeedBootstrapError, .closed) }
        let settled = await XCTWaiter.fulfillment(of: [suspended], timeout: 5)
        XCTAssertEqual(settled, .completed)
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
        XCTAssertNil(try PublicationStore(database: f.database).edition(id: id.editionID))
        XCTAssertFalse(try ContentStore(database: f.database).candidateWindow(sourceID: f.source, after: nil, examinedCapacity: 8).records.isEmpty,
            "Closing a session retains legitimately acquired canonical supply")
    }

    func testC6RealActiveGenerationConflictAndAdmissionFence() async throws {
        let f = try fixture(paused: true), coordinator = f.coordinator, oldWork = work(f.target), id = identity()
        let execution = Task { try await coordinator.execute(oldWork) }
        var started = f.http.started.makeAsyncIterator(); _ = await started.next()
        let active = await coordinator.activeExecutions()
        XCTAssertEqual(active, [AcquisitionActiveExecution(targetID: f.target.id, generation: 1)!])
        let next = try AcquisitionTargetAuthority(database: f.database).reconfigure(id: f.target.id,
            expectedGeneration: 1, connectorKind: .syndication, checkpoint: .preserve, authorizedSources: [f.source])
        let current = try snapshot(f.database, [registration(next, source: f.source, http: f.http)])
        let eligible = try current.eligibleTargets(for: f.plan.context)
        XCTAssertEqual(eligible, [next]); XCTAssertEqual(next.generation, 2)
        let demand = BootstrapPlan(contextKey: f.plan.context.key, editorialRevisionID: f.plan.revision.id,
            exhaustedLocalSupply: .init(readyCards: 0)!, acquisitionResources: planningResources())!.demand
        let result = try AcquisitionPlanner.plan(demand: demand, eligibleTargets: eligible,
            activeExecutions: await coordinator.activeExecutions(), resources: planningResources())
        XCTAssertEqual(result, .disposition(.activeGenerationConflict))
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: current, coordinator: coordinator, prepare: { _ in
                XCTFail("Conflict must not prepare publication"); throw Failure.preparation
            })
        let outcome = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 2)
        guard case .deferred(let progress, .activeGenerationConflict) = outcome else {
            f.http.release(); _ = try? await execution.value
            return XCTFail("Expected active execution conflict from bootstrap planner")
        }
        XCTAssertTrue(progress.exhausted); XCTAssertEqual(progress.examinedCount, 0)
        let stillActive = await coordinator.activeExecutions(); XCTAssertEqual(stillActive, active)
        XCTAssertEqual(f.http.calls, 1)
        try assertAbsent(f, identity: id)
        f.http.release()
        do { _ = try await execution.value; XCTFail("Old-generation admission must be fenced") }
        catch { XCTAssertEqual(error as? AcquisitionTargetStoreError, .staleGeneration(expected: 1, actual: 2)) }
        XCTAssertTrue(try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 8).records.isEmpty)
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
        XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id: next.id), next)
        let settled = await coordinator.activeExecutions(); XCTAssertTrue(settled.isEmpty)
    }
    private func identity(edition: FeedEditionID = FeedEditionID(), segment: FeedSegmentID = FeedSegmentID(),
        editionTime: Double = 10, segmentTime: Double = 11, checkpointTime: Double = 12) -> ColdFeedPublicationIdentity {
        .init(editionID: edition, publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 73,
            editionCreatedAt: Date(timeIntervalSince1970: editionTime), segmentID: segment, segmentSeed: 89,
            segmentCreatedAt: Date(timeIntervalSince1970: segmentTime), anchorPlacement: .center,
            checkpointedAt: Date(timeIntervalSince1970: checkpointTime))!
    }
    private func resources(local: Int = 8, targets: Int = 1) -> ColdFeedBootstrapResources {
        .init(localExaminedCapacity: local, acquisition: planningResources(targets: targets))!
    }
    /// The opportunity's request is fire-and-forget by design. The log is the state signal: waiting for the
    /// expected number of windows keeps the assertions deterministic without a barrier inside production.
    private func settleMedia(_ media: ColdMediaLog, after requests: Int,
        file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200_000 {
            if media.count >= requests { return }
            await Task.yield()
        }
        XCTFail("media preparation was not requested \(requests) times", file: file, line: line)
    }
    nonisolated private static func prepared(_ selection: SelectionResult, ids: [PublicationCardID]? = nil) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map {
            .init(origin: .init(originRecordID: $0.originRecordID, originRevisionID: $0.originRevisionID,
                sourceID: $0.sourceIDs.first, providerID: $0.providerID, sourceDisplayName: "Cold source", providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }, cardIDs: ids ?? selection.orderedCandidates.map { _ in PublicationCardID() })
    }
    private func owner(_ f: Fixture, acquisition: SyndicationAcquisitionSnapshot? = nil,
        prepare: (@Sendable (SelectionResult) throws -> LocalPreparedPublication)? = nil) throws -> ColdFeedBootstrap {
        let journal = f.journal
        return try .init(session: f.session, plan: f.plan, policy: f.policy, acquisition: acquisition ?? f.acquisition,
            coordinator: f.coordinator, prepare: prepare ?? { selection in
                journal.append("prepare"); return Self.prepared(selection)
            })
    }
    private func run(_ f: Fixture, identity: ColdFeedPublicationIdentity, local: Int = 8, targets: Int = 1,
        forward: Int = 8) async throws -> ColdFeedBootstrapOutcome {
        try await owner(f).run(identity: identity, resources: resources(local: local, targets: targets),
            backwardCapacity: 0, forwardCapacity: forward)
    }
    nonisolated private static func seed(_ db: RuntimeDatabase, source: SourceID, count: Int = 1, time: Double = 100,
        language: String? = nil) throws {
        for n in 0..<count {
            let record = OriginRecordID(), revision = OriginRevision(id: OriginRevisionID(), originRecordID: record,
                externalVersionIdentity: nil, headline: "Local \(n)", summary: nil, bodyText: nil, authoredAt: nil,
                modifiedAt: nil, observedAt: Date(timeIntervalSince1970: time + Double(n)), language: language,
                primaryLink: nil, searchProjection: nil, providerID: nil)
            try ContentStore(database: db).commitCanonicalChange(.init(recordID: record,
                externalObjectIdentity: .init(connectorKind: .syndication, namespace: "local", value: record.rawValue.uuidString, role: .object),
                revision: revision, mediaCandidates: [], availability: .available, observedAt: revision.observedAt,
                expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: revision.observedAt)]))
        }
    }
    private func canonical(_ f: Fixture) throws -> [ContentStore.CandidateRecord] {
        try ContentStore(database: f.database).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 100).records
    }
    private func assertAbsent(_ f: Fixture, identity: ColdFeedPublicationIdentity) throws {
        XCTAssertNil(try PublicationStore(database: f.database).edition(id: identity.editionID))
        XCTAssertThrowsError(try PublicationStore(database: f.database).segments(editionID: identity.editionID)) {
            XCTAssertEqual($0 as? PublicationStoreError, .missingEdition)
        }
        XCTAssertNil(try SessionStore(database: f.database).checkpoint())
    }
    private func published(_ outcome: ColdFeedBootstrapOutcome) throws -> FeedPresentationSnapshot {
        guard case .published(let snapshot) = outcome else { throw Failure.preparation }
        return snapshot
    }
    private func assertPublished(_ f: Fixture, identity: ColdFeedPublicationIdentity,
        snapshot: FeedPresentationSnapshot) async throws {
        let installed = await f.session.currentPresentation(); XCTAssertEqual(installed, snapshot)
        XCTAssertEqual(snapshot.editionID, identity.editionID)
        let store = PublicationStore(database: f.database)
        let edition = try XCTUnwrap(store.edition(id: identity.editionID))
        let segments = try store.segments(editionID: identity.editionID)
        XCTAssertEqual(edition.selectionSeed, identity.selectionSeed)
        XCTAssertEqual(edition.publicationSchemaVersion, identity.publicationSchemaVersion.rawValue)
        XCTAssertEqual(edition.createdAt, identity.editionCreatedAt)
        XCTAssertEqual(edition.editorialRevision, f.plan.revision)
        XCTAssertEqual(segments.count, 1)
        let segment = try XCTUnwrap(segments.first)
        XCTAssertEqual(segment.id, identity.segmentID); XCTAssertEqual(segment.ordinal, 0)
        XCTAssertEqual(segment.segmentSeed, identity.segmentSeed); XCTAssertEqual(segment.createdAt, identity.segmentCreatedAt)
        let checkpoint = try XCTUnwrap(SessionStore(database: f.database).checkpoint())
        XCTAssertEqual(checkpoint.editionID, identity.editionID)
        XCTAssertEqual(checkpoint.cardID, segment.cardIDs.first)
        XCTAssertEqual(checkpoint.anchorPlacement, identity.anchorPlacement.rawValue)
        XCTAssertEqual(checkpoint.updatedAt, identity.checkpointedAt)
        XCTAssertEqual(snapshot.window.anchor.cardID, checkpoint.cardID)
    }
    func testC1ExistingLocalSupplyPublishesWithZeroHTTP() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source)
        let snapshot = try published(await run(f, identity: id))
        XCTAssertEqual(f.http.calls, 0)
        try await assertPublished(f, identity: id, snapshot: snapshot)
    }
    func testC2FullColdRemotePathOnlyBootstrapRun() async throws {
        let f = try fixture(), id = identity()
        XCTAssertTrue(try canonical(f).isEmpty)
        // This invocation alone owns the local/planner/connector/admission/publication/restore chain.
        let snapshot = try published(await run(f, identity: id))
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(try canonical(f).count, 1)
        XCTAssertEqual(f.journal.values, ["A start", "A response", "prepare"])
        let origin = try XCTUnwrap(canonical(f).first)
        XCTAssertEqual(try ContentStore(database: f.database).memberships(originRecordID: origin.originRecordID).map(\.sourceID), [f.source])
        try await assertPublished(f, identity: id, snapshot: snapshot)
    }

    /// The head-keeping rule has to survive the publication that matters: with nothing to publish locally the
    /// first attempt returns `.notYet`, so the installed presentation comes from the retry after acquisition.
    /// That retry used to omit `keepsAdmittedHead`, and the default `false` silently installed a list bounded
    /// around the reader — the owner's decision was defeated on every cold launch that needed a fetch
    /// (2026-10-14: the admitted head walked from the Edition's first card to the reader's own, and the card a
    /// reader had passed left the drawn list).
    func testRetryAfterAcquisitionKeepsTheAdmittedHead() async throws {
        let f = try fixture(items: 30), id = identity()
        let outcome = try await owner(f).run(identity: id, resources: resources(local: 30, targets: 1),
            backwardCapacity: 0, forwardCapacity: 4, keepsAdmittedHead: true)
        let installed = try published(outcome)
        let head = try XCTUnwrap(installed.window.items.first?.id)
        XCTAssertEqual(f.http.calls, 1, "the retry after acquisition is the path that installs")
        let reader = try XCTUnwrap(installed.window.items.last)
        let anchor = ViewportObservation(anchor: .init(cardID: reader.id, placement: .top))
        _ = try await f.session.submitViewport(anchor)
        let after = try await f.session.admitPresentation(.forwardScroll(anchor))
        let moved = try XCTUnwrap(after)
        XCTAssertGreaterThan(moved.window.items.count, installed.window.items.count,
            "the move must extend the window, or the head assertion below is vacuous")
        XCTAssertEqual(moved.window.items.first?.id, head,
            "a presentation installed with keepsAdmittedHead keeps every card above the reader")
        XCTAssertGreaterThanOrEqual(moved.window.items.count, installed.window.items.count)
    }
    func testC3NonexhaustedLocalMissForbidsHTTPAndEligibility() async throws {
        let f = try fixture(sourceContext: true, filter: ReaderFilter(languages: ["en"])), id = identity()
        // Supply belongs to the selected source, but the reader's filter excludes it:
        // the local walk has real work and must not fetch yet.
        try Self.seed(f.database, source: f.source, count: 1, language: "pt-BR")
        // Materialize valid configuration, then explicitly advance authority so lookup would throw.
        let invalid = f.acquisition
        _ = try AcquisitionTargetAuthority(database: f.database).reconfigure(id: f.target.id,
            expectedGeneration: 1,connectorKind: .syndication,checkpoint: .preserve,authorizedSources: [f.source])
        XCTAssertThrowsError(try invalid.eligibleTargets(for: f.plan.context))
        let outcome = try await owner(f, acquisition: invalid).run(identity: id, resources: resources(local: 1),
            backwardCapacity: 0, forwardCapacity: 1)
        guard case .localWorkRemaining(let progress) = outcome else { return XCTFail("Expected bounded local work remaining") }
        XCTAssertFalse(progress.exhausted); XCTAssertEqual(progress.examinedCount, 1); XCTAssertNotNil(progress.nextCursor)
        XCTAssertEqual(f.http.calls, 0); XCTAssertTrue(f.journal.values.isEmpty)
        try assertAbsent(f, identity: id)
    }

    /// The preserved real-container failure, in both meaningful global orderings: the
    /// selected source owns no initial supply, so acquisition must run; after the fetch,
    /// the first-publication window must select the source's new item even when unrelated
    /// global rows are newer (time 100) or older (time 1) than the remote observation (50).
    /// The published card must carry the selected source identity, not just a count.
    func testSourceContextPublishesAfterAcquisitionWithUnrelatedSupplyNewerOrOlder() async throws {
        for unrelatedTime in [1.0, 100.0] {
            let f = try fixture(sourceContext: true), id = identity()
            try Self.seed(f.database, source: SourceID(), count: 3, time: unrelatedTime)
            let outcome = try await run(f, identity: id, local: 1)
            guard case .published(let snapshot) = outcome else {
                return XCTFail("unrelatedTime \(unrelatedTime): expected publication, got \(outcome)")
            }
            XCTAssertEqual(f.http.calls, 1, "unrelatedTime \(unrelatedTime)")
            XCTAssertEqual(f.journal.values.filter { $0 == "prepare" }.count, 1)
            XCTAssertEqual(snapshot.window.items.count, 1)
            XCTAssertEqual(snapshot.window.items.first?.sourceID, f.source,
                "unrelatedTime \(unrelatedTime): the published card must belong to the selected source")
            try await assertPublished(f, identity: id, snapshot: snapshot)
        }
    }
    func testC4EmptyAndNoEligibleTargetIsUnavailable() async throws {
        let f = try fixture(registrations: false), id = identity()
        guard case .unavailable(let progress) = try await run(f, identity: id) else { return XCTFail("Expected unavailable") }
        XCTAssertTrue(progress.exhausted); XCTAssertEqual(progress.examinedCount, 0)
        XCTAssertEqual(f.http.calls, 0); try assertAbsent(f, identity: id)
    }
    func testC5ResourceDeniedDefersWithoutHTTP() async throws {
        let f = try fixture(), id = identity()
        guard case .deferred(let progress, .resourceDenied) = try await run(f, identity: id, targets: 0) else {
            return XCTFail("Expected resource denial")
        }
        XCTAssertTrue(progress.exhausted); XCTAssertEqual(f.http.calls, 0); try assertAbsent(f, identity: id)
    }
    private func conditionalTarget(_ f: Fixture) throws {
        _ = try AcquisitionTargetAuthority(database: f.database).compareAndSwapCheckpoint(id: f.target.id,
            expectedGeneration: 1, expectedCheckpointRevision: 0,
            next: AcquisitionCheckpoint(blob: Data(#"{"etag":"cold-etag","nextItemIndex":0}"#.utf8),
                serializationSchema: 1, connectorVersion: "feedmine-syndication/1-feedkit/10.9.4")!)
    }
    private func noChangeProof(status: Int, items: Int) async throws {
        let f = try fixture(), id = identity(), db = f.database, source = f.source
        if status == 304 { try conditionalTarget(f) }
        // Supply appears independently during transport. A forbidden second local attempt would prepare it.
        let http = ColdHTTPFixture(items: items, status: status, journal: f.journal, onStart: {
            do { try Self.seed(db, source: source) } catch { XCTFail("Seed failed: \(error)") }
        })
        addTeardownBlock { http.remove() }
        let current = try XCTUnwrap(AcquisitionTargetAuthority(database: db).target(id: f.target.id))
        let acquisition = try snapshot(db, [registration(current, source: source, http: http)])
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: acquisition.makeCoordinator(), prepare: { selection in
                f.journal.append("prepare"); return Self.prepared(selection)
            }, onDurableSupply: { f.journal.append("supply") })
        let outcome = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 8)
        guard case .noPublicationAfterAcquisition(let progress, let results) = outcome else { return XCTFail("Expected no publication") }
        XCTAssertTrue(progress.exhausted); XCTAssertEqual(progress.examinedCount, 0)
        XCTAssertEqual(results.map(\.targetID), [f.target.id]); XCTAssertFalse(results[0].selectableSupplyChanged)
        XCTAssertFalse(f.journal.values.contains("supply"),
            "uma resposta igual (304/checkpoint sem novidade) não é fato de suprimento: nada é declarado ao dono do trabalho local")
        if status == 304 { XCTAssertEqual(results[0].stop, .upToDate); XCTAssertTrue(results[0].receipts.isEmpty) }
        else { XCTAssertEqual(results[0].receipts.count, 1); XCTAssertEqual(try AcquisitionTargetAuthority(database: db).target(id: f.target.id)?.checkpointRevision, 1) }
        XCTAssertEqual(http.calls, 1); XCTAssertFalse(f.journal.values.contains("prepare"))
        XCTAssertEqual(try canonical(f).count, 1); try assertAbsent(f, identity: id)
    }
    func testC7UpToDateDoesNotRunSecondLocalAttempt() async throws { try await noChangeProof(status: 304, items: 0) }
    func testC8CheckpointOnlyDoesNotRunSecondLocalAttempt() async throws { try await noChangeProof(status: 200, items: 0) }
    /// P0 (fiação): o resultado durável de uma fonte que responde **depois** da primeira Edição tem de entregar o
    /// fato ao dono que decide o trabalho local. O gate é o evento positivo de ingestão
    /// (`selectableSupplyChanged`), nunca a publicação: `first.snapshot == nil` é condição de este run publicar, não
    /// de o suprimento existir, e usá-la como gate deixava o suprimento tardio sem consumidor.
    func testDurableSupplyIsDeclaredForAnIngestionThatArrivesAfterTheFirstEdition() async throws {
        let f = try fixture(), id = identity(), db = f.database
        let b = ColdHTTPFixture(items: 2, paused: true, label: "B")
        addTeardownBlock { b.remove() }
        let authority = AcquisitionTargetAuthority(database: db)
        let targetB = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication,
            authorizedSources: [f.source])
        let acquisition = try snapshot(db, [registration(f.target, source: f.source, http: f.http),
            registration(targetB, source: f.source, http: b)])
        let facts = ColdJournal()
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: acquisition.makeCoordinator(),
            prepare: { selection in Self.prepared(selection) },
            onDurableSupply: { facts.append("supply") })
        let running = Task {
            try await bootstrap.run(identity: id, resources: resources(targets: 2),
                backwardCapacity: 0, forwardCapacity: 8)
        }
        let deadline = Date().addingTimeInterval(5)
        while (try? PublicationStore(database: db).edition(id: id.editionID)) == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(try PublicationStore(database: db).edition(id: id.editionID),
            "premissa: a fonte rápida publica com a lenta suspensa")
        XCTAssertEqual(facts.values.count, 1, "a ingestão da fonte rápida declara o próprio fato")
        XCTAssertEqual(b.calls, 1, "premissa: a fonte lenta foi consultada e está pendente")
        b.release()
        let outcome = try await running.value
        guard case .published = outcome else { return XCTFail("expected the fast publication") }
        XCTAssertEqual(facts.values.count, 2,
            "a ingestão que chega depois da primeira Edição também se declara — é o suprimento que a fatia local "
                + "consumirá na próxima chamada, e sem esta declaração ele ficava sem consumidor")
        XCTAssertEqual(try PublicationStore(database: db).segments(editionID: id.editionID).count, 1,
            "declarar o fato não publica: a Edição não cresce por esta chegada")
    }
    func testC9SupplyChangeRunsOneSecondLocalAttemptFromCanonicalHead() async throws {
        let f = try fixture(sourceContext: true), id = identity()
        // First capacity-two window contains one unrelated record and is exhausted. Remote observation is newer than its cursor.
        try Self.seed(f.database, source: SourceID(), time: 1)
        let result = try await run(f, identity: id, local: 2)
        let snapshot = try published(result)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.journal.values.filter { $0 == "prepare" }.count, 1)
        XCTAssertEqual(snapshot.window.items.count, 1)
        try await assertPublished(f, identity: id, snapshot: snapshot)
    }
    func testC10ExactIdentityAndCardIDsSurviveRemoteGap() async throws {
        let f = try fixture(items: 2), id = identity(), cards = [PublicationCardID(), PublicationCardID()]
        let bootstrap = try owner(f, prepare: { Self.prepared($0, ids: cards) })
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 1, forwardCapacity: 8))
        try await assertPublished(f, identity: id, snapshot: snapshot)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: id.editionID).first?.cardIDs, cards)
    }
    /// The cold bootstrap states the same cap: the first publication carries at most the reserve target, the rest
    /// stays in canonical supply, and the edition is not grown by a burst.
    func testPublicationCapLimitsTheFirstPublicationAtTheCompositionBoundary() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source, count: 40, time: 100)
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            publicationLimit: 16)
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(local: 40),
            backwardCapacity: 0, forwardCapacity: 16))
        XCTAssertEqual(snapshot.window.items.count, 16)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: id.editionID)
            .flatMap(\.cardIDs).count, 16)
        XCTAssertEqual(try canonical(f).count, 40, "the deferred stories stay in canonical supply")
        XCTAssertEqual(f.http.calls, 0, "local supply publishes before any fetch")
    }
    func testC11AcquisitionFailureSettlesOnce() async throws {
        let failure = URLError(.cannotConnectToHost), f = try fixture(error: failure), id = identity()
        guard case .noPublicationAfterAcquisition(_, let results) = try await run(f, identity: id) else {
            return XCTFail("Expected settled transport failure without publication")
        }
        XCTAssertEqual(results.count, 1); XCTAssertEqual(results[0].stop, .operationalFailure(.transport))
        XCTAssertTrue(results[0].receipts.isEmpty)
        XCTAssertEqual(f.http.calls, 1); XCTAssertTrue(try canonical(f).isEmpty); try assertAbsent(f, identity: id)
    }
    func testC12EarlierAdmissionPublishesDespiteLaterTargetFailure() async throws {
        let f = try fixture(), id = identity(), failure = URLError(.cannotFindHost)
        let b = ColdHTTPFixture(error: failure, journal: f.journal, label: "B")
        addTeardownBlock { b.remove() }
        let targetB = try AcquisitionTargetAuthority(database: f.database).register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [f.source])
        let acquisition = try snapshot(f.database, [registration(f.target, source: f.source, http: f.http), registration(targetB, source: f.source, http: b)])
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: acquisition.makeCoordinator(), prepare: { Self.prepared($0) })
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(targets: 2), backwardCapacity: 0, forwardCapacity: 2))
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(b.calls, 1); XCTAssertEqual(try canonical(f).count, 1)
        try await assertPublished(f, identity: id, snapshot: snapshot)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(b.calls, 1)
    }
    private func preparationFailureProof() async throws {
        let f = try fixture(), id = identity(), journal = f.journal
        let bootstrap = try owner(f, prepare: { _ in journal.append("prepare failure"); throw Failure.preparation })
        do { _ = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 2); XCTFail("Expected prepare failure") }
        catch { XCTAssertEqual(error as? Failure, .preparation) }
        XCTAssertEqual(try canonical(f).count, 1); XCTAssertEqual(f.http.calls, 1)
        XCTAssertEqual(journal.values, ["A start", "A response", "prepare failure"])
        try assertAbsent(f, identity: id)
    }
    func testC13PostAcquisitionPreparationFailurePreservesSupply() async throws { try await preparationFailureProof() }
    func testC14SecondLocalFailureDoesNotAcquireAgain() async throws { try await preparationFailureProof() }
    private func installDurable(_ f: Fixture) throws -> ColdFeedPublicationIdentity {
        let id = identity()
        _ = try InitialProductionSlice(database: f.database).run(.init(plan: f.plan, policy: f.policy, examinedCapacity: 8,
            editionID: id.editionID, publicationSchemaVersion: id.publicationSchemaVersion, selectionSeed: id.selectionSeed,
            editionCreatedAt: id.editionCreatedAt, segmentID: id.segmentID, segmentSeed: id.segmentSeed,
            segmentCreatedAt: id.segmentCreatedAt, anchorPlacement: id.anchorPlacement, checkpointedAt: id.checkpointedAt), prepare: { Self.prepared($0) })
        return id
    }
    func testC15InstalledSessionRefusedBeforeAnyWork() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source)
        let existing = try installDurable(f)
        let installed = try await f.session.admitPresentation(.restore(.init(backwardCapacity: 0, forwardCapacity: 1)))
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let bootstrap = try owner(f, prepare: { _ in XCTFail("Memory precondition must precede preparation"); throw Failure.preparation })
        do { _ = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 1); XCTFail("Expected memory fence") }
        catch { XCTAssertEqual(error as? ColdFeedBootstrapError, .sessionAlreadyInstalled) }
        XCTAssertEqual(f.http.calls, 0); XCTAssertNil(try PublicationStore(database: f.database).edition(id: id.editionID))
        XCTAssertNotNil(try PublicationStore(database: f.database).edition(id: existing.editionID))
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        let after = await f.session.currentPresentation(); XCTAssertEqual(after, installed)
    }
    func testC16DurableCheckpointFencePropagatesAndRollsBack() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source); _ = try installDurable(f)
        let checkpoint = try SessionStore(database: f.database).checkpoint()
        let memory = await f.session.currentPresentation(); XCTAssertNil(memory)
        do { _ = try await run(f, identity: id); XCTFail("Expected durable fence") }
        catch { XCTAssertEqual(error as? SessionStoreError, .checkpointAlreadyExists) }
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint(), checkpoint)
        XCTAssertNil(try PublicationStore(database: f.database).edition(id: id.editionID)); XCTAssertEqual(f.http.calls, 0)
        let after = await f.session.currentPresentation(); XCTAssertNil(after)
    }
    func testC17ExactInstalledWindowWithoutCheckpointRewrite() async throws {
        let f = try fixture(items: 4), id = identity()
        let snapshot = try published(await owner(f).run(identity: id, resources: resources(), backwardCapacity: 2, forwardCapacity: 1))
        try await assertPublished(f, identity: id, snapshot: snapshot)
        XCTAssertEqual(snapshot.window.items.count, 2); XCTAssertEqual(snapshot.window.anchor.placement, .center)
        let segment = try XCTUnwrap(PublicationStore(database: f.database).segments(editionID: id.editionID).first)
        XCTAssertEqual(snapshot.window.items.map(\.id), Array(segment.cardIDs.prefix(2)))
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: segment.cardIDs[1], placement: .top)))
        // Recording an observation moves the logical anchor; it does not rebuild the installed window.
        XCTAssertEqual(moved?.window.items.map(\.id), Array(segment.cardIDs.prefix(2)))
        XCTAssertEqual(moved?.window.anchor.cardID, segment.cardIDs[1])
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint()?.cardID, segment.cardIDs[0])
        XCTAssertEqual(try SessionStore(database: f.database).checkpoint()?.updatedAt, id.checkpointedAt)
    }
    func testC18LocalSearchDoesNotAcquire() async throws {
        let f = try fixture(search: true), id = identity()
        _ = try await run(f, identity: id)
        XCTAssertEqual(f.http.calls, 0); try assertAbsent(f, identity: id)
    }
    private func finitePlanProof() async throws {
        let f = try fixture(), id = identity(), db = f.database
        // R05 decoupled the publication callback from the network slot pump: with a sequential plan the next target
        // may start while the consumer is still publishing the previous one. What the cold path guarantees — and what
        // this proof keeps — is that the fast target's supply is durable before its own result is consumed, and that
        // the first publication carries only what the fast target brought; the slower target still contributes after.
        let b = ColdHTTPFixture(journal: f.journal, label: "B")
        addTeardownBlock { b.remove() }
        let authority = AcquisitionTargetAuthority(database: db)
        let targetB = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [f.source])
        let acquisition = try snapshot(db, [registration(f.target, source: f.source, http: f.http), registration(targetB, source: f.source, http: b)])
        let journal = f.journal
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: acquisition.makeCoordinator(), prepare: {
                journal.append("prepare"); return Self.prepared($0)
            })
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(targets: 2), backwardCapacity: 0, forwardCapacity: 8))
        let events = journal.values.filter { $0 != "prepare" }
        XCTAssertEqual(events, ["A start", "A response", "B start", "B response"],
            "o plano é sequencial: B só executa depois de A")
        XCTAssertEqual(journal.values.filter { $0 == "prepare" }.count, 1, "uma publicação inicial, e só uma")
        // The publication used the fast target's supply only, even though B had already started and its response
        // may have arrived before the consumer ran: the slower target's supply is admitted after the first card.
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(b.calls, 1); XCTAssertEqual(snapshot.window.items.count, 1)
        XCTAssertEqual(try ContentStore(database: db).candidateWindow(sourceID: nil, after: nil, examinedCapacity: 8).records.count, 2,
            "The slower target still contributes supply after first publication")
        XCTAssertEqual(try authority.target(id: f.target.id)?.checkpointRevision, 1)
        XCTAssertEqual(try authority.target(id: targetB.id)?.checkpointRevision, 1)
        try await assertPublished(f, identity: id, snapshot: snapshot)
    }
    /// R06 (cold path): the first publication follows the fast target's durable supply and does not wait for the
    /// slower one to answer. The bootstrap is still running when the edition is already durable and installed.
    func testFastSourcePublishesWhileSlowSourceIsPending() async throws {
        let f = try fixture(), id = identity(), db = f.database
        let b = ColdHTTPFixture(items: 2, paused: true, label: "B")
        addTeardownBlock { b.remove() }
        let authority = AcquisitionTargetAuthority(database: db)
        let targetB = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication,
            authorizedSources: [f.source])
        let acquisition = try snapshot(db, [registration(f.target, source: f.source, http: f.http),
            registration(targetB, source: f.source, http: b)])
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: acquisition.makeCoordinator(),
            prepare: { selection in Self.prepared(selection) })
        let running = Task {
            try await bootstrap.run(identity: id, resources: resources(targets: 2),
                backwardCapacity: 0, forwardCapacity: 8)
        }
        let deadline = Date().addingTimeInterval(5)
        while (try? PublicationStore(database: db).edition(id: id.editionID)) == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(try PublicationStore(database: db).edition(id: id.editionID),
            "a fonte rápida publica com a lenta suspensa")
        XCTAssertEqual(b.calls, 1, "a fonte lenta foi consultada e está pendente")
        b.release()
        let outcome = try await running.value
        guard case .published = outcome else { return XCTFail("expected the fast publication") }
    }
    func testC19FinitePlanSequentialOrderAndSettlement() async throws { try await finitePlanProof() }
    func testC20FinitePlanOnlyOnceWithoutReplanning() async throws { try await finitePlanProof() }
    func testC21ResourcesHaveOnlyExplicitMechanicalBounds() {
        let value = resources(local: 3, targets: 2)
        XCTAssertEqual(value.localExaminedCapacity, 3); XCTAssertEqual(value.acquisition, planningResources(targets: 2))
        XCTAssertEqual(Set(Mirror(reflecting: value).children.compactMap(\.label)), ["localExaminedCapacity", "acquisition", "localWindowCapacity"])
        XCTAssertNil(ColdFeedBootstrapResources(localExaminedCapacity: 0, acquisition: planningResources()))
        XCTAssertNil(ColdFeedBootstrapResources(localExaminedCapacity: -1, acquisition: planningResources()))
        XCTAssertNil(ColdFeedBootstrapResources(localExaminedCapacity: 1, acquisition: planningResources(), localWindowCapacity: 0))
    }
    func testC22ColdSuccessStopsAtInstalledPresentation() async throws {
        let f = try fixture(), id = identity()
        let snapshot = try published(await run(f, identity: id))
        let installed = await f.session.currentPresentation(); XCTAssertEqual(installed, snapshot)
        XCTAssertEqual(f.http.calls, 1)
        do { _ = try await run(f, identity: identity()); XCTFail("Second call must refuse installed presentation") }
        catch { XCTAssertEqual(error as? ColdFeedBootstrapError, .sessionAlreadyInstalled) }
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(f.journal.values.filter { $0 == "prepare" }.count, 1)
    }
    func testSecondNonexhaustedMissStopsWithSecondProgressAndOrderedResults() async throws {
        let f = try fixture(sourceContext: true, filter: ReaderFilter(languages: ["en"])), id = identity(), db = f.database
        let http = ColdHTTPFixture(onStart: {
            do { try Self.seed(db, source: f.source, count: 2, time: 100, language: "pt-BR") }
            catch { XCTFail("Seed failed: \(error)") }
        })
        addTeardownBlock { http.remove() }
        let acquisition = try snapshot(db, [registration(f.target, source: f.source, http: http)])
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: acquisition.makeCoordinator(), prepare: { _ in
                XCTFail("Second bounded window contains no matching source"); throw Failure.preparation
            })
        let outcome = try await bootstrap.run(identity: id, resources: resources(local: 1), backwardCapacity: 0, forwardCapacity: 1)
        guard case .noPublicationAfterAcquisition(let progress, let results) = outcome else {
            return XCTFail("Expected second-attempt progress without further work, got \(outcome)")
        }
        XCTAssertEqual(progress.examinedCount, 1); XCTAssertFalse(progress.exhausted); XCTAssertNotNil(progress.nextCursor)
        XCTAssertEqual(results.map(\.targetID), [f.target.id]); XCTAssertTrue(results[0].selectableSupplyChanged)
        XCTAssertEqual(http.calls, 1); XCTAssertEqual(try canonical(f).count, 3)
        try assertAbsent(f, identity: id)
    }
    func testColdWindowsShareOneMediaDeadlineAndTheNextOpportunityRenewsIt() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source, count: 10, time: 100)
        let journal = ColdJournal(), readiness = MediaReadiness()
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            readiness: readiness, makeMediaOpportunity: {
                journal.append("begin")
                let start = journal.values.filter { $0 == "begin" }.count == 1 ? 100.0 : 200.0
                return MediaPreparationOpportunity(waitSeconds: 4, startedAt: start) { _, deadline in
                    journal.append(String(deadline))
                }
            })
        let bounds = ColdFeedBootstrapResources(localExaminedCapacity: 1, acquisition: planningResources(), localWindowCapacity: 3)!
        guard case .localWorkRemaining = try await bootstrap.run(identity: id, resources: bounds,
            backwardCapacity: 0, forwardCapacity: 1) else { return XCTFail("Media remains pending") }
        XCTAssertEqual(journal.values, ["begin", "104.0", "104.0", "104.0"])
        guard case .localWorkRemaining = try await bootstrap.run(identity: id, resources: bounds,
            backwardCapacity: 0, forwardCapacity: 1) else { return XCTFail("Media remains pending") }
        XCTAssertEqual(journal.values, ["begin", "104.0", "104.0", "104.0", "begin", "204.0", "204.0", "204.0"])
        try assertAbsent(f, identity: id)
    }

    func testScopedPendingMediaResumesFiniteWindowsWithoutReservingPublication() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source, time: 1)
        let ready = try XCTUnwrap(canonical(f).first?.originRevisionID)
        try Self.seed(f.database, source: f.source, count: 10, time: 100)
        // Head media stays pending: only this older revision is legitimately settled. The readiness index is the
        // fact the slice judges with; the opportunity states each window's priority without gating it.
        let readiness = MediaReadiness(), media = ColdMediaLog()
        readiness.record(ready, nil, textDeclared: true)
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) }, readiness: readiness,
            makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in
                    media.record(revisions)
                }
            })
        let bounds = ColdFeedBootstrapResources(localExaminedCapacity: 1, acquisition: planningResources(), localWindowCapacity: 3)!
        var previous: CandidateSupplyCursor?
        for requested in [3, 6, 9] {
            let outcome = try await bootstrap.run(identity: id, resources: bounds, backwardCapacity: 0, forwardCapacity: 1)
            await settleMedia(media, after: requested)
            guard case .localWorkRemaining(let progress) = outcome else { return XCTFail("Pending media cannot reserve a publication") }
            XCTAssertNotEqual(progress.nextCursor, previous)
            previous = progress.nextCursor
            try assertAbsent(f, identity: id)
        }
        let snapshot = try published(await bootstrap.run(identity: id, resources: bounds, backwardCapacity: 0, forwardCapacity: 1))
        await settleMedia(media, after: 11)
        XCTAssertEqual(snapshot.window.items.compactMap(\.title), ["Local 0"])
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: id.editionID).map(\.ordinal), [0])
        XCTAssertEqual(media.count, 11, "cada janela examinada anuncia a sua prioridade antes do slice")
        XCTAssertTrue(media.requested.contains(ready), "a janela que publica pediu preparação da sua revisão")
        XCTAssertEqual(f.http.calls, 0)
    }

    func testScopedContinuationYieldsAfterFiniteWindowsAndResumesCursor() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source, time: 1)
        try Self.seed(f.database, source: SourceID(), count: 10, time: 100)
        let r = f.plan.revision
        let policy = ResolvedSelectionPolicy(contextKey: r.contextKey, userSelectionVersion: r.userSelectionVersion,
            eligibilityPolicyVersion: r.eligibilityPolicyVersion, scoringPolicyVersion: r.scoringPolicyVersion,
            sequencingPolicyVersion: r.sequencingPolicyVersion, exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion, eligibility: .selectedSources([f.source]),
            scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedRevisions)
        let media = ColdMediaLog()
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in media.record(revisions) }
            })
        let first = try await bootstrap.run(identity: id, resources: resources(local: 1),
            backwardCapacity: 0, forwardCapacity: 1)
        guard case .localWorkRemaining(let progress) = first else {
            return XCTFail("One opportunity must relinquish its finite examination budget")
        }
        XCTAssertFalse(progress.exhausted); XCTAssertNotNil(progress.nextCursor)
        try assertAbsent(f, identity: id)
        let second = try await bootstrap.run(identity: id, resources: resources(local: 1),
            backwardCapacity: 0, forwardCapacity: 1)
        XCTAssertEqual(try published(second).window.items.compactMap(\.title), ["Local 0"])
        await settleMedia(media, after: 1)
        XCTAssertEqual(media.count, 1, "só a janela com candidato da fonte selecionada anuncia prioridade")
        XCTAssertEqual(f.http.calls, 0)
    }

    func testScopedPreparationFailureRetainsResumedWindowAndPublicationIdentity() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source, time: 1)
        let ready = try XCTUnwrap(canonical(f).first?.originRevisionID)
        try Self.seed(f.database, source: f.source, time: 100)
        let readiness = MediaReadiness(), journal = ColdJournal(), media = ColdMediaLog()
        // The head's media is pending, so examination advances; the older revision is settled and is the only
        // one the selection can offer once the walk reaches it.
        readiness.record(ready, nil, textDeclared: true)
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { selection in
                XCTAssertEqual(selection.orderedCandidates.map(\.originRevisionID), [ready])
                journal.append("prepare")
                if journal.values.count == 1 { throw Failure.preparation }
                return Self.prepared(selection)
            }, readiness: readiness, makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in media.record(revisions) }
            })
        let bounds = ColdFeedBootstrapResources(localExaminedCapacity: 1,
            acquisition: planningResources(), localWindowCapacity: 1)!
        guard case .localWorkRemaining = try await bootstrap.run(identity: id, resources: bounds,
            backwardCapacity: 0, forwardCapacity: 1) else { return XCTFail("Pending head must advance examination") }
        await settleMedia(media, after: 1)
        try assertAbsent(f, identity: id)
        do {
            _ = try await bootstrap.run(identity: id, resources: bounds, backwardCapacity: 0, forwardCapacity: 1)
            XCTFail("Preparation must fail before publication")
        } catch { XCTAssertEqual(error as? Failure, .preparation) }
        await settleMedia(media, after: 2)
        try assertAbsent(f, identity: id)
        let snapshot = try published(await bootstrap.run(identity: id, resources: bounds,
            backwardCapacity: 0, forwardCapacity: 1))
        await settleMedia(media, after: 3)
        XCTAssertEqual(media.count, 3, "a janela retomada anuncia a sua prioridade em cada oportunidade")
        XCTAssertEqual(snapshot.window.items.count, 1)
        XCTAssertEqual(journal.values, ["prepare", "prepare"])
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: id.editionID).map(\.ordinal), [0])
        XCTAssertEqual(try canonical(f).count, 2)
        XCTAssertEqual(f.http.calls, 0)
    }

    func testClosedBootstrapCannotPublishAfterScopedLocalPreparation() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source)
        let readiness = MediaReadiness()
        let announced = expectation(description: "Local window preparation announced, bootstrap suspended")
        let suspended = expectation(description: "Local window media suspended while the run is revoked")
        let (release, signal) = AsyncStream<Void>.makeStream()
        addTeardownBlock { signal.finish() }
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { _ in
                XCTFail("Revoked bootstrap must not prepare publication")
                throw Failure.preparation
            }, evidence: { event in
                guard case .preparingMedia = event else { return }
                announced.fulfill()
                for await _ in release { break }
            }, readiness: readiness, makeMediaOpportunity: {
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in
                    suspended.fulfill()
                    XCTAssertEqual(revisions.count, 1)
                    for await _ in release { break }
                }
            })
        let bounds = resources()
        let task = Task { try await bootstrap.run(identity: id, resources: bounds,
            backwardCapacity: 0, forwardCapacity: 1) }
        let waited = await XCTWaiter.fulfillment(of: [announced], timeout: 5)
        XCTAssertEqual(waited, .completed)
        bootstrap.cancel()
        signal.yield(()); signal.finish()
        do { _ = try await task.value; XCTFail("Closed bootstrap published local supply") }
        catch { XCTAssertEqual(error as? ColdFeedBootstrapError, .closed) }
        let settled = await XCTWaiter.fulfillment(of: [suspended], timeout: 5)
        XCTAssertEqual(settled, .completed)
        try assertAbsent(f, identity: id)
        XCTAssertEqual(try canonical(f).count, 1)
        XCTAssertEqual(f.http.calls, 0)
    }

    func testStaticFiniteControlFlowAndModuleBoundaries() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineComposition/ColdFeedBootstrap.swift"), encoding: .utf8)
        for forbidden in ["RunwayController", "RunwayPolicy", "RunwayObservation", "RunwayAcquisitionCycle", "FeedRunwayDriver",
            "URLSession", "SyndicationConnector", "PublicationCoordinator", "PublicationStore", "SessionStore", "ContentStore", "CandidateProvider",
            "SQLite", "GRDB", "UUID()", "Date()", "Task {", "Task.detached", "TaskGroup", "Timer", "sleep", "retry", "backoff", "deadline",
            "minimumCards", "targetCards", "initialCardCount", "pageSize", "publicationGate", "bootstrapCursor", "BootstrapState", "makeCoordinator", "AcquisitionCoordinator("] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        XCTAssertNil(source.range(of: #"\b(while|repeat)\b"#, options: .regularExpression))
        // R07: the media branch no longer decides between two publication paths — the priority is requested and the
        // slice runs once on what is ready. One finite call site is strictly fewer paths than the two it replaces.
        XCTAssertEqual(source.components(separatedBy: "initialProductionSlice.run(").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "AcquisitionPlanner.plan(").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "coordinator.selectionOpportunity").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "coordinator.executeConcurrently(acquisitionPlan.work)").count - 1, 1)
        let plan = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineAcquisition/BootstrapPlan.swift"), encoding: .utf8)
        for forbidden in ["RuntimeDatabase", "AcquisitionTargetAuthority", "AcquisitionCoordinator", "FeedConnector", "Date", "Timer", "Task", "sleep", "minimumCards", "targetCards", "page", "deadline", "retry"] {
            XCTAssertFalse(plan.contains(forbidden), forbidden)
        }
    }
    func testIdentityRequiresAllThreeFiniteDates() {
        let e = FeedEditionID(), s = FeedSegmentID()
        for value in [Double.nan, .infinity, -.infinity] {
            for index in 0..<3 {
                let times = (0..<3).map { $0 == index ? Date(timeIntervalSinceReferenceDate: value) : Date(timeIntervalSince1970: 1) }
                XCTAssertNil(ColdFeedPublicationIdentity(editionID: e, publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 0,
                    editionCreatedAt: times[0], segmentID: s, segmentSeed: 0, segmentCreatedAt: times[1],
                    anchorPlacement: .top, checkpointedAt: times[2]))
            }
        }
    }
    func testPolicyContextMismatchRefusedAtConstruction() throws {
        let f = try fixture(), other = try fixture(sourceContext: true)
        XCTAssertThrowsError(try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: other.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) })) {
            XCTAssertEqual($0 as? ColdFeedBootstrapError, .policyContextMismatch)
        }
        XCTAssertEqual(f.http.calls, 0)
    }
    func testPublishedRestoreMustMatchCallerEdition() async throws {
        let f = try fixture(), other = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source); try Self.seed(other.database, source: other.source)
        _ = try installDurable(other)
        // Deliberately miscompose the session to exercise the required restore identity fence.
        let bootstrap = try ColdFeedBootstrap(session: other.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) })
        do { _ = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 2); XCTFail("Expected restore identity fence") }
        catch { XCTAssertEqual(error as? ColdFeedBootstrapError, .inconsistentPublishedRestore) }
        XCTAssertNotNil(try PublicationStore(database: f.database).edition(id: id.editionID)); XCTAssertEqual(f.http.calls, 0)
    }
}

extension ColdFeedBootstrapTests {
    /// H(a), spec "Estabilidade de coleta e UI": an empty database and the fixture transport must put at least
    /// ten cards on the first screen within three seconds. The criterion is stated on the app's own clock —
    /// `FeedLaunchWitness`, the same instrument the device journey reads — not on a test's wall clock.
    func testHFirstColdBatchReachesTenCardsWithinThreeSeconds() async throws {
        let f = try fixture(items: 12)
        FeedLaunchWitness.reset()
        FeedLaunchWitness.arm()
        let outcome = try await owner(f).run(identity: identity(),
            resources: .init(localExaminedCapacity: 32,
                acquisition: .init(targetWorkCapacity: CollectionLaunchSettings.defaultInitialParallelism,
                    batchCapacityPerNewExecution: 1, observationCapacityPerBatch: 20,
                    byteCapacityPerBatch: 100_000)!)!,
            backwardCapacity: 0, forwardCapacity: 20)
        let snapshot = try published(outcome)
        FeedLaunchWitness.note(.cards(snapshot.window.items.count))
        print("H(a) " + FeedLaunchWitness.record)
        let cards = try XCTUnwrap(FeedLaunchWitness.firstCardsCount)
        let milliseconds = try XCTUnwrap(FeedLaunchWitness.firstCardsMilliseconds)
        XCTAssertGreaterThanOrEqual(cards, 10)
        XCTAssertLessThanOrEqual(milliseconds, 3_000)
        XCTAssertEqual(cards, snapshot.window.items.count, "the witness states the batch it observed")
    }

    func test3R2ColdHTTPFailureDoesNotBlockHealthyTarget() async throws {
        let f = try fixture(status: 500)
        let b = try AcquisitionTargetAuthority(database: f.database).register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [f.source])
        let http = ColdHTTPFixture(items: 10, label: "B")
        addTeardownBlock { http.remove() }
        let acquisition = try snapshot(f.database, [registration(f.target, source: f.source, http: f.http), registration(b, source: f.source, http: http)])
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: acquisition, coordinator: acquisition.makeCoordinator(), prepare: { Self.prepared($0) })
        let r = ColdFeedBootstrapResources(localExaminedCapacity: 20, acquisition: .init(targetWorkCapacity: 2,
            batchCapacityPerNewExecution: 1, observationCapacityPerBatch: 20, byteCapacityPerBatch: 100_000)!)!
        guard case .published = try await bootstrap.run(identity: identity(), resources: r, backwardCapacity: 0, forwardCapacity: 20) else {
            return XCTFail("Healthy source must publish despite HTTP 500")
        }
        XCTAssertEqual(try canonical(f).count, 10)
        XCTAssertEqual(f.http.calls, 1); XCTAssertEqual(http.calls, 1)
    }
}

extension ColdFeedBootstrapTests {
    func test3R4RealSyndicationAdmitsTenItemsAndColdPublishesWithOneGET() async throws {
        for directCoordinator in [true, false] {
            let f = try fixture(items: 10)
            let acquisition = AcquisitionPlanningResources(targetWorkCapacity: 1, batchCapacityPerNewExecution: 2,
                observationCapacityPerBatch: 10, byteCapacityPerBatch: 100_000)!
            if directCoordinator {
                let result = try await f.coordinator.execute(.start(target: f.target,
                    bounds: .init(batchCapacity: 2, observationCapacityPerBatch: 10, byteCapacityPerBatch: 100_000)!))
                XCTAssertEqual(result.stop, .upToDate); XCTAssertEqual(result.receipts.count, 1)
                XCTAssertTrue(result.selectableSupplyChanged); XCTAssertTrue(result.receipts[0].checkpointAdvanced)
                XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id:f.target.id)?.checkpointRevision, 1)
            } else {
                let outcome = try await owner(f).run(identity: identity(),
                    resources: .init(localExaminedCapacity: 20, acquisition: acquisition)!, backwardCapacity: 0, forwardCapacity: 20)
                let snapshot = try published(outcome); XCTAssertEqual(snapshot.window.items.count, 10)
                XCTAssertEqual(Set(snapshot.window.items.compactMap(\.title)), Set((0..<10).map { "Remote \($0)" }))
                let target = try XCTUnwrap(AcquisitionTargetAuthority(database: f.database).target(id: f.target.id))
                XCTAssertEqual(target.checkpointRevision, 1); XCTAssertNotNil(target.checkpoint)
            }
            XCTAssertEqual(try canonical(f).count, 10); XCTAssertEqual(f.http.calls, 1)
        }
    }
    func test3R2ColdAllOperationalFailuresRetainsOrderedResultsWithoutPublication() async throws {
        let f = try fixture(status: 500)
        let b = try AcquisitionTargetAuthority(database: f.database).register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [f.source])
        let http = ColdHTTPFixture(error: URLError(.timedOut), label: "B")
        addTeardownBlock { http.remove() }
        let acquisition = try snapshot(f.database, [registration(f.target, source:f.source, http:f.http),registration(b, source:f.source, http:http)])
        let bootstrap = try ColdFeedBootstrap(session:f.session, plan:f.plan, policy:f.policy,
            acquisition:acquisition, coordinator:acquisition.makeCoordinator(), prepare: { Self.prepared($0) })
        let id = identity()
        guard case .noPublicationAfterAcquisition(_, let results) = try await bootstrap.run(identity:id,
            resources:resources(targets:2), backwardCapacity:0, forwardCapacity:2) else { return XCTFail("No invented presentation") }
        XCTAssertEqual(results.map(\.targetID),[f.target.id,b.id])
        XCTAssertEqual(results.map(\.stop),[.operationalFailure(.remoteResponse),.operationalFailure(.transport)])
        XCTAssertTrue(results.allSatisfy { $0.receipts.isEmpty && !$0.selectableSupplyChanged })
        XCTAssertEqual(f.http.calls,1); XCTAssertEqual(http.calls,1); try assertAbsent(f, identity:id)
    }
}


extension ColdFeedBootstrapTests {
    func test3R6ColdPublishesHealthyTargetAfterResidualRemoteFailuresWithoutRetry() async throws {
        for kind in 0..<3 {
            let f = try fixture(items: kind == 0 ? 100 : 1,status: kind == 1 ? 304 : 200,
                error: kind == 2 ? URLError(.cannotDecodeContentData) : nil)
            let b = try AcquisitionTargetAuthority(database: f.database).register(id: AcquisitionTargetID(),connectorKind: .syndication, authorizedSources: [f.source])
            let http = ColdHTTPFixture(items: 1,label: "B")
            addTeardownBlock { http.remove() }
            let acquisition = try snapshot(f.database,[registration(f.target,source: f.source,http: f.http),registration(b,source: f.source,http: http)])
            let bootstrap = try ColdFeedBootstrap(session: f.session,plan: f.plan,policy: f.policy,
                acquisition: acquisition,coordinator: acquisition.makeCoordinator(),prepare: { Self.prepared($0) })
            let resources = ColdFeedBootstrapResources(localExaminedCapacity: 10,acquisition: .init(targetWorkCapacity: 2,
                batchCapacityPerNewExecution: 1,observationCapacityPerBatch: 10,byteCapacityPerBatch: 512)!)!
            let snapshot = try published(await bootstrap.run(identity: identity(),resources: resources,backwardCapacity: 0,forwardCapacity: 10))
            XCTAssertEqual(snapshot.window.items.count,1)
            XCTAssertEqual(try canonical(f).count,1)
            XCTAssertEqual(f.http.calls,1); XCTAssertEqual(http.calls,1)
            XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id: f.target.id)?.checkpointRevision,0)
            XCTAssertNil(try AcquisitionTargetAuthority(database: f.database).target(id: f.target.id)?.checkpoint)
            XCTAssertEqual(try AcquisitionTargetAuthority(database: f.database).target(id: b.id)?.checkpointRevision,1)
        }
    }
}

extension ColdFeedBootstrapTests {
    /// P2 (review): the cold bootstrap publishes the first Edition itself — `launch()` receives the outcome and no
    /// driver receipt exists to act on. The reserve must mark the revisions those committed cards carry, or every
    /// prepared presentation of the first screen keeps `.ready` occupancy and retained bytes for cards the feed
    /// already shows, and the depth policy counts them as work still worth doing.
    func testColdPublicationLeavesNoReadyReserveOccupancy() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source, count: 2, time: 100)
        let reserve = PreparedReserve(targetDepth: 8, lowWaterMark: 4)
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            makeMediaOpportunity: {
                // The media pipeline's own conclusion, told in the reserve's terms: the first screen's revisions are
                // prepared before it publishes.
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in
                    for revision in await reserve.plan(offer: revisions) {
                        await reserve.markPreparing(revision, attempt: 0)
                        _ = await reserve.settle(revision, outcome: .prepared(hasImage: false), persistedBytes: 512)
                    }
                }
            })
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(local: 8),
            backwardCapacity: 0, forwardCapacity: 2))
        XCTAssertEqual(snapshot.window.items.count, 2)
        // The opportunity's request is fire-and-forget by design: wait for the conclusion it caused, not for time.
        for _ in 0..<200_000 {
            if await reserve.snapshot().ready > 0 { break }
            await Task.yield()
        }
        let prepared = await reserve.snapshot()
        XCTAssertEqual(prepared.ready, 2, "premissa: o primeiro ecrã tinha as duas apresentações preparadas")
        XCTAssertEqual(prepared.persistedBytes, 1_024)
        // What `launch()` does with the outcome the bootstrap returned (`markReservePublished`).
        await reserve.markPublished(cardIDs: snapshot.window.items.map(\.id), in: f.database)
        let accounted = await reserve.snapshot()
        XCTAssertEqual(accounted.ready, 0, "a card the edition shows no longer occupies the reserve")
        XCTAssertEqual(accounted.published, 2)
        XCTAssertEqual(accounted.persistedBytes, 0, "publication released every retained share")
    }

    /// P2 (review): the first publication commits its whole Segment while the installed window projects only the
    /// anchor and the frozen forward capacity (up to 32 cards committed, anchor + 16 projected). The reserve must be
    /// marked with the complete committed set — the receipt's own record in the store — and never with the
    /// projection, or the cards outside it stay `.ready`, charged against depth and retained bytes for stories the
    /// Edition already carries.
    func testColdPublicationMarksTheCommittedSegmentNotTheProjection() async throws {
        let f = try fixture(), id = identity()
        try Self.seed(f.database, source: f.source, count: 20, time: 100)
        let reserve = PreparedReserve(targetDepth: 32, lowWaterMark: 16)
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            makeMediaOpportunity: {
                // The media pipeline's own conclusions, told in the reserve's terms: the first screen's revisions are
                // prepared before the publication that follows.
                MediaPreparationOpportunity(waitSeconds: 4, startedAt: 100) { revisions, _ in
                    for revision in await reserve.plan(offer: revisions) {
                        await reserve.markPreparing(revision, attempt: 0)
                        _ = await reserve.settle(revision, outcome: .prepared(hasImage: false), persistedBytes: 512)
                    }
                }
            })
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(local: 32),
            backwardCapacity: 0, forwardCapacity: 2))
        // The opportunity's request is fire-and-forget by design: wait for the conclusion it caused, not for time.
        for _ in 0..<500_000 {
            if await reserve.snapshot().ready >= 20 { break }
            await Task.yield()
        }
        let prepared = await reserve.snapshot()
        XCTAssertEqual(prepared.ready, 20, "premissa: o primeiro ecrã tinha as apresentações preparadas")
        XCTAssertEqual(prepared.persistedBytes, 20 * 512)

        let publication = PublicationStore(database: f.database)
        let committed = try publication.segments(editionID: snapshot.editionID).flatMap(\.cardIDs)
        XCTAssertGreaterThan(committed.count, snapshot.window.items.count,
            "the publication committed more cards than the installed window projects")

        // What `markReservePublished` does with the bootstrap's outcome: the Edition's committed Segments, not the
        // window it happens to show.
        await reserve.markPublished(committedIn: snapshot.editionID, in: f.database)
        for cardID in committed {
            let revision = try XCTUnwrap(publication.card(id: cardID)?.originRevisionID)
            let phase = await reserve.phase(of: revision)
            XCTAssertTrue(phase == .published || phase == .exhausted(.superseded),
                "a revision the Edition committed cannot keep competing: \(phase)")
        }
        let accounted = await reserve.snapshot()
        XCTAssertEqual(accounted.ready, 0, "every prepared revision of a published card left the reserve")
        XCTAssertEqual(accounted.persistedBytes, 0, "publication released every retained share")
        XCTAssertEqual(accounted.published, 20)
    }
}

extension ColdFeedBootstrapTests {
    func testSourceRuleChangeDuringColdPreparationRestartsWithoutStartupFailure() async throws {
        let f = try fixture(), id = identity()
        _ = try ReaderPreferencesStore(database: f.database).initialize(sourceKeys: ["source"])
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator,
            prepare: { [database = f.database, source = f.source] selection in
                let prefs = ReaderPreferencesStore(database: database)
                var settings = try XCTUnwrap(prefs.load()).settings
                settings.contentSourceExclusions = [.init(sourceID: source, displayName: "Source")]
                _ = try prefs.setSettings(settings)
                return Self.prepared(selection)
            })
        _ = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 2)
        try assertAbsent(f, identity: id)
        XCTAssertFalse(try canonical(f).isEmpty, "source exclusion keeps legitimate canonical supply")
    }
}

extension ColdFeedBootstrapTests {
    func testWordCaptureMasksColdSupplyAndRemovalRecoversWithTheSameOwner() async throws {
        let f = try fixture(registrations: false)
        try Self.seed(f.database, source: f.source)
        let prefs = ReaderPreferencesStore(database: f.database)
        _ = try prefs.initialize(sourceKeys: ["source"])
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentFilterRules = ["local"]
        _ = try prefs.setSettings(settings)
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            wordPolicy: ReaderWordExclusionPolicy(database: f.database, templates: []))
        let id = identity()
        let masked = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 8)
        guard case .unavailable = masked else { return XCTFail("local rule must block first publication") }
        try assertAbsent(f, identity: id)
        settings.contentFilterRules = []
        _ = try prefs.setSettings(settings)
        let restored = try published(await bootstrap.run(identity: id, resources: resources(),
            backwardCapacity: 0, forwardCapacity: 8))
        XCTAssertEqual(restored.editionID, id.editionID)
        XCTAssertEqual(f.http.calls, 0)
    }

    func testColdPreparationWordRaceRestartsWithoutPublishingStaleCards() async throws {
        let f = try fixture(registrations: false)
        try Self.seed(f.database, source: f.source)
        let prefs = ReaderPreferencesStore(database: f.database)
        _ = try prefs.initialize(sourceKeys: ["source"])
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { selection in
                var settings = try XCTUnwrap(prefs.load()).settings
                settings.contentFilterRules = ["local"]
                _ = try prefs.setSettings(settings)
                return Self.prepared(selection)
            }, wordPolicy: ReaderWordExclusionPolicy(database: f.database, templates: []))
        let id = identity()
        let result = try await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 8)
        guard case .unavailable = result else { return XCTFail("new rule should suppress the stale prepared card") }
        try assertAbsent(f, identity: id)
        XCTAssertEqual(f.http.calls, 0)
    }
}

extension ColdFeedBootstrapTests {
    func testWordRemovalRestartsColdPartialWindowAtThePreviouslyMaskedHead() async throws {
        let f = try fixture(registrations: false)
        try Self.seed(f.database, source: f.source, count: 2)
        let newest = try XCTUnwrap(canonical(f).first).originRevisionID
        let prefs = ReaderPreferencesStore(database: f.database)
        _ = try prefs.initialize(sourceKeys: ["source"])
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentFilterRules = ["local"]
        _ = try prefs.setSettings(settings)
        let bootstrap = try ColdFeedBootstrap(session: f.session, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            wordPolicy: ReaderWordExclusionPolicy(database: f.database, templates: []))
        let id = identity()
        let masked = try await bootstrap.run(identity: id, resources: resources(local: 1),
            backwardCapacity: 0, forwardCapacity: 8)
        guard case .localWorkRemaining(let progress) = masked else { return XCTFail("must retain a partial cursor") }
        XCTAssertNotNil(progress.nextCursor)
        XCTAssertFalse(progress.exhausted)
        settings.contentFilterRules = []
        _ = try prefs.setSettings(settings)
        _ = try published(await bootstrap.run(identity: id, resources: resources(local: 1),
            backwardCapacity: 0, forwardCapacity: 8))
        let store = PublicationStore(database: f.database)
        let card = try XCTUnwrap(store.segments(editionID: id.editionID).first?.cardIDs.first)
        XCTAssertEqual(try store.card(id: card)?.originRevisionID, newest,
            "a changed word policy must rewind the partial walk to the masked head")
    }
}

extension ColdFeedBootstrapTests {
    func testBoundColdOwnerPublishesRestoresAndCheckpointsThroughTheSameActivation() async throws {
        let f = try fixture(registrations: false)
        try Self.seed(f.database, source: f.source)
        let checkpoints = SessionStore(database: f.database)
        let binding = try ReaderHistoryBindingStore(database: f.database).resolve(logicalKey: f.plan.context.key)
        let active = try checkpoints.activateBinding(binding.id)
        let reader = FeedSession(publicationHistory: PublicationHistory(database: f.database, bindingActivation: active))
        let bootstrap = try ColdFeedBootstrap(session: reader, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            bindingPublication: .init(activation: active))
        let id = identity()
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 8))
        XCTAssertEqual(snapshot.editionID, id.editionID)
        let wrote = try await reader.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(wrote)
        XCTAssertEqual(try checkpoints.checkpoint(bindingID: binding.id)?.cardID, snapshot.window.anchor.cardID)
        XCTAssertEqual(try checkpoints.checkpoint()?.updatedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(f.http.calls, 0)
    }
    func testPreparedColdOwnerPublishesWithoutTakingCurrentViewportAuthority() async throws {
        let f = try fixture(registrations: false)
        try Self.seed(f.database, source: f.source)
        let bindings = ReaderHistoryBindingStore(database: f.database), checkpoints = SessionStore(database: f.database)
        let old = try bindings.resolve(logicalKey: ContextKey(request: .source(SourceID())))
        let current = try checkpoints.activateBinding(old.id)
        let target = try bindings.resolve(logicalKey: f.plan.context.key), prepared = try checkpoints.prepareBinding(target.id)
        let reader = FeedSession(publicationHistory: PublicationHistory(database: f.database, bindingActivation: prepared))
        let bootstrap = try ColdFeedBootstrap(session: reader, plan: f.plan, policy: f.policy,
            acquisition: f.acquisition, coordinator: f.coordinator, prepare: { Self.prepared($0) },
            bindingPublication: .init(activation: prepared))
        let id = identity()
        let snapshot = try published(await bootstrap.run(identity: id, resources: resources(), backwardCapacity: 0, forwardCapacity: 8))
        XCTAssertEqual(snapshot.editionID, id.editionID)
        XCTAssertNil(try checkpoints.checkpoint())
        XCTAssertNil(try checkpoints.checkpoint(bindingActivation: current), "the prior empty reader still holds authority")
        XCTAssertNil(try bindings.binding(for: f.plan.context.key)?.activeEditionID)
        do {
            _ = try await reader.checkpointCurrentPosition(at: Date())
            XCTFail("hidden bootstrap cannot checkpoint a viewport")
        } catch { XCTAssertEqual(error as? SessionStoreError, .staleHistoryBinding) }
        try checkpoints.promotePreparedBinding(prepared)
        let wrote = try await reader.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(wrote)
        XCTAssertEqual(try checkpoints.checkpoint()?.editionID, id.editionID)
        XCTAssertThrowsError(try checkpoints.checkpoint(bindingActivation: current))
        XCTAssertEqual(f.http.calls, 0)
    }

}
