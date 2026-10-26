import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineAcquisition
import FeedMineComposition

/// S1: a source the reader explicitly opened is pulled by the **existing** coordinator and admitted by the
/// **existing** admission, licensed by a process-scoped authority instead of a durable target row. The payload is
/// canonical and durable; the licence and the cursor are the visit's. These cases are the causal, negative and
/// retired controls around exactly that, over a real loopback HTTP server (no stubbed URLProtocol): a stubbed session
/// would agree with whatever URL and licence it was handed.
@MainActor
final class VisitAcquisitionTests: XCTestCase {
    private let visitedSource = SourceID()
    private let otherSource = SourceID()

    private struct Fixture {
        let root: URL
        let server: CatalogAuthorityServer
        let database: RuntimeDatabase
    }

    private func fixture(items: Int = 2) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try rss(items: items, prefix: "visited").write(to: root.appendingPathComponent("visited.xml"))
        try rss(items: items, prefix: "other").write(to: root.appendingPathComponent("other.xml"))
        let server = try CatalogAuthorityServer(root: root)
        addTeardownBlock { server.stop() }
        let database = try RuntimeDatabase(location: .init(directory: root.appendingPathComponent("db")))
        return Fixture(root: root, server: server, database: database)
    }

    private func rss(items: Int, prefix: String) -> Data {
        let body = "<rss version=\"2.0\"><channel><title>\(prefix)</title>"
            + (0..<items).map {
                "<item><guid>\(prefix)-\($0)</guid><title>\(prefix) story \($0)</title>"
                    + "<link>https://example.test/\(prefix)-\($0)</link>"
                    + "<description>Body \(prefix) \($0)</description></item>"
            }.joined()
            + "</channel></rss>"
        return Data(body.utf8)
    }

    private func registration(targetID: AcquisitionTargetID, generation: UInt64 = 1, source: SourceID,
        endpoint: URL) -> SyndicationTargetRegistration {
        .init(targetID: targetID, targetGeneration: generation, endpoint: endpoint,
            bindings: [.init(id: SourceBindingID(), sourceID: source,
                externalPrincipal: .init(connectorKind: .syndication, namespace: "visit-test",
                    value: endpoint.absoluteString, role: .principal),
                aliases: [], generation: 1, state: .enabled)!])!
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return session
    }

    private func origin(_ server: CatalogAuthorityServer) -> URL {
        URL(string: "http://127.0.0.1:\(server.port)")!
    }

    /// The one snapshot shape under test: `other` is an ordinary durable registration (it stands for the reader's
    /// selection), `visited` is the process-scoped one, and both point at the same real server so "which one was
    /// pulled" is answered by what was admitted, not by a stub.
    private func snapshot(_ fixture: Fixture, durable: [SyndicationTargetRegistration],
        visit: [SyndicationTargetRegistration], authority: VisitTargetAuthority) throws -> SyndicationAcquisitionSnapshot {
        try .init(database: fixture.database, registrations: durable, session: session(), redirectCapacity: 0,
            authorizedNonPublicOrigins: [origin(fixture.server)],
            visitRegistrations: visit, visitAuthority: authority)
    }

    private func sourceContext() -> FeedContext {
        FeedContext(key: ContextKey(request: .source(visitedSource)))
    }

    func testVisitPullsOnlyItsOwnSourceAndAdmitsCanonicallyWithoutADurableTarget() async throws {
        let fixture = try fixture()
        let visitedTarget = AcquisitionTargetID(), otherTarget = AcquisitionTargetID()
        let otherRegistration = registration(targetID: otherTarget, source: otherSource,
            endpoint: fixture.server.url(for: "other.xml"))
        // The durable row the reader's own selection would have (registered through the ordinary owner).
        let durable = try AcquisitionTargetAuthority(database: fixture.database).register(id: otherTarget,
            connectorKind: .syndication, authorizedSources: [otherSource])
        let visitRegistration = registration(targetID: visitedTarget, source: visitedSource,
            endpoint: fixture.server.url(for: "visited.xml"))
        let visit = VisitTargetAuthority()
        XCTAssertNotNil(visit.arm(targetID: visitedTarget, authorizedSources: [visitedSource], sourceID: visitedSource))
        let snapshot = try snapshot(fixture, durable: [otherRegistration], visit: [visitRegistration], authority: visit)

        // Eligibility: the visited target inside its own source context, the durable one nowhere else. The durable
        // registration is not the visited source, so a `.source` opportunity names exactly one target.
        XCTAssertEqual(try snapshot.eligibleTargets(for: sourceContext()).map(\.id), [visitedTarget])
        // And the visit never leaks into `.main`: the gesture licensed one source's surface, not the reader's feed.
        XCTAssertEqual(try snapshot.eligibleTargets(for: FeedContext(request: .main)).map(\.id), [otherTarget])

        let coordinator = snapshot.makeCoordinator()
        let target = try XCTUnwrap(try AcquisitionTargetLedger(database: fixture.database, visit: visit).target(id: visitedTarget)?.target)
        let results = try await coordinator.executeConcurrently([.start(target: target,
            bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)] as [AcquisitionPlannedWork], onResult: { _ in })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].stop, AcquisitionExecutionStop.capacityReached,
            "the real server answered with one batch")
        XCTAssertEqual(results[0].receipts.count, 1)
        XCTAssertTrue(results[0].receipts[0].selectableSupplyChanged, "new canonical payload was admitted")
        XCTAssertFalse(results[0].receipts[0].checkpointAdvanced,
            "a visit has no durable cursor: nothing was written to acquisition_target")

        // The payload is durable and canonical: the visited source's memberships exist and the other source's do not.
        let window = try ContentStore(database: fixture.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 32)
        let sources = Set(window.records.flatMap(\.sourceIDs))
        XCTAssertEqual(sources, [visitedSource], "only the visited source's memberships were admitted")
        XCTAssertEqual(try ContentStore(database: fixture.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 32).records.count, 2)

        // Opening a source never creates or enables its durable target — the very thing S1 forbids.
        XCTAssertNil(try AcquisitionTargetAuthority(database: fixture.database).target(id: visitedTarget))
        XCTAssertEqual(try AcquisitionTargetAuthority(database: fixture.database).target(id: otherTarget), durable,
            "the ordinary registration's target and cursor are untouched")
        // The in-memory cursor exists on the arming only.
        XCTAssertEqual(visit.target(id: visitedTarget)?.checkpointRevision, 1)
    }

    func testRetiredVisitIssuesNothingAndCannotAdmitAgain() async throws {
        let fixture = try fixture()
        let visitedTarget = AcquisitionTargetID()
        let visitRegistration = registration(targetID: visitedTarget, source: visitedSource,
            endpoint: fixture.server.url(for: "visited.xml"))
        let visit = VisitTargetAuthority()
        _ = visit.arm(targetID: visitedTarget, authorizedSources: [visitedSource], sourceID: visitedSource)
        let snapshot = try snapshot(fixture, durable: [], visit: [visitRegistration], authority: visit)
        let coordinator = snapshot.makeCoordinator()
        let target = try XCTUnwrap(visit.target(id: visitedTarget))
        _ = try await coordinator.executeConcurrently([.start(target: target,
            bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)] as [AcquisitionPlannedWork], onResult: { _ in })

        // Retirement is the association's own act (close): the arming is gone, so the surface has no eligible target
        // and a stale work item cannot pull or admit.
        visit.revokeAll()
        XCTAssertTrue(try snapshot.eligibleTargets(for: sourceContext()).isEmpty,
            "a retired visit names no target and starts no coverage")
        do {
            _ = try await coordinator.execute(.start(target: target,
                bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!))
            XCTFail("a retired visit must not execute")
        } catch {
            XCTAssertEqual(error as? AcquisitionCoordinatorError, .targetMissing(target.id))
        }
        XCTAssertEqual(try ContentStore(database: fixture.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 32).records.count, 2,
            "retirement adds no canonical payload: the earlier, authorized batch is all there is")
    }

    func testARevokedDurableRowIsNeverRevivedByAVisit() throws {
        let fixture = try fixture()
        let visitedTarget = AcquisitionTargetID()
        let authority = AcquisitionTargetAuthority(database: fixture.database)
        let registered = try authority.register(id: visitedTarget, connectorKind: .syndication,
            authorizedSources: [visitedSource])
        let withdrawn = try authority.revoke(id: visitedTarget, expectedGeneration: registered.generation)
        let visit = VisitTargetAuthority()
        _ = visit.arm(targetID: visitedTarget, authorizedSources: [visitedSource], sourceID: visitedSource)
        let visitRegistration = registration(targetID: visitedTarget, generation: withdrawn.generation,
            source: visitedSource, endpoint: fixture.server.url(for: "visited.xml"))

        // The durable row is the only authority for that target, and it is withdrawn.
        XCTAssertEqual(try AcquisitionTargetLedger(database: fixture.database, visit: visit)
            .target(id: visitedTarget)?.origin, .durable)
        XCTAssertThrowsError(try snapshot(fixture, durable: [], visit: [visitRegistration], authority: visit)) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError, .visitAuthorityWithdrawn(visitedTarget))
        }
    }

    func testVisitRegistrationIsRefusedWhenTheArmingDoesNotExist() throws {
        let fixture = try fixture()
        let visitedTarget = AcquisitionTargetID()
        // No arming: a snapshot cannot manufacture authority from a registration alone.
        XCTAssertThrowsError(try snapshot(fixture, durable: [],
            visit: [registration(targetID: visitedTarget, source: visitedSource,
                endpoint: fixture.server.url(for: "visited.xml"))], authority: VisitTargetAuthority())) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError, .missingDurableTarget(visitedTarget))
        }
    }

    /// Canonical dedupe, measured across a second pull of the same visited source: the visit deliberately re-pulls
    /// from its in-memory cursor, so a revisit must converge on the same canonical supply rather than duplicate it.
    /// The store is the judge, not the request count: same two records, and the second settlement reports no new
    /// selectable supply.
    func testASecondPullOfTheSameVisitChangesNoCanonicalSupply() async throws {
        let fixture = try fixture()
        let visitedTarget = AcquisitionTargetID()
        let visitRegistration = registration(targetID: visitedTarget, source: visitedSource,
            endpoint: fixture.server.url(for: "visited.xml"))
        let visit = VisitTargetAuthority()
        _ = visit.arm(targetID: visitedTarget, authorizedSources: [visitedSource], sourceID: visitedSource)
        let snapshot = try snapshot(fixture, durable: [], visit: [visitRegistration], authority: visit)
        let coordinator = snapshot.makeCoordinator()
        let target = try XCTUnwrap(visit.target(id: visitedTarget))
        let work: AcquisitionPlannedWork = .start(target: target,
            bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)

        let first = try await coordinator.execute(work)
        XCTAssertTrue(first.selectableSupplyChanged, "premise: the first pull admits new supply")
        func canonicalCount() throws -> Int {
            try ContentStore(database: fixture.database)
                .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 32).records.count
        }
        XCTAssertEqual(try canonicalCount(), 2)

        let second = try await coordinator.execute(work)
        XCTAssertFalse(second.selectableSupplyChanged,
            "a second pull of the same bytes is not new supply (stop=\(second.stop))")
        XCTAssertEqual(try canonicalCount(), 2, "and it duplicates no canonical record")
        XCTAssertEqual(Set(try ContentStore(database: fixture.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 32).records.flatMap(\.sourceIDs)),
            [visitedSource])
        XCTAssertNil(try AcquisitionTargetAuthority(database: fixture.database).target(id: visitedTarget),
            "still no durable target after two pulls")
    }

    func testAnEnabledDurableRowKeepsItsOwnGenerationAndCursor() async throws {
        let fixture = try fixture()
        let target = try AcquisitionTargetAuthority(database: fixture.database).register(
            id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [visitedSource])
        let visit = VisitTargetAuthority()
        // The host arms the visit, but the durable row already exists: the ledger must answer with the durable one,
        // and admission must advance the durable checkpoint (no bifurcated cursor for one target).
        _ = visit.arm(targetID: target.id, authorizedSources: [visitedSource], sourceID: visitedSource)
        let registration = registration(targetID: target.id, generation: target.generation,
            source: visitedSource, endpoint: fixture.server.url(for: "visited.xml"))
        let snapshot = try snapshot(fixture, durable: [], visit: [registration], authority: visit)
        XCTAssertEqual(try snapshot.eligibleTargets(for: sourceContext()), [target])

        _ = try await snapshot.makeCoordinator().executeConcurrently([.start(target: target,
            bounds: .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!)] as [AcquisitionPlannedWork], onResult: { _ in })
        let current = try XCTUnwrap(try AcquisitionTargetAuthority(database: fixture.database).target(id: target.id))
        XCTAssertEqual(current.checkpointRevision, 1, "the durable row's own cursor advanced")
        XCTAssertEqual(visit.target(id: target.id)?.checkpointRevision, 0,
            "the visit's in-memory arming is not the authority where a durable row exists")
    }

    /// D2: admission writes canonical supply **before** the visit's cursor CAS. Retirement in that window therefore
    /// cannot roll the payload back; what it settles is the cursor and the receipt. The test fixes the permitted
    /// behavior instead of the comment that used to claim a rollback.
    func testSupplyAdmittedBeforeRetirementStaysCanonicalWhileTheVisitCursorDoesNotAdvance() throws {
        let fixture = try fixture()
        let visitedTarget = AcquisitionTargetID()
        let visit = VisitTargetAuthority()
        _ = visit.arm(targetID: visitedTarget, authorizedSources: [visitedSource], sourceID: visitedSource)
        let target = try XCTUnwrap(visit.target(id: visitedTarget))
        let observation = try XCTUnwrap(AcquisitionObservation(
            objectIdentity: ExternalIdentity(connectorKind: .syndication, namespace: "visit-test",
                value: "pre-retirement", role: .object),
            versionIdentity: nil, precedence: .makeCurrent, availability: .available,
            headline: "Pre-retirement", summary: nil, bodyText: nil, authoredAt: nil, modifiedAt: nil,
            observedAt: Date(timeIntervalSince1970: 1), language: nil, primaryLink: nil,
            searchProjection: nil, providerID: nil,
            memberships: [.init(sourceID: visitedSource, kind: .direct)], mediaCandidates: []))
        let next = try XCTUnwrap(AcquisitionCheckpoint(blob: Data([1]), serializationSchema: 1,
            connectorVersion: "v"))
        let batch = try XCTUnwrap(AcquisitionBatch(targetID: target.id, targetGeneration: target.generation,
            expectedCheckpointRevision: 0, observations: [observation], nextCheckpoint: next))
        let receipt = try AdmissionPolicy(database: fixture.database)
            .admit(batch, authority: .visit(connectorKind: .syndication, authorizedSources: [visitedSource]))
        XCTAssertTrue(receipt.selectableSupplyChanged, "premise: the batch was admitted")
        XCTAssertFalse(receipt.checkpointAdvanced, "a visit receipt never claims a durable cursor")

        visit.revokeAll()
        XCTAssertNil(visit.compareAndSwapCheckpoint(id: target.id, expectedGeneration: target.generation,
            expectedCheckpointRevision: 0, next: next),
            "a retired arming refuses the cursor")
        let window = try ContentStore(database: fixture.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 32)
        XCTAssertEqual(window.records.count, 1, "the admitted payload is durable supply, not a rolled-back batch")
        XCTAssertNil(try AcquisitionTargetAuthority(database: fixture.database).target(id: visitedTarget))
    }

    /// D3(a): a visit retired while its pull is in flight settles as `.cancelled` — not as an error that cancels its
    /// siblings — and no request is issued after retirement. The connector is held open so the revocation lands
    /// between "the pull started" and "the batch is validated", which is the exact window the fences guard.
    func testRevocationHeldDuringThePullCancelsWithoutAdmittingOrPullingAgain() async throws {
        let fixture = try fixture()
        let visitedTarget = AcquisitionTargetID()
        let visit = VisitTargetAuthority()
        _ = visit.arm(targetID: visitedTarget, authorizedSources: [visitedSource], sourceID: visitedSource)
        let target = try XCTUnwrap(visit.target(id: visitedTarget))
        let connector = BarrierConnector(source: visitedSource)
        let coordinator = AcquisitionCoordinator(database: fixture.database, connectorForTarget: { _ in connector },
            visitAuthority: visit)

        let execution = Task {
            try await coordinator.execute(.start(target: target, bounds:
                .init(batchCapacity: 1, observationCapacityPerBatch: 8, byteCapacityPerBatch: 100_000)!))
        }
        await connector.waitUntilPulling()
        visit.revokeAll()
        await connector.release()

        let result = try await execution.value
        XCTAssertEqual(result.stop, .cancelled, "retirement is a named cancellation, not a thrown failure")
        XCTAssertTrue(result.receipts.isEmpty, "a retired visit admits no batch")
        let pulls = await connector.pulls
        XCTAssertEqual(pulls, 1, "no request is issued after the arming is retired")
        XCTAssertEqual(try ContentStore(database: fixture.database)
            .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 32).records.count, 0,
            "the held batch never became canonical supply")
    }
}

/// Holds one pull until the test releases it, then answers with a well-formed batch — the connector side of the
/// retirement barrier. It carries no FeedMine policy; it only makes the timing deterministic.
private actor BarrierConnector: FeedConnector {
    private let source: SourceID
    private var continuation: CheckedContinuation<Void, Never>?
    private var pullWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var pulls = 0

    init(source: SourceID) { self.source = source }

    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        pulls += 1
        for waiter in pullWaiters { waiter.resume() }
        pullWaiters = []
        if !released { await withCheckedContinuation { continuation = $0 } }
        guard let observation = AcquisitionObservation(
            objectIdentity: ExternalIdentity(connectorKind: .syndication, namespace: "visit-test",
                value: "held", role: .object),
            versionIdentity: nil, precedence: .makeCurrent, availability: .available,
            headline: "Held", summary: nil, bodyText: nil, authoredAt: nil, modifiedAt: nil,
            observedAt: Date(timeIntervalSince1970: 1), language: nil, primaryLink: nil,
            searchProjection: nil, providerID: nil,
            memberships: [.init(sourceID: source, kind: .direct)], mediaCandidates: []),
            let checkpoint = AcquisitionCheckpoint(blob: Data([1]), serializationSchema: 1, connectorVersion: "v"),
            let batch = AcquisitionBatch(targetID: request.targetID,
                targetGeneration: request.targetGeneration, expectedCheckpointRevision: request.checkpointRevision,
                observations: [observation], nextCheckpoint: checkpoint) else { return .upToDate }
        return .batch(batch, transportByteCount: 100)
    }

    func waitUntilPulling() async {
        if pulls > 0 { return }
        await withCheckedContinuation { pullWaiters.append($0) }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
