import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineComposition

@MainActor
final class SyndicationAcquisitionSnapshotTests: XCTestCase {
    private let defaultSource = SourceID()
    private let endpoint = URL(string:"https://example.test/feed?Case=A")!
    private let clock = Date(timeIntervalSince1970:12345.125)
    private func binding(id:SourceBindingID = SourceBindingID(),source:SourceID = SourceID(),
        kind:ConnectorKind = .syndication,state:SourceBindingState = .enabled) -> SourceBinding {
        .init(id:id,sourceID:source,externalPrincipal:.init(connectorKind:kind,namespace:"principals",value:"opaque",role:.principal),
            aliases:[],generation:99,state:state)!
    }
    private func registration(id:AcquisitionTargetID = AcquisitionTargetID(),generation:UInt64 = 1,
        endpoint:URL? = nil,bindings:[SourceBinding]? = nil) -> SyndicationTargetRegistration {
        .init(targetID:id,targetGeneration:generation,endpoint:endpoint ?? self.endpoint,bindings:bindings ?? [binding(source: defaultSource)])!
    }
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return try RuntimeDatabase(location:.init(directory:root))
    }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BridgeHTTPProtocol.self]
        let session = URLSession(configuration:configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return session
    }
    private func snapshot(_ database:RuntimeDatabase,_ registrations:[SyndicationTargetRegistration],redirects:Int = 0) throws -> SyndicationAcquisitionSnapshot {
        let now = clock
        return try .init(database:database,registrations:registrations,session:session(),redirectCapacity:redirects,now:{ now })
    }
    private func work(_ target:AcquisitionTarget,capacity:Int = 4) -> AcquisitionPlannedWork {
        .start(target:target,bounds:.init(batchCapacity:1,observationCapacityPerBatch:capacity,byteCapacityPerBatch:100_000)!)
    }
    private func response(items:Int = 1,url:URL? = nil) -> BridgeHTTPResponse {
        let body = Data(("<rss version=\"2.0\"><channel><title>Feed</title>"+(0..<items).map { "<item><guid>item-\($0)</guid><title>Title \($0)</title></item>" }.joined()+"</channel></rss>").utf8)
        let fixture = url.map { BridgeHTTPResponse(body:body,url:$0) } ?? BridgeHTTPResponse(body:body)
        addTeardownBlock { fixture.remove() }
        return fixture
    }
    func test01BasicRegistrationAndStructuralValidation() {
        let id = AcquisitionTargetID(),b = binding()
        let r = SyndicationTargetRegistration(targetID:id,targetGeneration:1,endpoint:endpoint,bindings:[b])
        XCTAssertEqual(r?.targetID,id); XCTAssertEqual(r?.targetGeneration,1); XCTAssertEqual(r?.bindings,[b]); XCTAssertEqual(r?.endpoint,endpoint)
        XCTAssertNil(SyndicationTargetRegistration(targetID:id,targetGeneration:0,endpoint:endpoint,bindings:[b]))
        XCTAssertNil(SyndicationTargetRegistration(targetID:id,targetGeneration:1,endpoint:endpoint,bindings:[]))
        for url in ["file:///feed","https:///","https://user:password@example.test/feed"] {
            XCTAssertNil(SyndicationTargetRegistration(targetID:id,targetGeneration:1,endpoint:URL(string:url)!,bindings:[b]))
        }
    }
    func test02TargetIDNotDerived() {
        let b = binding(),a = registration(bindings:[b]),c = registration(bindings:[b])
        XCTAssertEqual(a.endpoint,c.endpoint); XCTAssertEqual(a.bindings,c.bindings); XCTAssertNotEqual(a.targetID,c.targetID)
    }
    func test03NonSyndicationBindingRefused() {
        XCTAssertNil(SyndicationTargetRegistration(targetID:AcquisitionTargetID(),targetGeneration:1,endpoint:endpoint,bindings:[binding(kind:ConnectorKind(rawValue:"other"))]))
    }
    func test04RevokedBindingRefused() {
        XCTAssertNil(SyndicationTargetRegistration(targetID:AcquisitionTargetID(),targetGeneration:1,endpoint:endpoint,bindings:[binding(state:.revoked)]))
    }
    func test05DuplicateBindingIDRefused() {
        let id = SourceBindingID()
        XCTAssertNil(SyndicationTargetRegistration(targetID:AcquisitionTargetID(),targetGeneration:1,endpoint:endpoint,bindings:[binding(id:id),binding(id:id)]))
    }
    func test06DuplicateSourceIDRefused() {
        let source = SourceID()
        XCTAssertNil(SyndicationTargetRegistration(targetID:AcquisitionTargetID(),targetGeneration:1,endpoint:endpoint,bindings:[binding(source:source),binding(source:source)]))
    }
    func test07SameBindingMayMapToTwoTargets() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),b = binding()
        let a = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [b.sourceID])
        let c = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [b.sourceID])
        let s = try snapshot(db,[registration(id:a.id,bindings:[b]),registration(id:c.id,bindings:[b])])
        XCTAssertEqual(try s.eligibleTargets(for:.init(request:.main)),[a,c])
    }
    func test08MultipleBindingsShareOneTarget() {
        let bindings = [binding(),binding()]
        XCTAssertEqual(registration(bindings:bindings).bindings,bindings)
        // Ordered direct membership materialization is exercised through the real connector in test18.
    }
    func test09DuplicateTargetIDRefused() throws {
        let db = try database(),id = AcquisitionTargetID()
        XCTAssertThrowsError(try snapshot(db,[registration(id:id),registration(id:id)])) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.duplicateTargetID(id))
        }
    }
    func test10NegativeRedirectCapacity() throws {
        XCTAssertThrowsError(try snapshot(database(),[],redirects:-1)) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.invalidRedirectCapacity)
        }
    }
    func test11MainEligibilityOrderAndExactDurableCheckpoint() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db)
        let a = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let b = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let c = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let changed = try authority.compareAndSwapCheckpoint(id:b.id,expectedGeneration:1,expectedCheckpointRevision:0,
            next:AcquisitionCheckpoint(blob:Data([1,2,3]),serializationSchema:3,connectorVersion:"opaque")!)
        let s = try snapshot(db,[registration(id:b.id),registration(id:a.id),registration(id:c.id)])
        XCTAssertEqual(try s.eligibleTargets(for:.init(request:.main)),[changed,a,c])
    }
    func test12SourceEligibilityOrderAndIrrelevantMissingTarget() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),one = binding(),two = binding()
        let a = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [one.sourceID])
        let b = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [two.sourceID])
        let c = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [one.sourceID,two.sourceID])
        let s = try snapshot(db,[registration(id:a.id,bindings:[one]),registration(id:b.id,bindings:[two]),
            registration(id:c.id,bindings:[one,two])])
        let missing = registration(bindings: [two])
        XCTAssertThrowsError(try snapshot(db,[registration(id:a.id,bindings:[one]),missing])) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.missingDurableTarget(missing.targetID))
        }
        XCTAssertEqual(try s.eligibleTargets(for:.init(request:.source(one.sourceID))),[a,c])
    }
    func test13RevokedDurableTargetSkipped() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db)
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let revoked = try authority.revoke(id:t.id,expectedGeneration:1)
        let s = try snapshot(db,[registration(id:t.id,generation:revoked.generation)])
        XCTAssertEqual(try s.eligibleTargets(for:.init(request:.main)),[])
    }
    func test14MissingDurableTargetErrorsWithoutPartialResult() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db)
        let good = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource]),missing = AcquisitionTargetID()
        XCTAssertThrowsError(try snapshot(db,[registration(id:good.id),registration(id:missing)])) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.missingDurableTarget(missing))
        }
        XCTAssertNil(try authority.target(id:missing)); XCTAssertEqual(try authority.target(id:good.id),good)
    }
    func test15StaleGenerationErrors() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db)
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        _ = try authority.reconfigure(id:t.id,expectedGeneration:1,connectorKind:.syndication,checkpoint:.preserve, authorizedSources: [defaultSource])
        XCTAssertThrowsError(try snapshot(db,[registration(id:t.id)])) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.staleConfigurationGeneration(targetID:t.id,configured:1,durable:2))
        }
    }
    func test16ConnectorKindMismatch() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db)
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:ConnectorKind(rawValue:"other"), authorizedSources: [defaultSource])
        XCTAssertThrowsError(try snapshot(db,[registration(id:t.id)])) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.connectorKindMismatch(targetID:t.id))
        }
    }
    func test17LocalSearchHasNoAcquisitionTargets() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db)
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let s = try snapshot(db,[registration(id:t.id)])
        XCTAssertTrue(try s.eligibleTargets(for: .init(request: .search(SearchContext(query: "feed")!))).isEmpty)
        XCTAssertEqual(try authority.target(id:t.id),t)
    }
    func test18RealBindingTargetConnectorAdmissionAndMembershipOrder() async throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),bindings = [binding(),binding()],http = response()
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: Set(bindings.map(\.sourceID)))
        let s = try snapshot(db,[registration(id:t.id,endpoint:http.url,bindings:bindings)])
        let eligible = try s.eligibleTargets(for:.init(request:.source(bindings[0].sourceID)))
        XCTAssertEqual(eligible,[t])
        let resolved = try XCTUnwrap(s.connector(for:eligible[0]))
        let event = try await resolved.pull(FeedConnectorPull(targetID:t.id,targetGeneration:1,checkpointRevision:0,checkpoint:nil,observationCapacity:4,byteCapacity:100_000)!)
        guard case .batch(let translated,_) = event else { return XCTFail("Expected real connector batch") }
        XCTAssertEqual(translated.observations[0].memberships,bindings.map { AcquisitionMembershipClaim(sourceID:$0.sourceID,kind:.direct) })
        let result = try await s.makeCoordinator().execute(work(eligible[0]))
        XCTAssertEqual(result.receipts.count,1); XCTAssertEqual(result.receipts[0].selectableSupplyChanged,true)
        let store = ContentStore(database:db)
        let candidates = try store.candidateWindow(sourceID:bindings[0].sourceID,after:nil,examinedCapacity:8).records
        XCTAssertEqual(candidates.count,1); XCTAssertEqual(candidates[0].observedAt,clock)
        let memberships = try store.memberships(originRecordID:candidates[0].originRecordID)
        XCTAssertEqual(Set(memberships.map(\.sourceID)),Set(bindings.map(\.sourceID)))
        XCTAssertTrue(memberships.allSatisfy { $0.kind == .direct })
        XCTAssertEqual(http.calls,2)
    }
    func test19SharedTargetOneExecutionVisibleForBothSources() async throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),a = binding(),b = binding(),http = response()
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [a.sourceID,b.sourceID])
        let s = try snapshot(db,[registration(id:t.id,endpoint:http.url,bindings:[a,b])])
        let targets = try s.eligibleTargets(for:.init(request:.main))
        let result = try await s.makeCoordinator().execute(work(targets[0]))
        XCTAssertEqual(result.receipts.count,1); XCTAssertTrue(result.receipts[0].selectableSupplyChanged)
        let store = ContentStore(database:db)
        let one = try store.candidateWindow(sourceID:a.sourceID,after:nil,examinedCapacity:8).records
        let two = try store.candidateWindow(sourceID:b.sourceID,after:nil,examinedCapacity:8).records
        XCTAssertEqual(one.count,1); XCTAssertEqual(two.count,1)
        XCTAssertEqual(one[0].originRecordID,two[0].originRecordID); XCTAssertEqual(http.calls,1)
    }
    func test20ResolutionRequiresExactEnabledSyndicationTargetGeneration() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),http = response()
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let s = try snapshot(db,[registration(id:t.id,endpoint:http.url)])
        XCTAssertNotNil(s.connector(for:t))
        for value in [AcquisitionTarget(id:t.id,connectorKind:.syndication,generation:2,state:.enabled,checkpointRevision:0,checkpoint:nil)!,
                      AcquisitionTarget(id:t.id,connectorKind:.syndication,generation:1,state:.revoked,checkpointRevision:0,checkpoint:nil)!,
                      AcquisitionTarget(id:t.id,connectorKind:ConnectorKind(rawValue:"other"),generation:1,state:.enabled,checkpointRevision:0,checkpoint:nil)!,
                      AcquisitionTarget(id:AcquisitionTargetID(),connectorKind:.syndication,generation:1,state:.enabled,checkpointRevision:0,checkpoint:nil)!] {
            XCTAssertNil(s.connector(for:value))
        }
        XCTAssertEqual(http.calls,0)
    }
    func test21ReconfigureInvalidatesOldSnapshotNewSnapshotWorks() throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),b = binding()
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [b.sourceID])
        let old = try snapshot(db,[registration(id:t.id,bindings:[b])])
        XCTAssertEqual(try old.eligibleTargets(for:.init(request:.main)),[t])
        let next = try authority.reconfigure(id:t.id,expectedGeneration:1,connectorKind:.syndication,checkpoint:.preserve, authorizedSources: [b.sourceID])
        XCTAssertThrowsError(try old.eligibleTargets(for:.init(request:.main))) {
            XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.staleConfigurationGeneration(targetID:t.id,configured:1,durable:2))
        }
        let new = try snapshot(db,[registration(id:t.id,generation:next.generation,bindings:[b])])
        XCTAssertEqual(try new.eligibleTargets(for:.init(request:.main)),[next])
    }
    func test22OldSnapshotCannotBypassCoordinatorFence() async throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),http = response()
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let old = try snapshot(db,[registration(id:t.id,endpoint:http.url)]),coordinator = old.makeCoordinator()
        _ = try authority.reconfigure(id:t.id,expectedGeneration:1,connectorKind:.syndication,checkpoint:.preserve, authorizedSources: [defaultSource])
        do { _ = try await coordinator.execute(work(t)); XCTFail("Expected durable generation fence") }
        catch { XCTAssertEqual(error as? AcquisitionCoordinatorError,.stalePlannedGeneration(targetID:t.id,planned:1,actual:2)) }
        XCTAssertEqual(http.calls,0)
    }
    func test23ConnectorReconstructionUsesDurableContinuation() async throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),http = response(items:2)
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication, authorizedSources: [defaultSource])
        let s = try snapshot(db,[registration(id:t.id,endpoint:http.url)])
        _ = try await s.makeCoordinator().execute(work(t,capacity:1))
        let current = try XCTUnwrap(authority.target(id:t.id)); XCTAssertNotNil(current.checkpoint); XCTAssertEqual(current.checkpointRevision,1)
        let first = try XCTUnwrap(s.connector(for:current)),second = try XCTUnwrap(s.connector(for:current))
        let request = FeedConnectorPull(targetID:current.id,targetGeneration:current.generation,checkpointRevision:current.checkpointRevision,
            checkpoint:current.checkpoint,observationCapacity:1,byteCapacity:100_000)!
        for connector in [first,second] {
            let event = try await connector.pull(request)
            guard case .batch(let batch,_) = event else { return XCTFail("Expected continuation batch") }
            XCTAssertEqual(batch.observations.map(\.objectIdentity.value),["item-1"])
            XCTAssertEqual(batch.expectedCheckpointRevision,1)
        }
        XCTAssertEqual(try authority.target(id:t.id),current); XCTAssertEqual(http.calls,3)
    }
}

// Kiro K-05: a development composition may authorize the exact non-public origin of its own fixture
// server; product snapshots (default) never contact non-public hosts.
extension SyndicationAcquisitionSnapshotTests {
    private func lanSnapshot(_ db:RuntimeDatabase,_ registration:SyndicationTargetRegistration,
        origins:[URL]) throws -> SyndicationAcquisitionSnapshot {
        let now = clock
        return try .init(database:db,registrations:[registration],session:session(),redirectCapacity:0,
            now:{ now },authorizedNonPublicOrigins:origins)
    }
    private func pullRequest(_ t:AcquisitionTarget) -> FeedConnectorPull {
        FeedConnectorPull(targetID:t.id,targetGeneration:t.generation,checkpointRevision:t.checkpointRevision,
            checkpoint:nil,observationCapacity:4,byteCapacity:100_000)!
    }
    func testK05AuthorizedBenchmarkOriginIsReachable() async throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),b = binding()
        let http = response(url:URL(string:"http://10.77.0.1:8757/bench/feed.xml")!)
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication,authorizedSources:[b.sourceID])
        let s = try lanSnapshot(db,registration(id:t.id,endpoint:http.url,bindings:[b]),
            origins:[URL(string:"http://10.77.0.1:8757")!])
        let connector = try XCTUnwrap(s.connector(for:t))
        guard case .batch = try await connector.pull(pullRequest(t)) else { return XCTFail("Expected batch from authorized origin") }
        XCTAssertEqual(http.calls,1)
    }
    func testK05DefaultSnapshotRefusesNonPublicEndpointWithoutContact() async throws {
        let db = try database(),authority = AcquisitionTargetAuthority(database:db),b = binding()
        let http = response(url:URL(string:"http://10.77.0.2:8757/bench/feed.xml")!)
        let t = try authority.register(id:AcquisitionTargetID(),connectorKind:.syndication,authorizedSources:[b.sourceID])
        // Same LAN, other host: authorization is exact, so this behaves like the product default.
        for origins in [[], [URL(string:"http://10.77.0.1:8757")!]] {
            let s = try lanSnapshot(db,registration(id:t.id,endpoint:http.url,bindings:[b]),origins:origins)
            let connector = try XCTUnwrap(s.connector(for:t))
            do { _ = try await connector.pull(pullRequest(t)); XCTFail("Expected refusal") }
            catch { XCTAssertEqual(error as? ConnectorOperationalFailure,.remoteResponse) }
        }
        XCTAssertEqual(http.calls,0)
    }
    func testK05InvalidAuthorizedOriginRefusesSnapshot() throws {
        let db = try database()
        for raw in ["https://example.test","ftp://10.77.0.1/feed","http://user:pw@10.77.0.1:8757"] {
            let url = URL(string:raw)!
            XCTAssertThrowsError(try lanSnapshot(db,registration(),origins:[url])) {
                XCTAssertEqual($0 as? SyndicationAcquisitionSnapshotError,.invalidAuthorizedOrigin(url),raw)
            }
        }
    }
}

// One local response per actual URLSession request; no live network or scheduling controls.
private final class BridgeHTTPResponse: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry:[String:BridgeHTTPResponse] = [:]
    let url: URL
    let body:Data
    private let lock = NSLock()
    private var count = 0
    init(body:Data,url:URL = URL(string:"https://bridge-"+UUID().uuidString.lowercased()+".test/feed")!) {
        self.url = url; self.body = body; Self.registryLock.withLock { Self.registry[url.host!] = self }
    }
    static func find(_ url:URL?) -> BridgeHTTPResponse? { registryLock.withLock { registry[url?.host ?? ""] } }
    func remove() { _ = Self.registryLock.withLock { Self.registry.removeValue(forKey:url.host!) } }
    var calls:Int { lock.withLock { count } }
    func respond(_ loader:BridgeHTTPProtocol) {
        lock.withLock { count += 1 }
        let response = HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/rss+xml"])!
        loader.client?.urlProtocol(loader,didReceive:response,cacheStoragePolicy:.notAllowed)
        loader.client?.urlProtocol(loader,didLoad:body)
        loader.client?.urlProtocolDidFinishLoading(loader)
    }
}
private final class BridgeHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request:URLRequest) -> Bool { BridgeHTTPResponse.find(request.url) != nil }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() { BridgeHTTPResponse.find(request.url)?.respond(self) }
    override func stopLoading() {}
}
