import Foundation
import XCTest
@testable import FeedMineSyndication

// The seam replaces only external I/O; HTTP orchestration remains production code.
actor ScriptedSyndicationTransport: SyndicationHTTPTransport {
    private var steps: [Result<SyndicationHTTPHop, Error>]
    private var requests: [URLRequest] = []
    init(_ hops: [SyndicationHTTPHop]) { steps = hops.map { .success($0) } }
    init(error: Error) { steps = [.failure(error)] }
    func execute(_ request: URLRequest, bodyByteCapacity: Int) async throws -> SyndicationHTTPHop {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.resourceUnavailable) }
        return try steps.removeFirst().get()
    }
    func journal() -> [URLRequest] { requests }
}

final class SyndicationHTTPTests: XCTestCase {
    private let endpoint = URL(string: "https://example.test/feed?Case=A")!
    private var boundary: SyndicationCheckpointState {
        .init(etag: "W/\"opaque\"", lastModified: "Wed, 01 Jan 2020 00:00:00 GMT", documentFingerprint: nil, nextItemIndex: 0)!
    }
    private func fetch(_ transport: ScriptedSyndicationTransport, state: SyndicationCheckpointState? = nil,
        redirects: Int = 2, capacity: Int = 64) async throws -> SyndicationHTTPOutcome {
        try await SyndicationHTTPClient(transport: transport, redirectCapacity: redirects)
            .fetch(endpoint: endpoint, checkpoint: state ?? SyndicationCheckpointCodec.empty, bodyByteCapacity: capacity)
    }
    private func hop(_ status: Int = 200, location: String? = nil, body: Data = Data()) -> SyndicationHTTPHop {
        .init(statusCode: status, location: location, etag: nil, lastModified: nil, body: body)
    }
    private func failure(_ transport: ScriptedSyndicationTransport, expected: SyndicationHTTPError,
        state: SyndicationCheckpointState? = nil, redirects: Int = 2, capacity: Int = 64) async {
        do { _ = try await fetch(transport, state: state, redirects: redirects, capacity: capacity); XCTFail("Expected typed HTTP failure") }
        catch { XCTAssertEqual(error as? SyndicationHTTPError, expected) }
    }
    func test01DirectConditionalHeaders() async throws {
        let t = ScriptedSyndicationTransport([hop()]); _ = try await fetch(t, state: boundary)
        let journal = await t.journal()
        let r = try XCTUnwrap(journal.first)
        XCTAssertEqual(r.url,endpoint); XCTAssertEqual(r.httpMethod,"GET"); XCTAssertNil(r.httpBody)
        XCTAssertEqual(r.cachePolicy,.reloadIgnoringLocalCacheData)
        XCTAssertEqual(r.value(forHTTPHeaderField:"If-None-Match"),boundary.etag)
        XCTAssertEqual(r.value(forHTTPHeaderField:"If-Modified-Since"),boundary.lastModified)
        XCTAssertNil(r.value(forHTTPHeaderField:"Authorization"))
    }
    func test02PartialSuppressesConditional() async throws {
        let t = ScriptedSyndicationTransport([hop()])
        _ = try await fetch(t,state: .init(etag: "e",lastModified: "m",documentFingerprint: "f",nextItemIndex: 1)!)
        let journal = await t.journal()
        XCTAssertNil(journal[0].value(forHTTPHeaderField:"If-None-Match")); XCTAssertNil(journal[0].value(forHTTPHeaderField:"If-Modified-Since"))
    }
    func test03Valid304() async throws {
        let t = ScriptedSyndicationTransport([hop(304)])
        let outcome = try await fetch(t,state: boundary)
        guard case .notModified = outcome else { return XCTFail("Expected notModified") }
    }
    func test04Unconditional304Refused() async { await failure(.init([hop(304)]),expected: .notModifiedWithoutConditionalRequest) }
    func test05RedirectStripsValidators() async throws {
        for destination in ["https://other.example/feed","/same-host"] {
            let t = ScriptedSyndicationTransport([hop(302,location:destination),hop()])
            let outcome = try await fetch(t,state:boundary)
            let journal = await t.journal(); XCTAssertEqual(journal.count,2)
            XCTAssertEqual(journal[0].value(forHTTPHeaderField:"If-None-Match"),boundary.etag)
            XCTAssertNil(journal[1].value(forHTTPHeaderField:"If-None-Match")); XCTAssertNil(journal[1].value(forHTTPHeaderField:"If-Modified-Since"))
            guard case .document(let d) = outcome else { return XCTFail("Expected document") }
            XCTAssertEqual(d.redirectCount,1)
        }
    }
    func test06RelativeRedirect() async throws {
        let t = ScriptedSyndicationTransport([hop(307,location:"/new-feed"),hop()]); _ = try await fetch(t)
        let journal = await t.journal(); XCTAssertEqual(journal[1].url?.absoluteString,"https://example.test/new-feed")
    }
    func test07InvalidRedirect() async {
        for url in ["file:///tmp/feed","data:text/plain,feed","https:///","https://user:password@example.test/feed"] {
            await failure(.init([hop(301,location:url)]),expected:.invalidRedirectTarget)
        }
    }
    /// v1 lesson IN-2 / review M13: an https request never follows a redirect to http.
    func test07bHTTPSDowngradeRefused() async throws {
        for url in ["http://example.test/feed","HTTP://other.example/feed"] {
            let t = ScriptedSyndicationTransport([hop(301,location:url),hop()])
            await failure(t,expected:.invalidRedirectTarget)
            let journal = await t.journal(); XCTAssertEqual(journal.count,1)
        }
        // Upgrade and same-scheme redirects remain allowed.
        let t = ScriptedSyndicationTransport([hop(302,location:"https://secure.example/feed"),hop()])
        _ = try await fetch(t)
        let journal = await t.journal(); XCTAssertEqual(journal.count,2)
    }
    /// Kiro K-01 (review R15 applied to feed documents): a public feed cannot redirect the
    /// acquisition request into loopback, the local network or a cloud metadata address.
    private let privateHosts = ["https://127.0.0.1/feed","https://10.0.0.1/feed","https://169.254.169.254/latest/meta-data/",
        "https://[::1]/feed","https://localhost/feed","https://printer.local/feed","https://2130706433/feed",
        "https://[::ffff:127.0.0.1]/feed","https://192.168.1.20:8443/feed"]
    func test07cRedirectIntoPrivateNetworkRefused() async throws {
        for url in privateHosts {
            let t = ScriptedSyndicationTransport([hop(302,location:url),hop()])
            await failure(t,expected:.nonPublicHost)
            let journal = await t.journal(); XCTAssertEqual(journal.count,1,"must not contact \(url)")
        }
        // The rule applies on every hop, not only the first one.
        let chained = ScriptedSyndicationTransport([hop(302,location:"https://cdn.example/feed"),
            hop(302,location:"https://192.168.1.1/feed"),hop()])
        await failure(chained,expected:.nonPublicHost)
        let chainedJournal = await chained.journal(); XCTAssertEqual(chainedJournal.count,2)
    }
    /// A non-public endpoint is refused by default even before any redirect: being private is not an
    /// authorization (OPML imports and catalog rows are untrusted input). Nothing reaches the transport.
    func test07dPrivateEndpointWithoutAuthorizationRefused() async throws {
        for url in privateHosts {
            let t = ScriptedSyndicationTransport([hop()])
            do {
                _ = try await SyndicationHTTPClient(transport:t,redirectCapacity:2)
                    .fetch(endpoint:URL(string:url)!,checkpoint:SyndicationCheckpointCodec.empty,bodyByteCapacity:64)
                XCTFail("Expected refusal for \(url)")
            } catch { XCTAssertEqual(error as? SyndicationHTTPError,.nonPublicHost,url) }
            let journal = await t.journal(); XCTAssertTrue(journal.isEmpty,"must not contact \(url)")
        }
    }
    /// Only an explicit, internal opt-in (reachable from @testable tests, not from product composition)
    /// lets a controlled fixture use a private endpoint and redirect within it.
    func test07eExplicitControlledFixtureAuthorized() async throws {
        XCTAssertEqual(SyndicationHTTPClient(transport:ScriptedSyndicationTransport([]),redirectCapacity:0).hostAccess,.publicOnly)
        let t = ScriptedSyndicationTransport([hop(302,location:"/moved"),hop()])
        let outcome = try await SyndicationHTTPClient(transport:t,redirectCapacity:2,hostAccess:.controlledFixture)
            .fetch(endpoint:URL(string:"http://127.0.0.1:8080/feed")!,checkpoint:SyndicationCheckpointCodec.empty,bodyByteCapacity:64)
        guard case .document(let d) = outcome else { return XCTFail("Expected document") }
        XCTAssertEqual(d.redirectCount,1)
        let journal = await t.journal(); XCTAssertEqual(journal.last?.url?.absoluteString,"http://127.0.0.1:8080/moved")
    }
    /// Development/benchmark builds authorize exact non-public origins; nothing else in private space opens.
    func test07fAuthorizedOriginIsExactSchemeHostPort() throws {
        let origin = try XCTUnwrap(SyndicationAuthorizedOrigin(URL(string:"http://192.168.1.76:8757")!))
        XCTAssertEqual(origin.scheme,"http"); XCTAssertEqual(origin.host,"192.168.1.76"); XCTAssertEqual(origin.port,8757)
        XCTAssertEqual(SyndicationAuthorizedOrigin(URL(string:"https://bench.local/")!)?.port,443)
        XCTAssertEqual(SyndicationAuthorizedOrigin(URL(string:"http://127.0.0.1")!)?.port,80)
        // A public host needs no authorization; userinfo and non-HTTP schemes are never authorizable; an
        // authorization is an origin, so a path, query or fragment is refused rather than trimmed.
        for raw in ["https://example.test","http://user:pw@192.168.1.76:8757","ftp://192.168.1.76",
            "http://192.168.1.76:8757/bench/feed.xml","http://192.168.1.76:8757/?token=x","http://192.168.1.76:8757/#frag"] {
            XCTAssertNil(SyndicationAuthorizedOrigin(URL(string:raw)!),raw)
        }
        let access = SyndicationHostAccess(authorizedOrigins:[origin])
        XCTAssertTrue(access.permits(URL(string:"http://192.168.1.76:8757/other")!))
        XCTAssertTrue(access.permits(URL(string:"https://example.test/feed")!))
        for raw in ["http://192.168.1.76:8758/feed","https://192.168.1.76:8757/feed","http://192.168.1.77:8757/feed",
            "http://169.254.169.254/latest/meta-data/","http://127.0.0.1:8757/feed"] {
            XCTAssertFalse(access.permits(URL(string:raw)!),raw)
        }
        XCTAssertEqual(SyndicationHostAccess(authorizedOrigins:[]),.publicOnly)
    }
    /// An authorized benchmark origin can serve and redirect within itself, but a redirect from it to another
    /// private host (or another port) is refused before contact.
    func test07gAuthorizedOriginRedirects() async throws {
        let origin = try XCTUnwrap(SyndicationAuthorizedOrigin(URL(string:"http://192.168.1.76:8757")!))
        let endpoint = URL(string:"http://192.168.1.76:8757/feed")!
        let within = ScriptedSyndicationTransport([hop(302,location:"/moved"),hop()])
        let outcome = try await SyndicationHTTPClient(transport:within,redirectCapacity:2,hostAccess:.init(authorizedOrigins:[origin]))
            .fetch(endpoint:endpoint,checkpoint:SyndicationCheckpointCodec.empty,bodyByteCapacity:64)
        guard case .document = outcome else { return XCTFail("Expected document") }
        for escape in ["http://192.168.1.1/admin","http://192.168.1.76:22/","http://169.254.169.254/latest/meta-data/"] {
            let t = ScriptedSyndicationTransport([hop(302,location:escape),hop()])
            do {
                _ = try await SyndicationHTTPClient(transport:t,redirectCapacity:2,hostAccess:.init(authorizedOrigins:[origin]))
                    .fetch(endpoint:endpoint,checkpoint:SyndicationCheckpointCodec.empty,bodyByteCapacity:64)
                XCTFail("Expected refusal for \(escape)")
            } catch { XCTAssertEqual(error as? SyndicationHTTPError,.nonPublicHost,escape) }
            let journal = await t.journal(); XCTAssertEqual(journal.count,1,escape)
        }
    }
    func test08MissingLocation() async {
        for location in [nil,""] as [String?] { await failure(.init([hop(308,location:location)]),expected:.missingRedirectLocation(308)) }
    }
    func test09RedirectCapacity() async {
        let t = ScriptedSyndicationTransport([hop(302,location:"/next"),hop()])
        await failure(t,expected:.redirectCapacityExceeded(0),redirects:0)
        let journal = await t.journal(); XCTAssertEqual(journal.count,1)
    }
    func test10Redirected304Refused() async {
        await failure(.init([hop(303,location:"/next"),hop(304)]),expected:.notModifiedWithoutConditionalRequest,state:boundary)
    }
    func test11StatusStrictness() async {
        for status in [204,400,401,403,404,408,429,500,503] {
            let t = ScriptedSyndicationTransport([hop(status)])
            await failure(t,expected:.unexpectedStatus(status))
            let journal = await t.journal(); XCTAssertEqual(journal.count,1)
        }
    }
    func test12ByteLimitExact() async throws {
        let fixture = LocalSyndicationHTTPFixture(body:Data([1,2,3,4]))
        let session = fixture.session(); defer { session.invalidateAndCancel(); fixture.remove() }
        let hop = try await URLSessionSyndicationHTTPTransport(session:session).execute(URLRequest(url:fixture.url),bodyByteCapacity:4)
        XCTAssertEqual(hop.body,Data([1,2,3,4]))
    }
    func test13ByteLimitPlusOne() async {
        let fixture = LocalSyndicationHTTPFixture(body:Data([1,2,3,4,5]))
        let session = fixture.session(); defer { session.invalidateAndCancel(); fixture.remove() }
        do { _ = try await URLSessionSyndicationHTTPTransport(session:session).execute(URLRequest(url:fixture.url),bodyByteCapacity:4); XCTFail("Expected overflow") }
        catch { XCTAssertEqual(error as? SyndicationHTTPError,.bodyTooLarge(limit:4,actualAtLeast:5)) }
    }
    func test14PhysicalBoundStopsIncrementalBody() async throws {
        let fixture = LocalSyndicationHTTPFixture(body:Data([1,2]),incremental:true)
        let session = fixture.session(); defer { session.invalidateAndCancel(); fixture.remove() }
        let task = Task { try await URLSessionSyndicationHTTPTransport(session:session).execute(URLRequest(url:fixture.url),bodyByteCapacity:4) }
        var started = fixture.started.makeAsyncIterator(); _ = await started.next()
        fixture.emit(Data([3,4,5]))
        do { _ = try await task.value; XCTFail("Expected overflow") }
        catch { XCTAssertEqual(error as? SyndicationHTTPError,.bodyTooLarge(limit:4,actualAtLeast:5)) }
        var stopped = fixture.stopped.makeAsyncIterator(); _ = await stopped.next()
        XCTAssertFalse(fixture.emit(Data(repeating:9,count:100_000)))
        XCTAssertEqual(fixture.emittedByteCount,5)
    }
    func test15RealTransportDoesNotAutomaticallyRedirect() async throws {
        let fixture = LocalSyndicationHTTPFixture(body:Data(),status:302,redirect:true)
        let session = fixture.session(); defer { session.invalidateAndCancel(); fixture.remove() }
        let hop = try await URLSessionSyndicationHTTPTransport(session:session).execute(URLRequest(url:fixture.url),bodyByteCapacity:4)
        XCTAssertEqual(hop.statusCode,302); XCTAssertEqual(hop.location,"/next"); XCTAssertTrue(hop.body.isEmpty)
        XCTAssertEqual(fixture.startedCount,1)
    }
    func test16CancellationNormalization() async {
        for code in [URLError.cancelled,.notConnectedToInternet] {
            let fixture = LocalSyndicationHTTPFixture(body:Data(),error:URLError(code))
            let session = fixture.session(); defer { session.invalidateAndCancel(); fixture.remove() }
            do { _ = try await URLSessionSyndicationHTTPTransport(session:session).execute(URLRequest(url:fixture.url),bodyByteCapacity:4); XCTFail("Expected transport error") }
            catch {
                if code == .cancelled { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertEqual((error as? URLError)?.code,code) }
            }
        }
    }
}

// URLProtocol drives the actual production URLSession delegate, without internet or timing assumptions.
final class LocalSyndicationHTTPFixture: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String:LocalSyndicationHTTPFixture] = [:]
    let url = URL(string:"https://fixture-"+UUID().uuidString.lowercased()+".test/feed")!
    let body: Data
    let status: Int
    let incremental: Bool
    let redirect: Bool
    let error: URLError?
    let started: AsyncStream<Void>
    let stopped: AsyncStream<Void>
    private let startSignal: AsyncStream<Void>.Continuation
    private let stopSignal: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var loader: LocalSyndicationURLProtocol?
    private var didStop = false
    private var emitted = 0
    private var starts = 0
    init(body:Data,status:Int = 200,incremental:Bool = false,redirect:Bool = false,error:URLError? = nil) {
        self.body = body; self.status = status; self.incremental = incremental; self.redirect = redirect; self.error = error
        (started,startSignal) = AsyncStream.makeStream(); (stopped,stopSignal) = AsyncStream.makeStream()
        Self.registryLock.withLock { Self.registry[url.host!] = self }
    }
    static func find(_ url:URL?) -> LocalSyndicationHTTPFixture? { registryLock.withLock { registry[url?.host ?? ""] } }
    func remove() { _ = Self.registryLock.withLock { Self.registry.removeValue(forKey:url.host!) } }
    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [LocalSyndicationURLProtocol.self]
        return URLSession(configuration:configuration)
    }
    var emittedByteCount:Int { lock.withLock { emitted } }
    var startedCount:Int { lock.withLock { starts } }
    func start(_ loader:LocalSyndicationURLProtocol) {
        lock.withLock { self.loader = loader; starts += 1 }
        if let error { loader.client?.urlProtocol(loader,didFailWithError:error); startSignal.yield(()); return }
        let response = HTTPURLResponse(url:loader.request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:status == 302 ? ["Location":"/next"] : ["Content-Type":"application/rss+xml"])!
        if redirect {
            loader.client?.urlProtocol(loader,wasRedirectedTo:URLRequest(url:URL(string:"/next",relativeTo:loader.request.url)!.absoluteURL),redirectResponse:response)
            // A refused redirect leaves the original response available to the caller.
            loader.client?.urlProtocol(loader,didReceive:response,cacheStoragePolicy:.notAllowed)
            loader.client?.urlProtocolDidFinishLoading(loader)
        } else {
            loader.client?.urlProtocol(loader,didReceive:response,cacheStoragePolicy:.notAllowed)
            _ = emit(body)
            if !incremental { loader.client?.urlProtocolDidFinishLoading(loader) }
        }
        startSignal.yield(())
    }
    @discardableResult func emit(_ data:Data) -> Bool {
        let activeLoader: LocalSyndicationURLProtocol? = lock.withLock {
            guard !didStop, let current = self.loader else { return nil }
            emitted += data.count
            return current
        }
        guard let activeLoader else { return false }
        activeLoader.client?.urlProtocol(activeLoader,didLoad:data)
        return true
    }
    func stop() { lock.withLock { didStop = true }; stopSignal.yield(()) }
}
final class LocalSyndicationURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request:URLRequest) -> Bool { LocalSyndicationHTTPFixture.find(request.url) != nil }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() { LocalSyndicationHTTPFixture.find(request.url)?.start(self) }
    override func stopLoading() { LocalSyndicationHTTPFixture.find(request.url)?.stop() }
}

extension SyndicationHTTPTests {
    func test3R3CompletedFingerprintAllowsEachValidatorAnd304() async throws {
        for useETag in [true,false] {
            let state = SyndicationCheckpointState(etag:useETag ? "etag" : nil,lastModified:useETag ? nil : "date",
                documentFingerprint:"sha256:complete",nextItemIndex:0)!
            let transport = ScriptedSyndicationTransport([hop(304)])
            let client = SyndicationHTTPClient(transport:transport,redirectCapacity:0)
            guard case .notModified = try await client.fetch(endpoint:endpoint,checkpoint:state,bodyByteCapacity:100) else {
                return XCTFail("Completed fingerprint must not disable conditional requests")
            }
            let requests = await transport.journal(); XCTAssertEqual(requests.count,1)
            XCTAssertEqual(requests[0].value(forHTTPHeaderField:"If-None-Match"),state.etag)
            XCTAssertEqual(requests[0].value(forHTTPHeaderField:"If-Modified-Since"),state.lastModified)
        }
    }
}
