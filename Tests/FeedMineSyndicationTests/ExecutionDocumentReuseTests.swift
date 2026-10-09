import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
@testable import FeedMineSyndication

@MainActor
final class ExecutionDocumentReuseTests: XCTestCase {
    func test3R4OneDocumentMultipleConfirmedPages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let authority = AcquisitionTargetAuthority(database: database)
        let source = SourceID()
        let target = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [source])
        let body = Data(("<rss version=\"2.0\"><channel><title>Feed</title>" + (0..<5).map {
            "<item><guid>item-\($0)</guid><title>Title \($0)</title></item>"
        }.joined() + "</channel></rss>").utf8)
        let hop = SyndicationHTTPHop(statusCode: 200, location: nil, etag: nil, lastModified: nil, body: body)
        let transport = ScriptedSyndicationTransport(Array(repeating: hop, count: 4))
        let connector = SyndicationConnector(configuration: .init(targetID: target.id,
            endpoint: URL(string: "https://pagination.test/feed")!, memberships: [.init(sourceID: source, kind: .direct)])!,
            redirectCapacity: 0, now: { Date(timeIntervalSince1970: 100) }, transport: transport)!
        let coordinator = AcquisitionCoordinator(database: database, connectorForTarget: { _ in connector })
        let bounds = AcquisitionWorkBounds(batchCapacity: 5, observationCapacityPerBatch: 2, byteCapacityPerBatch: body.count)!
        let result = try await coordinator.execute(.start(target: target, bounds: bounds))
        let requests = await transport.journal()
        let settled = try XCTUnwrap(authority.target(id: target.id))
        let records = try ContentStore(database: database).candidateWindow(sourceID: source, after: nil, examinedCapacity: 10).records
        print("3R4 measurement GETs=\(requests.count) batches=\(result.receipts.count) observations=\(records.count) checkpoints=\(settled.checkpointRevision) distinctRevisions=\(Set(records.map(\.originRevisionID)).count)")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(result.stop, .upToDate)
        XCTAssertEqual(result.receipts.count, 3)
        XCTAssertTrue(result.receipts.allSatisfy(\.checkpointAdvanced))
        XCTAssertEqual(settled.checkpointRevision, 3)
        XCTAssertEqual(records.count, 5)
        XCTAssertEqual(Set(records.map(\.originRevisionID)).count, 5)
        let state = try SyndicationCheckpointCodec.decode(XCTUnwrap(settled.checkpoint))
        XCTAssertEqual(state.documentFingerprint, syndicationBodyFingerprint(body)); XCTAssertEqual(state.nextItemIndex, 0)
    }
}

// Test-only lifetime witness wraps (without replacing) the real connector's opaque state.
private final class DocumentLifetime: Sendable {}
private final class DocumentLifetimeJournal: @unchecked Sendable {
    private let lock = NSLock()
    private weak var last: DocumentLifetime?
    private var count = 0
    func record(_ value: DocumentLifetime) { lock.withLock { last = value; count += 1 } }
    var live: Bool { lock.withLock { last != nil } }
    var created: Int { lock.withLock { count } }
}
private actor PaginationProbe {
    let pausedRevision: UInt64?
    private var pulls: [FeedConnectorPull] = []
    private var batches: [AcquisitionBatch] = []
    private var bytes: [Int] = []
    private var ready = false
    private var released = false
    private var observer: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(pausedRevision: UInt64? = nil) { self.pausedRevision = pausedRevision }
    func before(_ request: FeedConnectorPull) async {
        pulls.append(request)
        if request.checkpointRevision == pausedRevision && !released {
            ready = true; observer?.resume(); observer = nil
            await withCheckedContinuation { waiter = $0 }
        }
    }
    func waitForPage() async {
        if !ready { await withCheckedContinuation { observer = $0 } }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
    func record(_ event: FeedConnectorEvent) {
        if case .batch(let batch, let count) = event { batches.append(batch); bytes.append(count) }
    }
    func journal() -> ([FeedConnectorPull], [AcquisitionBatch], [Int]) { (pulls, batches, bytes) }
}
private struct ProbedSyndicationConnector: FeedConnector {
    let base: SyndicationConnector
    let probe: PaginationProbe
    let lifetime: DocumentLifetimeJournal
    let rejectSecondPage: Bool
    private struct Retained: Sendable {
        var context: FeedConnectorExecutionContext
        let witness: DocumentLifetime
    }
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent { try await base.pull(request) }
    func pull(_ request: FeedConnectorPull, context: inout FeedConnectorExecutionContext) async throws -> FeedConnectorEvent {
        var retained: Retained
        if let old = context.retainedValue as? Retained { retained = old }
        else {
            let witness = DocumentLifetime(); lifetime.record(witness)
            retained = Retained(context: .init(), witness: witness)
        }
        await probe.before(request)
        var event = try await base.pull(request, context: &retained.context)
        context.retainedValue = retained
        if rejectSecondPage, request.checkpointRevision == 1, case .batch(let batch, let bytes) = event {
            let original = batch.observations[0]
            let rejected = AcquisitionObservation(objectIdentity: original.objectIdentity, versionIdentity: nil,
                precedence: .historicalOnly, availability: original.availability, headline: original.headline,
                summary: original.summary, bodyText: original.bodyText, authoredAt: original.authoredAt,
                modifiedAt: original.modifiedAt, observedAt: original.observedAt, language: original.language,
                primaryLink: original.primaryLink, searchProjection: original.searchProjection, providerID: original.providerID,
                memberships: original.memberships, mediaCandidates: original.mediaCandidates)!
            event = .batch(.init(targetID: batch.targetID, targetGeneration: batch.targetGeneration,
                expectedCheckpointRevision: batch.expectedCheckpointRevision, observations: [rejected],
                nextCheckpoint: batch.nextCheckpoint)!, transportByteCount: bytes)
        }
        await probe.record(event)
        return event
    }
}

private extension AcquisitionCoordinator {
    func paginationJoin(_ target: AcquisitionTarget, entered: CheckedContinuation<Void, Never>) async throws -> AcquisitionExecutionResult {
        entered.resume()
        return try await execute(.joinActive(target: target))
    }
}

extension ExecutionDocumentReuseTests {
    private struct Fixture {
        let database: RuntimeDatabase
        let directory: URL
        let target: AcquisitionTarget
        let source: SourceID
        let body: Data
        let transport: ScriptedSyndicationTransport
        let probe: PaginationProbe
        let lifetime: DocumentLifetimeJournal
        let coordinator: AcquisitionCoordinator
        var authority: AcquisitionTargetAuthority { .init(database: database) }
        var records: [ContentStore.CandidateRecord] {
            get throws { try ContentStore(database: database).candidateWindow(sourceID: source, after: nil, examinedCapacity: 20).records }
        }
    }
    private func body(_ ids: [String]) -> Data {
        Data(("<rss version=\"2.0\"><channel><title>Feed</title>" + ids.map {
            "<item><guid>\($0)</guid><title>\($0)</title></item>"
        }.joined() + "</channel></rss>").utf8)
    }
    private func fixture(pause: UInt64? = nil, rejected: Bool = false, failure: (any Error)? = nil) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let source = SourceID(), body = body(["a", "b", "c", "d", "e"])
        let target = try AcquisitionTargetAuthority(database: database).register(id: AcquisitionTargetID(), connectorKind: .syndication, authorizedSources: [source])
        let transport = failure.map { ScriptedSyndicationTransport(error: $0) } ?? ScriptedSyndicationTransport(Array(repeating:
            .init(statusCode: 200, location: nil, etag: nil, lastModified: nil, body: body), count: 10))
        let probe = PaginationProbe(pausedRevision: pause), lifetime = DocumentLifetimeJournal()
        let connector = ProbedSyndicationConnector(base: connector(target.id, source, transport), probe: probe,
            lifetime: lifetime, rejectSecondPage: rejected)
        let coordinator = AcquisitionCoordinator(database: database, connectorForTarget: { _ in connector })
        return Fixture(database: database, directory: directory, target: target, source: source, body: body,
            transport: transport, probe: probe, lifetime: lifetime, coordinator: coordinator)
    }
    private func connector(_ id: AcquisitionTargetID, _ source: SourceID, _ transport: ScriptedSyndicationTransport) -> SyndicationConnector {
        .init(configuration: .init(targetID: id, endpoint: URL(string: "https://pagination.test/feed")!,
            memberships: [.init(sourceID: source, kind: .direct)])!, redirectCapacity: 0,
            now: { Date(timeIntervalSince1970: 100) }, transport: transport)!
    }
    private func bounds(_ batches: Int = 5, _ observations: Int = 2, _ bytes: Int = 100_000) -> AcquisitionWorkBounds {
        .init(batchCapacity: batches, observationCapacityPerBatch: observations, byteCapacityPerBatch: bytes)!
    }
    private func assertPrefix(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        let target = try XCTUnwrap(f.authority.target(id: f.target.id), file: file, line: line)
        XCTAssertEqual(target.checkpointRevision, 1, file: file, line: line)
        let state = try SyndicationCheckpointCodec.decode(XCTUnwrap(target.checkpoint))
        XCTAssertEqual(state.nextItemIndex, 2, file: file, line: line)
        XCTAssertEqual(state.documentFingerprint, syndicationBodyFingerprint(f.body), file: file, line: line)
        XCTAssertEqual(Set(try f.records.compactMap(\.headline)), ["a", "b"], file: file, line: line)
    }
    func test3R4ConfirmedPageOrderBoundsAndNormalCleanup() async throws {
        let f = try fixture()
        let result = try await f.coordinator.execute(.start(target: f.target, bounds: bounds()))
        XCTAssertEqual(result.stop, .upToDate); XCTAssertEqual(result.receipts.count, 3)
        let (pulls, batches, bytes) = await f.probe.journal()
        XCTAssertEqual(pulls.map(\.checkpointRevision), [0,1,2,3])
        XCTAssertEqual(batches.map(\.expectedCheckpointRevision), [0,1,2])
        XCTAssertEqual(batches.map { $0.observations.count }, [2,2,1])
        XCTAssertEqual(batches.flatMap { $0.observations.map(\.objectIdentity.value) }, ["a","b","c","d","e"])
        XCTAssertEqual(bytes, [f.body.count,0,0])
        XCTAssertEqual(try pulls.dropFirst().map { try SyndicationCheckpointCodec.decode(XCTUnwrap($0.checkpoint)).nextItemIndex }, [2,4,0])
        let requests = await f.transport.journal(); XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(f.lifetime.live); XCTAssertEqual(f.lifetime.created,1)
    }
    func test3R4CapacityDiscardsDocumentAndNewExecutionResumes() async throws {
        let f = try fixture()
        let first = try await f.coordinator.execute(.start(target: f.target, bounds: bounds(1)))
        XCTAssertEqual(first.stop,.capacityReached); XCTAssertEqual(first.receipts.count,1)
        try assertPrefix(f); XCTAssertFalse(f.lifetime.live)
        let target = try XCTUnwrap(f.authority.target(id:f.target.id))
        let next = try await f.coordinator.execute(.start(target:target, bounds:bounds()))
        XCTAssertEqual(next.receipts.count,2); XCTAssertEqual(next.stop,.upToDate)
        XCTAssertFalse(f.lifetime.live); XCTAssertEqual(f.lifetime.created,2)
        let requests = await f.transport.journal(); XCTAssertEqual(requests.count,2)
        XCTAssertEqual(Set(try f.records.compactMap(\.headline)), ["a","b","c","d","e"])
        XCTAssertEqual(try f.authority.target(id:f.target.id)?.checkpointRevision,3)
    }
    func test3R6OversizedDocumentSettlesOperationallyAndIsReleased() async throws {
        let f = try fixture()
        let capacity = f.body.count - 1
        XCTAssertGreaterThan(f.body.count,capacity)
        let workBounds = bounds(5,2,capacity)
        let result = try await f.coordinator.execute(.start(target:f.target,bounds:workBounds))
        XCTAssertEqual(result.stop,.operationalFailure(.remoteContent))
        XCTAssertEqual(result.targetID,f.target.id); XCTAssertEqual(result.generation,f.target.generation)
        XCTAssertTrue(result.receipts.isEmpty); XCTAssertFalse(result.selectableSupplyChanged)
        XCTAssertTrue(try f.records.isEmpty)
        let target = try XCTUnwrap(f.authority.target(id:f.target.id))
        XCTAssertEqual(target.checkpointRevision,0); XCTAssertNil(target.checkpoint)
        XCTAssertFalse(f.lifetime.live); XCTAssertEqual(f.lifetime.created,1)
        let active = await f.coordinator.activeExecutions(); XCTAssertTrue(active.isEmpty)
        let firstRequests = await f.transport.journal(); XCTAssertEqual(firstRequests.count,1)
        // A new caller opportunity must perform its own GET with the same unchanged bound.
        let next = try await f.coordinator.execute(.start(target:target,bounds:workBounds))
        XCTAssertEqual(next.stop,.operationalFailure(.remoteContent))
        XCTAssertEqual(next.targetID,target.id); XCTAssertEqual(next.generation,target.generation)
        XCTAssertTrue(next.receipts.isEmpty); XCTAssertFalse(next.selectableSupplyChanged)
        XCTAssertEqual(try f.authority.target(id:target.id),target); XCTAssertTrue(try f.records.isEmpty)
        XCTAssertFalse(f.lifetime.live); XCTAssertEqual(f.lifetime.created,2)
        let nextActive = await f.coordinator.activeExecutions(); XCTAssertTrue(nextActive.isEmpty)
        let requests = await f.transport.journal(); XCTAssertEqual(requests.count,2)
        let (pulls,batches,_) = await f.probe.journal()
        XCTAssertEqual(pulls.map(\.byteCapacity),[capacity,capacity]); XCTAssertTrue(batches.isEmpty)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func test3R4AdmissionFailureAfterFirstPageIsFatalAndReleasesDocument() async throws {
        let f = try fixture(rejected:true)
        do { _ = try await f.coordinator.execute(.start(target:f.target,bounds:bounds())); XCTFail("Expected fatal admission") }
        catch { XCTAssertEqual(error as? AdmissionPolicyError,.unsupportedUnversionedHistorical(index:0)) }
        try assertPrefix(f); XCTAssertFalse(f.lifetime.live)
        let requests = await f.transport.journal(); XCTAssertEqual(requests.count,1)
    }
    func test3R4CreatorCancellationAfterAdmissionStopsFurtherPagesAndReleasesDocument() async throws {
        let f = try fixture(pause:1)
        let task = Task { try await f.coordinator.execute(.start(target:f.target,bounds:bounds())) }
        await f.probe.waitForPage(); try assertPrefix(f); XCTAssertTrue(f.lifetime.live)
        task.cancel(); await f.probe.release()
        let result = try await task.value
        XCTAssertEqual(result.stop,.cancelled); XCTAssertEqual(result.receipts.count,1)
        try assertPrefix(f); XCTAssertFalse(f.lifetime.live)
        let requests = await f.transport.journal(); XCTAssertEqual(requests.count,1)
    }
    func test3R4GenerationAndRevocationFenceReusedPages() async throws {
        for revoked in [false,true] {
            let f = try fixture(pause:1)
            let task = Task { try await f.coordinator.execute(.start(target:f.target,bounds:bounds())) }
            await f.probe.waitForPage(); try assertPrefix(f)
            if revoked { _ = try f.authority.revoke(id:f.target.id,expectedGeneration:1) }
            else { _ = try f.authority.reconfigure(id:f.target.id,expectedGeneration:1,connectorKind:.syndication,checkpoint:.preserve, authorizedSources: [f.source]) }
            await f.probe.release()
            do { _ = try await task.value; XCTFail("Late reused page must not be admitted") }
            catch {
                XCTAssertEqual(error as? AcquisitionTargetStoreError, revoked ? .targetRevoked(f.target.id) : .staleGeneration(expected:1,actual:2))
            }
            try assertPrefix(f); XCTAssertFalse(f.lifetime.live)
            let requests = await f.transport.journal(); XCTAssertEqual(requests.count,1)
        }
    }
    func test3R4JoinerSharesDocumentAndCannotCancelCreator() async throws {
        let f = try fixture(pause:1)
        let creator = Task { try await f.coordinator.execute(.start(target:f.target,bounds:bounds())) }
        await f.probe.waitForPage()
        var joiner: Task<AcquisitionExecutionResult, Error>!
        await withCheckedContinuation { entered in
            joiner = Task { try await f.coordinator.paginationJoin(f.target, entered:entered) }
        }
        joiner.cancel(); await f.probe.release()
        let first = try await creator.value, second = try await joiner.value
        XCTAssertEqual(first,second); XCTAssertEqual(first.stop,.upToDate); XCTAssertEqual(first.receipts.count,3)
        XCTAssertFalse(f.lifetime.live); XCTAssertEqual(f.lifetime.created,1)
        let requests = await f.transport.journal(); XCTAssertEqual(requests.count,1)
    }
    func test3R4ReopenResumesPartialOrRestartsChangedDocumentWithoutOldBuffer() async throws {
        for changed in [false,true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            addTeardownBlock { try? FileManager.default.removeItem(at:directory) }
            let id = AcquisitionTargetID(), source = SourceID(), original = body(["a","b","c","d","e"])
            weak var oldDatabase: RuntimeDatabase?
            func firstExecution() async throws {
                let database = try RuntimeDatabase(location:.init(directory:directory)); oldDatabase = database
                let target = try AcquisitionTargetAuthority(database:database).register(id:id,connectorKind:.syndication, authorizedSources: [source])
                let transport = ScriptedSyndicationTransport([.init(statusCode:200,location:nil,etag:nil,lastModified:nil,body:original)])
                let connector = self.connector(id,source,transport)
                let coordinator = AcquisitionCoordinator(database:database,connectorForTarget:{ _ in connector })
                let result = try await coordinator.execute(.start(target:target,bounds:bounds(1)))
                XCTAssertEqual(result.stop,.capacityReached); XCTAssertEqual(result.receipts.count,1)
                let requests = await transport.journal(); XCTAssertEqual(requests.count,1)
            }
            try await firstExecution(); XCTAssertNil(oldDatabase)
            let database = try RuntimeDatabase(location:.init(directory:directory))
            let authority = AcquisitionTargetAuthority(database:database), target = try XCTUnwrap(authority.target(id:id))
            XCTAssertEqual(target.checkpointRevision,1)
            let nextBody = changed ? body(["x","y","z"]) : original
            let transport = ScriptedSyndicationTransport([.init(statusCode:200,location:nil,etag:nil,lastModified:nil,body:nextBody)])
            let connector = self.connector(id,source,transport)
            let coordinator = AcquisitionCoordinator(database:database,connectorForTarget:{ _ in connector })
            let result = try await coordinator.execute(.start(target:target,bounds:bounds()))
            XCTAssertEqual(result.stop,.upToDate); XCTAssertEqual(result.receipts.count,2)
            let requests = await transport.journal(); XCTAssertEqual(requests.count,1)
            let records = try ContentStore(database:database).candidateWindow(sourceID:source,after:nil,examinedCapacity:20).records
            XCTAssertEqual(Set(records.compactMap(\.headline)),changed ? ["a","b","x","y","z"] : ["a","b","c","d","e"])
            let settled = try XCTUnwrap(authority.target(id:id))
            let state = try SyndicationCheckpointCodec.decode(XCTUnwrap(settled.checkpoint))
            XCTAssertEqual(settled.checkpointRevision,3); XCTAssertEqual(state.nextItemIndex,0)
            XCTAssertEqual(state.documentFingerprint,syndicationBodyFingerprint(nextBody))
        }
    }
}


extension ExecutionDocumentReuseTests {
    func test3R4InitialRealTransportTimeoutSettlesWithoutReceiptsAndReleasesContext() async throws {
        let f = try fixture(failure: URLError(.timedOut))
        let result = try await f.coordinator.execute(.start(target:f.target,bounds:bounds()))
        XCTAssertEqual(result.stop,.operationalFailure(.transport)); XCTAssertTrue(result.receipts.isEmpty)
        XCTAssertFalse(result.selectableSupplyChanged); XCTAssertTrue(try f.records.isEmpty)
        XCTAssertEqual(try f.authority.target(id:f.target.id)?.checkpointRevision,0)
        XCTAssertFalse(f.lifetime.live)
        let requests = await f.transport.journal(); XCTAssertEqual(requests.count,1)
    }
}
