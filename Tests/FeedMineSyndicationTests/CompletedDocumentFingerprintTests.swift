import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
@testable import FeedMineSyndication

private final class CompletedHTTPFixture: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: CompletedHTTPFixture] = [:]
    let url = URL(string: "https://completed-" + UUID().uuidString.lowercased() + ".test/feed")!
    let body: Data
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    init(body: Data) {
        self.body = body
        Self.registryLock.withLock { Self.registry[url.host!] = self }
    }
    static func find(_ url: URL?) -> CompletedHTTPFixture? { registryLock.withLock { registry[url?.host ?? ""] } }
    func remove() { _ = Self.registryLock.withLock { Self.registry.removeValue(forKey: url.host!) } }
    var received: [URLRequest] { lock.withLock { requests } }
    func respond(_ loader: CompletedURLProtocol) {
        lock.withLock { requests.append(loader.request) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
        loader.client?.urlProtocol(loader, didLoad: body)
        loader.client?.urlProtocolDidFinishLoading(loader)
    }
}
private final class CompletedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = CompletedHTTPFixture.find(request.url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        fixture.respond(self)
    }
    override func stopLoading() {}
}

@MainActor
final class CompletedDocumentFingerprintTests: XCTestCase {
    private func rss(_ items: String) -> Data {
        Data(("<rss version=\"2.0\"><channel><title>Feed</title>" + items + "</channel></rss>").utf8)
    }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompletedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return session
    }
    private func connector(_ server: CompletedHTTPFixture, target: AcquisitionTargetID, source: SourceID) -> SyndicationConnector {
        .init(configuration: .init(targetID: target, endpoint: server.url, memberships: [.init(sourceID:source, kind:.direct)])!,
            session: session(), redirectCapacity: 0, now: { Date(timeIntervalSince1970: 100) })!
    }
    private func root() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:directory) }
        return directory
    }
    private var bounds: AcquisitionWorkBounds {
        .init(batchCapacity:5, observationCapacityPerBatch:10, byteCapacityPerBatch:100_000)!
    }
    func test3R3NoValidatorDedupSurvivesDatabaseReopenAndNewConnector() async throws {
        let directory = root(), id = AcquisitionTargetID(), source = SourceID()
        let body = rss("<item><guid>a</guid><title>A</title></item>"), server = CompletedHTTPFixture(body:body)
        addTeardownBlock { server.remove() }
        weak var originalDatabase: RuntimeDatabase?
        func firstOpportunity() async throws -> AcquisitionTarget {
            let database = try RuntimeDatabase(location:.init(directory:directory)); originalDatabase = database
            let authority = AcquisitionTargetAuthority(database:database)
            let target = try authority.register(id:id, connectorKind:.syndication)
            let connector = self.connector(server, target:id, source:source)
            let coordinator = AcquisitionCoordinator(database:database, connectorForTarget: { _ in connector })
            let result = try await coordinator.execute(.start(target:target, bounds:bounds))
            XCTAssertEqual(result.stop,.upToDate); XCTAssertEqual(result.receipts.count,1)
            XCTAssertTrue(result.selectableSupplyChanged); XCTAssertTrue(result.receipts[0].checkpointAdvanced)
            XCTAssertEqual(server.received.count,2) // First acquisition + terminal verification; only one batch.
            let settled = try XCTUnwrap(authority.target(id:id)), checkpoint = try XCTUnwrap(settled.checkpoint)
            let state = try SyndicationCheckpointCodec.decode(checkpoint)
            XCTAssertEqual(state.documentFingerprint,syndicationBodyFingerprint(body)); XCTAssertEqual(state.nextItemIndex,0)
            XCTAssertNil(state.etag); XCTAssertNil(state.lastModified); XCTAssertEqual(settled.checkpointRevision,1)
            XCTAssertEqual(try ContentStore(database:database).candidateWindow(sourceID:source,after:nil,examinedCapacity:10).records.count,1)
            return settled
        }
        let before = try await firstOpportunity()
        XCTAssertNil(originalDatabase) // The first pool/owner lifetime has ended before reopening.
        let database = try RuntimeDatabase(location:.init(directory:directory))
        let authority = AcquisitionTargetAuthority(database:database), target = try XCTUnwrap(authority.target(id:id))
        XCTAssertEqual(target,before)
        let connector = self.connector(server,target:id,source:source)
        let rebuilt = AcquisitionCoordinator(database:database,connectorForTarget: { _ in connector })
        let start = server.received.count
        let result = try await rebuilt.execute(.start(target:target,bounds:bounds))
        XCTAssertEqual(server.received.count-start,1)
        XCTAssertEqual(result.stop,.upToDate); XCTAssertTrue(result.receipts.isEmpty); XCTAssertFalse(result.selectableSupplyChanged)
        XCTAssertEqual(try authority.target(id:id),before)
        XCTAssertEqual(try ContentStore(database:database).candidateWindow(sourceID:source,after:nil,examinedCapacity:10).records.count,1)
        XCTAssertTrue(server.received.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField:"If-None-Match") == nil && $0.value(forHTTPHeaderField:"If-Modified-Since") == nil })
    }
    func test3R3EmptyAndAllRejectedDocumentsAdvanceOnceWithoutSupply() async throws {
        for body in [rss(""),rss("<item><title>No stable identity</title></item>")] {
            let database = try RuntimeDatabase(location:.init(directory:root()))
            let authority = AcquisitionTargetAuthority(database:database), id = AcquisitionTargetID(), source = SourceID()
            let target = try authority.register(id:id,connectorKind:.syndication), server = CompletedHTTPFixture(body:body)
            addTeardownBlock { server.remove() }
            let connector = self.connector(server,target:id,source:source)
            let coordinator = AcquisitionCoordinator(database:database,connectorForTarget: { _ in connector })
            let first = try await coordinator.execute(.start(target:target,bounds:bounds))
            XCTAssertEqual(first.stop,.upToDate); XCTAssertEqual(first.receipts.count,1)
            XCTAssertTrue(first.receipts[0].checkpointAdvanced); XCTAssertFalse(first.selectableSupplyChanged)
            let settled = try XCTUnwrap(authority.target(id:id))
            XCTAssertEqual(settled.checkpointRevision,1)
            let state = try SyndicationCheckpointCodec.decode(XCTUnwrap(settled.checkpoint))
            XCTAssertEqual(state.documentFingerprint,syndicationBodyFingerprint(body)); XCTAssertEqual(state.nextItemIndex,0)
            XCTAssertTrue(try ContentStore(database:database).candidateWindow(sourceID:nil,after:nil,examinedCapacity:10).records.isEmpty)
            let start = server.received.count
            let second = try await coordinator.execute(.start(target:settled,bounds:bounds))
            XCTAssertEqual(server.received.count-start,1); XCTAssertTrue(second.receipts.isEmpty)
            XCTAssertEqual(second.stop,.upToDate); XCTAssertFalse(second.selectableSupplyChanged)
            XCTAssertEqual(try authority.target(id:id),settled)
        }
    }
}

extension CompletedDocumentFingerprintTests {
    func test3R3ChangedCompleteAndChangedPartialDocumentsRestartDurably() async throws {
        func document(_ ids: [String]) -> Data { rss(ids.map { "<item><guid>\($0)</guid></item>" }.joined()) }
        let first = document(["a"]), second = document(["x","y"]), third = document(["q","r","s"])
        let transport = ScriptedSyndicationTransport([first,second,third,third,third,third].map {
            SyndicationHTTPHop(statusCode:200,location:nil,etag:nil,lastModified:nil,body:$0)
        })
        let database = try RuntimeDatabase(location:.init(directory:root()))
        let authority = AcquisitionTargetAuthority(database:database), id = AcquisitionTargetID(), source = SourceID()
        _ = try authority.register(id:id,connectorKind:.syndication)
        let connector = SyndicationConnector(configuration:.init(targetID:id,endpoint:URL(string:"https://example.test/feed")!,
            memberships:[.init(sourceID:source,kind:.direct)])!,redirectCapacity:0,now:{ Date(timeIntervalSince1970:100) },transport:transport)!
        let coordinator = AcquisitionCoordinator(database:database,connectorForTarget: { _ in connector })
        let bounds = AcquisitionWorkBounds(batchCapacity:1,observationCapacityPerBatch:1,byteCapacityPerBatch:100_000)!
        let bodies = [first,second,third,third,third]
        for index in 0..<5 {
            let target = try XCTUnwrap(authority.target(id:id))
            let result = try await coordinator.execute(.start(target:target,bounds:bounds))
            XCTAssertEqual(result.receipts.count,1); XCTAssertTrue(result.selectableSupplyChanged)
            let settled = try XCTUnwrap(authority.target(id:id))
            let state = try SyndicationCheckpointCodec.decode(XCTUnwrap(settled.checkpoint))
            XCTAssertEqual(state.documentFingerprint,syndicationBodyFingerprint(bodies[index]))
            XCTAssertEqual(state.nextItemIndex,[0,1,1,2,0][index])
            XCTAssertEqual(settled.checkpointRevision,UInt64(index+1))
        }
        let target = try XCTUnwrap(authority.target(id:id))
        let result = try await coordinator.execute(.start(target:target,bounds:bounds))
        XCTAssertEqual(result.stop,.upToDate); XCTAssertTrue(result.receipts.isEmpty)
        XCTAssertEqual(try authority.target(id:id),target)
        let records = try ContentStore(database:database).candidateWindow(sourceID:source,after:nil,examinedCapacity:10).records
        XCTAssertEqual(records.count,5) // a, x, q, r, s; never old partial y.
        let requests = await transport.journal(); XCTAssertEqual(requests.count,6)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField:"If-None-Match") == nil })
    }
}
