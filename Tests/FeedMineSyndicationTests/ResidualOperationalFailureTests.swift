// Residual H2 boundary proofs: explicit remote failures, durable fences and finite requests.
import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
@testable import FeedMineSyndication

@MainActor
final class ResidualOperationalFailureTests: XCTestCase {
    private let source = SourceID()
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: .init(directory: root))
    }
    private func hop(_ status: Int = 200, location: String? = nil, body: Data = Data()) -> SyndicationHTTPHop {
        .init(statusCode: status,location: location,etag: nil,lastModified: nil,body: body)
    }
    private var validBody: Data { Data("<rss version=\"2.0\"><channel><title>Feed</title><item><guid>valid</guid><title>Healthy</title></item></channel></rss>".utf8) }
    private func connector(_ target: AcquisitionTarget,transport: any SyndicationHTTPTransport,redirects: Int = 1) -> SyndicationConnector {
        .init(configuration: .init(targetID: target.id,endpoint: URL(string: "https://residual.test/feed")!,
            memberships: [.init(sourceID: source,kind: .direct)])!,redirectCapacity: redirects,
            now: { Date(timeIntervalSince1970: 100) },transport: transport)!
    }
    private func assertIsolated(_ transport: ScriptedSyndicationTransport,category: ConnectorOperationalFailure,
        redirects: Int = 1,gets: Int = 1) async throws {
        let database = try database(), authority = AcquisitionTargetAuthority(database: database)
        let targets = try (0..<3).map { _ in try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication, authorizedSources: [source]) }
        let b = ScriptedSyndicationTransport([hop(body: validBody)]), c = ScriptedSyndicationTransport([hop(body: validBody)])
        let mapping = [targets[0].id: connector(targets[0],transport: transport,redirects: redirects),
            targets[1].id: connector(targets[1],transport: b),targets[2].id: connector(targets[2],transport: c)]
        let coordinator = AcquisitionCoordinator(database: database,connectorForTarget: { mapping[$0.id] })
        var results: [AcquisitionExecutionResult] = []
        let bounds = AcquisitionWorkBounds(batchCapacity: 1,observationCapacityPerBatch: 10,byteCapacityPerBatch: 512)!
        for target in targets { results.append(try await coordinator.execute(.start(target: target,bounds: bounds))) }
        XCTAssertEqual(results.map(\.targetID),targets.map(\.id))
        XCTAssertEqual(results.map(\.generation),targets.map(\.generation))
        XCTAssertEqual(results[0].stop,.operationalFailure(category)); XCTAssertTrue(results[0].receipts.isEmpty)
        XCTAssertFalse(results[0].selectableSupplyChanged)
        XCTAssertEqual(results.map { $0.receipts.count },[0,1,1])
        XCTAssertTrue(results[1].selectableSupplyChanged); XCTAssertTrue(results[2].selectableSupplyChanged)
        XCTAssertEqual(try authority.target(id: targets[0].id)?.checkpointRevision,0)
        XCTAssertNil(try authority.target(id: targets[0].id)?.checkpoint)
        XCTAssertEqual(try ContentStore(database: database).candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.count,2)
        let aRequests = await transport.journal(), bRequests = await b.journal(), cRequests = await c.journal()
        XCTAssertEqual(aRequests.count,gets); XCTAssertEqual(bRequests.count,1); XCTAssertEqual(cRequests.count,1)
        XCTAssertTrue((aRequests+bRequests+cRequests).allSatisfy { $0.httpMethod == "GET" })
    }
    func testE1BodyTooLargeIsRemoteContentAndOtherTargetsAdmit() async throws {
        try await assertIsolated(.init([hop(body: Data(repeating: 65,count: 513))]),category: .remoteContent)
    }
    func testE1PhysicalStreamStopsAtBoundBeforeRemainingDocumentAndHealthyTargetContinues() async throws {
        let database = try database(), authority = AcquisitionTargetAuthority(database: database)
        let a = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication, authorizedSources: [source])
        let b = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication, authorizedSources: [source])
        let fixture = LocalSyndicationHTTPFixture(body: Data([1,2]),incremental: true)
        let session = fixture.session()
        defer { session.invalidateAndCancel(); fixture.remove() }
        let aConnector = SyndicationConnector(configuration: .init(targetID: a.id,endpoint: fixture.url,
            memberships: [.init(sourceID: source,kind: .direct)])!,session: session,redirectCapacity: 0,
            now: { Date(timeIntervalSince1970: 100) })!
        let transport = ScriptedSyndicationTransport([hop(body: validBody)])
        let bConnector = connector(b,transport: transport)
        let mapping = [a.id: aConnector,b.id: bConnector]
        let coordinator = AcquisitionCoordinator(database: database,connectorForTarget: { mapping[$0.id] })
        let task = Task { try await coordinator.execute(.start(target: a,bounds: .init(batchCapacity: 1,observationCapacityPerBatch: 1,byteCapacityPerBatch: 4)!)) }
        var started = fixture.started.makeAsyncIterator(); _ = await started.next()
        XCTAssertTrue(fixture.emit(Data([3,4,5])))
        let result = try await task.value
        XCTAssertEqual(result.stop,.operationalFailure(.remoteContent)); XCTAssertTrue(result.receipts.isEmpty)
        var stopped = fixture.stopped.makeAsyncIterator(); _ = await stopped.next()
        XCTAssertFalse(fixture.emit(Data(repeating: 9,count: 100_000)))
        XCTAssertEqual(fixture.emittedByteCount,5); XCTAssertEqual(fixture.startedCount,1)
        XCTAssertEqual(try authority.target(id: a.id)?.checkpointRevision,0)
        let healthy = try await coordinator.execute(.start(target: b,bounds: .init(batchCapacity: 1,observationCapacityPerBatch: 1,byteCapacityPerBatch: 512)!))
        XCTAssertEqual(healthy.receipts.count,1); XCTAssertTrue(healthy.selectableSupplyChanged)
        let requests = await transport.journal(); XCTAssertEqual(requests.count,1)
        XCTAssertEqual(try ContentStore(database: database).candidateWindow(sourceID: nil,after: nil,examinedCapacity: 10).records.count,1)
    }
    func testE2InvalidRedirectTargetIsRemoteResponseAndOthersContinue() async throws {
        try await assertIsolated(.init([hop(302,location: "file:///feed")]),category: .remoteResponse)
    }
    func testE3RedirectCapacityIsRemoteResponseAndFinite() async throws {
        try await assertIsolated(.init([hop(302,location: "/again"),hop(302,location: "/again")]),category: .remoteResponse,gets: 2)
    }
    func testE4MissingRedirectLocationIsRemoteResponse() async throws {
        try await assertIsolated(.init([hop(302)]),category: .remoteResponse)
    }
    func testE5Unsolicited304IsNotUpToDate() async throws {
        try await assertIsolated(.init([hop(304)]),category: .remoteResponse)
    }
    func testE6BadServerResponse() async throws { try await assertIsolated(.init(error: URLError(.badServerResponse)),category: .remoteResponse) }
    func testE6CannotParseResponse() async throws { try await assertIsolated(.init(error: URLError(.cannotParseResponse)),category: .remoteResponse) }
    func testE6TooManyRedirects() async throws { try await assertIsolated(.init(error: URLError(.httpTooManyRedirects)),category: .remoteResponse) }
    func testE6ResourceUnavailable() async throws { try await assertIsolated(.init(error: URLError(.resourceUnavailable)),category: .transport) }
    func testE6CannotDecodeContentData() async throws { try await assertIsolated(.init(error: URLError(.cannotDecodeContentData)),category: .remoteContent) }

    private func checkpointFailure(_ checkpoint: AcquisitionCheckpoint,expected: SyndicationCheckpointError) async throws {
        let database = try database(), authority = AcquisitionTargetAuthority(database: database)
        let registered = try authority.register(id: AcquisitionTargetID(),connectorKind: .syndication, authorizedSources: [source])
        let target = try authority.compareAndSwapCheckpoint(id: registered.id,expectedGeneration: 1,expectedCheckpointRevision: 0,next: checkpoint)
        let transport = ScriptedSyndicationTransport([]), connector = connector(target,transport: transport)
        let coordinator = AcquisitionCoordinator(database: database,connectorForTarget: { _ in connector })
        do {
            _ = try await coordinator.execute(.start(target: target,bounds: .init(batchCapacity: 1,observationCapacityPerBatch: 1,byteCapacityPerBatch: 512)!))
            XCTFail("Durable checkpoint error must propagate")
        } catch { XCTAssertEqual(error as? SyndicationCheckpointError,expected) }
        XCTAssertEqual(try authority.target(id: target.id),target)
        let requests = await transport.journal(); XCTAssertTrue(requests.isEmpty)
    }
    func testE8MalformedDurableCheckpointIsFatal() async throws {
        try await checkpointFailure(.init(blob: Data("malformed".utf8),serializationSchema: 1,connectorVersion: SyndicationCheckpointCodec.connectorVersion)!,expected: .malformed)
    }
    func testE9UnsupportedDurableConnectorVersionIsFatal() async throws {
        try await checkpointFailure(.init(blob: Data(),serializationSchema: 1,connectorVersion: "unsupported")!,expected: .unsupportedConnectorVersion("unsupported"))
    }
    func testE10UnsupportedDurableSchemaIsFatal() async throws {
        try await checkpointFailure(.init(blob: Data(),serializationSchema: 2,connectorVersion: SyndicationCheckpointCodec.connectorVersion)!,expected: .unsupportedSchema(2))
    }
    func testE7CancelledStaysCancellationAndUnmappedLocalURLCodePropagates() async throws {
        let database = try database(), target = try AcquisitionTargetAuthority(database: database).register(id: AcquisitionTargetID(),connectorKind: .syndication, authorizedSources: [source])
        for code in [URLError.Code.cancelled,.unsupportedURL] {
            let transport = ScriptedSyndicationTransport(error: URLError(code)), connector = connector(target,transport: transport)
            let request = FeedConnectorPull(targetID: target.id,targetGeneration: target.generation,checkpointRevision: 0,checkpoint: nil,observationCapacity: 1,byteCapacity: 512)!
            do { _ = try await connector.pull(request); XCTFail("Expected propagated failure") }
            catch {
                if code == .cancelled { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertEqual((error as? URLError)?.code,.unsupportedURL) }
            }
            let requests = await transport.journal(); XCTAssertEqual(requests.count,1)
        }
    }
}
