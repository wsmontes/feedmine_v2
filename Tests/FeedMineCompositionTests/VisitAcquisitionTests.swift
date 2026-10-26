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
}
