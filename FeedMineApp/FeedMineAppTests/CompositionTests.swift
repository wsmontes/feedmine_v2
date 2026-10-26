import XCTest
import Foundation
import UIKit
import Vision
import SwiftUI
import Synchronization
import CryptoKit
@testable import FeedMinePersistence
import FeedMineDomain
import FeedMineRuntime
import FeedMineUI
// `@testable` on purpose: the app smoke asserts the **effective** policy (`policyIncludingDiscovery`), which is
// what the drivers ask the acquisition snapshot for before a slice — and that is an internal of the module.
@testable import FeedMineComposition
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMine

// Controlled transport exists only in this test target; all admission and publication are real.
final class FixtureTransport: URLProtocol, @unchecked Sendable {
    static let rejecting = Mutex(false)
    static let holdingScience = Mutex(false)
    /// Counts science requests that actually entered the held gate. A test uses this handshake instead of a
    /// fixed sleep to know the activation reached the relevant Network boundary.
    static let scienceEntered = Mutex(0)
    /// Holds every request, for an activation whose launch may have nothing to ask the science endpoint.
    static let holdingAll = Mutex(false)
    static let allEntered = Mutex(0)
    /// U-reading: every request this transport answered. A test can therefore state that opening a card's reading
    /// makes none at all — which is what separates an explicit request for the site from the feed's own work.
    static let requests = Mutex<[String]>([])
    private final class HeldLoaders: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [FixtureTransport] = []
        func append(_ loader: FixtureTransport) { lock.lock(); defer { lock.unlock() }; values.append(loader) }
        func take() -> [FixtureTransport] { lock.lock(); defer { lock.unlock() }; let all = values; values = []; return all }
    }
    private static let held = HeldLoaders()
    static func releaseScience() {
        holdingScience.withLock { $0 = false }
        let loaders = held.take()
        loaders.forEach { $0.respond() }
    }

    static func releaseAll(failing: Bool = false) {
        holdingAll.withLock { $0 = false }
        let loaders = held.take()
        loaders.forEach { $0.respond(fail: failing) }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.rejecting.withLock({ $0 }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if Self.holdingAll.withLock({ $0 }) {
            Self.allEntered.withLock { $0 += 1 }
            Self.held.append(self)
            return
        }
        if Self.holdingScience.withLock({ $0 }), request.url?.path.contains("science") == true {
            Self.scienceEntered.withLock { $0 += 1 }
            Self.held.append(self)
            return
        }
        respond()
    }
    /// How many items a feed response carries, so one run can watch supply arrive **later**: a case lowers it
    /// before the launch and raises it afterwards, and the second publication brings stories the first could not.
    /// `nil` — the default, and what the case that raises it restores in its own `defer` — keeps every response
    /// byte-identical to `ReadingFixture.payload()`, item for item: `payload(for:)` is the same fixture document,
    /// and only a case that set a count gets a different number of items inside it.
    static let feedItemCount = Mutex<Int?>(nil)

    /// F-UX-2's positive control: the same transport answers with its channel and no stories, the way the app's
    /// own `FEEDMINE_EMPTY_FEEDS` instrument does on the device. A launch that finds nothing must not be
    /// mistaken for one that could not connect.
    static let answersWithNothing = Mutex(false)

    private static func payload(for url: URL?) -> (contentType: String, body: Data) {
        if answersWithNothing.withLock({ $0 }), url?.host()?.contains("bbci.co.uk") == true {
            let body = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Trusted fixture</title>"
                + "<link>https://fixture.invalid/</link><description>Integration</description></channel></rss>"
            return ("application/rss+xml", Data(body.utf8))
        }
        guard let count = feedItemCount.withLock({ $0 }), url?.host()?.contains("bbci.co.uk") == true else {
            return ReadingFixture.payload()
        }
        let items = (1...count).map {
            "<item><guid>fixture-\($0)</guid><title>Published fixture \($0)</title>"
                + "<link>https://fixture.invalid/story-\($0)</link>"
                + "<description>Readable local story \($0)</description></item>"
        }.joined()
        let body = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Trusted fixture</title>"
            + "<link>https://fixture.invalid/</link><description>Integration</description>\(items)</channel></rss>"
        return ("application/rss+xml", Data(body.utf8))
    }

    private func respond(fail: Bool = false) {
        if fail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        FixtureTransport.requests.withLock { $0.append(request.url?.absoluteString ?? "") }
        // The shape is the default (`shortSummary`) unless a test set another one, and the default payload is the
        // exact document this transport always served.
        let payload = FixtureTransport.payload(for: request.url)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": payload.contentType])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Standard-public-URL test transport. Manifest and declared OPML requests are intercepted;
/// unrelated RSS requests pass through FixtureTransport. Unlike FEEDMINE_CATALOGUE_AUTHORITY,
/// this exercises the release path.
final class StandardCatalogueTransport: URLProtocol, @unchecked Sendable {
    static let etag = "\"bundle-test\""
    static let manifest = Mutex<Data?>(nil)
    static let requests = Mutex<[String?]>([])
    struct PayloadObservation: Sendable {
        let requestedURL: String
        let relativePath: String
        let byteCount: Int?
        let sha256: String?
    }
    // Diagnostic evidence of *actual* fixture responses; this replaces the former path-only log.
    static let payloadObservations = Mutex<[PayloadObservation]>([])
    static let fallbackRequestOffset = Mutex(0)
    static let force304 = Mutex(false)
    static let payloads = Mutex<[String: Data]>([:])
    static let holdManifest = Mutex(false)
    // Keep held URLProtocol instances behind the same lock-owned wrapper as FixtureTransport.
    // Swift 6 does not allow transferring task-isolated self through Mutex's sending inout state.
    private final class HeldLoaders: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [StandardCatalogueTransport] = []
        func append(_ loader: StandardCatalogueTransport) {
            lock.lock(); defer { lock.unlock() }
            values.append(loader)
        }
        func take() -> [StandardCatalogueTransport] {
            lock.lock(); defer { lock.unlock() }
            let loaders = values
            values.removeAll()
            return loaders
        }
    }
    private static let held = HeldLoaders()

    static func prepare(_ data: Data, unsolicited304: Bool = false,
        payloads: [String: Data] = [:], paused: Bool = false) {
        manifest.withLock { $0 = data }
        requests.withLock { $0 = [] }
        payloadObservations.withLock { $0 = [] }
        let offset = FixtureTransport.requests.withLock { $0.count }
        fallbackRequestOffset.withLock { $0 = offset }
        force304.withLock { $0 = unsolicited304 }
        Self.payloads.withLock { $0 = payloads }
        holdManifest.withLock { $0 = paused }
        _ = held.take()
    }

    static func releaseManifest() {
        holdManifest.withLock { $0 = false }
        let loaders = held.take()
        loaders.forEach { $0.deliver() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        // deletingLastPathComponent() already ends in "/". Adding another slash here silently
        // sent every declared OPML to FixtureTransport (RSS bytes), making valid offers fail SHA-256.
        let payloadBase = CatalogUpdateChannel.publicManifestURL.deletingLastPathComponent()
        return url == CatalogUpdateChannel.publicManifestURL
            || (url.absoluteString.hasPrefix(payloadBase.absoluteString)
                && !Self.payloads.withLock { $0.isEmpty })
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url == CatalogUpdateChannel.publicManifestURL {
            let conditional = request.value(forHTTPHeaderField: "If-None-Match")
            Self.requests.withLock { $0.append(conditional) }
            if Self.holdManifest.withLock({ $0 }) {
                Self.held.append(self)
                return
            }
        }
        deliver()
    }

    private func deliver() {
        guard let url = request.url else { return }
        let isManifest = url == CatalogUpdateChannel.publicManifestURL
        let relative = String(url.path.dropFirst(
            CatalogUpdateChannel.publicManifestURL.deletingLastPathComponent().path.count + 1))
        let data = isManifest ? Self.manifest.withLock { $0 } : Self.payloads.withLock { $0[relative] }
        if !isManifest {
            let digest = data.map {
                SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
            }
            let observation = PayloadObservation(requestedURL: url.absoluteString,
                relativePath: relative, byteCount: data?.count, sha256: digest)
            Self.payloadObservations.withLock { $0.append(observation) }
        }
        guard let data else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let conditional = request.value(forHTTPHeaderField: "If-None-Match")
        let status = isManifest && (Self.force304.withLock { $0 } || conditional == Self.etag) ? 304 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: isManifest && status == 200 ? ["ETag": Self.etag] : [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status == 200 { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The one read of a profile's pool, held open so the test decides **when** it concludes. The composition awaits
/// a value, so the test owns both ends of that await — which is the only way to stage "the reader moved while the
/// pool was being read, and the old read concluded last" without a sleep, a timer or a retry loop. It is the same
/// kind of instrument the controlled transport already is: the product's own seam, answered by the test.
final class DiscoveryGate: @unchecked Sendable {
    /// What a read answers: the entries the catalogue offered, and the subject of each.
    struct Answer: @unchecked Sendable {
        let entries: [LegacyCatalogEntry]
        let subjects: [SourceID: AppComposition.EditorialSubject]
    }

    /// One read as it arrived at the composition: the profile it was for, and the box its answer goes in.
    final class Read: @unchecked Sendable {
        let profile: ReaderDiscoveryProfile
        private let lock = NSLock()
        private var waiting: CheckedContinuation<Answer, Never>?
        private var ready: Answer?
        fileprivate init(profile: ReaderDiscoveryProfile) { self.profile = profile }

        fileprivate func take() async -> Answer {
            await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
                var immediate: Answer?
                lock.withLock {
                    if let ready { immediate = ready; self.ready = nil } else { waiting = continuation }
                }
                if let immediate { continuation.resume(returning: immediate) }
            }
        }

        fileprivate func give(_ answer: Answer) {
            var parked: CheckedContinuation<Answer, Never>?
            lock.withLock {
                if let waiting { parked = waiting; self.waiting = nil } else { ready = answer }
            }
            parked?.resume(returning: answer)
        }
    }

    private let lock = NSLock()
    private var arrived: [Read] = []
    private var waiting: [CheckedContinuation<Read, Never>] = []

    /// The composition's replacement query.
    var query: AppComposition.DiscoveryQuery {
        { [self] profile, _ in
            let read = Read(profile: profile)
            var parked: CheckedContinuation<Read, Never>?
            lock.withLock {
                if waiting.isEmpty { arrived.append(read) } else { parked = waiting.removeFirst() }
            }
            parked?.resume(returning: read)
            let answer = await read.take()
            return (answer.entries, answer.subjects)
        }
    }

    /// The next read the composition started, in the order it happened.
    func nextRead() async -> Read {
        await withCheckedContinuation { (continuation: CheckedContinuation<Read, Never>) in
            var available: Read?
            lock.withLock {
                if arrived.isEmpty { waiting.append(continuation) } else { available = arrived.removeFirst() }
            }
            if let available { continuation.resume(returning: available) }
        }
    }

    /// A read that has already arrived, or nil. It never waits: a gated read whose continuation is parked can
    /// only be resumed by an answer, so a test that is done waiting must be able to walk away from it.
    func takeArrivedRead() -> Read? {
        lock.withLock { arrived.isEmpty ? nil : arrived.removeFirst() }
    }

    /// Answers one read, which resumes the composition at exactly that point.
    func answer(_ read: Read, entries: [LegacyCatalogEntry],
        subjects: [SourceID: AppComposition.EditorialSubject]) {
        read.give(Answer(entries: entries, subjects: subjects))
    }
}

/// R01's controlled clock: the instant the reader produced each fact is a value the test owns, so coalescing can be
/// proven **not** to turn the drain's own latency into reading velocity. Production passes the process uptime.
final class IngressClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double
    /// Every read advances the clock a little, like the process uptime it replaces: a controller that measures a
    /// slice's latency refuses a zero one, so a frozen clock would fail the launch for the wrong reason. The test
    /// still owns the **large** intervals (`advance`), which is what the consumption arithmetic reads.
    private let tick: Double
    init(seconds: Double = 1_000, tick: Double = 0.001) { self.seconds = seconds; self.tick = tick }
    func next() -> RunwayMonotonicTime {
        lock.lock(); defer { lock.unlock() }
        seconds += tick
        return RunwayMonotonicTime(seconds: seconds)!
    }
    func advance(_ delta: Double) { lock.lock(); defer { lock.unlock() }; seconds += delta }
}

/// R02's controlled storage seam: every durable bookmark read arrives here and the test decides **when** and
/// **what** it answers, so "installation performs no read" and "an older preparation cannot undo a confirmed
/// toggle" are staged without sleeps or retries.
final class BookmarkReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [CheckedContinuation<Set<PublicationCardID>, Never>] = []
    private var total = 0

    var read: @Sendable () async throws -> Set<PublicationCardID> {
        { [self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Set<PublicationCardID>, Never>) in
                lock.lock(); pending.append(continuation); total += 1; lock.unlock()
            }
        }
    }

    /// How many reads the product requested so far.
    var arrivals: Int { lock.lock(); defer { lock.unlock() }; return total }
    /// How many are waiting for an answer.
    var unanswered: Int { lock.lock(); defer { lock.unlock() }; return pending.count }

    func answer(_ ids: Set<PublicationCardID>) {
        lock.lock()
        let next = pending.isEmpty ? nil : pending.removeFirst()
        lock.unlock()
        next?.resume(returning: ids)
    }
}

@MainActor
final class CompositionTests: XCTestCase {

    private func root(requestTimeout: TimeInterval = 60, directory: URL? = nil,
        feeds: [TrustedFeed] = TrustedFeed.development,
        clock: IngressClock? = nil,
        bookmarkRead: (@Sendable () async throws -> Set<PublicationCardID>)? = nil) -> AppComposition {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = requestTimeout
        let now: @Sendable () -> RunwayMonotonicTime
        if let clock { now = { clock.next() } }
        else { now = { .init(seconds: ProcessInfo.processInfo.systemUptime)! } }
        return AppComposition(directory: directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            feeds: feeds, transportConfiguration: configuration, monotonicNow: now,
            bookmarkRead: bookmarkRead)
    }

    /// T1: exercise the real lifecycle and context composition around the existing owner.
    func testForegroundPreservesLearnedConsumptionAndContextChangeStartsFresh() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 64 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let root = root()
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let initial = try XCTUnwrap(association.store.state.presentation)
        XCTAssertGreaterThan(initial.window.items.count, 3)
        await association.viewport(.init(anchor: .init(cardID: initial.window.items[1].id, placement: .top)),
            activity: .forward)
        await association.viewport(.init(anchor: .init(cardID: initial.window.items[3].id, placement: .top)),
            activity: .forward)
        let runway = await association.driver.runway
        let learned = await runway.snapshot()
        XCTAssertGreaterThan(try XCTUnwrap(learned.consumption.cardsPerSecond), 0)

        await root.inactive()
        await root.background()
        await root.foreground()
        XCTAssertTrue(root.association === association)
        let resumed = await runway.snapshot()
        XCTAssertEqual(resumed.scope, learned.scope)
        XCTAssertEqual(resumed.consumption.cardsPerSecond, learned.consumption.cardsPerSecond)

        try await root.selectContext(.source(TrustedFeed.development[0].sourceID))
        let replacement = try XCTUnwrap(root.association)
        XCTAssertFalse(replacement === association)
        let replacementRunway = await replacement.driver.runway
        let fresh = await replacementRunway.snapshot()
        XCTAssertNotEqual(fresh.scope, learned.scope)
        XCTAssertNil(fresh.consumption.cardsPerSecond)
        await root.inactive()
        await replacement.close()
    }

    /// A real SQLite refusal installed for one test; no injected seam and no second architecture.
    private func trigger(_ statements: [String], in directory: URL) throws {
        let database = try RuntimeDatabase(location: .init(directory: directory))
        try database.write { db in for statement in statements { try db.execute(sql: statement) } }
    }

    private func dropTriggers(_ names: [String], in directory: URL) throws {
        let database = try RuntimeDatabase(location: .init(directory: directory))
        try database.write { db in for name in names { try db.execute(sql: "DROP TRIGGER " + name) } }
    }

    /// A canonical occurrence with no media candidates: enough to publish a card that declares media, so the
    /// saved preparation reaches its failure outcome without any network.
    private func admitOccurrence(in database: RuntimeDatabase, headline: String = "H",
        primaryLink: URL? = nil) throws -> (OriginRecordID, OriginRevisionID) {
        let origin = OriginRecordID(), revision = OriginRevisionID()
        let date = Date(timeIntervalSince1970: 100)
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "media",
                value: UUID().uuidString, role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: headline, summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil,
                observedAt: date, language: nil, primaryLink: primaryLink, searchProjection: nil,
                providerID: nil),
            mediaCandidates: [], availability: .available, observedAt: date, expectedCurrent: .none,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        return (origin, revision)
    }

    private func publishOccurrence(in database: RuntimeDatabase, origin: OriginRecordID,
        revision: OriginRevisionID, mediaKey: String) throws -> PublicationStore.CardRecord {
        let card = PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: origin,
            originRevisionID: revision, sourceID: nil, providerID: nil, sourceDisplayName: "Fonte",
            providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil, title: "Mídia salva",
            primaryText: " texto ", timestampValue: nil, timestampKind: nil, mediaKey: mediaKey,
            mediaPixelWidth: 2, mediaPixelHeight: 3, mediaMimeType: nil, renderLayout: "thumbnail",
            renderMediaAspectRatio: 2.0 / 3.0, primaryActionKind: "externalURL",
            primaryActionReference: "https://example.test/artigo")
        let editorial = EditorialRevision(id: EditorialRevisionID(), contextKey: ContextKey(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 1),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 1),
            sequencingPolicyVersion: PolicyVersion(rawValue: 2), exposurePolicyVersion: PolicyVersion(rawValue: 2),
            selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: editorial,
            publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date(timeIntervalSince1970: 10))
        let segment = PublicationStore.SegmentRecord(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
            segmentSeed: 1, publicationSchemaVersion: 1, createdAt: Date(timeIntervalSince1970: 11),
            cardIDs: [card.id])
        try PublicationStore(database: database).createEdition(edition, firstSegment: segment, cards: [card])
        return card
    }

    private func launched() async throws -> (AppComposition, FeedAssociation) {
        let root = root()
        await root.launch()
        XCTAssertNil(root.startupFailure)
        let association = try XCTUnwrap(root.association)
        XCTAssertNotNil(association.store.state.presentation, "Real cold acquisition must publish")
        return (root, association)
    }

    /// T2/T3: production and admission are separate, so a test that needs a window wider than the anchor card
    /// asks for it the way a reader does — production fills the reserve, then an explicit admission installs the
    /// next prefix. Reading the window right after `launch()` sees the anchor and nothing else, by contract.
    /// The activity is the discriminating input: `.explicitTailApproach` is the only one
    /// `RunwayActivity.admitsForwardContent` accepts, so `.forward` observes the position and never extends
    /// the admitted list. The anchor is the admitted tail, so the append lands after it.
    private func produceAndAdmit(_ association: FeedAssociation) async throws {
        _ = try await association.driver.drive(resources: association.resources)
        guard let anchor = association.store.state.presentation?.window.items.last else { return }
        await association.viewport(.init(anchor: .init(cardID: anchor.id, placement: .top)), activity: .explicitTailApproach)
    }

    #if DEBUG
    func testDevelopmentProxyBlocksActualRSSTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        DevelopmentNetworkBlock.apply(to: configuration)
        configuration.timeoutIntervalForRequest = 5
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        do {
            _ = try await transport.data(from: TrustedFeed.development[0].endpoint)
            XCTFail("The exact proxy configuration used by offline relaunch must block real RSS")
        } catch {
            let failure = error as NSError
            // CFNetworkErrors.h: kCFErrorHTTPSProxyConnectionFailure = 310.
            XCTAssertEqual(failure.domain, "kCFErrorDomainCFNetwork")
            XCTAssertEqual(failure.code, 310, "The closed HTTPS proxy must refuse the real connection")
        }
    }
    #endif

    func testEmptyLaunchRecoversAtForegroundAfterCooldownWithoutReplacingAssociation() async throws {
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let root = root(requestTimeout: 0.05)
        await root.launch()
        FixtureTransport.rejecting.withLock { $0 = false }
        let association = try XCTUnwrap(root.association)
        let store = association.store
        XCTAssertNil(store.state.presentation)
        // A foreground opportunity respects the same acquisition cooldown as autonomous retry.
        try await Task.sleep(for: .milliseconds(75))
        await root.foreground()
        // A scheduled cold retry may already own launch; wait for its real publication.
        for _ in 0..<200 where store.state.presentation == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(store.state.presentation)
        XCTAssertTrue(root.association === association)
        XCTAssertTrue(association.store === store)
        await association.close()
    }

    func testColdStartRecoversAutonomouslyWithoutGesture() async throws {
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let root = root(requestTimeout: 0.05)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        XCTAssertNil(association.store.state.presentation)
        FixtureTransport.rejecting.withLock { $0 = false }
        for _ in 0..<200 where association.store.state.presentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(association.store.state.presentation)
        XCTAssertTrue(root.association === association)
        await association.close()
    }

    func testBackgroundCancelsColdRetryUntilForeground() async throws {
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let root = root(requestTimeout: 0.05)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        await root.background()
        FixtureTransport.rejecting.withLock { $0 = false }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(association.store.state.presentation)
        await root.foreground()
        for _ in 0..<200 where association.store.state.presentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(association.store.state.presentation)
        await association.close()
    }

    /// F-UX-2: a **fresh install** whose transport cannot reach a source tells the reader that, not that there
    /// are no stories. The controlled transport answers every request with `URLError(.notConnectedToInternet)` —
    /// what URLSession reports on a device with no connection, and the error the connector states as
    /// `ConnectorOperationalFailure.transport` — so the first acquisition settles without publication and the
    /// transports that settled are the evidence. Nothing here reads supply absence back as connectivity.
    func testOfflineFirstLaunchStatesConnectivityNotNoStories() async throws {
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let root = root(requestTimeout: 5)
        await root.launch()
        XCTAssertNil(root.startupFailure, "the connection failure is an outcome, not a thrown launch failure")
        let association = try XCTUnwrap(root.association)
        XCTAssertNil(association.store.state.presentation)
        XCTAssertEqual(association.store.state.work, .unreachable)
        XCTAssertNotEqual(association.store.state.work, .unavailable,
            "an unreachable source is never the absence of stories")
        await association.close()
    }

    /// F-UX-2's positive control, on the same fresh install: a source that answers with no stories is the empty
    /// state, and it keeps the two actions it owns. A change that reported every absence as unreachable fails here.
    func testFirstLaunchWithAnEmptySourceStillStatesNoStories() async throws {
        FixtureTransport.answersWithNothing.withLock { $0 = true }
        defer { FixtureTransport.answersWithNothing.withLock { $0 = false } }
        let root = root(requestTimeout: 5)
        await root.launch()
        XCTAssertNil(root.startupFailure)
        let association = try XCTUnwrap(root.association)
        XCTAssertNil(association.store.state.presentation)
        XCTAssertEqual(association.store.state.work, .unavailable)
        XCTAssertNotEqual(association.store.state.work, .unreachable)
        await association.close()
    }

    /// B03: the first installed screen must seed and drive the runway while cold acquisition is still pending.
    /// This uses the association's real evidence recipient, without a viewport event or foreground timer.
    func testFirstPresentationDrivesRunwayBeforeHeldBootstrapFinishes() async throws {
        FixtureTransport.holdingScience.withLock { $0 = true }
        defer { FixtureTransport.releaseScience() }
        let root = root()
        let launch = Task { await root.launch() }
        for _ in 0..<500 where root.association?.store.state.presentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let association = try XCTUnwrap(root.association)
        let first = try XCTUnwrap(association.store.state.presentation)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        var observed = await association.driver.runway.snapshot()
        while observed.lastCoverage == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            observed = await association.driver.runway.snapshot()
        }
        XCTAssertTrue(FixtureTransport.holdingScience.withLock { $0 }, "bootstrap still has a held source")
        XCTAssertEqual(observed.latestObservation?.anchorCardID, first.window.anchor.cardID)
        XCTAssertEqual(observed.latestObservation?.activity, .stationary)
        XCTAssertNotNil(observed.lastCoverage, "the first presentation must reach observation → drive within 1 s")
        FixtureTransport.releaseScience()
        await launch.value
        XCTAssertNil(root.startupFailure, "late bootstrap settlement must not replay an obsolete projection")
        let current = await association.session.currentPresentation()
        XCTAssertEqual(association.store.state.presentation, current)
        await association.close()
    }

    func testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates() async throws {
        FixtureTransport.holdingScience.withLock { $0 = true }
        defer { FixtureTransport.releaseScience() }
        let root = root()
        let launch = Task { await root.launch() }
        for _ in 0..<200 where root.association?.store.state.presentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let first = root.association?.store.state.presentation
        XCTAssertEqual(first?.window.items.count, 1, "One PD-4-valid fast card is visible while the other feed is suspended")
        XCTAssertEqual(first?.window.items.first?.sourceDisplayName, "BBC World")
        FixtureTransport.releaseScience()
        await launch.value
        let association = try XCTUnwrap(root.association)
        try await produceAndAdmit(association)
        let window = try XCTUnwrap(association.store.state.presentation).window
        let cards = window.items
        // O que a reserva promete é o **teto à frente da âncora** (`FeedPresentationBounds.forwardCapacity`), não um
        // total: `keepsAdmittedHead` preserva toda carta acima do leitor, e é a própria sessão que recorta a cauda
        // (`FeedSession.swift:233-235`, `last = min(items.count - 1, anchorIndex + forwardCapacity)`) — nenhuma
        // chegada consegue pôr mais de 16 cartas à frente. O total depende de quanta antecipação de consumo a lane
        // já admitiu quando a janela é lida, e antecipar é o que a diretiva (linha 86) manda o runtime fazer.
        // Ver CompositionTests:1768 ("o total não é mais limitado") e CONTINUOUS_FEED_RUNWAY_DESIGN.md §18, emenda
        // de 2026-10-15: a demanda nasce do déficit medido, e a pressão lógica — sem contagem — segue o mesmo
        // critério de oportunidade.
        let anchorIndex = try XCTUnwrap(cards.firstIndex { $0.id == window.anchor.cardID },
            "a âncora do leitor tem de estar na janela")
        XCTAssertLessThanOrEqual(cards.count - anchorIndex - 1, 16,
            "a reserva à frente da âncora não passa de dezesseis cartas")
        XCTAssertGreaterThanOrEqual(cards.count, 17,
            "a apresentação admite a âncora e a reserva de dezesseis cartas do bootstrap")
        for (left, right) in zip(cards, cards.dropFirst()) {
            XCTAssertNotEqual(left.sourceDisplayName, right.sourceDisplayName)
        }
        await association.close()
    }

    /// P0 (fiação): o suprimento durável que a fonte lenta admite **depois** da primeira Edição tem de reabrir a
    /// caminhada local que o primeiro drive declarou esgotada. A ordem é forçada, não sorteada: a fonte lenta fica
    /// retida até `RunwayController.localSupplyExhausted` — o estado que hoje latcheia — e só então é liberada. O
    /// vermelho medido antes da correção é a janela parada em 1 carta (7 de 7 execuções isoladas, `:647`).
    ///
    /// O que este caso mede é *suprimento reabre a fatia*: nenhum gesto, nenhum refresh, nenhum `foreground()`.
    /// Os 17 são lidos da apresentação admitida, depois do fato; nenhuma espera aqui ordena a chegada.
    func testHeldDurableSupplyReopensTheExhaustedWalkAndFillsTheReserveWithoutAGesture() async throws {
        FixtureTransport.holdingScience.withLock { $0 = true }
        defer { FixtureTransport.releaseScience() }
        let root = root()
        let launch = Task { await root.launch() }
        for _ in 0..<200 where root.association?.store.state.presentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let association = try XCTUnwrap(root.association)
        let first = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(first.window.items.count, 1,
            "premissa: com uma fonte pronta, PD-4 publica a âncora e nada mais")
        let published = PublicationStore(database: association.database)
        func publishedAroundAnchor() throws -> [PublicationCardID] {
            try published.cards(editionID: first.editionID, around: first.window.anchor.cardID,
                backwardCapacity: 0, forwardCapacity: 400).map(\.id)
        }
        // A premissa do caso: a caminhada local já se declarou esgotada **enquanto** a fonte lenta está retida.
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var exhausted = await association.driver.runway.snapshot().localSupplyExhausted
        while !exhausted, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            exhausted = await association.driver.runway.snapshot().localSupplyExhausted
        }
        XCTAssertTrue(exhausted,
            "premissa: a caminhada local tem de se declarar esgotada com a fonte lenta ainda retida")
        XCTAssertTrue(FixtureTransport.holdingScience.withLock { $0 },
            "premissa: a fonte lenta ainda está retida — o fato medido é a chegada dela, não uma corrida")
        XCTAssertEqual(try publishedAroundAnchor().count, 1,
            "premissa: nada além da âncora foi publicado antes da chegada")

        FixtureTransport.releaseScience()
        await launch.value
        let grew = await Self.waitUntil(30) {
            (association.store.state.presentation?.window.items.count ?? 0) >= 17
        }
        let window = try XCTUnwrap(association.store.state.presentation).window
        let publishedCards = try publishedAroundAnchor()
        XCTAssertTrue(grew,
            "o suprimento durável que a fonte lenta admitiu depois da primeira Edição tem de reabrir a fatia local: "
                + "a janela admitida ficou em \(window.items.count) cartas e a edição carrega "
                + "\(publishedCards.count) publicadas — "
                + root.diagnosticsForTheWiringTest(association))
        let anchorIndex = try XCTUnwrap(window.items.firstIndex { $0.id == window.anchor.cardID },
            "a âncora do leitor tem de estar na janela")
        XCTAssertLessThanOrEqual(window.items.count - anchorIndex - 1, association.bounds.forwardCapacity,
            "o crescimento não passa do teto congelado à frente da âncora")
        for (left, right) in zip(window.items, window.items.dropFirst()) {
            XCTAssertNotEqual(left.sourceDisplayName, right.sourceDisplayName,
                "PD-4: a reserva reaberta alterna as duas fontes")
        }
        await association.close()
    }

    /// Controle da mesma fiação: com a fonte lenta retida o run inteiro, a única resposta honesta é **uma** carta.
    /// Nenhum caminho pode inventar alternância para chegar a 17 — e nada cresce só porque o tempo passou.
    func testAFeedHeldForTheWholeRunPublishesOneHonestCardAndNeverInventsAlternation() async throws {
        FixtureTransport.holdingScience.withLock { $0 = true }
        defer { FixtureTransport.releaseScience() }
        let root = root()
        let launch = Task { await root.launch() }
        for _ in 0..<200 where root.association?.store.state.presentation == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let association = try XCTUnwrap(root.association)
        let first = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(first.window.items.count, 1,
            "PD-4: uma fonte pronta publica a âncora e nada mais")
        XCTAssertEqual(first.window.items.first?.sourceDisplayName, "BBC World")
        let published = PublicationStore(database: association.database)
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var snapshot = await association.driver.runway.snapshot()
        while !snapshot.localSupplyExhausted, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            snapshot = await association.driver.runway.snapshot()
        }
        XCTAssertTrue(snapshot.localSupplyExhausted,
            "com a fonte lenta retida, a caminhada local tem de se declarar esgotada")
        // A metade negativa: tempo decorrido não publica nem cresce a janela.
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(association.store.state.presentation?.window.items.count, 1,
            "nada cresce a janela por tempo: a fonte lenta ainda está retida")
        XCTAssertEqual(try published.cards(editionID: first.editionID, around: first.window.anchor.cardID,
            backwardCapacity: 0, forwardCapacity: 400).count, 1,
            "nada publica além da âncora sem o suprimento que a segunda fonte traria")
        FixtureTransport.releaseScience()
        await launch.value
        await association.close()
    }

    /// R6-E — a publicação legitimamente concluída depois da janela antiga tem de fazer a apresentação crescer
    /// sozinha. O caso nasceu vermelho e é a regressão do gate: o crescimento tem de seguir o **fato da publicação**,
    /// não o relógio.
    ///
    /// A janela antiga era a cadeia de polling que `AppComposition.swift` carregava (1 consulta imediata + 8 de
    /// 0,75 s, isto é **6,0 s**, rearmada no fim do `launch()`, no `.settled` de uma fonte que trouxe suprimento e na
    /// primeira edição publicada). Ela já não existe: o crescimento passou a ser disparado pelo **recibo do segmento**
    /// que o `FeedRunwayDriver` entrega no `runLocalSlice` que o concluiu (`onPublication`), pela publicação do
    /// próprio cold bootstrap e pelas duas oportunidades do leitor (`viewport`, `foreground`).
    ///
    /// A espera de **8,0 s** continua sendo o que prova a metade negativa deste caso: passado todo o tempo que a
    /// janela antiga levava para se esgotar, **nada** cresce a janela enquanto nada publica — nenhum caminho cresce a
    /// janela por tempo decorrido.
    ///
    /// O que ele faz é o caminho do próprio produto: libera a **segunda publicação** por
    /// `driver.submitViewport(activity: .explicitTailApproach)` — a oportunidade que o leitor oferece ao chegar à
    /// cauda admitida e pedir mais — na mesma chamada que a associação faz (`FeedPresentationHandoff.submitViewport`)
    /// e **sem** o `growAdmittedWindowIfPublished()` que a associação executa depois dela. É essa omissão que separa
    /// as duas metades: as cartas novas só podem aparecer pelo recibo do segmento que o dreno entrega, e o caso
    /// afirma que a janela ainda era a antiga **no instante em que o recibo chegou**.
    ///
    /// A ativação da pista (`activateCurrentPresentation`) não serve como instrumento, e a medição de 2026-10-17
    /// explica por quê: ela reenvia a posição como `stationary`, e a medição seguinte registra **0 cartas/s**; com
    /// taxa medida zero e nenhum sinal de cauda, `RunwayPolicy` responde `healthy` e a pista corretamente **não**
    /// repõe nada — o leitor está parado e a reserva de 3 cartas diante dele não é um déficit. O transporte
    /// controlado serve dois itens por fonte antes da espera e vinte e quatro depois, então a primeira publicação
    /// não enche a janela (4 cartas de 17 possíveis, pelo teto congelado) e a segunda publica cartas novas na
    /// reserva da mesma edição.
    ///
    /// Estratégia de espera, declarada: `Task.sleep` **só** para atravessar a janela antiga, que é o objeto do caso,
    /// e uma observação limitada a 3,0 s (a `waitUntil` deste arquivo) para o valor admitido mudar — nenhum timer
    /// como correção. Os dois fatos que o determinismo exige são afirmados, nunca supostos: (a) a publicação tem de
    /// chegar à reserva, lida no `PublicationStore` antes e depois, com a falha dizendo que a **premissa** não valeu;
    /// e (b) nenhum prazo derivado de fato pode disparar um `foreground()` no meio da medida — com o transporte
    /// saudável `localRetryEligibleAt()` e `acquisitionResumeAt()` são nulos, e é isso que o caso afirma antes de
    /// medir, em vez de supor (é o `scheduleLocalRetryIfNeeded`).
    func testAPublicationConcludedAfterTheFollowUpWindowGrowsTheAdmittedWindow() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 2 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let publication = PublicationStore(database: association.database)
        let editionID = try XCTUnwrap(association.store.state.presentation).editionID
        let anchor = try XCTUnwrap(association.store.state.presentation).window.anchor.cardID
        func admitted() -> [PublicationCardID] {
            association.store.state.presentation?.window.items.map(\.id) ?? []
        }
        /// O que a reserva já publicou **além da âncora**, lido do store: é a premissa do caso.
        func reservedAhead() throws -> Int {
            try publication.cards(editionID: editionID, around: anchor, backwardCapacity: 0,
                forwardCapacity: 400).count - 1
        }
        let before = admitted()
        let reservedBefore = try reservedAhead()
        let anchorIndex = try XCTUnwrap(before.firstIndex(of: anchor), "a âncora do leitor tem de estar na janela")
        let ceiling = anchorIndex + association.bounds.forwardCapacity + 1
        XCTAssertLessThan(before.count, ceiling,
            "premissa: a janela admitida tem de ter espaço dentro do teto congelado — cheia, o crescimento seria impossível por outra razão")

        // A janela antiga inteira, e mais margem: aqui ela prova que nenhum tempo cresce a janela.
        try await Task.sleep(for: .seconds(8))
        XCTAssertEqual(admitted(), before,
            "premissa: nada pode crescer a janela admitida nesta espera — nenhum caminho cresce a janela por tempo decorrido, e a reserva estava inteiramente admitida")
        XCTAssertEqual(try reservedAhead(), reservedBefore,
            "premissa: a reserva tem de estar quieta durante a espera — nada publicou neste intervalo")
        let localRetryDeadline = await association.driver.localRetryEligibleAt()
        let acquisitionResumeDeadline = await association.driver.acquisitionResumeAt()
        XCTAssertNil(localRetryDeadline,
            "premissa: com o transporte saudável não há prazo de retry local para disparar um foreground() na medida")
        XCTAssertNil(acquisitionResumeDeadline, "premissa: nem uma aquisição adiada para retomar")

        /// O que o pool canônico já admitiu — a resposta do transporte vira suprimento aqui, antes de publicar.
        func admittedCandidates() throws -> Int {
            try ContentStore(database: association.database)
                .candidateWindow(sourceID: nil, after: nil, examinedCapacity: 500).records.count
        }
        func interceptedRequests() -> [String] {
            FixtureTransport.requests.withLock { $0.filter { $0.contains("bbci.co.uk") } }
        }
        let candidatesBefore = try admittedCandidates()
        XCTAssertEqual(candidatesBefore, 4,
            "premissa: o transporte serviu dois itens por fonte e os quatro candidatos estão no pool canônico")

        // O recibo, retido no destinatário: é ele o fato medido. O que a janela valia **na chegada** do recibo
        // separa o crescimento causado por ele de um crescimento anterior.
        var receipts: [PublicationReceipt] = []
        var admittedWhenReceiptArrived: [Int] = []
        let recipient = association.publicationRelay.receive
        association.publicationRelay.receive = { receipt in
            receipts.append(receipt)
            admittedWhenReceiptArrived.append(association.store.state.presentation?.window.items.count ?? -1)
            await recipient?(receipt)
        }

        // A segunda publicação: mais itens por fonte e a oportunidade de cauda do leitor, pela mesma chamada do
        // driver que a associação faz — e sem o `growAdmittedWindowIfPublished()` que a acompanha.
        let requestsBefore = interceptedRequests()
        FixtureTransport.feedItemCount.withLock { $0 = 24 }
        _ = try await association.driver.submitViewport(
            .init(anchor: .init(cardID: anchor, placement: .top)), activity: .explicitTailApproach,
            resources: association.resources)

        // (1) A segunda resposta é outra: as fontes foram consultadas de novo, depois da resposta de dois itens.
        // Quantas vezes é do dreno, não do caso — o que a premissa exige é que a segunda resposta tenha sido
        // buscada, e o pool abaixo é a prova de que ela trouxe suprimento.
        XCTAssertGreaterThan(interceptedRequests().count, requestsBefore.count,
            "premissa: a oportunidade de cauda tem de consultar as fontes depois da resposta de dois itens")
        // (2) Os candidatos novos foram admitidos ao pool canônico antes de qualquer carta publicada.
        XCTAssertGreaterThan(try admittedCandidates(), candidatesBefore,
            "premissa: a segunda resposta tinha de trazer candidatos novos, e eles foram admitidos")
        // (3) A publicação concluiu: o segmento existe e o recibo chegou ao destinatário.
        let reservedAfter = try reservedAhead()
        XCTAssertGreaterThan(reservedAfter, reservedBefore,
            "premissa: a segunda publicação tem de chegar à reserva da edição \(editionID.rawValue.uuidString): "
                + "cartas além da âncora \(reservedBefore) -> \(reservedAfter). Esta falha é a premissa, não o defeito do R6-E")
        XCTAssertGreaterThan(try publication.segments(editionID: editionID).count, 1,
            "premissa: a segunda publicação tem de existir como segmento durável antes da asserção visual")
        XCTAssertFalse(receipts.isEmpty,
            "premissa: o recibo da segunda publicação tem de chegar ao destinatário da edição vigente")
        XCTAssertEqual(Set(receipts.map(\.editionID)), [editionID],
            "premissa: todos os recibos da medida identificam a edição vigente")
        // (4) O crescimento segue o recibo: o **primeiro** recibo encontrou a janela ainda antiga, e foi a entrega
        // dele que a fez crescer. Um crescimento anterior à publicação tornaria esta lista diferente de `before`.
        XCTAssertEqual(admittedWhenReceiptArrived.first, before.count,
            "o crescimento não pode anteceder o recibo — o primeiro recibo tinha de encontrar a janela antiga, "
                + "e encontrou \(String(describing: admittedWhenReceiptArrived.first)) cartas")
        _ = await Self.waitUntil(3) { admitted().count > before.count }
        XCTAssertGreaterThan(admitted().count, before.count,
            "uma publicação concluída depois da janela antiga (6,0 s) tem de crescer a janela admitida sem gesto: "
                + "a reserva foi de \(reservedBefore) para \(reservedAfter) cartas além da âncora e a janela admitida "
                + "ficou em \(admitted().count) cartas (antes: \(before.count), teto: \(ceiling)) — "
                + root.diagnosticsForTheWiringTest(association))
        XCTAssertEqual(Array(admitted().prefix(before.count)), before,
            "o crescimento só anexa cartas já publicadas — a lista admitida anterior é preservada, na ordem")
        await association.close()
    }

    /// R6-E, a cerca do **destinatário**: um recibo de edição **superada** não admite na edição vigente.
    ///
    /// O dreno valida o recibo quando conclui a fatia (`FeedRunwayDriver`: `intent.scope == scope` e
    /// `session.currentRunwayScope() == scope`), mas existe uma suspensão entre essa validação e a entrega ao host.
    /// E `admitPublishedGrowth()` opera sobre a **edição instalada**, não sobre a edição que o recibo identifica
    /// (lê `current.presentation.editionID`): a validação do produtor não substitui a verificação do destinatário,
    /// porque um recibo de edição superada entregue depois do movimento admitiria na edição vigente cartas que só a
    /// publicação dela autoriza.
    ///
    /// O vinco usado é o que existe: o `PublicationRelay` por onde o dreno entrega, cujo receptor é
    /// `publicationConcluded` — o destinatário, **lido** aqui e em nenhum momento reescrito por política. O caso,
    /// em ordem:
    ///
    /// 1. **Retém** o recibo real de uma segunda publicação da edição que o leitor vai deixar (o mecanismo da
    ///    R6-E: mais itens por fonte e a oportunidade de cauda do leitor, que é o que conclui a fatia no dreno). É a suspensão
    ///    nomeada, instanciada: a fatia concluiu, o recibo existe, e ainda não chegou ao host.
    /// 2. **Move o leitor** por um caminho do produto — `selectContext` — de modo que a edição acima fica superada
    ///    (a associação que a carregava está retirada) e a vigente é outra.
    /// 3. **Publica na edição vigente e retém o recibo dela.** Sem esta retenção o recibo obsoleto não teria o que
    ///    admitir: toda admissão deixa a janela no teto congelado ou com toda a reserva já admitida, de modo que só
    ///    uma publicação **sem fato de crescimento** abre espaço — e a publicação cujo recibo está retido é
    ///    exatamente isso. A R6-E é a outra metade: com o recibo entregue, a janela cresce.
    /// 4. **Entrega** o recibo obsoleto ao mesmo destinatário, por um instrumento que só registra e encaminha — a
    ///    política exercitada é a do produto.
    ///
    /// As premissas são afirmadas antes de medir, como na R6-E: a publicação tem de chegar à reserva (lida no
    /// `PublicationStore` antes e depois), a janela admitida não pode ter crescido enquanto o recibo dela estava
    /// retido, e nenhum prazo derivado de fato pode disparar um `foreground()` na medida — com o transporte
    /// saudável `localRetryEligibleAt()` e `acquisitionResumeAt()` são nulos (`scheduleLocalRetryIfNeeded`).
    func testAReceiptForASupersededEditionDoesNotGrowTheCurrentEditionsWindow() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 2 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        let superseded = try XCTUnwrap(root.association)
        let supersededEdition = try XCTUnwrap(superseded.store.state.presentation).editionID

        // 1. O recibo da edição que o leitor vai deixar, retido na entrega real do dreno. O acréscimo é modesto
        //    de propósito: os itens que ele traz ficam no `ContentStore`, que é **um só** para o diretório, e a
        //    edição vigente do passo 2 nasce dessa mesma oferta local — com vinte e quatro itens por fonte ela
        //    nasceria já no teto congelado e não sobraria espaço para o caso medir nada.
        var leftBehind: [PublicationReceipt] = []
        superseded.publicationRelay.receive = { leftBehind.append($0) }
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        let supersededAnchor = try XCTUnwrap(superseded.store.state.presentation).window.anchor.cardID
        _ = try await superseded.driver.submitViewport(
            .init(anchor: .init(cardID: supersededAnchor, placement: .top)), activity: .explicitTailApproach,
            resources: superseded.resources)
        let stale = try XCTUnwrap(leftBehind.first,
            "premissa: a segunda publicação da edição que o leitor vai deixar tem de entregar um recibo")
        XCTAssertTrue(leftBehind.allSatisfy { $0.editionID == supersededEdition },
            "premissa: os recibos retidos identificam a edição \(supersededEdition.rawValue.uuidString)")

        // 2. O leitor muda de contexto: a edição acima fica superada, e a vigente é outra.
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        try await root.selectContext(.source(TrustedFeed.development[0].sourceID))
        let live = try XCTUnwrap(root.association)
        XCTAssertTrue(root.association === live)
        XCTAssertFalse(live === superseded)
        XCTAssertFalse(superseded.active, "premissa: a associação que carregava a edição superada está retirada")
        let liveEdition = try XCTUnwrap(live.store.state.presentation).editionID
        XCTAssertNotEqual(liveEdition, supersededEdition,
            "premissa: a edição vigente tem de ser outra — o recibo obsoleto identifica a que o leitor deixou")

        let publication = PublicationStore(database: live.database)
        let anchor = try XCTUnwrap(live.store.state.presentation).window.anchor.cardID
        func admitted() -> [PublicationCardID] {
            live.store.state.presentation?.window.items.map(\.id) ?? []
        }
        /// O que a reserva já publicou **além da âncora**, lido do store: é a premissa do caso.
        func reservedAhead() throws -> Int {
            try publication.cards(editionID: liveEdition, around: anchor, backwardCapacity: 0,
                forwardCapacity: 400).count - 1
        }
        let before = admitted()
        let reservedBefore = try reservedAhead()
        let anchorIndex = try XCTUnwrap(before.firstIndex(of: anchor), "a âncora do leitor tem de estar na janela")
        let ceiling = anchorIndex + live.bounds.forwardCapacity + 1
        XCTAssertLessThan(before.count, ceiling,
            "premissa: a janela admitida tem de ter espaço dentro do teto congelado — cheia, a admissão seria impossível por outra razão")

        // 3. A publicação da edição vigente, com o recibo dela retido: publicada, ainda não admitida.
        let recipient = live.publicationRelay.receive
        var currentEditionReceipts: [PublicationReceipt] = []
        live.publicationRelay.receive = { currentEditionReceipts.append($0) }
        FixtureTransport.feedItemCount.withLock { $0 = 24 }
        _ = try await live.driver.submitViewport(
            .init(anchor: .init(cardID: anchor, placement: .top)), activity: .explicitTailApproach,
            resources: live.resources)
        XCTAssertFalse(currentEditionReceipts.isEmpty,
            "premissa: a segunda publicação da edição vigente tem de concluir e entregar um recibo")
        XCTAssertTrue(currentEditionReceipts.allSatisfy { $0.editionID == liveEdition },
            "premissa: os recibos retidos identificam a edição vigente \(liveEdition.rawValue.uuidString)")
        let reservedAfter = try reservedAhead()
        XCTAssertGreaterThan(reservedAfter, reservedBefore,
            "premissa: a segunda publicação da edição vigente tem de chegar à reserva: cartas além da âncora \(reservedBefore) -> \(reservedAfter)")
        XCTAssertEqual(admitted(), before,
            "premissa: com o recibo da edição vigente retido, nada cresce a janela admitida")
        let localRetryDeadline = await live.driver.localRetryEligibleAt()
        let acquisitionResumeDeadline = await live.driver.acquisitionResumeAt()
        XCTAssertNil(localRetryDeadline,
            "premissa: com o transporte saudável não há prazo de retry local para disparar um foreground() na medida")
        XCTAssertNil(acquisitionResumeDeadline, "premissa: nem uma aquisição adiada para retomar")

        // 4. A entrega do recibo obsoleto: o destinatário do produto decide; o instrumento só observa.
        var delivered: [PublicationReceipt] = []
        live.publicationRelay.receive = { receipt in
            delivered.append(receipt)
            await recipient?(receipt)
        }
        await live.publicationRelay.deliver(stale)
        XCTAssertEqual(delivered.map(\.editionID), [supersededEdition],
            "premissa: o recibo obsoleto tem de ser entregue ao destinatário da edição vigente — a falha seguinte é do defeito, não da entrega")
        XCTAssertEqual(admitted(), before,
            "um recibo de edição superada (\(supersededEdition.rawValue.uuidString)) não pode admitir na edição "
                + "vigente (\(liveEdition.rawValue.uuidString)): a reserva foi de \(reservedBefore) para "
                + "\(reservedAfter) cartas além da âncora e a janela admitida ficou em \(admitted().count) cartas "
                + "(antes: \(before.count), teto: \(ceiling)) — \(root.diagnosticsForTheWiringTest(live))")
        await live.close()
    }

    // MARK: - R20: atomic catalogue activation

    /// The durable identity and the opened session are one outcome. A rebuild that throws after the key was
    /// written must not leave the reader on a context whose session never opened: the previous identity returns in
    /// memory and in the preferences, and the caller still receives the failure.
    func testFailedActivationLeavesThePreviousContextAndKeyIntact() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 6 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        let before = root.currentContextKey
        func durableKey() throws -> ContextKey? {
            try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
                .load()?.activeContextKey
        }
        XCTAssertEqual(try durableKey(), before, "premissa: a chave da base está durável")

        let search = try XCTUnwrap(SearchContext(query: "clima"))
        let victim = ContextKey(request: .search(search))
        struct ActivationRefused: Error {}
        root.beforeBuildingSession = { key in if key == victim { throw ActivationRefused() } }
        do {
            try await root.activateSavedPreset(victim)
            XCTFail("uma transição que não abriu a sessão não pode se declarar concluída")
        } catch is ActivationRefused {}

        XCTAssertEqual(root.currentContextKey, before, "a identidade anterior volta em memória")
        XCTAssertEqual(try durableKey(), before, "e a chave durável volta com ela")
        let restored = try XCTUnwrap(root.association)
        XCTAssertEqual(restored.contextKey, before, "a sessão anterior foi reaberta, não deixada em nil")
        XCTAssertNil(root.startupFailure)

        // The seam is a failure injector only: with it clear, the same transition succeeds.
        root.beforeBuildingSession = nil
        try await root.activateSavedPreset(victim)
        XCTAssertEqual(root.currentContextKey, victim)
        XCTAssertEqual(try XCTUnwrap(root.association).contextKey, victim)
        await root.association?.close()
    }

    // MARK: - R19: honest source and site actions

    /// "Ver fonte" opens the source's **internal context**; it never presents the source's website, and the
    /// reader's position in the previous context is restored by its own checkpoint on the way back.
    func testViewSourceOpensInternalSourceContext() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let presentation = try XCTUnwrap(association.store.state.presentation)
        let card = try XCTUnwrap(presentation.window.items.first?.id)
        let record = try XCTUnwrap(PublicationStore(database: association.database).card(id: card))
        let sourceID = try XCTUnwrap(record.sourceID, "premissa: a carta declara a fonte")
        let origin = root.currentContextKey
        let anchor = presentation.window.anchor
        var opened: [URL] = []
        root.onExternalURL = { opened.append($0) }

        association.perform(.viewSource, cardID: card)
        let switched = await Self.waitUntil(5) {
            if case .source(sourceID) = root.currentContextKey.request { return true }
            return false
        }
        XCTAssertTrue(switched, "Ver fonte abre o contexto interno da fonte")
        XCTAssertTrue(opened.isEmpty, "Ver fonte não abre o site da fonte")

        // Back to the previous context: its own checkpoint restores the promised position. The switch the card
        // action started may still be settling — a concurrent switch is refused by contract
        // (`ReaderContextSwitchError.inProgress`) and its end is not observable from here — so ask again until it
        // accepts. What is asserted below is unchanged.
        var returned = false
        let returnDeadline = Date().addingTimeInterval(10)
        while Date() < returnDeadline, !returned {
            do {
                try await root.selectContext(origin.request)
                returned = true
            } catch ReaderContextSwitchError.inProgress {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        XCTAssertTrue(returned, "o contexto de origem volta a ser alcançável depois da troca")
        let back = try XCTUnwrap(root.association)
        XCTAssertEqual(back.store.state.presentation?.window.anchor, anchor)
        XCTAssertEqual(back.store.state.presentation?.editionID, presentation.editionID)
        await back.close()
    }

    /// The explicit website action is the card's declared link — a different action from "Ver fonte".
    func testExplicitWebsiteActionOpensDeclaredURL() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let card = try XCTUnwrap(association.store.state.presentation?.window.items.first?.id)
        let record = try XCTUnwrap(PublicationStore(database: association.database).card(id: card))
        let declared = try XCTUnwrap(record.primaryActionReference.flatMap(URL.init(string:)))
        var opened: [URL] = []
        root.onExternalURL = { opened.append($0) }
        association.perform(.open, cardID: card)
        let delivered = await Self.waitUntil(5) { !opened.isEmpty }
        XCTAssertTrue(delivered)
        XCTAssertEqual(opened, [declared], "a ação de site abre exatamente o link declarado")
        await association.close()
    }

    // MARK: - R18: first experience

    /// A refused welcome write must not claim the reader has met the app: the flag is the only durable fact that
    /// closes the first-run gate, and a later launch reads it.
    func testWelcomePersistenceFailureDoesNotClaimCompletedOnboarding() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 4 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        XCTAssertTrue(root.needsOnboarding, "premissa: uma instalação nova ainda não viu o app")

        try trigger(["""
            CREATE TRIGGER welcome_boundary_reject_settings
            BEFORE UPDATE ON reader_preferences
            WHEN NEW.settings IS NOT OLD.settings
            BEGIN SELECT RAISE(ABORT, 'welcome boundary: settings write refused'); END;
            """], in: directory)
        XCTAssertFalse(root.completeOnboarding(), "a recusa tem de ser devolvida ao chamador")
        XCTAssertTrue(root.needsOnboarding, "a primeira execução não pode ser declarada concluída sem o registro")

        try dropTriggers(["welcome_boundary_reject_settings"], in: directory)
        XCTAssertTrue(root.completeOnboarding())
        XCTAssertFalse(root.needsOnboarding)
        // A later launch reads the durable flag, not this process's memory.
        let relaunched = self.root(directory: directory)
        XCTAssertFalse(relaunched.needsOnboarding)
    }

    // MARK: - R16: unified local search scopes

    /// Each scope returns only its own real result kinds, computed from the authorities that own them: sources from
    /// the catalogue, saved occurrences from the reader's bookmarks, articles from canonical local content. A
    /// scope never presents results it did not query.
    func testSearchScopesReturnOnlyTheirRealResultKinds() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let card = try XCTUnwrap(association.store.state.presentation?.window.items.first?.id)
        try PublicationStore(database: association.database).toggleBookmark(cardID: card,
            in: ReaderBookmarkList.defaultID, at: Date())

        let contentsValue = await root.unifiedSearch("Published", scope: .contents, token: 1)
        let contents = try XCTUnwrap(contentsValue)
        XCTAssertTrue(contents.sources.isEmpty, "conteúdo não devolve fontes")
        XCTAssertTrue(contents.all.allSatisfy { $0.kind == .saved || $0.kind == .article },
            "só os tipos reais do escopo de conteúdo")
        XCTAssertTrue(contents.saved.contains { $0.destination == .savedCard(card) },
            "o salvo aparece com a ocorrência real")
        XCTAssertFalse(contents.articles.isEmpty, "o artigo local aparece")

        let sourcesValue = await root.unifiedSearch("Published", scope: .sources, token: 2)
        let sources = try XCTUnwrap(sourcesValue)
        XCTAssertTrue(sources.saved.isEmpty && sources.articles.isEmpty,
            "o escopo de fontes não devolve conteúdo")
        XCTAssertTrue(sources.all.allSatisfy { $0.kind == .source })

        let bothValue = await root.unifiedSearch("Published", scope: .both, token: 3)
        let both = try XCTUnwrap(bothValue)
        var expected: Set<ReaderSearchResultKind> = [.saved, .article]
        if !both.sources.isEmpty { expected.insert(.source) }
        XCTAssertEqual(Set(both.all.map(\.kind)), expected)
        await association.close()
    }

    /// A suspended completion for an older term/scope cannot replace a newer search at the surface.
    func testStaleSearchCompletionCannotReplaceNewScope() async throws {
        let store = ReaderSearchResultsStore()
        let old = store.begin()
        let current = store.begin()
        let stale = ReaderSearchResults(query: "old", scope: .sources, token: old,
            sources: [ReaderSearchResult(id: "s", kind: .source, title: "velho", subtitle: nil,
                destination: .source(principal: "x", sourceID: nil))], saved: [], articles: [])
        XCTAssertFalse(store.apply(stale), "uma conclusão antiga não substitui a busca nova")
        XCTAssertNil(store.results)
        let fresh = ReaderSearchResults(query: "new", scope: .contents, token: current,
            sources: [], saved: [], articles: [ReaderSearchResult(id: "a", kind: .article, title: "novo",
                subtitle: nil, destination: .article(cardID: nil, originRecordID: OriginRecordID()))])
        XCTAssertTrue(store.apply(fresh))
        XCTAssertEqual(store.results?.query, "new")
        XCTAssertEqual(store.results?.scope, .contents)
    }

    /// A saved search states the expression and the scope in its durable key; reopening it offline runs the same
    /// search over local authorities (no network is consulted by `unifiedSearch`).
    func testSavedSearchReopensWithSameExpressionAndScopeOffline() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 30 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let expression = "fixture -19"
        let search = try XCTUnwrap(SearchContext(query: expression))
        let key = ContextKey(request: .search(search), searchScope: .contents)
        let json = try XCTUnwrap(key.canonicalJSON())
        let reopened = try XCTUnwrap(ContextKey.fromCanonicalJSON(json))
        XCTAssertEqual(reopened, key, "a expressão e o escopo voltam idênticos do registro durável")
        XCTAssertEqual(reopened.request, .search(search))
        XCTAssertEqual(reopened.searchScope, .contents)

        // Offline: the local authorities answer; no request is made by the search itself. The expression the
        // durable key carries is the one executed — an existing test round-tripped the negative but searched only
        // the positive term, so the exclusion was never proven end to end.
        let before = FixtureTransport.requests.withLock { $0.count }
        let resultsValue = await root.unifiedSearch(expression, scope: .contents, token: 1)
        let results = try XCTUnwrap(resultsValue)
        XCTAssertEqual(FixtureTransport.requests.withLock { $0.count }, before,
            "a busca local não faz aquisição")
        XCTAssertFalse(results.articles.isEmpty, "o conteúdo local responde offline")
        XCTAssertTrue(results.articles.contains { $0.title.contains("Published fixture 11") },
            "o termo positivo encontra os artigos; títulos \(results.articles.prefix(6).map(\.title))")
        XCTAssertFalse(results.articles.contains { $0.title.contains("Published fixture 19") },
            "o termo negado exclui o artigo a que se refere")
        await association.close()
    }

    /// P07/A7: a matching article beyond the first 400-candidate window is reachable through the continuation the
    /// result states. The first page is not presented as the whole universe.
    func testLocalMatchBeyondFirst400IsReachable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let store = ContentStore(database: database)
        // The needle is the **oldest** occurrence, so the newest-first 400-row window does not contain it.
        for index in 0..<450 {
            let date = Date(timeIntervalSince1970: Double(index) + 1)
            let origin = OriginRecordID(), revision = OriginRevisionID()
            try store.commitCanonicalChange(.init(recordID: origin,
                externalObjectIdentity: .init(connectorKind: .syndication, namespace: "p07",
                    value: UUID().uuidString, role: .object),
                revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                    headline: index == 0 ? "needle story" : "filler \(index)", summary: nil, bodyText: nil,
                    authoredAt: date, modifiedAt: nil, observedAt: date, language: nil, primaryLink: nil,
                    searchProjection: nil, providerID: nil),
                mediaCandidates: [], availability: .available, observedAt: date,
                expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        }
        let expression = try XCTUnwrap(SearchExpression(query: "needle"))
        let first = await ReaderLocalSearch.run(expression: expression, scope: .contents, token: 1,
            database: database, catalogueURL: nil, feeds: [])
        XCTAssertTrue(first.articles.isEmpty, "a primeira janela não contém o resultado antigo")
        let continuation = try XCTUnwrap(first.articleContinuation,
            "a janela truncada declara a continuação em vez de um universo completo")
        let second = await ReaderLocalSearch.run(expression: expression, scope: .contents, token: 2,
            database: database, catalogueURL: nil, feeds: [], articleAfter: continuation)
        XCTAssertEqual(second.articles.count, 1)
        XCTAssertEqual(second.articles.first?.title, "needle story")
    }

    /// P07/E07: the **host's** continuation serves the next article page. The test above proves the reader
    /// (`ReaderLocalSearch.run(articleAfter:)`); this one goes through `AppComposition.unifiedSearch(articleAfter:)`,
    /// which is what the surface calls when the reader asks for more.
    func testUnifiedSearchHostContinuationServesTheNextArticlePage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let store = ContentStore(database: database)
        for index in 0..<450 {
            let date = Date(timeIntervalSince1970: Double(index) + 1)
            let origin = OriginRecordID(), revision = OriginRevisionID()
            try store.commitCanonicalChange(.init(recordID: origin,
                externalObjectIdentity: .init(connectorKind: .syndication, namespace: "p07-host",
                    value: UUID().uuidString, role: .object),
                revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                    headline: index == 0 ? "needle story" : "filler \(index)", summary: nil, bodyText: nil,
                    authoredAt: date, modifiedAt: nil, observedAt: date, language: nil, primaryLink: nil,
                    searchProjection: nil, providerID: nil),
                mediaCandidates: [], availability: .available, observedAt: date,
                expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        }
        let root = root(directory: directory)
        await root.launch()
        let firstValue = await root.unifiedSearch("needle", scope: .contents, token: 1)
        let first = try XCTUnwrap(firstValue)
        XCTAssertFalse(first.articles.contains { $0.title == "needle story" },
            "a primeira página não contém o resultado mais antigo")
        let continuation = try XCTUnwrap(first.articleContinuation,
            "a página truncada declara a continuação")
        let secondValue = await root.unifiedSearch("needle", scope: .contents, token: 2,
            articleAfter: continuation)
        let second = try XCTUnwrap(secondValue)
        XCTAssertTrue(second.articles.contains { $0.title == "needle story" },
            "o host serve a página seguinte com o resultado antigo")
        await root.association?.close()
    }

    /// P07/E07: the host's **source** page advances too. The first page declares truncation; page 1 returns a
    /// disjoint set of sources from the shipped catalogue instead of repeating the first page.
    func testUnifiedSearchHostSourcePageServesADisjointNextPage() async throws {
        let (root, association) = try await launched()
        let firstValue = await root.unifiedSearch("news", scope: .sources, token: 1)
        let first = try XCTUnwrap(firstValue)
        XCTAssertEqual(first.sources.count, 40, "a página é a declarada pelo host")
        XCTAssertTrue(first.sourceTruncated, "o universo continua além da primeira página")
        let secondValue = await root.unifiedSearch("news", scope: .sources, token: 2, sourcePage: 1)
        let second = try XCTUnwrap(secondValue)
        XCTAssertFalse(second.sources.isEmpty, "a segunda página existe")
        XCTAssertTrue(Set(first.sources.map(\.id)).isDisjoint(with: Set(second.sources.map(\.id))),
            "a continuação não repete a primeira página")
        await association.close()
    }

    /// P07/E07: when the saved authority cannot be read, the failure is named and the content authority still
    /// answers in the same page. An empty saved section is not evidence of absence.
    func testSearchSavedAuthorityFailureIsExplicitAndContentStillAnswers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        // Remove the authority's table after launch: the next saved read fails for real, not by injection.
        let database = try RuntimeDatabase(location: .init(directory: directory))
        try database.write { db in
            try db.execute(sql: "DROP TABLE reader_bookmark_memberships")
        }
        let value = await root.unifiedSearch("fixture", scope: .both, token: 1)
        let results = try XCTUnwrap(value)
        XCTAssertTrue(results.failedAuthorities.contains(.saved),
            "a autoridade de salvos que não pode ser lida é uma falha nomeada")
        XCTAssertTrue(results.hasFailure)
        XCTAssertFalse(results.articles.isEmpty, "a autoridade de conteúdo responde na mesma página")
        await root.association?.close()
    }

    /// P07/E07: the content authority's failure is named too (the saved authority is the sibling case above).
    func testSearchContentAuthorityFailureIsExplicit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        // The content authority reads `selection_supply` first; removing that table makes its read fail for real,
        // without touching the published rows the rest of the session relies on.
        let database = try RuntimeDatabase(location: .init(directory: directory))
        try database.write { db in
            try db.execute(sql: "DROP TABLE selection_supply")
        }
        let value = await root.unifiedSearch("fixture", scope: .contents, token: 1)
        let results = try XCTUnwrap(value)
        XCTAssertTrue(results.failedAuthorities.contains(.content),
            "a autoridade de conteúdo que não pode ser lida é uma falha nomeada")
        XCTAssertTrue(results.hasFailure)
        await root.association?.close()
    }

    /// A context request that arrives while a replacement is still running cannot start. The composition states
    /// that truthfully (`contextSwitchInProgress`) so the control is presented as busy and disabled, and it refuses
    /// the request instead of silently accepting it. This unit proves only that contract: the attribution of the
    /// 235621Z benchmark tap to the `replacingSession` guard remains a hypothesis, never a reproduction claim.
    func testAContextRequestDuringAReplacementIsRefusedAsBusy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        XCTAssertNil(root.startupFailure)
        let science = try XCTUnwrap(TrustedFeed.development.first { $0.principal == "bbc-science" })
        XCTAssertTrue(root.feeds.contains { $0.sourceID == science.sourceID },
            "the source is part of this reader's selection")
        XCTAssertFalse(root.contextSwitchInProgress, "an idle reader is not replacing anything")
        let previous = try XCTUnwrap(root.association)

        // The science feed's answer is held, so the source transition stays inside its launch: the same window a
        // reader's tap can land in while the header is already usable.
        FixtureTransport.holdingScience.withLock { $0 = true }
        defer { FixtureTransport.releaseScience() }
        let finished = Mutex(false)
        let transition = Task {
            defer { finished.withLock { $0 = true } }
            try await root.selectContext(.source(science.sourceID))
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(root.contextSwitchInProgress
            && root.currentContextKey.request == .source(science.sourceID)) { await Task.yield() }
        XCTAssertTrue(root.contextSwitchInProgress, "a running replacement states its own readiness")
        XCTAssertEqual(root.currentContextKey.request, .source(science.sourceID),
            "the in-flight transition committed the destination it was asked for")
        XCTAssertFalse(finished.withLock { $0 }, "the first transition is still in flight")

        // The control is disabled while busy; a request that still arrives is refused, never silently accepted.
        do {
            try await root.selectContext(.main)
            XCTFail("a context request during a replacement is refused as busy")
        } catch {
            XCTAssertEqual(error as? ReaderContextSwitchError, .inProgress)
        }
        XCTAssertTrue(root.contextSwitchInProgress, "the refusal did not disturb the running replacement")
        XCTAssertEqual(root.currentContextKey.request, .source(science.sourceID),
            "the refused request did not replace the in-flight destination")

        FixtureTransport.releaseScience()
        _ = try? await transition.value
        XCTAssertFalse(root.contextSwitchInProgress, "readiness clears when the replacement finishes")

        // The live association is the one the accepted replacement built, and the previous one is inactive.
        let sourceLive = try XCTUnwrap(root.association)
        XCTAssertEqual(sourceLive.contextKey, root.currentContextKey)
        XCTAssertEqual(root.currentContextKey.request, .source(science.sourceID))
        XCTAssertFalse(previous.active, "the replaced association is inactive")

        // Once the replacement finished, the control is actionable again and the reader's choice is honoured.
        try await root.selectContext(.main)
        XCTAssertEqual(root.currentContextKey.request, .main)
        let mainLive = try XCTUnwrap(root.association)
        XCTAssertEqual(mainLive.contextKey, root.currentContextKey)
        XCTAssertFalse(sourceLive.active, "the previous source association is inactive")
        await mainLive.close()
    }

    /// The replacement guard must not silently swallow a source toggle either. While a replacement owns the
    /// session the toggle is refused with the same busy error, the selection and the committed destination stay
    /// as they were, and after completion the same toggle runs.
    func testASourceToggleDuringAReplacementIsRefusedAsBusy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        XCTAssertNil(root.startupFailure)
        let science = try XCTUnwrap(TrustedFeed.development.first { $0.principal == "bbc-science" })
        let other = try XCTUnwrap(TrustedFeed.development.first { $0.sourceID != science.sourceID })
        let selectionBefore = root.feeds.map(\.principal).sorted()

        FixtureTransport.holdingScience.withLock { $0 = true }
        defer { FixtureTransport.releaseScience() }
        let transition = Task { try await root.selectContext(.source(science.sourceID)) }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(root.contextSwitchInProgress
            && root.currentContextKey.request == .source(science.sourceID)) { await Task.yield() }
        XCTAssertTrue(root.contextSwitchInProgress, "a running replacement states its own readiness")

        do {
            try await root.toggleSource(other.sourceID)
            XCTFail("a source toggle during a replacement is refused as busy")
        } catch {
            XCTAssertEqual(error as? ReaderContextSwitchError, .inProgress)
        }
        XCTAssertEqual(root.feeds.map(\.principal).sorted(), selectionBefore,
            "the refused toggle did not change the reader's selection")
        XCTAssertEqual(root.currentContextKey.request, .source(science.sourceID),
            "the refused toggle did not disturb the in-flight destination")

        FixtureTransport.releaseScience()
        _ = try? await transition.value
        XCTAssertFalse(root.contextSwitchInProgress, "readiness clears when the replacement finishes")

        // Enabled after completion: the same toggle now runs instead of refusing. As in the selection test, the
        // catalogue choices are refreshed the way the product's own selection surface does.
        try await root.searchSources("")
        try await root.toggleSource(other.sourceID)
        await root.association?.close()
    }

    /// P08/E07: opening a search result goes through the destination its authority named. A source destination
    /// moves the reader to that source's context, not to a copy of the list.
    func testOpeningASourceSearchResultSelectsThatSourceContext() async throws {
        let (root, association) = try await launched()
        let feed = TrustedFeed.development[0]
        association.onSearchResult?(ReaderSearchResult(id: "source:" + feed.principal, kind: .source,
            title: feed.displayName, subtitle: nil, destination: .source(principal: feed.principal,
                sourceID: feed.sourceID)))
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, root.currentContextKey.request != .source(feed.sourceID) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(root.currentContextKey.request, .source(feed.sourceID),
            "o destino da fonte abre o contexto daquela fonte")
        await association.close()
    }

    /// P07/A7: an authority that cannot be read is an explicit failure, never an empty result. The other
    /// authority still answers in the same page.
    func testSearchFailureIsNotEmptyResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let date = Date(timeIntervalSince1970: 10)
        let origin = OriginRecordID(), revision = OriginRevisionID()
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "p07",
                value: UUID().uuidString, role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "comet story", summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil,
                observedAt: date, language: nil, primaryLink: nil, searchProjection: nil, providerID: nil),
            mediaCandidates: [], availability: .available, observedAt: date,
            expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))

        // A file that is not a catalogue: the reader's source authority cannot answer.
        let badCatalogue = directory.appendingPathComponent("not-a-catalogue.sqlite")
        try Data("not sqlite".utf8).write(to: badCatalogue)
        let expression = try XCTUnwrap(SearchExpression(query: "comet"))
        let result = await ReaderLocalSearch.run(expression: expression, scope: .both, token: 1,
            database: database, catalogueURL: badCatalogue, feeds: [])
        XCTAssertEqual(result.failedAuthorities, [.catalogue])
        XCTAssertTrue(result.hasFailure)
        XCTAssertFalse(result.articles.isEmpty, "a autoridade de conteúdo ainda responde")

        let absent = await ReaderLocalSearch.run(
            expression: try XCTUnwrap(SearchExpression(query: "absent")), scope: .both, token: 2,
            database: database, catalogueURL: badCatalogue, feeds: [])
        XCTAssertTrue(absent.isEmpty)
        XCTAssertTrue(absent.hasFailure, "vazio com falha não é prova de ausência")
    }

    /// P08: the reader's own search bar reaches the product surface. Submitting installs a real typed page from the
    /// local authorities into the (rebuilt) search association's store.
    func testReaderSearchShowsRealTypedSections() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let card = try XCTUnwrap(association.store.state.presentation?.window.items.first?.id)
        try PublicationStore(database: association.database).toggleBookmark(cardID: card,
            in: ReaderBookmarkList.defaultID, at: Date())
        association.store.submitSearch("Published")
        let ready = await Self.waitUntil(10) {
            guard let search = root.association?.store.searchResults else { return false }
            return !search.saved.isEmpty && !search.articles.isEmpty
        }
        XCTAssertTrue(ready, "a barra real instala a página tipada das autoridades locais")
        let results = try XCTUnwrap(root.association?.store.searchResults)
        XCTAssertEqual(results.scope, .both)
        XCTAssertTrue(results.saved.contains { $0.destination == .savedCard(card) })
        XCTAssertFalse(root.association?.store.isSearchingResults ?? true)

        // The destinations the search names are executed by the host, not just labelled in the page.
        var reading: FeedReadingContent?
        root.onReading = { target in if case .local(let content) = target { reading = content } }
        var externalURL: URL?
        root.onExternalURL = { url in externalURL = url }
        let savedResult = try XCTUnwrap(results.saved.first { result in
            if case .savedCard = result.destination { return true }
            return false
        })
        root.association?.store.selectSearchResult(savedResult)
        let openedSaved = await Self.waitUntil(10) { reading != nil || externalURL != nil }
        XCTAssertTrue(openedSaved, "o destino .savedCard abre o leitor pelo dono de salvos")

        // An occurrence with no published card: the article destination must resolve the revision's own link.
        let link = try XCTUnwrap(URL(string: "https://example.test/external-needle"))
        _ = try admitOccurrence(in: association.database, headline: "external needle", primaryLink: link)
        externalURL = nil
        let articlePage = await root.unifiedSearch("needle", scope: .contents, token: 99)
        let unpublished = try XCTUnwrap(articlePage?.articles.first { result in
            if case .article(cardID: nil, originRecordID: _) = result.destination { return true }
            return false
        })
        root.association?.store.selectSearchResult(unpublished)
        let openedArticle = await Self.waitUntil(10) { externalURL != nil }
        XCTAssertTrue(openedArticle, "o destino .article sem carta local abre o link da revisão, não um vazio")
        XCTAssertEqual(externalURL, link)
        await root.association?.close()
    }

    /// P08: a newer term/scope invalidates an older completion at the surface; it can never replace the page.
    @MainActor
    func testNewTermOrScopeRejectsStaleUICompletion() {
        let store = FeedScreenStore { _, _ in }
        let first = store.beginUnifiedSearch(term: "astro", scope: .both)
        let old = ReaderSearchResults(query: "astro", scope: .both, token: first,
            sources: [], saved: [], articles: [])
        XCTAssertTrue(store.applyUnifiedSearch(old))
        let second = store.beginUnifiedSearch(term: "astro", scope: .sources)
        XCTAssertTrue(store.applyUnifiedSearch(old) == false, "uma conclusão do termo/escopo anterior não entra")
        XCTAssertTrue(store.isSearchingResults)
        let fresh = ReaderSearchResults(query: "astro", scope: .sources, token: second,
            sources: [], saved: [], articles: [])
        XCTAssertTrue(store.applyUnifiedSearch(fresh))
        XCTAssertEqual(store.searchResults?.scope, .sources)
    }

    /// P08/P07: a saved search reopens offline with the same scope, and the launch installs its results without a
    /// new submission.
    func testSavedSearchReopensOfflineInSameScope() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = root(directory: directory)
        await first.launch()
        try await first.submitSearch("Published")
        let key = first.currentContextKey
        XCTAssertEqual(key.searchScope, .both, "sem escopo explícito, a busca usa o todo (normalizado na chave)")
        await first.association?.close()

        let second = root(directory: directory)
        await second.launch()
        let reopened = await Self.waitUntil(10) { second.association?.store.searchResults != nil }
        XCTAssertTrue(reopened, "o contexto de busca durável abre já com os resultados locais")
        XCTAssertEqual(second.currentContextKey, key)
        XCTAssertEqual(second.association?.store.searchResults?.scope, key.searchScope ?? .both)
        await second.association?.close()
    }

    // MARK: - R15: search origin, cancel and recoverable outcomes

    /// Cancelling a search returns to the **exact** previous context: the same preset/filter key and the anchor the
    /// origin's own checkpoint promised (the search session's retirement checkpointed the origin before closing).
    func testCancelSearchRestoresExactPreviousContextAndAnchor() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 16 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let origin = root.currentContextKey
        let edition = association.store.state.presentation?.editionID
        let anchor = association.store.state.presentation?.window.anchor

        try await root.submitSearch("Published")
        guard case .search = root.currentContextKey.request else {
            return XCTFail("premissa: a busca é o contexto vigente")
        }
        XCTAssertFalse(root.association === association, "a busca tem a própria associação")

        await root.cancelSearch()
        XCTAssertEqual(root.currentContextKey, origin, "o contexto anterior é restaurado inteiro")
        let back = try XCTUnwrap(root.association)
        XCTAssertEqual(back.store.state.presentation?.editionID, edition,
            "a edição canônica do contexto anterior é a mesma")
        XCTAssertEqual(back.store.state.presentation?.window.anchor, anchor,
            "a âncora prometida vem do checkpoint do contexto anterior")
        await back.close()
    }

    /// A search that fails **before** the durable write is not saved; a failure **after** it is saved but not
    /// presented. The two outcomes are different, and the durable key states which one happened.
    func testSavedSearchFailureDistinguishesWriteFromActivation() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        let before = root.currentContextKey
        func durableKey() throws -> ContextKey? {
            try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
                .load()?.activeContextKey
        }

        // A refused context write: nothing is saved, nothing changes.
        try trigger(["""
            CREATE TRIGGER search_boundary_reject_context
            BEFORE UPDATE ON reader_preferences
            WHEN NEW.active_context IS NOT OLD.active_context
            BEGIN SELECT RAISE(ABORT, 'search boundary: context write refused'); END;
            """], in: directory)
        do {
            try await root.submitSearch("Published")
            XCTFail("a refused write must not be reported as saved")
        } catch {
            XCTAssertEqual((error as? ReaderSearchFailure)?.selectionIsSaved, false)
        }
        XCTAssertEqual(root.currentContextKey, before)
        XCTAssertEqual(try durableKey(), before)
        try dropTriggers(["search_boundary_reject_context"], in: directory)

        // A refused retirement checkpoint: the key is durable, the presentation did not happen.
        try trigger(["""
            CREATE TRIGGER search_boundary_reject_checkpoint
            BEFORE INSERT ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'search boundary: checkpoint write refused'); END;
            """, """
            CREATE TRIGGER search_boundary_reject_checkpoint_update
            BEFORE UPDATE ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'search boundary: checkpoint write refused'); END;
            """], in: directory)
        do {
            try await root.submitSearch("Published")
            XCTFail("a failed activation after confirmation must be reported, never hidden")
        } catch {
            XCTAssertEqual((error as? ReaderSearchFailure)?.selectionIsSaved, true)
        }
        guard case .search = root.currentContextKey.request else {
            return XCTFail("a confirmação durável continua identificada")
        }
        XCTAssertEqual(try durableKey(), root.currentContextKey,
            "a busca confirmada é a chave durável, mesmo sem apresentação")
        try dropTriggers(["search_boundary_reject_checkpoint", "search_boundary_reject_checkpoint_update"],
            in: directory)

        // Retrying the same intention presents it; the key is not duplicated.
        try await root.submitSearch("Published")
        XCTAssertEqual(try durableKey(), root.currentContextKey)
        await root.association?.close()
    }

    /// R15/P2: changing the search scope is a durable context confirmation. A refused write leaves the context and
    /// the surface where they were, and the reader sees the failure instead of a scope that was never saved.
    func testRefusedScopeWriteKeepsTheSearchAndSurfacesTheFailure() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        try await root.submitSearch("Published")
        let association = try XCTUnwrap(root.association)
        let token = association.store.beginUnifiedSearch(term: "Published", scope: .both)
        let page = ReaderSearchResults(query: "Published", scope: .both, token: token,
            sources: [], saved: [], articles: [])
        XCTAssertTrue(association.store.applyUnifiedSearch(page))
        let before = root.currentContextKey
        func durableKey() throws -> ContextKey? {
            try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
                .load()?.activeContextKey
        }

        try trigger(["""
            CREATE TRIGGER search_scope_reject_context
            BEFORE UPDATE ON reader_preferences
            WHEN NEW.active_context IS NOT OLD.active_context
            BEGIN SELECT RAISE(ABORT, 'search scope: context write refused'); END;
            """], in: directory)
        association.store.setSearchScope(.sources)

        let surfaced = await Self.waitUntil(5) {
            association.store.toast?.text == String(localized: "Não foi possível salvar a busca")
        }
        XCTAssertTrue(surfaced, "a recusa da escrita durável é visível ao leitor")
        XCTAssertEqual(root.currentContextKey, before, "o contexto não muda sem confirmação durável")
        XCTAssertEqual(try durableKey(), before, "a chave durável também não muda")
        XCTAssertEqual(association.store.searchScope, .both, "a superfície volta ao escopo que o contexto tem")
        XCTAssertEqual(association.store.searchResults?.scope, .both, "a página apresentada não foi trocada")
        try dropTriggers(["search_scope_reject_context"], in: directory)

        // The same intention can be retried once the write is durable again.
        association.store.setSearchScope(.sources)
        let changed = await Self.waitUntil(20) { root.currentContextKey.searchScope == .sources }
        XCTAssertTrue(changed, "a intenção repetida, agora com escrita durável, muda o contexto")
        await root.association?.close()
    }

    /// P2: a saved-media preparation whose durable write is refused reaches the reader — the row states failed
    /// for this session and the retry says so — and a later attempt with a writable store records the real
    /// failure durably instead of leaving an old pending state.
    func testRefusedSavedMediaWriteIsShownOnTheRowAndRetryRecordsTheOutcome() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let (origin, revision) = try admitOccurrence(in: association.database)
        let card = try publishOccurrence(in: association.database, origin: origin, revision: revision,
            mediaKey: "sha256:" + String(repeating: "0", count: 64))
        try PublicationStore(database: association.database).toggleBookmark(cardID: card.id,
            in: ReaderBookmarkList.defaultID, at: Date())
        let savedIDs = try association.savedArticles().map(\.id)
        XCTAssertEqual(savedIDs, [card.id])

        try trigger(["""
            CREATE TRIGGER refuse_saved_media_availability
            BEFORE INSERT ON saved_media_availability
            BEGIN SELECT RAISE(ABORT, 'availability write refused'); END;
            """], in: directory)
        association.retrySavedMedia(card.id)
        let firstSettled = await Self.waitUntil(5) { association.savedMediaRevision > 0 }
        XCTAssertTrue(firstSettled, "a preparação recusada chega à superfície")
        let savedFirst = try association.savedArticles().first
        XCTAssertEqual(savedFirst?.availability, .failed,
            "a linha não continua mostrando o pending que a escrita recusada não gravou")
        XCTAssertEqual(association.store.toast?.text, String(localized: "Não foi possível preparar a mídia salva"))
        XCTAssertNil(try SavedMediaAvailabilityStore(database: association.database)
            .availability(cardID: card.id), "nenhuma linha durável foi prometida")
        try dropTriggers(["refuse_saved_media_availability"], in: directory)

        association.store.dismissToast()
        association.retrySavedMedia(card.id)
        let secondSettled = await Self.waitUntil(5) { association.savedMediaRevision > 1 }
        XCTAssertTrue(secondSettled, "a tentativa seguinte também chega à superfície")
        let settledFirst = try association.savedArticles().first
        XCTAssertEqual(settledFirst?.availability, .failed,
            "a ocorrência declara mídia e nenhum candidato é preparável: a falha é durável")
        XCTAssertEqual(try SavedMediaAvailabilityStore(database: association.database)
            .availability(cardID: card.id)?.availability, .failed,
            "com a escrita permitida, o estado real fica durável")
        await association.close()
    }

    /// Returning from an article does not lose the search: the context and the reading position stay exactly where
    /// the search left them.
    func testReturningFromArticleRestoresSearch() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, _) = try await launched()
        try await root.submitSearch("Published")
        let search = try XCTUnwrap(root.association)
        let key = root.currentContextKey
        let anchor = search.store.state.presentation?.window.anchor
        guard let card = search.store.state.presentation?.window.items.first?.id else {
            return XCTFail("premissa: a busca publica cartas")
        }
        let target = try XCTUnwrap(search.readingTarget(card), "a carta da busca abre a leitura local")
        search.onReading?(target)
        XCTAssertEqual(root.currentContextKey, key, "abrir/voltar do artigo não troca o contexto da busca")
        XCTAssertEqual(search.store.state.presentation?.window.anchor, anchor)
        await search.close()
    }

    // MARK: - R11: context switches under load reuse canonical work

    /// A→B→A with the science feed suspended and new supply arriving on the other: coming back must reuse the
    /// canonical Edition and the promised position (the durable checkpoint), not repeat bytes through a fresh
    /// publication. The bytes a valid edition already carries are used again; no anchor is invented.
    func testContextSwitchUnderLoadReusesCanonicalWork() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 64 }
        defer {
            FixtureTransport.releaseScience()
            FixtureTransport.feedItemCount.withLock { $0 = nil }
        }
        let (root, association) = try await launched()
        let first = try XCTUnwrap(association.store.state.presentation)
        let aEdition = first.editionID
        let aAnchor = first.window.anchor

        // The next opportunity is under load: the science feed suspends and the other brings a different response.
        FixtureTransport.holdingScience.withLock { $0 = true }
        FixtureTransport.feedItemCount.withLock { $0 = 24 }

        try await root.selectContext(.source(TrustedFeed.development[0].sourceID))
        let b = try XCTUnwrap(root.association)
        XCTAssertNotEqual(b.store.state.presentation?.editionID, aEdition,
            "premissa: o contexto B tem a própria edição")

        try await root.selectContext(.main)
        let back = try XCTUnwrap(root.association)
        XCTAssertFalse(back === b)
        XCTAssertEqual(back.store.state.presentation?.editionID, aEdition,
            "a volta a A reaproveita a edição canônica, sem republicar")
        XCTAssertEqual(back.store.state.presentation?.window.anchor, aAnchor,
            "e a posição prometida do checkpoint, não uma inventada")
        XCTAssertFalse(back.store.state.presentation?.window.items.isEmpty ?? true)
        await back.close()
    }

    // MARK: - R01: bounded viewport ingress

    /// R01: the reader's callback records a fact and returns; it never awaits the producer and never creates one
    /// task per event. With one feed suspended mid-acquisition, the capture's observation has to return **before**
    /// the producer is released, and a burst of callbacks may not grow the pending work with the burst's size.
    ///
    /// The bounded summary keeps the earliest movement (the measurement anchor), the latest position and the newest
    /// fact of each semantic kind — six slots in total. A `Task` per callback (the behavior this replaces) grew the
    /// pending work by one per event; the mutation proof is recorded in the execution register.
    func testScrollIngressDoesNotAwaitProducer() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 2 }
        defer {
            FixtureTransport.releaseScience()
            FixtureTransport.feedItemCount.withLock { $0 = nil }
        }
        let (root, association) = try await launched()
        let presentation = try XCTUnwrap(association.store.state.presentation)
        XCTAssertGreaterThan(presentation.window.items.count, 3)

        // The next acquisition is the producer that suspends the consumer: the held feed is part of the supply the
        // opportunity asks for, and the coordinator does not settle the round until it answers.
        FixtureTransport.holdingScience.withLock { $0 = true }
        FixtureTransport.feedItemCount.withLock { $0 = 24 }

        // The capture's own callback, exactly as the view calls it. It returns synchronously; the single consumer
        // starts and suspends inside the held producer.
        let tail = try XCTUnwrap(presentation.window.items.last?.id)
        association.store.submitViewport(.init(anchor: .init(cardID: tail, placement: .top)),
            activity: .explicitTailApproach, rendered: presentation)
        XCTAssertGreaterThanOrEqual(association.pendingViewportIngressCount, 1,
            "o callback tem de registrar o fato mesmo com o produtor suspenso")

        // A burst of observations while the consumer is suspended: the pending work is the finite summary, not the
        // burst. Every card the reader actually passed is exposed at ingress, before any delivery.
        let burst = presentation.window.items.map(\.id)
        for index in 0..<300 {
            association.store.submitViewport(.init(anchor: .init(cardID: burst[index % burst.count],
                placement: .top)), activity: index.isMultiple(of: 2) ? .forward : .backward, rendered: presentation)
        }
        XCTAssertLessThanOrEqual(association.pendingViewportIngressCount, 6,
            "a rajada não pode crescer o trabalho pendente: são os slots finitos do resumo, não uma fila")
        for id in Set(burst) {
            XCTAssertTrue(association.editorialExposure.wasExposed(id),
                "a exposição é do instante da captura: coalescer depois não pode perder uma carta vista")
        }

        FixtureTransport.releaseScience()
        _ = await Self.waitUntil(10) { association.pendingViewportIngressCount == 0 }
        XCTAssertEqual(association.pendingViewportIngressCount, 0,
            "o consumo pendente termina quando os fatos terminam")
        XCTAssertNotNil(association.store.state.presentation)
        await association.close()
    }

    /// R01: a burst with movement, reversal and rest — delivered late — keeps the facts the product acts on: the
    /// **last** position is the reader's, the advanced cards produce a real consumption measure (high-water moved),
    /// every seen card is exposed, and the rest is recorded durably at the drawn position.
    func testMovingObservationsRemainBoundedAndPreserveRest() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 64 }
        defer {
            FixtureTransport.releaseScience()
            FixtureTransport.feedItemCount.withLock { $0 = nil }
        }
        let clock = IngressClock()
        let root = root(clock: clock)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let presentation = try XCTUnwrap(association.store.state.presentation)
        let items = presentation.window.items
        XCTAssertGreaterThan(items.count, 8)
        guard items.count > 8, let lastItem = items.last else {
            XCTFail("premissa: a janela admitida precisa de mais de oito cartas — veio \(items.count)")
            await association.close()
            return
        }

        // The next acquisition is the producer that holds the consumer. The local slice cannot close the deficit
        // once the tail opportunity asks for more and the held feed is the supply that would arrive.
        FixtureTransport.feedItemCount.withLock { $0 = 2 }
        FixtureTransport.holdingScience.withLock { $0 = true }
        clock.advance(0.5)
        association.store.submitViewport(.init(anchor: .init(cardID: lastItem.id, placement: .top)),
            activity: .explicitTailApproach, rendered: presentation)

        // The burst: movement forward and backward across the admitted window, with the reader's own instants.
        let burst = 200
        for index in 0..<burst {
            clock.advance(0.01)
            association.store.submitViewport(.init(anchor: .init(cardID: items[index % items.count].id,
                placement: .top)), activity: index.isMultiple(of: 2) ? .forward : .backward,
                rendered: presentation)
        }
        XCTAssertLessThanOrEqual(association.pendingViewportIngressCount, 6,
            "rajada de \(burst) avanços: o pendente é o resumo finito")

        // The reader rests at a drawn position. Both streams carry it: the rest settles the session, and the drawn
        // top is what a durable record may name.
        let restIndex = items.count / 2
        let rest = items[restIndex].id
        clock.advance(0.01)
        association.store.submitViewport(.init(anchor: .init(cardID: rest, placement: .top)),
            activity: .stationary, rendered: presentation)
        association.store.publishPresentedPosition(.init(cardID: rest, placement: .top), atRest: true)
        XCTAssertLessThanOrEqual(association.pendingViewportIngressCount, 6)

        FixtureTransport.releaseScience()
        _ = await Self.waitUntil(15) { association.pendingViewportIngressCount == 0 }
        XCTAssertEqual(association.pendingViewportIngressCount, 0)

        // Last position: the rest fact is the newest, so the reader ends there.
        let settled = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(settled.window.anchor.cardID, rest,
            "a última posição entregue tem de ser a do leitor — a ordem é a dos instantes de captura")
        // High-water: the delivered movement measured a real advance; a coalesced delivery does not drop it.
        let rate = await association.driver.runway.snapshot().consumption.cardsPerSecond
        XCTAssertGreaterThan(try XCTUnwrap(rate), 0, "o avanço medido tem de sobreviver ao coalescing")
        // Exposure: every card the reader passed is in the ledger.
        for id in Set((0..<burst).map { items[$0 % items.count].id }) {
            XCTAssertTrue(association.editorialExposure.wasExposed(id))
        }
        // Rest is durable at the drawn position, not at the window's own anchor.
        let checkpoint = try XCTUnwrap(SessionStore(database: association.database)
            .checkpoint(for: association.contextKey))
        XCTAssertEqual(checkpoint.cardID, rest, "o repouso tem de ser gravado onde o desenho parou")
        await association.close()
    }

    /// R01: the reader's instant is captured **at ingress**. A coalesced delivery is late by construction; if the
    /// runway stamped the sample on delivery, the drain's own latency would become reading velocity. The clock is
    /// controlled, so the expected rate is arithmetic, not a tolerance: two cards advanced over two seconds.
    func testCoalescingPreservesCapturedConsumptionTiming() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 2 }
        defer {
            FixtureTransport.releaseScience()
            FixtureTransport.feedItemCount.withLock { $0 = nil }
        }
        let clock = IngressClock()
        let root = root(clock: clock)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let presentation = try XCTUnwrap(association.store.state.presentation)
        let items = presentation.window.items
        XCTAssertGreaterThanOrEqual(items.count, 2)
        guard let first = items.first, items.count >= 2 else {
            XCTFail("premissa: a janela admitida precisa de duas cartas — veio \(items.count)")
            await association.close()
            return
        }
        let second = items[1]

        // Suspend the producer for the opportunity that asks for more; the two movement facts below queue behind
        // it and are delivered only after the release.
        FixtureTransport.feedItemCount.withLock { $0 = 24 }
        FixtureTransport.holdingScience.withLock { $0 = true }
        clock.advance(2)
        association.store.submitViewport(.init(anchor: .init(cardID: first.id, placement: .top)),
            activity: .explicitTailApproach, rendered: presentation)
        XCTAssertGreaterThanOrEqual(association.pendingViewportIngressCount, 1)

        clock.advance(2)
        association.store.submitViewport(.init(anchor: .init(cardID: second.id, placement: .top)),
            activity: .forward, rendered: presentation)
        XCTAssertLessThanOrEqual(association.pendingViewportIngressCount, 6,
            "o segundo fato é coalescido enquanto o consumidor está suspenso")

        FixtureTransport.releaseScience()
        // The empty ingress summary is not completion: the consumer removes a fact before awaiting the viewport
        // measurement. Wait for the existing owner drain to release ownership; the rate is then the captured one.
        _ = await Self.waitUntil(10) { association.viewportDrainIdle }
        XCTAssertTrue(association.viewportDrainIdle, "the single consumer must finish before the measurement is read")
        XCTAssertEqual(association.pendingViewportIngressCount, 0)

        // The advance from the reader's first position to the second is one card, and the two facts were captured
        // two seconds apart: 0.5 cards/s. A delivery-time stamp would make both samples share one instant (the
        // second is rejected as non-monotonic) and the learned rate would not be this number.
        let snapshot = await association.driver.runway.snapshot()
        let rate = try XCTUnwrap(snapshot.consumption.cardsPerSecond)
        XCTAssertEqual(rate, 0.5, accuracy: 0.01,
            "a taxa é das capturas (1 carta / 2 s), não do tempo que o dreno levou para entregá-las")
        await association.close()
    }

    // MARK: - R02: prepared installation and confirmed bookmarks

    /// P06/A10: the production launch prepares the durable bookmark set **before** installing the first
    /// projection. The reader's first list already carries it, and no second read is needed for that install.
    func testFirstProductionInstallationCarriesPreparedBookmarks() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let gate = BookmarkReadGate()
        let root = root(bookmarkRead: gate.read)
        let durable = Set([PublicationCardID()])
        let launch = Task { await root.launch() }
        let arrived = await Self.waitUntil(5) { gate.arrivals == 1 }
        XCTAssertTrue(arrived, "o primeiro install prepara os bookmarks antes de instalar")
        gate.answer(durable)
        await launch.value
        let association = try XCTUnwrap(root.association)
        XCTAssertNotNil(association.store.state.presentation)
        XCTAssertEqual(association.store.bookmarkedIDs, durable,
            "a primeira projeção já representa o conjunto durável")
        // A window that **grows** during the launch is a new window and asks its own bounded refresh; that is the
        // product's existing rule, not the installation reading storage. What matters is that the first projection
        // already carried the set.
        if gate.unanswered > 0 { gate.answer(durable) }
        let settled = await Self.waitUntil(5) { gate.unanswered == 0 }
        XCTAssertTrue(settled)
        XCTAssertEqual(association.store.bookmarkedIDs, durable)
        await association.close()
    }

    /// R02/P06: installation assigns **values**. A work-only report and a prepared package both complete while the
    /// storage seam is suspended, and neither asks the storage or the preparer for anything.
    func testInstallDoesNotReadDatabase() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let gate = BookmarkReadGate()
        let root = root(bookmarkRead: gate.read)
        let launch = Task { await root.launch() }
        let prepared = await Self.waitUntil(5) { gate.arrivals == 1 }
        XCTAssertTrue(prepared, "premissa: o launch prepara a leitura de bookmarks — off-main")
        gate.answer([])
        await launch.value
        let association = try XCTUnwrap(root.association)
        XCTAssertNotNil(association.store.state.presentation)
        let card = try XCTUnwrap(association.store.state.presentation?.window.items.first?.id)
        let readsBefore = gate.arrivals

        // (1) A work report: the store installs the report and the installation consults no storage.
        try association.install(PreparedFeedInstallation(state: association.store.state.reporting(.pending)))
        XCTAssertEqual(association.store.work, .pending)
        XCTAssertEqual(gate.arrivals, readsBefore, "instalar não pode ler o armazenamento")

        // (2) A prepared package: the bookmark half is assigned from the value it carries — still no read.
        try association.install(PreparedFeedInstallation(state: association.store.state,
            bookmarks: .init(ids: [card], base: association.bookmarkMutationRevision)))
        XCTAssertEqual(association.store.bookmarkedIDs, [card])
        XCTAssertEqual(gate.arrivals, readsBefore, "instalar um pacote não chama o preparador")

        gate.answer([card])
        let answered = await Self.waitUntil(5) { gate.unanswered == 0 }
        XCTAssertTrue(answered)
        XCTAssertEqual(association.store.bookmarkedIDs, [card])
        await association.close()
    }

    /// R02: the confirmed toggle is durable before the UI is told, and the preparation it outran cannot undo it.
    /// One read is in flight; the reader saves; the stale answer arrives last. The stale answer is discarded
    /// (its base is older than the confirmed revision), the one refreshed read is scheduled, and the confirmed set
    /// wins. The same fence is exercised with an inverted completion and with a box deletion, which is delivered
    /// through the same confirmed path.
    func testOldBookmarkPreparationCannotUndoConfirmedToggle() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let gate = BookmarkReadGate()
        let root = root(bookmarkRead: gate.read)
        let launch = Task { await root.launch() }
        let prepared = await Self.waitUntil(5) { gate.arrivals == 1 }
        XCTAssertTrue(prepared, "premissa: a leitura do launch está preparada")
        gate.answer([])
        await launch.value
        let association = try XCTUnwrap(root.association)
        let card = try XCTUnwrap(association.store.state.presentation?.window.items.first?.id)
        XCTAssertEqual(association.bookmarkMutationRevision, 0)

        // Confirmed mutations: save, remove. Each durable write moves the revision before the UI sees a set.
        association.store.perform(ReaderCardActionEvent(action: .save, cardID: card))
        XCTAssertEqual(association.bookmarkMutationRevision, 1,
            "o toggle confirmado move a revisão antes de a UI ver o conjunto")
        let inFlight = await Self.waitUntil(5) { gate.unanswered == 1 }
        XCTAssertTrue(inFlight, "a confirmação pede a leitura vigente")
        association.store.perform(ReaderCardActionEvent(action: .save, cardID: card))
        XCTAssertEqual(association.bookmarkMutationRevision, 2)
        // The read prepared under revision 1 answers last, with a set that would wrongly re-save the card. It is
        // older than the confirmed removal, so it cannot install — and it schedules the refreshed read.
        gate.answer([card])
        let refreshed = await Self.waitUntil(5) { gate.arrivals == 3 }
        XCTAssertTrue(refreshed, "a resposta velha é descartada e o conjunto vigente é lido de novo")
        XCTAssertEqual(association.store.bookmarkedIDs, [],
            "a preparação antiga não pode desfazer a remoção confirmada")
        gate.answer([])
        let settled = await Self.waitUntil(5) { association.store.bookmarkedIDs.isEmpty && gate.unanswered == 0 }
        XCTAssertTrue(settled)
        XCTAssertEqual(association.store.bookmarkedIDs, [])
        XCTAssertEqual(association.bookmarkMutationRevision, 2)

        // Two boxes: a card lives in the default box and in a second one; deleting the second removes only its
        // membership, and the deletion is delivered through the confirmed path.
        let library = ReaderLibraryStore(database: association.database)
        let box = try library.createBookmarkList(named: "Segunda")
        try library.setBookmarkMembership(cardID: card, listID: ReaderBookmarkList.defaultID,
            included: true, at: Date())
        try library.setBookmarkMembership(cardID: card, listID: box.id, included: true, at: Date())
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), [card])
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: box.id), [card])
        let boxes = try XCTUnwrap(root.makeBookmarkBoxesStore())
        await boxes.delete(id: box.id)
        XCTAssertEqual(association.bookmarkMutationRevision, 3,
            "a exclusão de caixa é uma mutação confirmada da biblioteca")
        let deletionRead = await Self.waitUntil(5) { gate.unanswered == 1 }
        XCTAssertTrue(deletionRead, "a exclusão pede a leitura do conjunto vigente")
        gate.answer(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID))
        let kept = await Self.waitUntil(5) { association.store.bookmarkedIDs == [card] }
        XCTAssertTrue(kept, "apagar a segunda caixa mantém a carta salva na caixa padrão")
        await association.close()
    }

    /// P10/R17: the production composition creates new Editions under the supported sequencing version and the
    /// publication freezes each occurrence's editorial facts — the tie-break is no longer dormant.
    func testNewEditionsCarrySupportedVersionAndFrozenDiversity() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let (root, association) = try await launched()
        let presentation = try XCTUnwrap(association.store.state.presentation)
        let store = PublicationStore(database: association.database)
        let edition = try XCTUnwrap(try store.edition(id: presentation.editionID))
        XCTAssertEqual(edition.editorialRevision.sequencingPolicyVersion.rawValue, 6,
            "edições novas declaram a versão suportada de diversidade")
        let record = try XCTUnwrap(try store.card(id: presentation.window.items[0].id))
        let diversity = try XCTUnwrap(record.diversity, "a ocorrência carrega os fatos congelados")
        XCTAssertFalse(diversity.sourceIDs.isEmpty)
        XCTAssertTrue(try store.recentDiversity(editionID: presentation.editionID, limit: 16).contains(diversity),
            "os fatos congelados entram no contexto editorial da edição")
        await association.close()
    }

    /// P12: a saved occurrence survives force quit (a new composition over the same directory) and a disposable
    /// cache purge, offline.
    func testSavedArticleSurvivesForceQuitAndCachePurgeOffline() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = root(directory: directory)
        await first.launch()
        let association = try XCTUnwrap(first.association)
        let card = try XCTUnwrap(association.store.state.presentation?.window.items.first)
        try PublicationStore(database: association.database).toggleBookmark(cardID: card.id,
            in: ReaderBookmarkList.defaultID, at: Date())
        await association.close()

        // Only disposable caches are purged; the library database is not personal-data loss.
        for name in ["Caches", "URLCache"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let second = root(directory: directory)
        await second.launch()
        let reopened = try XCTUnwrap(second.association)
        let reopenedIDs = try reopened.savedArticles().map(\.id)
        XCTAssertTrue(reopenedIDs.contains(card.id),
            "o salvo sobrevive ao encerramento e à limpeza de cache, mesmo offline")
        XCTAssertTrue(try PublicationStore(database: reopened.database).bookmarkedCardIDs().contains(card.id))
        await reopened.close()
    }

    /// P12/R15: the search context is declared durably before activation. A process that dies after that write
    /// reopens on the declared context instead of rolling it back.
    func testProcessDeathDuringPresetActivationRecoversDeclaredContext() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = root(directory: directory)
        await first.launch()
        try await first.submitSearch("Published")
        let declared = first.currentContextKey
        // No close/checkpoint: the process is gone from the composition's point of view.
        let reopened = root(directory: directory)
        XCTAssertEqual(reopened.currentContextKey, declared,
            "o contexto confirmado é a autoridade; a morte durante a ativação não o desfaz")
        await reopened.launch()
        XCTAssertEqual(reopened.currentContextKey, declared)
        await reopened.association?.close()
    }

    // MARK: - PD10-P0A: public sync contract, through the production URL and the real composition root

    private func publicCatalogueRoot(directory: URL) -> AppComposition {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandardCatalogueTransport.self, FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 10
        return AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
    }

    private func bundledPublicManifest() throws -> CatalogManifest {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog.manifest", withExtension: "json"))
        let bundled = try CatalogManifest.decode(Data(contentsOf: url))
        return CatalogManifest(revision: bundled.revision, schemaVersion: bundled.schemaVersion,
            generatedAt: bundled.generatedAt, sourceCount: bundled.sourceCount,
            fileCount: bundled.opmlEntries.count, files: bundled.opmlEntries)
    }

    private func syncRecordURL(_ directory: URL) -> URL {
        directory.appendingPathComponent("catalogue/sync.json")
    }

    private func readSyncRecord(_ directory: URL) throws -> CatalogSyncRecord {
        try JSONDecoder().decode(CatalogSyncRecord.self, from: Data(contentsOf: syncRecordURL(directory)))
    }

    private func writeSyncRecord(_ record: CatalogSyncRecord, to directory: URL) throws {
        try JSONEncoder().encode(record).write(to: syncRecordURL(directory), options: .atomic)
    }

    /// Criteria 1/3/7: a locally verified, published feed appears before *any* manifest GET. The first
    /// foreground really consults the STANDARD public URL, recognizes the same 118 OPML inputs against
    /// the installed 119-entry descriptor, and leaves the active snapshot and visible cards untouched.
    func testPD10StandardPublicAuthorityChecksFirstForegroundAfterLocalPaint() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try bundledPublicManifest()
        XCTAssertFalse(manifest.opmlEntries.isEmpty)
        StandardCatalogueTransport.prepare(try manifest.encoded())
        let composition = publicCatalogueRoot(directory: directory)
        await composition.launch()
        let association = try XCTUnwrap(composition.association)
        let before = try XCTUnwrap(association.store.state.presentation)
        let visible = before.window.items.map(\.id)
        let activeBefore = try XCTUnwrap(CatalogInstallation(appDirectory: directory).activeSnapshot())

        XCTAssertTrue(StandardCatalogueTransport.requests.withLock { $0.isEmpty },
            "the local first paint must never depend on a remote manifest request")
        XCTAssertFalse(FileManager.default.fileExists(atPath: syncRecordURL(directory).path),
            "local bootstrap must not start the remote verification window")

        await composition.foreground()

        let requests = StandardCatalogueTransport.requests.withLock { $0 }
        XCTAssertEqual(requests.count, 1, "the release authority must be checked on the first opportunity")
        XCTAssertNil(try XCTUnwrap(requests.first), "the first GET has no conditional validator")
        let recorded = try readSyncRecord(directory)
        XCTAssertEqual(recorded.verifiedRevision, manifest.revision)
        XCTAssertEqual(recorded.remoteRevision, manifest.revision)
        XCTAssertNotNil(recorded.verifiedAt)
        XCTAssertEqual(recorded.etag, StandardCatalogueTransport.etag)
        let activeAfter = try XCTUnwrap(CatalogInstallation(appDirectory: directory).activeSnapshot())
        XCTAssertEqual(activeAfter.fingerprint, activeBefore.fingerprint,
            "equal public revision is not downloaded, compiled or replaced")
        XCTAssertTrue(CatalogInstallation(appDirectory: directory).ledger().allSatisfy { $0.outcome != .activated })
        XCTAssertTrue(composition.association === association, "checking does not rebuild the visible session")
        let after = association.store.state.presentation?.window.items.map(\.id) ?? []
        XCTAssertEqual(Array(after.prefix(visible.count)), visible, "published cards remain in place")
        await association.close()
    }

    /// Criteria 2/6/7: the durable clock is from the remote check, not from any subsequent local bootstrap;
    /// a 23-hour relaunch skips while a 25-hour relaunch sends a conditional GET and valid 304 renews the clock.
    func testPD10RelaunchRespects23And25HourWindowAndConsistent304() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try bundledPublicManifest()
        StandardCatalogueTransport.prepare(try manifest.encoded())
        let first = publicCatalogueRoot(directory: directory)
        await first.launch()
        await first.foreground()
        let verified = try readSyncRecord(directory)
        XCTAssertNotNil(verified.verifiedAt)
        await first.association?.close()

        let at23 = Date().addingTimeInterval(-23 * 3600)
        try writeSyncRecord(CatalogSyncRecord(verifiedRevision: verified.verifiedRevision, verifiedAt: at23,
            remoteRevision: verified.remoteRevision, etag: verified.etag), to: directory)
        StandardCatalogueTransport.requests.withLock { $0 = [] }
        let second = publicCatalogueRoot(directory: directory)
        await second.launch()
        XCTAssertTrue(StandardCatalogueTransport.requests.withLock { $0.isEmpty })
        await second.foreground()
        XCTAssertTrue(StandardCatalogueTransport.requests.withLock { $0.isEmpty },
            "relaunch after 23 hours must not restart the window or consult the authority")
        XCTAssertEqual(try XCTUnwrap(readSyncRecord(directory).verifiedAt).timeIntervalSince1970,
            at23.timeIntervalSince1970, accuracy: 0.001,
            "skip must not rewrite the successful remote-verification timestamp")
        await second.association?.close()

        let at25 = Date().addingTimeInterval(-25 * 3600)
        try writeSyncRecord(CatalogSyncRecord(verifiedRevision: verified.verifiedRevision, verifiedAt: at25,
            remoteRevision: verified.remoteRevision, etag: verified.etag), to: directory)
        let third = publicCatalogueRoot(directory: directory)
        await third.launch()
        XCTAssertTrue(StandardCatalogueTransport.requests.withLock { $0.isEmpty })
        await third.foreground()
        let requests = StandardCatalogueTransport.requests.withLock { $0 }
        XCTAssertEqual(requests.count, 1, "the 25-hour window expires even after a local relaunch")
        XCTAssertEqual(requests.first ?? nil, StandardCatalogueTransport.etag,
            "the 304 must be conditional on the last successfully committed validator")
        let renewed = try readSyncRecord(directory)
        XCTAssertEqual(renewed.verifiedRevision, manifest.revision)
        XCTAssertEqual(renewed.remoteRevision, manifest.revision)
        XCTAssertEqual(renewed.etag, StandardCatalogueTransport.etag)
        XCTAssertGreaterThan(try XCTUnwrap(renewed.verifiedAt), at25,
            "304 with a matching installed revision and prior verification renews the clock")
        await third.association?.close()
    }

    /// Criterion 5: a 200 for a newer revision, followed by a payload rejection, must be retried with a
    /// fresh unconditional GET; the uninstalled ETag may not turn the next opportunity into a 304.
    func testPD10FailedInstallNeverPersistsTheOfferedETag() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = try bundledPublicManifest()
        let invalid = CatalogManifest(revision: bundled.revision + 1, sourceCount: 1, fileCount: 1,
            files: [CatalogManifestEntry(path: "Feeds/invalid.opml", bytes: 5,
                sha256: String(repeating: "a", count: 64))])
        StandardCatalogueTransport.prepare(try invalid.encoded())
        // Requests for invalid.opml fall through to FixtureTransport and serve bytes that fail SHA/size.
        let composition = publicCatalogueRoot(directory: directory)
        await composition.launch()
        let initial = try XCTUnwrap(CatalogInstallation(appDirectory: directory).activeSnapshot())
        await composition.foreground()
        XCTAssertFalse(FileManager.default.fileExists(atPath: syncRecordURL(directory).path),
            "a failed install must not persist either ETag or verification timestamp")
        await composition.foreground()
        let requests = StandardCatalogueTransport.requests.withLock { $0 }
        XCTAssertEqual(requests.count, 2, "the second foreground must retry the authority")
        XCTAssertTrue(requests.allSatisfy { $0 == nil }, "neither request may carry the uncommitted ETag")
        let installation = CatalogInstallation(appDirectory: directory)
        XCTAssertEqual(installation.activeSnapshot()?.fingerprint, initial.fingerprint)
        XCTAssertTrue(installation.ledger().contains { $0.outcome == .rejected })
        XCTAssertFalse(installation.ledger().contains { $0.outcome == .activated })
        await composition.association?.close()
    }

    /// Criterion 6: an unsolicited 304 after a mismatched durable record must NOT refresh that record.
    func testPD10Unsolicited304CannotRenewAnInconsistentRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try bundledPublicManifest()
        StandardCatalogueTransport.prepare(try manifest.encoded(), unsolicited304: true)
        let composition = publicCatalogueRoot(directory: directory)
        await composition.launch()
        let previous = CatalogSyncRecord(verifiedRevision: manifest.revision, verifiedAt: Date().addingTimeInterval(-25 * 3600),
            remoteRevision: manifest.revision + 1, etag: StandardCatalogueTransport.etag)
        try writeSyncRecord(previous, to: directory)
        await composition.foreground()
        XCTAssertEqual(StandardCatalogueTransport.requests.withLock { $0 }, [nil],
            "a mismatched verification record must never send its validator")
        XCTAssertEqual(try readSyncRecord(directory), previous,
            "the unsolicited 304 must not renew verifiedAt or bless a mismatched revision")
        await composition.association?.close()
    }

    /// B1/B3/B7, native app proof. The foreground request is held *after* the association's foreground
    /// completed so a full presentation comparison isolates the catalogue activation from ordinary feed work.
    /// Nothing in the initial presentation may wait for the public authority.
    func testPD10B1B3ForegroundActivatesSixWithoutChangingCompletePublishedPresentation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            StandardCatalogueTransport.releaseManifest()
            try? FileManager.default.removeItem(at: directory)
        }
        let published = try makePD10BPublishedRevision()
        StandardCatalogueTransport.prepare(try published.manifest.encoded(),
            payloads: published.payloads, paused: true)
        let root = publicCatalogueRoot(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        XCTAssertNotNil(association.store.state.presentation, "first paint came from local data")
        XCTAssertTrue(StandardCatalogueTransport.requests.withLock { $0.isEmpty })
        let beforeSnapshot = try XCTUnwrap(CatalogInstallation(appDirectory: directory).activeSnapshot())
        XCTAssertEqual(beforeSnapshot.revision, 5)
        let foreground = Task { await root.foreground() }
        for _ in 0..<300 where StandardCatalogueTransport.requests.withLock({ $0.isEmpty }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(StandardCatalogueTransport.requests.withLock { $0.count }, 1)
        let frozen = try XCTUnwrap(association.store.state.presentation)
        StandardCatalogueTransport.releaseManifest()
        await foreground.value
        let installation = CatalogInstallation(appDirectory: directory)
        let activated = try XCTUnwrap(installation.activeSnapshot())
        XCTAssertEqual(activated.revision, 6)
        XCTAssertEqual(activated.sourceCount, 4)
        assertPD10BPayload(published, installation: CatalogInstallation(appDirectory: directory))
        XCTAssertEqual(activated.fingerprint, try CatalogManifest.sha256(ofFile: activated.catalogueURL))
        let pointer = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: installation.directory.appendingPathComponent("active.json")))
            as? [String: String])
        XCTAssertEqual(pointer["fingerprint"], activated.fingerprint)
        XCTAssertEqual(pointer["cataloguePath"], activated.catalogueURL.path)
        XCTAssertEqual(installation.ledger().map(\.outcome), [.bootstrapped, .activated])
        XCTAssertEqual(installation.ledger().last?.kind, "update")
        XCTAssertEqual(installation.ledger().last?.revision, 6)
        XCTAssertTrue(root.association === association, "activation must not replace the reading association")
        XCTAssertEqual(association.store.state.presentation, frozen,
            "anchor, admitted window, complete card content and metadata must remain identical")
        await association.close()
    }

    /// B2 partial, native app proof: repeating an already queried profile on a *new* association sees the
    /// new catalog fingerprint. It does not claim to fence new work of the old association's acquisition.
    func testPD10B2NewContextAndSourceSearchUseActivatedCatalogue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: db)
        _ = try preferences.initialize(sourceKeys: TrustedFeed.development.map(\.principal))
        var settings = (try preferences.load())?.settings ?? .standard
        settings.discoveryProfile = FeedRecipeDefinition.neutral(languages: ["pt"])
        _ = try preferences.setSettings(settings)
        let published = try makePD10BPublishedRevision()
        StandardCatalogueTransport.prepare(try published.manifest.encoded(), payloads: published.payloads)
        let root = publicCatalogueRoot(directory: directory)
        await root.launch()
        let oldAssociation = try XCTUnwrap(root.association)
        let oldPool = Set(oldAssociation.discovery.map(\.principal))
        XCTAssertFalse(oldPool.isEmpty)
        await root.foreground()
        let active = try XCTUnwrap(CatalogInstallation(appDirectory: directory).activeSnapshot())
        XCTAssertEqual(active.revision, 6)
        assertPD10BPayload(published, installation: CatalogInstallation(appDirectory: directory))
        try await root.searchSources("Alpha")
        XCTAssertTrue(root.sourceOptions.contains { $0.name == "Alpha News" },
            "source management must query the newly activated catalogue")
        try await root.selectContext(.source(TrustedFeed.development[0].sourceID))
        let next = try XCTUnwrap(root.association)
        XCTAssertFalse(next === oldAssociation)
        XCTAssertEqual(next.catalogueURL, active.catalogueURL)
        let freshPool = Set(next.discovery.map(\.principal))
        XCTAssertTrue(freshPool.contains("https://alpha.example/feed"))
        XCTAssertNotEqual(freshPool, oldPool, "a cached old profile must not answer for revision 6")
        await next.close()
    }

    /// B4, native stores rather than byte counts: reader import, explicit selection, bookmark, saved
    /// collection, curated preset and durable reading position survive a managed-catalogue update.
    func testPD10B4PersonalLibraryAndPublishedHistorySurviveActivation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: TrustedFeed.development.map(\.principal))
        let library = ReaderLibraryStore(database: database)
        let mine = ReaderImportEntry(id: "https://mine.example/rss", title: "Minha fonte",
            requestURL: "https://mine.example/rss", categoryPath: [])
        _ = try library.commitImport([mine], rejected: 0, at: Date())
        let published = try makePD10BPublishedRevision()
        StandardCatalogueTransport.prepare(try published.manifest.encoded(), payloads: published.payloads)
        let root = publicCatalogueRoot(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let card = try XCTUnwrap(association.store.state.presentation?.window.items.first)
        let publication = PublicationStore(database: database)
        try publication.toggleBookmark(cardID: card.id, at: Date())
        await association.viewport(.init(anchor: .init(cardID: card.id, placement: .top)), activity: .forward)
        _ = try await association.session.checkpointCurrentPosition(at: Date())
        let position = try XCTUnwrap(SessionStore(database: database).checkpoint())
        let collection = try XCTUnwrap(root.collectCurrentSources(named: "Minha coleção"))
        let savedPreset = try XCTUnwrap(root.saveCuratedFeed(.neutral(languages: ["pt"]),
            named: "Minha curadoria"))
        let selected = try XCTUnwrap(preferences.load()).sourceKeys
        let imported = try library.importedSources()
        let members = try library.sourceKeys(inCollection: collection.id)
        let recipe = try XCTUnwrap(root.makeCuratedCoordinator()?.curatedPresets()
            .first(where: { $0.id == savedPreset.id })?.recipe)
        let originalEdition = try XCTUnwrap(publication.edition(id: position.editionID))

        await root.foreground()
        XCTAssertEqual(CatalogInstallation(appDirectory: directory).activeSnapshot()?.revision, 6)
        assertPD10BPayload(published, installation: CatalogInstallation(appDirectory: directory))
        XCTAssertEqual(try preferences.load()?.sourceKeys, selected,
            "the source selection belongs to the reader, not to the managed catalogue")
        XCTAssertEqual(try library.importedSources(), imported)
        XCTAssertTrue(try library.importedSources().contains { $0.id == mine.id })
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id), members)
        XCTAssertTrue(try library.collections().contains { $0.id == collection.id })
        XCTAssertEqual(try root.makeCuratedCoordinator()?.curatedPresets()
            .first(where: { $0.id == savedPreset.id })?.recipe, recipe)
        XCTAssertTrue(try publication.bookmarkedCardIDs().contains(card.id))
        let afterPosition = try XCTUnwrap(SessionStore(database: database).checkpoint())
        XCTAssertEqual(afterPosition.editionID, position.editionID)
        XCTAssertEqual(afterPosition.cardID, position.cardID)
        XCTAssertEqual(afterPosition.anchorPlacement, position.anchorPlacement)
        XCTAssertEqual(try publication.edition(id: position.editionID), originalEdition,
            "published historical edition is not rewritten by a catalogue update")
        XCTAssertTrue(root.association === association)
        await association.close()
    }

    /// Diagnostic of the complete foreground download. Report both the attempted real URL and the
    /// relative key used by the fixture, including a missing response (nil bytes/digest). A fallback
    /// to FixtureTransport is visible separately; it must never count as an OPML response.
    private func assertPD10BPayload(_ published: (manifest: CatalogManifest, payloads: [String: Data]),
        installation: CatalogInstallation, file: StaticString = #filePath, line: UInt = #line) {
        let observed = StandardCatalogueTransport.payloadObservations.withLock { $0 }
        let declarations = published.manifest.opmlEntries
        let ledgerReason = installation.ledger().last?.reason ?? "<no ledger record>"
        let fallbackStart = StandardCatalogueTransport.fallbackRequestOffset.withLock { $0 }
        let unexpectedFallbacks = FixtureTransport.requests.withLock {
            Array($0.dropFirst(fallbackStart)).filter { $0.hasSuffix(".opml") }
        }
        print("PD10B_PAYLOAD_LEDGER_LAST_REASON: \(ledgerReason)")
        print("PD10B_PAYLOAD_FALLBACK_REQUESTS: \(unexpectedFallbacks)")
        for declared in declarations {
            let expectedURL = declared.path.split(separator: "/").reduce(
                CatalogUpdateChannel.publicManifestURL.deletingLastPathComponent()
            ) { $0.appendingPathComponent(String($1)) }
            print("PD10B_PAYLOAD_DECLARED expectedURL=\(expectedURL.absoluteString)"
                + " path=\(declared.path) bytes=\(declared.bytes) sha256=\(declared.sha256)")
        }
        for delivered in observed {
            print("PD10B_PAYLOAD_DELIVERED url=\(delivered.requestedURL)"
                + " relative=\(delivered.relativePath) bytes=\(String(describing: delivered.byteCount))"
                + " sha256=\(delivered.sha256 ?? "<not served>")")
        }
        let details = "ledger.last.reason=\(ledgerReason); "
            + "delivered=\(observed.map { "\($0.requestedURL) => \($0.relativePath) / \(String(describing: $0.byteCount)) / \($0.sha256 ?? "<not served>")" }); "
            + "fallbackOPML=\(unexpectedFallbacks)"
        XCTAssertEqual(observed.map(\.relativePath).sorted(), declarations.map(\.path).sorted(),
            "every OPML declared must be requested from the controlled authority; \(details)", file: file, line: line)
        XCTAssertTrue(unexpectedFallbacks.isEmpty,
            "no OPML request may escape to FixtureTransport; \(details)", file: file, line: line)
        for delivered in observed {
            guard let declared = declarations.first(where: { $0.path == delivered.relativePath }) else {
                XCTFail("unrecognized payload key; \(details)", file: file, line: line)
                continue
            }
            XCTAssertEqual(delivered.byteCount, declared.bytes,
                "payload size must match the public manifest; \(details)", file: file, line: line)
            XCTAssertEqual(delivered.sha256, declared.sha256.lowercased(),
                "payload digest must match the public manifest; \(details)", file: file, line: line)
        }
    }

    private func makePD10BPublishedRevision() throws ->
        (manifest: CatalogManifest, payloads: [String: Data]) {
        let first = """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0"><head><title>noticias</title><language>pt</language></head>
            <body><outline text="Mundo" title="Mundo">
            <outline text="Alpha News" title="Alpha News" xmlUrl="https://alpha.example/feed" feedmineMediaKind="text" />
            <outline text="Beta News" title="Beta News" xmlUrl="https://beta.example/feed" feedmineMediaKind="text" />
            </outline></body></opml>
            """
        let second = """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0"><head><title>programas</title><language>pt</language></head>
            <body><outline text="Programas" title="Programas">
            <outline text="Gamma Cast" title="Gamma Cast" xmlUrl="https://gamma.example/feed" feedmineMediaKind="audio" />
            <outline text="Delta Video" title="Delta Video" xmlUrl="https://delta.example/feed" feedmineMediaKind="video" />
            </outline></body></opml>
            """
        let payloads = ["Feeds/noticias.opml": Data(first.utf8),
            "Feeds/programas.opml": Data(second.utf8)]
        let declarations = payloads.keys.sorted().map { path in
            CatalogManifestEntry(path: path, bytes: payloads[path]!.count,
                sha256: CryptoKit.SHA256.hash(data: payloads[path]!)
                    .map { String(format: "%02x", $0) }.joined())
        }
        return (CatalogManifest(revision: 6, sourceCount: 4, fileCount: declarations.count,
            files: declarations), payloads)
    }

    func testBundledCatalogHasRealBytesAndStableBoundedDefaults() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let reader = try LegacyCatalogReader(catalogURL: url)
        // The identity is checked against the descriptor this build ships, not against a literal. The bootstrap
        // pipeline re-derives the catalogue from the public channel, so a pinned hash turns every legitimate
        // re-bootstrap into a test failure — and a test that must be edited whenever the artefact is legitimately
        // rebuilt stops being evidence. What must hold is the PD-10 property: the file the app carries is the one
        // its descriptor declares, and it is a real catalogue rather than a placeholder.
        let descriptorURL = try XCTUnwrap(Bundle.main.url(forResource: "catalog.manifest", withExtension: "json"))
        let descriptor = try JSONDecoder().decode(CatalogManifest.self, from: Data(contentsOf: descriptorURL))
        let declared = try XCTUnwrap(descriptor.catalogueEntry,
            "the descriptor must declare the compiled catalogue it describes")
        XCTAssertEqual(try reader.sourceCount(), descriptor.sourceCount,
            "the catalogue counts what its descriptor declares")
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int(try XCTUnwrap(handle.seekToEnd()))
        XCTAssertEqual(size, declared.bytes, "the bytes on disk are the bytes declared")
        XCTAssertGreaterThan(size, 100_000_000, "a real catalogue, not a placeholder")
        try handle.seek(toOffset: 0)
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        XCTAssertEqual(hash.finalize().map { String(format: "%02x", $0) }.joined(), declared.sha256,
            "the file the app carries is the one its descriptor describes")
        let defaults = try TrustedFeed.catalog(limit: 64, resourceURL: url)
        XCTAssertEqual(defaults.count, 4)
        XCTAssertEqual(Set(defaults.map(\.sourceID)).count, 4)
        XCTAssertEqual(try TrustedFeed.catalog(limit: 2, resourceURL: url).count, 2)
        XCTAssertEqual(defaults.map(\.sourceID), try TrustedFeed.catalog(limit: 64, resourceURL: url).map(\.sourceID))
    }

    func testCatalogNameSearchIsLiteralBoundedAndMeasured() throws {
        let reader = try LegacyCatalogReader(catalogURL: XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite")))
        var samples: [Double] = []
        for _ in 0..<20 {
            let started = ProcessInfo.processInfo.systemUptime
            let rows = try reader.matchingSources(query: "BBC", limit: 5)
            samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            XCTAssertFalse(rows.isEmpty)
            XCTAssertLessThanOrEqual(rows.count, 5)
        }
        XCTAssertTrue(try reader.matchingSources(query: "%' OR 1=1 --", limit: 5).isEmpty)
        samples.sort()
        print("T7 catalog 77443 sources, BBC limit5 p50ms=\(samples[9]) p95ms=\(samples[18])")
    }

    func testCatalogMissingOrCorruptIsAnExplicitFailure() throws {
        XCTAssertThrowsError(try TrustedFeed.catalog(limit: 64, resourceURL: nil))
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("corrupt catalog".utf8).write(to: invalid)
        defer { try? FileManager.default.removeItem(at: invalid) }
        XCTAssertThrowsError(try TrustedFeed.catalog(limit: 64, resourceURL: invalid))
    }

    /// PD10-P0D P1/D1: catalog availability is not the authority over durable selection.
    func testSavedKeysMissingFromCatalogRemainSelectedWithoutVersionBump() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let starter = try TrustedFeed.catalog(limit: 64, resourceURL: XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite")))
        do {
            let store = ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
            _ = try store.initialize(sourceKeys: ["https://absent.example/rss", "bbc-world"])
            _ = try store.setContext(.source(SourceID()))
        }
        let composition = AppComposition(directory: directory, feeds: starter, transportConfiguration: .ephemeral)
        XCTAssertNil(composition.startupFailure)
        XCTAssertTrue(composition.feeds.isEmpty, "no unrelated starter feed may replace missing choices")
        XCTAssertEqual(composition.currentContext, .main)
        let retained = try XCTUnwrap(ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory))).load())
        XCTAssertEqual(retained.sourceKeys, ["https://absent.example/rss", "bbc-world"])
        XCTAssertEqual(retained.selectionVersion, 2, "availability cannot bump the reader's selection version")
        XCTAssertEqual(retained.activeContext, .main)

        // Resolution may omit unavailable keys from the operational list, never from persistence.
        let partial = try TrustedFeed.resolveAvailable(keys: ["https://absent.example/rss", starter[1].principal],
            fallback: starter, catalogueURL: Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        XCTAssertEqual(partial.map(\.principal), [starter[1].principal])
    }


    /// PD10-P0D D1: turning off A cannot erase the reader's still-selected but unavailable B.
    /// A/B/C are initially available; on reopen B is absent from the operational authority.
    func testPD10P0DDisablingAvailableSourceKeepsMissingSelectionThroughReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = TrustedFeed.development[0], c = TrustedFeed.development[1]
        let b = TrustedFeed(targetID: AcquisitionTargetID(), sourceID: SourceID(),
            bindingID: SourceBindingID(), principal: "https://temporarily-unavailable.example/rss",
            endpoint: URL(string: "https://temporarily-unavailable.example/rss")!,
            displayName: "Temporarily unavailable")
        let first = root(directory: directory, feeds: [a, b, c])
        XCTAssertNil(first.startupFailure)
        XCTAssertEqual(first.feeds.map(\.principal), [a.principal, b.principal, c.principal])
        let preferences = ReaderPreferencesStore(database: try RuntimeDatabase(
            location: .init(directory: directory)))
        let initiallySaved = try XCTUnwrap(preferences.load())
        XCTAssertEqual(initiallySaved.sourceKeys, [a.principal, b.principal, c.principal])

        // B is no longer offered, but no reader action has deselected it.
        let withoutB = root(directory: directory, feeds: [a, c])
        XCTAssertNil(withoutB.startupFailure)
        XCTAssertEqual(withoutB.feeds.map(\.principal), [a.principal, c.principal])
        XCTAssertEqual(try preferences.load()?.sourceKeys, initiallySaved.sourceKeys)
        XCTAssertEqual(try preferences.load()?.selectionVersion, initiallySaved.selectionVersion)
        await withoutB.launch()
        try await withoutB.searchSources("")
        try await withoutB.toggleSource(a.sourceID)

        XCTAssertEqual(withoutB.feeds.map(\.principal), [c.principal])
        XCTAssertEqual(try preferences.load()?.sourceKeys, [b.principal, c.principal],
            "removing A must not silently discard unresolved B")
        XCTAssertEqual(try preferences.load()?.selectionVersion, initiallySaved.selectionVersion + 1,
            "one explicit toggle is exactly one selection change")
        await withoutB.association?.close()

        let reopened = root(directory: directory, feeds: [a, c])
        XCTAssertNil(reopened.startupFailure)
        XCTAssertEqual(reopened.feeds.map(\.principal), [c.principal])
        XCTAssertEqual(try preferences.load()?.sourceKeys, [b.principal, c.principal])
        XCTAssertEqual(try preferences.load()?.selectionVersion, initiallySaved.selectionVersion + 1)
        await reopened.launch()
        XCTAssertEqual(reopened.feeds.map(\.principal), [c.principal])
        XCTAssertEqual(try preferences.load()?.sourceKeys, [b.principal, c.principal])
        await reopened.association?.close()
    }

    /// PD10-P0D P1/P6/P7/P13: native composition and persisted authority, no HTTP.
    func testPD10P0DImportedManagedIdentityRemainsSingleAndAvailableOffline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let managed = try XCTUnwrap(TrustedFeed.catalog(limit: 1, resourceURL: bundled).first)
        let imported = ReaderImportEntry(id: managed.principal, title: "Meu título",
            requestURL: managed.endpoint.absoluteString + "?my_access=1", categoryPath: [])
        let persisted: ReaderPreferencesStore.Record
        do {
            let database = try RuntimeDatabase(location: .init(directory: directory))
            let preferences = ReaderPreferencesStore(database: database)
            _ = try preferences.initialize(sourceKeys: [])
            let library = ReaderLibraryStore(database: database)
            _ = try library.commitImport([imported], rejected: 0, at: Date(timeIntervalSince1970: 1))
            persisted = try XCTUnwrap(preferences.load())
            XCTAssertEqual(persisted.sourceKeys, [managed.principal])
        }
        let first = AppComposition(directory: directory, feeds: [], transportConfiguration: .ephemeral)
        XCTAssertNil(first.startupFailure)
        XCTAssertEqual(first.feeds.count, 1, "import and catalog are one active source")
        XCTAssertEqual(first.feeds[0].sourceID, managed.sourceID)
        XCTAssertEqual(first.feeds[0].bindingID, managed.bindingID)
        let library = ReaderLibraryStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        let pinned = try library.sourceLinks()
        XCTAssertEqual(pinned[managed.principal]?.authority, "catalog")
        let offline = try TrustedFeed.resolveAvailable(keys: persisted.sourceKeys, fallback: [],
            readerSources: [imported], catalogueURL: nil, identities: pinned)
        XCTAssertEqual(offline.count, 1)
        XCTAssertEqual(offline.first?.sourceID, managed.sourceID,
            "removing the managed record must not flip source IDs to the import namespace")
        XCTAssertEqual(offline.first?.targetID, managed.targetID)
        XCTAssertEqual(offline.first?.endpoint.absoluteString, imported.requestURL)
        let reopened = AppComposition(directory: directory, feeds: [], transportConfiguration: .ephemeral)
        XCTAssertEqual(reopened.feeds.count, 1)
        XCTAssertEqual(reopened.feeds[0].sourceID, managed.sourceID)
        XCTAssertEqual(try ReaderPreferencesStore(database: try RuntimeDatabase(
            location: .init(directory: directory))).load()?.selectionVersion, persisted.selectionVersion)
    }

    /// P0B/P0D integration: revision 6 removes a managed source that the user also imported.
    /// The visible Edition stays frozen and the *next* association retains the historical IDs.
    func testPD10P0DLiveCatalogActivationPreservesPersonalIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let managed = try XCTUnwrap(TrustedFeed.catalog(limit: 2, resourceURL: bundled).last)
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: [managed.principal])
        let imported = ReaderImportEntry(id: managed.principal, title: "Meu feed science",
            requestURL: managed.endpoint.absoluteString, categoryPath: [])
        let library = ReaderLibraryStore(database: database)
        _ = try library.commitImport([imported], rejected: 0, at: Date())
        let before = try XCTUnwrap(preferences.load())

        let published = try makePD10BPublishedRevision()
        StandardCatalogueTransport.prepare(try published.manifest.encoded(),
            payloads: published.payloads, paused: true)
        defer { StandardCatalogueTransport.releaseManifest() }
        let root = publicCatalogueRoot(directory: directory)
        XCTAssertNil(root.startupFailure)
        XCTAssertEqual(root.feeds.map(\.sourceID), [managed.sourceID])
        XCTAssertEqual(try library.sourceLinks()[managed.principal]?.authority, "catalog")
        await root.launch()
        let original = try XCTUnwrap(root.association)
        let foreground = Task { await root.foreground() }
        for _ in 0..<300 where StandardCatalogueTransport.requests.withLock({ $0.isEmpty }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(StandardCatalogueTransport.requests.withLock { $0.count }, 1)
        let frozen = original.store.state.presentation
        StandardCatalogueTransport.releaseManifest()
        await foreground.value
        let activated = try XCTUnwrap(CatalogInstallation(appDirectory: directory).activeSnapshot())
        XCTAssertEqual(activated.revision, 6)
        XCTAssertTrue(root.association === original)
        XCTAssertEqual(original.store.state.presentation, frozen)
        XCTAssertEqual(try preferences.load()?.sourceKeys, before.sourceKeys)
        XCTAssertEqual(try preferences.load()?.selectionVersion, before.selectionVersion)

        try await root.replaceSession()
        let refreshed = try XCTUnwrap(root.association)
        XCTAssertFalse(refreshed === original)
        XCTAssertEqual(refreshed.catalogueURL, activated.catalogueURL)
        XCTAssertEqual(refreshed.feeds.map(\.sourceID), [managed.sourceID])
        XCTAssertEqual(refreshed.feeds.map(\.targetID), [managed.targetID])
        XCTAssertEqual(refreshed.feeds.map(\.bindingID), [managed.bindingID])
        XCTAssertEqual(refreshed.feeds.first?.endpoint, managed.endpoint)
        XCTAssertEqual(try library.importedSources().first?.requestURL, imported.requestURL)
        XCTAssertEqual(try preferences.load()?.sourceKeys, before.sourceKeys)
        await refreshed.close()
    }

    /// UX12-C (F12 benchmark) + R4/R6: enabling or disabling a source while a feed containing it is published.
    /// The choice has to **appear** (durable, one source fewer), **change future production** (the disabled source
    /// leaves the acquisition inputs) and **not remove or reorder the cards already published** — same Edition,
    /// same published card ids in the same order, same destination, same anchor — through the toggle and through a
    /// relaunch. The behaviour before this was measured: the destination was rewritten to `.source(remaining)`, a
    /// new Edition was published and all eight cards were replaced.
    func testSourceSelectionSurvivesRelaunchAndFiltersCanonicalSupply() async throws {
        FixtureTransport.feedItemCount.withLock { $0 = 8 }
        defer { FixtureTransport.feedItemCount.withLock { $0 = nil } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = root(directory: directory)
        await first.launch()
        let association = try XCTUnwrap(first.association)
        let initial = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(Set(initial.window.items.compactMap(\.sourceID)), Set(TrustedFeed.development.map(\.sourceID)),
            "premise: the published feed carries both selected sources")
        // The reader is deeper into the feed than the anchor the Edition started at.
        let deeper = try XCTUnwrap(initial.window.items.count > 3 ? initial.window.items[3] : nil,
            "premise: there is a card to advance the anchor to")
        await association.viewport(.init(anchor: .init(cardID: deeper.id, placement: .top)), activity: .forward)
        let atRest = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(atRest.window.anchor.cardID, deeper.id, "premise: the reader's position moved")
        let destination = first.currentContextKey.request
        let preferences = ReaderPreferencesStore(database: association.database)
        let versionBefore = try XCTUnwrap(preferences.load()?.selectionVersion)
        let publishedBefore = try PublicationStore(database: association.database)
            .segments(editionID: atRest.editionID).flatMap(\.cardIDs)
        XCTAssertFalse(publishedBefore.isEmpty, "premise: the Edition has published history")
        let eligibleBefore = try association.acquisition
            .eligibleTargets(for: FeedContext(key: association.contextKey)).map(\.id)

        try await first.searchSources("")
        try await first.toggleSource(TrustedFeed.development[1].sourceID)

        // (a) The choice appears: one source left, and the selection version is durable.
        XCTAssertEqual(first.feeds.map(\.sourceID), [TrustedFeed.development[0].sourceID])
        XCTAssertEqual(try preferences.load()?.selectionVersion, versionBefore + 1,
            "the toggle is a durable selection change")
        // (b) It changes future production: the disabled source is no longer an acquisition input.
        let current = try XCTUnwrap(first.association)
        XCTAssertTrue(eligibleBefore.contains(TrustedFeed.development[1].targetID),
            "control: the disabled source was an acquisition input before the toggle")
        let eligibleAfter = try current.acquisition
            .eligibleTargets(for: FeedContext(key: current.contextKey)).map(\.id)
        XCTAssertFalse(eligibleAfter.contains(TrustedFeed.development[1].targetID),
            "the disabled source stops being a future opportunity")
        XCTAssertTrue(eligibleAfter.contains(TrustedFeed.development[0].targetID),
            "the remaining source still supplies")
        // (c) …and it is not a navigation: destination, Edition, published cards and anchor stay where they were.
        XCTAssertEqual(first.currentContextKey.request, destination,
            "managing a source does not move the reader (UX12-C/R6)")
        let now = try XCTUnwrap(current.store.state.presentation)
        XCTAssertEqual(now.editionID, atRest.editionID, "the Edition being read is not replaced")
        let publishedAfter = try PublicationStore(database: association.database)
            .segments(editionID: now.editionID).flatMap(\.cardIDs)
        XCTAssertEqual(Array(publishedAfter.prefix(publishedBefore.count)), publishedBefore,
            "no published card is removed or reordered; the tail only grows")
        XCTAssertEqual(now.window.anchor, atRest.window.anchor, "the reader's anchor is where they left it")

        // (d) A relaunch restores the same history at the same position, with the reader's own selection.
        await current.background()
        await current.close()
        let reopened = root(directory: directory)
        XCTAssertEqual(reopened.feeds.map(\.sourceID), first.feeds.map(\.sourceID))
        await reopened.launch()
        XCTAssertEqual(reopened.currentContextKey.request, destination)
        let restored = try XCTUnwrap(reopened.association?.store.state.presentation)
        XCTAssertEqual(restored.editionID, atRest.editionID, "the relaunch shows that history, not a successor")
        XCTAssertEqual(restored.window.anchor, atRest.window.anchor, "the position survives the relaunch")
        let reopenedDatabase = try XCTUnwrap(reopened.association).database
        let publishedRestored = try PublicationStore(database: reopenedDatabase)
            .segments(editionID: restored.editionID).flatMap(\.cardIDs)
        XCTAssertEqual(Array(publishedRestored.prefix(publishedBefore.count)), publishedBefore,
            "the relaunch keeps every published card in its published order")
        // (e) The last selected source cannot be removed: an empty selection is refused and nothing moves.
        try await reopened.searchSources("")
        do { try await reopened.toggleSource(TrustedFeed.development[0].sourceID); XCTFail("Empty selection") }
        catch { XCTAssertEqual(reopened.feeds.count, 1) }
        XCTAssertEqual(reopened.currentContextKey.request, destination, "the refusal moves nothing either")
        await reopened.association?.close()
    }

    func testMainSourceMainRestoresPositionOfflineAndRejectsOldAssociation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = root(directory: directory)
        await root.launch()
        let old = try XCTUnwrap(root.association)
        try await produceAndAdmit(old)
        let initial = try XCTUnwrap(old.store.state.presentation)
        let card = try XCTUnwrap(initial.window.items.dropFirst().first)
        await old.viewport(.init(anchor: .init(cardID: card.id, placement: .top)), activity: .forward)
        let saved = try XCTUnwrap(old.store.state.presentation)
        try await root.selectContext(.source(TrustedFeed.development[1].sourceID))
        let other = try XCTUnwrap(root.association)
        XCTAssertFalse(old.active)
        XCTAssertNotEqual(other.store.state.presentation?.editionID, saved.editionID)
        XCTAssertTrue(other.store.state.presentation?.window.items.allSatisfy { $0.sourceDisplayName == "BBC Science" } == true)
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        try await root.selectContext(.main)
        let restored = try XCTUnwrap(root.association?.store.state.presentation)
        XCTAssertEqual(restored.editionID, saved.editionID)
        XCTAssertEqual(restored.window.anchor, saved.window.anchor)
        XCTAssertThrowsError(try old.install(.init(presentation: initial)))
        XCTAssertEqual(root.association?.store.state.presentation, restored)
        await root.association?.close()
    }

    /// T6: filters *are* context identity. A→B→A recovers A's own edition and reading position, B gets its own
    /// identity, and the retired association's callback can never install into the active store.
    func testT6FilterTransitionKeepsContextsSeparateAndStaleCallbackInert() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = root(directory: directory)
        await root.launch()
        let plain = try XCTUnwrap(root.association)
        let plainKey = root.currentContextKey
        XCTAssertTrue(plainKey.isDefaultSurface, "a reader who never filters is on the pre-T6 identity")
        let initial = try XCTUnwrap(plain.store.state.presentation)
        // Advance inside A and make the position durable, so A→B→A has something to recover. How many cards
        // the development feeds publish in the first breath varies, so the move does not depend on a second one.
        if let card = initial.window.items.dropFirst().first {
            await plain.viewport(.init(anchor: .init(cardID: card.id, placement: .top)), activity: .forward)
        } else {
            await plain.viewport(.init(anchor: initial.window.anchor), activity: .explicitTailApproach)
        }
        let a = try XCTUnwrap(plain.store.state.presentation)
        _ = try await plain.session.checkpointCurrentPosition(at: Date())

        // A → B: a filtered context is a different identity, its own association, its own edition.
        try await root.applyFilter(ReaderFilter(mood: .fun), preset: .everything)
        let filtered = try XCTUnwrap(root.association)
        XCTAssertFalse(filtered === plain)
        XCTAssertFalse(plain.active)
        XCTAssertEqual(root.currentFilter.mood, .fun)
        XCTAssertNotEqual(root.currentContextKey, plainKey)
        XCTAssertNotEqual(filtered.store.state.presentation?.editionID, a.editionID,
            "a filtered context never shows the plain context's edition")

        // B → A, offline: A's own edition and anchor come back.
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        try await root.applyFilter(.unrestricted, preset: .everything)
        let back = try XCTUnwrap(root.association)
        XCTAssertEqual(root.currentContextKey, plainKey)
        let restored = try XCTUnwrap(back.store.state.presentation)
        XCTAssertEqual(restored.editionID, a.editionID, "returning to A recovers A's edition")
        XCTAssertEqual(restored.window.anchor, a.window.anchor, "…and A's reading position")

        // T6 expiry: a pending deadline is resolved by an *explicit transition*, and by nothing else.
        let preferences = ReaderPreferencesStore(database: plain.database)
        try await root.applyFilter(ReaderFilter(languages: ["pt"], mood: .fun), preset: .everything)
        XCTAssertEqual(root.currentFilter.languages, ["pt"], "a fresh selection starts its own window")
        let renewedStart = try XCTUnwrap(preferences.load()?.filterExpiry.startsAt)
        XCTAssertEqual(renewedStart.timeIntervalSince1970, Date().timeIntervalSince1970, accuracy: 30,
            "applying a selection renews the window")
        // Age the record, then switch surfaces: that transition drops the overlay criteria.
        _ = try preferences.setFilterExpiry(ReaderFilterExpiry(isEnabled: true,
            startsAt: Date().addingTimeInterval(-5 * 3600)))
        try await root.selectContext(.main)
        XCTAssertTrue(root.currentFilter.languages.isEmpty, "an expired overlay selection is dropped")
        XCTAssertEqual(root.currentFilter.mood, .all)

        // The retired association is inert: neither its snapshot nor its callbacks reach the active store.
        let installed = back.store.state
        XCTAssertThrowsError(try back.install(.init(presentation: a))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .projectionSequenceMismatch)
        }
        await plain.viewport(.init(anchor: a.window.anchor), activity: .forward)
        XCTAssertThrowsError(try plain.install(.init(presentation: a))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .projectionSequenceMismatch)
        }
        XCTAssertEqual(back.store.state, installed)
        await back.close()
    }

    /// T6: the compatibility predicate is the whole decision — identity first, then the presentation rules that
    /// make a restored Edition reusable. A foreign identity is refused even when everything else matches.
    /// UX12-C adds the complement, stated here rather than implied: the reader's **selection version** is not one
    /// of those rules. It names which sources future production may use, not how published cards are presented, so
    /// an Edition published under an older selection is still the history the reader is reading.
    func testT6RevisionCompatibilityRequiresTheWholeIdentity() throws {
        let key = ContextKey(request: .main, filter: ReaderFilter(languages: ["pt"]))
        let foreign = ContextKey(request: .main, filter: ReaderFilter(languages: ["en"]))
        func revision(_ contextKey: ContextKey, selection: UInt64 = 7, eligibility: UInt64 = 2) -> EditorialRevision {
            .init(id: EditorialRevisionID(), contextKey: contextKey, catalogGeneration: .init(rawValue: 1),
                userSelectionVersion: PolicyVersion(rawValue: selection),
                eligibilityPolicyVersion: PolicyVersion(rawValue: eligibility),
                scoringPolicyVersion: PolicyVersion(rawValue: 1),
                sequencingPolicyVersion: PolicyVersion(rawValue: 2),
                exposurePolicyVersion: PolicyVersion(rawValue: 2),
                selectionSchemaVersion: .init(rawValue: 1))
        }
        XCTAssertTrue(FeedAssociation.mayShow(revision(key), for: key))
        XCTAssertFalse(FeedAssociation.mayShow(revision(foreign), for: key),
            "an edition from another filter is never shown")
        XCTAssertFalse(FeedAssociation.mayShow(revision(ContextKey(request: .main)), for: key),
            "the plain identity is not the filtered one either")
        XCTAssertTrue(FeedAssociation.mayShow(revision(key, selection: 6), for: key),
            "an Edition published under an older selection is the history being read, not a policy to re-run")
        XCTAssertFalse(FeedAssociation.mayShow(revision(key, eligibility: 1), for: key),
            "an older eligibility policy is refused")
        // Equivalent selections are the same identity, so they are compatible.
        let equivalent = ContextKey(request: .main, filter: ReaderFilter(languages: ["pt"], mood: .all))
        XCTAssertTrue(FeedAssociation.mayShow(revision(equivalent), for: key))
    }

    /// R2 review: the mapping is exact, never a threshold. A version this build does not know must not be
    /// silently treated as v3, and v2 must keep the behavior its Editions were published under.
    func testSequencingVersionMappingIsExplicit() throws {
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 1)), .recencyDescending)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 2)), .recencyAlternatingSources)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 3)), .recencyAlternatingSourcesBySupplyShare)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 4)), .recencyAlternatingSourcesByWeightedSupplyShare)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 5)), .recencyDescending,
            "v5's alternation shape is supplied by the composition that knows its scoring; the fallback is recency")
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 6)), .maximumDistance,
            "fresh v6 editions use maximum distance")
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 7)), .recencyDescending,
            "an unknown future version does not inherit v6")
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 99)), .recencyDescending)
    }

    /// The two live paths at the 5/6 seam: a fresh Edition says 6 and gets maximum distance; a restored v5
    /// Edition keeps the shaped behavior its composition supplied, not the static fallback.
    func testFreshSixAndRestoredFiveKeepDistinctSequencingBehavior() throws {
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 6)), .maximumDistance)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 5)), .recencyDescending,
            "restored v5 keeps its composition-shaped policy; only a fresh Edition is 6")
        XCTAssertNotEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 6)),
            FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 5)))
    }

    /// R2-D2/R2-D8: a behavior change gets its own EditorialRevision identity. `PublicationStore`
    /// rejects a second Edition whose `editorial_revision_id` matches an existing row with different
    /// revision content, so the identity must carry every version that changes the behavior — otherwise
    /// the next publication on an installation that already holds a v2 Edition would fail.
    func testASequencingBehaviorChangeGetsItsOwnEditorialRevisionIdentity() throws {
        let key = ContextKey(request: .main)
        let encoded = try JSONEncoder().encode(key).base64EncodedString()
        // The derivation an existing installation's v2 Edition was stored under.
        let storedUnderV2 = LegacyCatalogImport.stableUUID(namespace: "feedmine.editorial.context",
            key: encoded + "|" + "2")
        // The derivation this build uses for a v3 Edition of the same context and selection.
        let storedUnderV3 = LegacyCatalogImport.stableUUID(namespace: "feedmine.editorial.context",
            key: encoded + "|" + "2" + "|scoring:1|sequencing:3")
        XCTAssertNotEqual(storedUnderV2, storedUnderV3,
            "a v3 Edition must not reuse the identity a v2 Edition was persisted under")
    }

    /// F07/T6: the four-hour overlay deadline is a product promise, and **a launch is a boundary like any
    /// other transition**. The app used to adopt the persisted context verbatim, so an overlay the reader
    /// could no longer see stayed in force on every launch and quietly excluded everything the discovery
    /// brought: measured on a physical device, a `languages: ["pt"]` overlay outlived its window by a day
    /// and the feed starved with "no stories" the whole time, with no way out but an explicit switch.
    func testALaunchDropsAnExpiredOverlaySelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalog = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let starter = try TrustedFeed.catalog(limit: 1, resourceURL: catalog)

        // A reader who narrowed the feed by language, and let that window expire before closing the app.
        do {
            let database = try RuntimeDatabase(location: .init(directory: directory))
            let preferences = ReaderPreferencesStore(database: database)
            _ = try preferences.initialize(sourceKeys: starter.map(\.principal))
            _ = try preferences.setContext(ContextKey(request: .main, preset: .everything,
                filter: ReaderFilter(languages: ["pt"])))
            _ = try preferences.setFilterExpiry(ReaderFilterExpiry(isEnabled: true,
                startsAt: Date().addingTimeInterval(-5 * 3600)))
        }

        let reopened = root(directory: directory, feeds: starter)
        XCTAssertNil(reopened.startupFailure)
        XCTAssertTrue(reopened.currentFilter.languages.isEmpty,
            "an overlay the product itself had already expired does not survive a launch")
        XCTAssertEqual(reopened.currentFilter.mood, .all)
        let persisted = try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory))).load()
        XCTAssertTrue(try XCTUnwrap(persisted).activeContextKey.filter.languages.isEmpty,
            "the context the app rebuilds from is the resolved one, not the stale overlay")
    }

    /// v6: a fresh session declares maximum-distance sequencing, and a v2 revision stays usable
    /// for the Editions already published under it.
    func testFreshSessionDeclaresMaximumDistanceAndStillAcceptsV2Editions() async throws {
        let root = root()
        await root.launch()
        let association = try XCTUnwrap(root.association)
        // New editions use v6; the legacy v2 assertion below still protects already-published behavior.
        XCTAssertEqual(association.policy.sequencingPolicyVersion, PolicyVersion(rawValue: 6))
        XCTAssertEqual(association.policy.sequencing, .maximumDistance)
        let v2 = EditorialRevision(id: EditorialRevisionID(), contextKey: ContextKey(request: .main),
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 2),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 1),
            sequencingPolicyVersion: PolicyVersion(rawValue: 2), exposurePolicyVersion: PolicyVersion(rawValue: 2),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))
        XCTAssertTrue(FeedAssociation.mayShow(v2, for: ContextKey(request: .main)),
            "an Edition published under v2 is still shown, and keeps running under v2")
        await association.close()
    }

    /// T8: a saved smart bookmark is offered by the filter sheet with the identity it activates, and choosing
    /// it moves the session there through T6's transition — no second feed engine, no draft side effect.
    func testT8ASavedPresetIsOfferedAndActivatesItsOwnContext() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = root(directory: directory)
        await root.launch()
        // A search context, saved under a name: the terms and the scope travel with it.
        let search = try XCTUnwrap(SearchContext(query: "clima"))
        try await root.selectContext(.search(search))
        let savedPreset = try await root.saveCurrentContextAsPreset(named: "Clima", kind: .smartBookmark)
        let saved = try XCTUnwrap(savedPreset)
        XCTAssertEqual(saved.key.request, .search(search))
        XCTAssertEqual(saved.key.preset, saved.presetID)
        let rows = root.presetRows()
        XCTAssertEqual(rows.prefix(2).map(\.id), ["everything", "lastClicked"], "V1's two plain entries come first")
        let offered = try XCTUnwrap(rows.first { $0.id == saved.presetID.identityText })
        XCTAssertEqual(offered.name, "Clima")
        XCTAssertEqual(offered.key, saved.key, "the row carries the whole identity, not just a name")
        XCTAssertTrue(offered.isSelected, "the reader is on it")
        // Activating it is an ordinary transition: the session moves to the stored key.
        try await root.activateSavedPreset(saved.key)
        XCTAssertEqual(root.currentContextKey, saved.key)
        XCTAssertEqual(try XCTUnwrap(root.association).contextKey, saved.key,
            "the session runs on the identity the reader saved")
        // A collection the reader made is offered too, and without a key it is chosen as a plain criterion.
        _ = try root.collectCurrentSources(named: "Minhas")
        let collectionRow = try XCTUnwrap(root.presetRows().first { $0.name == "Minhas" })
        XCTAssertNil(collectionRow.key)
        if case .collection = collectionRow.preset {} else { XCTFail("a collection row carries its identity") }
        try await root.selectContext(.main)
    }

    /// T11: a curated feed's session ranks by the reader's own recipe, and editing the recipe is a different
    /// behaviour for the same identity — which keeps an older checkpoint from being restored under it.
    ///
    /// The feed has to be one the **catalogue** knows: a recipe weighs sources by what the catalogue says about
    /// them, so a source with no catalogue record is correctly left at the centre (the development feeds are
    /// exactly that, which is why this test reads the shipped catalogue).
    func testT11ACuratedFeedRanksByItsRecipeAndEditingChangesTheBehaviorVersion() async throws {
        let catalog = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        let root = AppComposition(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            feeds: try TrustedFeed.catalog(limit: 4, resourceURL: catalog),
            transportConfiguration: configuration)
        await root.launch()
        let feed = try XCTUnwrap(root.association?.feeds.first)
        let reader = try LegacyCatalogReader(catalogURL: catalog)
        let record = try XCTUnwrap(try reader.source(key: feed.principal),
            "a curated feed ranks by sources the catalogue knows")
        let node = try XCTUnwrap(record.nodeKeys.first, "every catalogue source is placed somewhere")
        // A recipe that asks for more of the node this feed is placed under.
        var recipe = FeedRecipeDefinition(discoveryLevel: 0.2)
        recipe.topicPreferences["topic:\(node)"] = .more
        let saved = try root.saveCuratedFeed(recipe, named: "Curadoria")
        let preset = try XCTUnwrap(saved, "a curated feed is saved with its recipe")
        try await root.activateSavedPreset(preset.key)
        let association = try XCTUnwrap(root.association)
        XCTAssertEqual(association.contextKey.preset, preset.presetID, "the session runs on the feed's identity")
        // Diagnostics: the pieces the ranking is built from, asserted before the policy itself.
        let summary = try XCTUnwrap(root.currentCuratedSummary(), "the hood can read the feed the reader is on")
        XCTAssertEqual(summary.answers.first?.key, "topic:\(node)", "the recipe states the node it answered on")
        let storedRecipe = try XCTUnwrap(try XCTUnwrap(root.makeCuratedCoordinator()).curatedPresets()
            .first(where: { $0.id == preset.id })?.recipe, "the recipe is stored with the preset")
        XCTAssertEqual(storedRecipe.topicPreferences["topic:\(node)"], ReaderPreferenceLevel.more)
        XCTAssertFalse(FeedRecipeResolution.multipliers(for: [
            FeedRecipeResolution.SourceFacts(identity: feed.principal, nodeKeys: record.nodeKeys,
                mediaKind: record.mediaKind, nature: record.nature, qualityScore: record.qualityScore)
        ], recipe: storedRecipe).isEmpty, "the recipe weighs a source the catalogue places on that node")
        XCTAssertFalse(root.feedFacts().isEmpty, "the app states the catalogue's facts for its own feeds")
        guard case .weighted(let weights) = association.policy.scoring else {
            return XCTFail("a curated feed ranks by its recipe, not by the baseline")
        }
        XCTAssertFalse(weights.isEmpty, "the weights name the sources the recipe says something about")
        let version = association.policy.scoringPolicyVersion
        XCTAssertEqual(preset.recipeRevision, 1, "a recipe starts at its first revision")
        XCTAssertEqual(version.rawValue, UInt64(preset.recipeRevision),
            "the published behaviour is the revision of the recipe it was ranked by")
        // Editing the recipe keeps the identity and changes the behaviour: a new scoring version.
        var edited = recipe
        edited.discoveryLevel = 0.9
        let updatedPreset = try root.updateCuratedFeed(preset, recipe: edited, named: "Curadoria")
        let updated = try XCTUnwrap(updatedPreset, "editing a curated feed returns the edited one")
        XCTAssertEqual(updated.id, preset.id, "an edit keeps the stored identity")
        let reread = try XCTUnwrap(try XCTUnwrap(root.makeCuratedCoordinator()).curatedPresets()
            .first(where: { $0.id == updated.id }))
        XCTAssertEqual(reread.recipeRevision, 2, "the edited revision is what the library holds")
        XCTAssertEqual(reread.recipe?.discoveryLevel, 0.9, "and it is the edited recipe")
        let resolved = root.scoring(for: updated.key)
        XCTAssertEqual(resolved.1, 2, "the app resolves the edited revision for that key")
        let before = try XCTUnwrap(root.association)
        try await root.activateSavedPreset(updated.key)
        let after = try XCTUnwrap(root.association)
        XCTAssertFalse(after === before, "a behaviour change replaces the session")
        XCTAssertEqual(after.contextKey.preset, preset.presetID, "editing is not a new feed")
        XCTAssertEqual(updated.recipeRevision, 2, "an edit is the next revision of the same recipe")
        XCTAssertEqual(after.policy.scoringPolicyVersion.rawValue, UInt64(updated.recipeRevision),
            "the new session ranks under the edited revision")
        XCTAssertNotEqual(after.policy.scoringPolicyVersion, version,
            "a different recipe is a different behaviour, so an older Edition is not reused")
    }

    func testS1SameSessionStoreAcrossViewportRefreshAndLifecycle() async throws {
        let (root, association) = try await launched()
        try await produceAndAdmit(association)
        let store = association.store
        let initial = try XCTUnwrap(store.state.presentation)
        let card = try XCTUnwrap(initial.window.items.dropFirst().first)
        await association.viewport(.init(anchor: .init(cardID: card.id, placement: .top)), activity: .forward)
        await root.background()
        await root.foreground()
        XCTAssertTrue(root.association === association)
        XCTAssertTrue(association.store === store)
        XCTAssertEqual(store.state.presentation?.provenance.sequenceID, initial.provenance.sequenceID)
        await association.close()
    }

    func testS2DelayedResultAndS7AtomicWorkRejection() async throws {
        let (_, association) = try await launched()
        try await produceAndAdmit(association)
        let a = try XCTUnwrap(association.store.state.presentation)
        let card = try XCTUnwrap(a.window.items.dropFirst().first)
        let bResult = try await association.session.submitViewport(.init(anchor: .init(cardID: card.id, placement: .top)))
        let b = try XCTUnwrap(bResult)
        try association.install(FeedPresentationState(presentation: b).reporting(.pending))
        let installed = association.store.state
        XCTAssertThrowsError(try association.install(FeedPresentationState(presentation: a).reporting(.failed(message: "late")))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .staleProjection)
        }
        XCTAssertEqual(association.store.state, installed)
        await association.close()
    }

    private enum RebuildRoute { case replacement, context, preset }

    private func assertAnswerDuringReconstruction(_ route: RebuildRoute) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: TrustedFeed.development.map(\.principal))
        var settings = ReaderSettings.standard
        settings.discoveryProfile = .neutral(languages: ["pt"])
        settings.discoveryProfile.topicPreferences["topic:90_countries/brazil"] = .more
        _ = try preferences.setSettings(settings)
        let root = root(directory: directory)
        await root.launch()
        let old = try XCTUnwrap(root.association)
        XCTAssertFalse(old.discovery.isEmpty)
        // A new profile forces the real detached catalogue read, giving the answer a controlled construction boundary.
        settings.discoveryProfile.topicPreferences = ["topic:04-technology-science": .more]
        _ = try preferences.setSettings(settings)
        let transition = Task { @MainActor in
            switch route {
            case .replacement: try await root.replaceSession()
            case .context: try await root.selectContext(.source(TrustedFeed.development[0].sourceID))
            case .preset: try await root.activateSavedPreset(.init(request: .main, preset: .lastClicked))
            }
        }
        // Observe the real retirement boundary, before the asynchronous constructor finishes.
        let limit = ProcessInfo.processInfo.systemUptime + 5
        while root.association != nil, ProcessInfo.processInfo.systemUptime < limit { await Task.yield() }
        XCTAssertNil(root.association, "The answer must land during construction")
        let answered = await root.voteOnTopic(nodeKey: "04-technology-science", level: .less)
        XCTAssertTrue(answered)
        try await transition.value
        let next = try XCTUnwrap(root.association)
        XCTAssertFalse(next === old)
        let catalog = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let expected = try ReaderDiscoveryBuilder(catalogURL: catalog).pool(for: .init(languages: ["pt"],
            excludedTopicNodeKeys: ["04-technology-science"]), limit: AppComposition.discoverySourceLimit)
        XCTAssertEqual(Set(next.discovery.map(\.sourceID)), Set(expected.entries.map { $0.source.id }),
            "The final association must read the answer received during construction")
        XCTAssertEqual(root.declaredLevel(forNode: "04-technology-science"), .less)
        await next.close()
    }

    func testAnswerDuringReplaceSessionIsApplied() async throws {
        try await assertAnswerDuringReconstruction(.replacement)
    }

    func testAnswerDuringContextTransitionIsApplied() async throws {
        try await assertAnswerDuringReconstruction(.context)
    }

    func testAnswerDuringPresetTransitionIsApplied() async throws {
        try await assertAnswerDuringReconstruction(.preset)
    }

    /// Kiro K-01/K-05 **wiring**, na forma que o arquiteto exigiu **depois de revisar o PR #3** ("a autorização
    /// DEBUG é derivada dos endpoints do catálogo; esse HEAD não deve ser mergeado"). Ele estava certo: o catálogo
    /// é entrada não confiável, e derivar dele deixaria uma linha de catálogo — ou um OPML importado — nomear um
    /// host da LAN e ser autorizada por isso. A autorização vem de um input que a **execução declara**.
    ///
    /// Três casos, medidos: a origem **declarada** publica (é o benchmark: o corpus é servido nesse host, e o
    /// catálogo que ele injeta nomeia esses endpoints — motivo pelo qual o catálogo não pode ser a fonte); a
    /// **mesma forma** de host, **não declarada**, é recusada antes do transporte; e um host **público** publica
    /// sem autorização nenhuma (o controle do arranjo).
    func testK05DeclaredOriginPublishesAndAnUndeclaredOneIsRefused() async throws {
        // `setenv` **dentro do helper** é o mesmo que o runner faz ao exportar a origem para o app: é a declaração
        // da execução, não um dado do catálogo. **Uma URL, com esquema, host e porta** — é o que o arquiteto exigiu
        // depois de revisar o HEAD anterior, e é o valor que o runner exporta (`bench/run.sh`).
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml", expected: true,
            "a origem DECLARADA pela execução tem de publicar")
        try await assertTheEndpointPublishes("http://10.77.0.9:8757/feed.xml", expected: false,
            "a mesma forma de host, NÃO declarada, tem de ser recusada — senão uma linha de catálogo autoriza a rede privada sozinha")
        try await assertTheEndpointPublishes("https://bench.example/feed.xml", expected: true,
            "um host público publica sem precisar de autorização (controle do arranjo)")
    }

    /// A exigência do arquiteto na revisão seguinte: a configuração declara **uma URL com esquema, host e porta** —
    /// não um host que o código converte em HTTP **e** HTTPS. Este caso é a prova de que ele foi obedecido: um valor
    /// que traz só `host:porta`, sem esquema, **não autoriza nada**, porque o código que sintetizasse os dois
    /// esquemas estaria autorizando mais do que a execução declarou — e é exatamente esse silêncio que se quer
    /// impossível.
    func testK05AnInexactOrInvalidDeclarationAuthorizesNothing() async throws {
        // Controle do arranjo, pela mesma porta do helper: a declaração exata autoriza.
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml", expected: true,
            "controle: a declaração exata autoriza")
        // Sem esquema: `host:porta` não é uma origem, e nenhum esquema pode ser inferido.
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml", expected: false,
            "sem esquema declarado, nenhum esquema pode ser inferido: host:porta não é uma origem",
            declaring: "10.77.0.1:8757")
        // Com caminho: **recusar, não limpar** — sanear esconderia que a execução declarou algo que não é origem.
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml", expected: false,
            "declarar com caminho tem de ser recusado, não saneado até virar origem",
            declaring: "http://10.77.0.1:8757/feed.xml")
        // Com credenciais: idem.
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml", expected: false,
            "declarar com credenciais tem de ser recusado", declaring: "http://u:p@10.77.0.1:8757")
        // Sem porta: a porta faz parte da origem.
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml", expected: false,
            "declarar sem porta não autoriza: a porta faz parte da origem", declaring: "http://10.77.0.1")
        // Porta DIFERENTE — a prova de que a configuração explícita chega ao app, e chega exata: quem declara 8756
        // não autoriza 8757.
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml", expected: false,
            "declarar outra porta não autoriza a porta do endpoint", declaring: "http://10.77.0.1:8756")
    }

    private func assertTheEndpointPublishes(_ raw: String, expected: Bool, _ message: String,
        declaring declared: String = "http://10.77.0.1:8757") async throws {
        // A declaração vive aqui, num lugar só: cada caso diz o que a execução declara, e a asserção mede se o app
        // obedeceu exatamente aquilo.
        setenv("FEEDMINE_BENCH_TRANSPORT_ORIGIN", declared, 1)
        defer { unsetenv("FEEDMINE_BENCH_TRANSPORT_ORIGIN") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let endpoint = URL(string: raw)!
        let feed = TrustedFeed(targetID: AcquisitionTargetID(), sourceID: SourceID(rawValue: UUID()),
            bindingID: SourceBindingID(), principal: endpoint.absoluteString, endpoint: endpoint,
            displayName: "fixture")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 20
        let root = AppComposition(directory: directory, feeds: [feed], transportConfiguration: configuration)

        await root.launch()
        XCTAssertNil(root.startupFailure)
        let association = try XCTUnwrap(root.association)
        let published = await Self.waitUntil(expected ? 20 : 8) { association.store.state.presentation != nil }
        if published != expected {
            // Why it behaved that way, instead of guessing: the run's own facts.
            XCTFail("\(message) — \(root.diagnosticsForTheWiringTest(association))")
        }
        await association.close()
    }

    private static func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Kiro K-06, achado 5, e o arquiteto fixou o que exigir: voltar a um contexto **preserva a edição, a âncora e
    /// a posição**, com histórico alcançável — **sem impor igualdade de tamanho da janela**, que é uma expectativa
    /// que o próprio `testS5` põe e que a arquitetura não promete.
    ///
    /// Dois testes, um com resposta no meio e um sem: a diferença entre eles é o experimento que localiza a causa.
    /// Se o ida-e-volta simples preserva e o respondido não, o custo está em responder — e responder não pode custar
    /// ao leitor a posição dele.
    func testK06RoundTripBetweenContextsKeepsTheEditionAnchorAndPosition() async throws {
        try await assertRoundTripKeepsTheReader(answering: false, switchingBy: .source)
    }

    /// O terceiro gêmeo: o **mesmo** ida-e-volta trocando por **filtro**, que é o caminho do teste verde que
    /// preserva a edição. É o experimento que separa "a troca de fonte é o problema" de "o meu arranjo é o
    /// problema" — sem ele, a hipótese fica no ar.
    func testK06RoundTripByFilterKeepsTheEdition() async throws {
        try await assertRoundTripKeepsTheReader(answering: false, switchingBy: .filter)
    }

    func testK06AnsweringInABetweenAAndBKeepsTheReaderWhereTheyWere() async throws {
        try await assertRoundTripKeepsTheReader(answering: true, switchingBy: .source)
    }

    private enum RoundTripSwitch { case source, filter }

    private func assertRoundTripKeepsTheReader(answering: Bool, switchingBy: RoundTripSwitch) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        // A **identidade** de A tem de ser a mesma na ida e na volta, senão o teste compara dois contextos e o
        // produto cunhar uma edição nova é o comportamento CERTO (contexto novo, edição nova). Trocar por filtro
        // é o controle que já provava isso: ele volta à mesma identidade e preserva.
        if case .source = switchingBy {
            try await root.selectContext(.source(TrustedFeed.development[0].sourceID))
        }
        let a = try XCTUnwrap(root.association)
        let aSnapshot = try XCTUnwrap(a.store.state.presentation)
        let aCard = try XCTUnwrap(aSnapshot.window.items.first)

        // A save the reader made in A, and the card they were reading there.
        let publication = try PublicationStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        try publication.toggleBookmark(cardID: aCard.id, at: Date())
        await a.viewport(.init(anchor: .init(cardID: aCard.id, placement: .top)), activity: .forward)
        let aAnchor = try XCTUnwrap(a.store.state.presentation).window.anchor
        // A posição durável antes de sair. Desde 2026-10-14 a observação estabelecida do leitor já a torna
        // durável (é o que um fechamento à força recupera), então este milestone não é mais o que a torna
        // possível: ele fica como o controle explícito do teste, e prova que o caminho de milestone continua
        // escrevendo a mesma posição.
        _ = try await a.session.checkpointCurrentPosition(at: Date())

        if answering {
            let answered = await root.voteOnTopic(nodeKey: "04-technology-science", level: .more)
            XCTAssertTrue(answered)
        }

        // Go to B, then come back to A — pelo caminho que o parâmetro escolhe.
        switch switchingBy {
        case .source: try await root.selectContext(.source(TrustedFeed.development[1].sourceID))
        case .filter: try await root.applyFilter(ReaderFilter(mood: .fun), preset: .everything)
        }
        // (B é uma identidade diferente de A nos dois casos: outra fonte, ou outro filtro.)
        let b = try XCTUnwrap(root.association)
        XCTAssertFalse(b === a, "ir a B constrói outra associação")
        switch switchingBy {
        case .source: try await root.selectContext(.source(TrustedFeed.development[0].sourceID))
        case .filter: try await root.applyFilter(.unrestricted, preset: .everything)
        }
        let back = try XCTUnwrap(root.association)

        let restored = try XCTUnwrap(back.store.state.presentation)
        // Fatos do store no log, para quem for ler este vermelho: onde exatamente o fio se rompeu. O diagnóstico
        // vem antes das asserções de propósito — uma asserção que falha primeiro esconde o que explica a falha.
        do {
            let db = try RuntimeDatabase(location: .init(directory: directory))
            let key = ContextKey(request: .source(TrustedFeed.development[0].sourceID))
            let stored = try SessionStore(database: db).checkpoint(for: key)
            let active = try SessionStore(database: db).checkpoint()
            let editionThere = try PublicationStore(database: db).edition(id: aSnapshot.editionID) != nil
            let restoredPub = try PublicationHistory(database: db).restore(backwardCapacity: 8,
                forwardCapacity: 16, contextKey: key)
            let revision = restoredPub?.edition.editorialRevision
            print("ROUNDTRIP_FACTS via=\(switchingBy) responding=\(answering) checkpoint-contexto="
                + "\(stored == nil ? "nil" : "presente") checkpoint-ativo=\(active == nil ? "nil" : "presente") "
                + "edicao-de-A-no-store=\(editionThere) restore-devolve-algo=\(restoredPub != nil)")
            if let revision {
                // As quatro comparações que o `mayShow` faz, uma a uma: é o que decide se a restauração é usada
                // ou descartada (e descartada significa edição nova).
                print("ROUNDTRIP_MAYSHOW contexto-da-revisao==chave: \(revision.contextKey == key)"
                    + " | selecao: revisao=\(revision.userSelectionVersion.rawValue)"
                    + " | elegibilidade: revisao=\(revision.eligibilityPolicyVersion.rawValue)"
                    + " | scoring: revisao=\(revision.scoringPolicyVersion.rawValue)")
                let presentedEdition = try PublicationStore(database: db).edition(id: restored.editionID)
                let presentedRevision = presentedEdition?.editorialRevision.id
                print("ROUNDTRIP_KEY chave-consultada=\(key.canonicalIdentity)")
                print("ROUNDTRIP_PRESENTED mesma-revisao-que-a-restaurada: "
                    + "\(presentedRevision == revision.id) (apresentada=\(presentedRevision?.rawValue.uuidString.prefix(8) ?? "nil") "
                    + "restaurada=\(revision.id.rawValue.uuidString.prefix(8)))")
            }
        } catch { print("ROUNDTRIP_FACTS falha ao ler o store: \(error)") }
        XCTAssertEqual(restored.editionID, aSnapshot.editionID,
            "voltar a A devolve a edição de A (responding: \(answering))")
        XCTAssertEqual(restored.window.anchor, aAnchor,
            "a âncora de A é a mesma — o leitor volta para onde estava")
        XCTAssertEqual(restored.window.items.first?.id, aCard.id,
            "e o topo da janela é o mesmo card")
        if answering {
            XCTAssertEqual(root.declaredLevel(forNode: "04-technology-science"), .more,
                "a resposta dada em A sobrevive à ida a B e à volta")
            XCTAssertTrue(try publication.bookmarkedCardIDs().contains(aCard.id),
                "os salvos do leitor sobrevivem à ida e à volta")
        }
        await back.close()
    }

    func testS3ReplacementAndS4OldCallbackCannotInstall() async throws {
        let (root, old) = try await launched()
        let oldStore = old.store
        let oldSnapshot = try XCTUnwrap(oldStore.state.presentation)
        await old.background()
        try await root.replaceSession()
        let next = try XCTUnwrap(root.association)
        XCTAssertFalse(old.active)
        XCTAssertFalse(next.store === oldStore)
        let current = try XCTUnwrap(next.store.state.presentation)
        XCTAssertEqual(current.editionID, oldSnapshot.editionID)
        XCTAssertNotEqual(current.provenance.sequenceID, oldSnapshot.provenance.sequenceID)
        let installed = next.store.state
        XCTAssertThrowsError(try next.install(.init(presentation: oldSnapshot))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .projectionSequenceMismatch)
        }
        await old.viewport(.init(anchor: oldSnapshot.window.anchor), activity: .forward)
        XCTAssertThrowsError(try old.install(.init(presentation: oldSnapshot))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .projectionSequenceMismatch)
        }
        XCTAssertEqual(next.store.state, installed)
        await next.close()
    }

    func testS5OfflineReopenRestoresEditionWithFreshProvenance() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        let root = AppComposition(directory: directory, feeds: TrustedFeed.development, transportConfiguration: configuration)
        await root.launch()
        let old = try XCTUnwrap(root.association)
        try await produceAndAdmit(old)
        // **Uma segunda publicação**, e ela é o que torna o alcance dos DOIS lados uma asserção real: a primeira
        // deixa o leitor no topo do store (medido: 9 cards e a âncora na última), e ali não existe posterior para
        // alcançar — exigir isso seria exigir conteúdo que o fixture não tem, que foi exatamente o erro que a
        // versão anterior desta asserção cometeu. Com a segunda, o leitor fica com histórico dos dois lados, e a
        // âncora tem de continuar sendo a posição dele (ela não anda para o conteúdo novo).
        try await produceAndAdmit(old)
        let snapshot = try XCTUnwrap(old.store.state.presentation)
        await old.background()
        await old.close()
        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let reopened = AppComposition(directory: directory, feeds: TrustedFeed.development, transportConfiguration: configuration)
        await reopened.launch()
        XCTAssertNil(reopened.startupFailure)
        let next = try XCTUnwrap(reopened.association)
        XCTAssertFalse(next.store === old.store)
        let restored = try XCTUnwrap(next.store.state.presentation)
        XCTAssertEqual(restored.editionID, snapshot.editionID,
            "reabrir devolve a EDIÇÃO do leitor — é a prova de acesso ao histórico, e ela fica")
        XCTAssertNotEqual(restored.provenance.sequenceID, snapshot.provenance.sequenceID,
            "com proveniência NOVA: a reabertura não é uma reinstalação do estado antigo")
        // A janela não é comparada por **igualdade de tamanho**: o arquiteto fixou que preservar significa a
        // edição, a **âncora** e a posição, e que impor o tamanho da janela exige mais do que a arquitetura
        // promete (a janela é recalculada com as capacidades pedidas, e o número de cards publicados varia).
        XCTAssertEqual(restored.window.anchor, snapshot.window.anchor,
            "a âncora volta a ser a mesma — e a âncora É a posição do leitor")
        // **Alcance do histórico** (o arquiteto pediu, na revisão do PR #3): o que se afirma não é a *forma* da
        // janela, é o **alcance** dela atrás da âncora — o leitor tem de continuar voltando a ter o que já tinha.
        // O witness é o próprio snapshot, com as capacidades do produto (8 atrás / 16 à frente). Duas versões
        // anteriores desta asserção erraram o juiz, e as duas estão registradas porque o erro é instrutivo: uma
        // exigia "posterior" fixo (num teste sem viewport a âncora é o topo do store, então exigia conteúdo
        // inexistente) e a outra perguntava ao store, cujo `cards(around:)` **ignora visibilidade** — o que ele
        // devolvia eram cartas do segmento novo, ainda não visível ao leitor, e o produto acerta em não mostrá-las.
        let items = restored.window.items
        let index = try XCTUnwrap(items.firstIndex { $0.id == restored.window.anchor.cardID },
            "a âncora tem de estar dentro da janela restaurada")
        let before = snapshot.window.items.firstIndex { $0.id == snapshot.window.anchor.cardID } ?? 0
        XCTAssertGreaterThanOrEqual(index, min(before, 8),
            "o alcance ANTERIOR à âncora não pode encolher: tinha \(before) antes, a restauração devolveu \(index)")
        XCTAssertGreaterThan(items.count, 1, "a janela restaurada não é degenerada")
        // keepsAdmittedHead restaura a cabeça completa do leitor, não um recorte de oito cartas.
        // O banco pode conter cartas publicadas mas ainda não admitidas; não confundir essas populações.
        let admittedBeforeClose = Set(snapshot.window.items.map(\.id))
        let restoredIDs = Set(items.map(\.id))
        let editionCards = try PublicationStore(database: next.database).cards(
            editionID: restored.editionID, around: restored.window.anchor.cardID,
            backwardCapacity: Int.max, forwardCapacity: Int.max)
        let editionIDs = Set(editionCards.map(\.id))
        XCTAssertEqual(editionIDs.count, editionCards.count, "a Edition não pode repetir IDs publicados")
        XCTAssertEqual(restoredIDs.count, items.count, "a janela não pode repetir IDs admitidos")
        XCTAssertTrue(restoredIDs.isSubset(of: editionIDs), "todo card restaurado pertence à Edition")
        XCTAssertTrue(admittedBeforeClose.isSubset(of: restoredIDs),
            "reabrir offline deve preservar TODOS os cards admitidos antes de fechar")
        let oldest = try XCTUnwrap(items.first)
        XCTAssertEqual(oldest.id, editionCards.first?.id,
            "a restauração com keepsAdmittedHead deve alcançar o início da Edition")

        // Andar para trás não implica que novas cartas tenham de aparecer: elas já podem estar
        // na janela restaurada. O gesto correto é backward, não explicitTailApproach.
        await next.viewport(
            ViewportObservation(anchor: PresentationAnchor(cardID: oldest.id, placement: .top)),
            activity: .backward)
        let movedBack = try XCTUnwrap(next.store.state.presentation)
        XCTAssertEqual(movedBack.window.anchor.cardID, oldest.id)
        XCTAssertEqual(movedBack.window.items.first?.id, oldest.id)
        XCTAssertTrue(Set(movedBack.window.items.map(\.id)).isSubset(of: editionIDs))

        // Regressar à posição original exige, quando necessário, percorrer a reserva futura
        // admitindo a cauda local — nunca enviar diretamente uma âncora fora da janela.
        for _ in 0..<editionCards.count {
            let current = try XCTUnwrap(next.store.state.presentation)
            if current.window.items.contains(where: { $0.id == restored.window.anchor.cardID }) { break }
            guard let tail = current.window.items.last else { break }
            await next.viewport(.init(anchor: .init(cardID: tail.id, placement: .top)),
                activity: .explicitTailApproach)
        }
        XCTAssertTrue(next.store.state.presentation?.window.items.contains(where: {
            $0.id == restored.window.anchor.cardID
        }) == true, "o card onde o leitor estava deve permanecer alcançável offline")
        await next.viewport(ViewportObservation(anchor: restored.window.anchor), activity: .forward)
        let returned = try XCTUnwrap(next.store.state.presentation)
        XCTAssertEqual(returned.window.anchor, restored.window.anchor,
            "a navegação para trás e de volta não altera a posição original")
        XCTAssertTrue(Set(returned.window.items.map(\.id)).isSubset(of: editionIDs))
        print("C01 S5: editionDistinct=\(editionIDs.count) previouslyAdmitted=\(admittedBeforeClose.count) "
            + "restoredAdmitted=\(restoredIDs.count) afterBackward=\(movedBack.window.items.count) "
            + "returnedAdmitted=\(returned.window.items.count); snapshot != geometric viewport")
        await next.close()
    }

    /// A **regressão vermelha** que o arquiteto exigiu: "IDs efetivamente publicados e acessíveis antes de fechar,
    /// além do `backwardCapacity`; exigir alcance depois de reabrir e navegação de volta para frente". Ela falha
    /// no HEAD em que foi escrita — a edição tem cartas além da janela restaurada, e nenhum gesto para trás as
    /// alcança. Fica vermelha como prova da perda; o commit que a deixa verde é o da admissão para trás.
    func testReopeningOfflineKeepsCardsBeyondTheBackwardCapacityReachable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        let root = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
        ReadingFixture.generation.withLock { $0 = 0 }
        defer { ReadingFixture.generation.withLock { $0 = 0 } }
        await root.launch()
        let old = try XCTUnwrap(root.association)
        var publishedWhileOpen = Set(old.store.state.presentation?.window.items.map(\.id) ?? [])
        // IDs actually admitted while reading, across distinct batches: one bounded window
        // cannot be the oracle for all previously reachable history.
        for _ in 0..<4 {
            ReadingFixture.generation.withLock { $0 += 1 }
            try await produceAndAdmit(old)
            publishedWhileOpen.formUnion(old.store.state.presentation?.window.items.map(\.id) ?? [])
        }
        let before = try XCTUnwrap(old.store.state.presentation)
        XCTAssertGreaterThan(publishedWhileOpen.count, 25,
            "the previously reached history must exceed a full presentation window")
        await old.background()
        await old.close()

        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let reopened = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
        await reopened.launch()
        let next = try XCTUnwrap(reopened.association)
        let restored = try XCTUnwrap(next.store.state.presentation)
        XCTAssertEqual(restored.window.anchor, before.window.anchor, "a âncora volta a ser a posição do leitor")

        // Anda para trás como o leitor andaria: re-ancora no topo da janela e pede mais. O que aparecer só pode vir
        // do store — o transporte continua rejeitando —, então isto mede o histórico local, não a rede.
        var reachable = Set(restored.window.items.map(\.id))
        for _ in 0..<40 {
            guard let head = next.store.state.presentation?.window.items.first else { break }
            next.store.submitViewport(
                ViewportObservation(anchor: PresentationAnchor(cardID: head.id, placement: .top)),
                activity: .backward)
            var step: Set<PublicationCardID>?
            let deadline = Date().addingTimeInterval(4)
            repeat {
                step = Set(next.store.state.presentation?.window.items.map(\.id) ?? [])
                if let step, !step.isSubset(of: reachable) { break }
                try await Task.sleep(for: .milliseconds(120))
            } while Date() < deadline
            guard let step, !step.isSubset(of: reachable) else { break }
            reachable.formUnion(step)
        }
        let lost = publishedWhileOpen.subtracting(reachable)
        XCTAssertTrue(lost.isEmpty,
            "\(lost.count) cartas que o leitor alcançava ANTES de fechar não voltam por nenhum gesto para trás: "
                + lost.map(\.rawValue.uuidString).sorted().joined(separator: ", "))
        // E a segunda metade da exigência: **navegação de volta para frente**. Depois de andar para trás, o leitor
        // tem de poder retornar à posição em que estava — a história ganha acima dele não pode empurrá-lo nem
        // afastar o que ele já tinha.
        // Return by actual admissions, rather than submitting an off-window anchor (a no-op).
        for _ in 0..<40 {
            let items = next.store.state.presentation?.window.items ?? []
            if items.contains(where: { $0.id == before.window.anchor.cardID }) { break }
            guard let tail = items.last else { break }
            await next.viewport(.init(anchor: .init(cardID: tail.id, placement: .top)), activity: .explicitTailApproach)
        }
        next.store.submitViewport(
            ViewportObservation(anchor: PresentationAnchor(cardID: before.window.anchor.cardID, placement: .top)),
            activity: .forward)
        // `submitViewport` na fachada é uma emissão: quem executa é o consumidor externo, de forma assíncrona. Ler
        // o estado sem esperar mediria a corrida, não o produto — então espera-se, como a caminhada para trás faz.
        var returned: FeedPresentationSnapshot?
        let returnDeadline = Date().addingTimeInterval(5)
        repeat {
            returned = next.store.state.presentation
            if returned?.window.anchor.cardID == before.window.anchor.cardID { break }
            try await Task.sleep(for: .milliseconds(120))
        } while Date() < returnDeadline
        XCTAssertEqual(returned?.window.anchor.cardID, before.window.anchor.cardID,
            "voltar para frente tem de re-ancorar na posição do leitor")
        XCTAssertTrue(Set(returned?.window.items.map(\.id) ?? []).contains(before.window.anchor.cardID),
            "e a carta onde ele estava tem de continuar admitida depois de o histórico aparecer acima dela")
        await next.close()
    }

    /// A demonstração que o arquiteto exigiu depois de aceitar o reparo: **memória limitada durante navegação
    /// longa**, para trás e para frente, e **sem perder acesso** ao que saiu da janela. Ele está certo em separar
    /// as duas coisas: limitar *cada* extensão por `backwardCapacity - anchorIndex` não limita a janela **total** —
    /// dez passos para trás podem prepender dez lotes, e a lista cresce sem teto enquanto cada passo parece
    /// obediente. Aqui a janela é medida a cada passo.
    /// A decisão do dono (2026-10-13) mudou o que este teste afirma: a janela **não** é mais limitada nos dois
    /// sentidos — nada acima do leitor é removido, então ela cresce com o quanto ele leu. O que continua valendo, e
    /// é o que a V1 também garantia, é o teto **à frente** (a reserva a partir da âncora) e a acessibilidade de tudo
    /// o que o leitor já alcançava.
    func testLongNavigationKeepsTheForwardReserveBoundedAndEverythingReachable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        let root = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
        await root.launch()
        let old = try XCTUnwrap(root.association)
        // **Oito publicações com itens DISTINTOS** (a geração do fixture): cada uma traz 24 itens novos, então a
        // edição passa a ter ~190 cartas — muito mais do que uma janela. Com o fixture parado, cada publicação
        // republicava os mesmos 24 itens, a edição saturava em ~20 cartas e a navegação longa nunca chegava a
        // exercitar o limite (medido: a janela não passava de 20). O arranjo é a prova; sem ele o teste é vacuoso.
        ReadingFixture.generation.withLock { $0 = 0 }
        defer { ReadingFixture.generation.withLock { $0 = 0 } }
        var publishedWhileOpen = Set(old.store.state.presentation?.window.items.map(\.id) ?? [])
        for _ in 0..<8 {
            try await produceAndAdmit(old)
            publishedWhileOpen.formUnion(old.store.state.presentation?.window.items.map(\.id) ?? [])
            ReadingFixture.generation.withLock { $0 += 1 }
        }
        XCTAssertGreaterThan(publishedWhileOpen.count, 25,
            "the reachability oracle must include cards outside the final bounded window")
        await old.background()
        await old.close()

        FixtureTransport.rejecting.withLock { $0 = true }
        defer { FixtureTransport.rejecting.withLock { $0 = false } }
        let reopened = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
        await reopened.launch()
        let next = try XCTUnwrap(reopened.association)
        let restored = try XCTUnwrap(next.store.state.presentation)
        // keepsAdmittedHead preserva o histórico anterior; só a reserva posterior tem teto.
        let restoredItems = restored.window.items
        let restoredAnchorIndex = try XCTUnwrap(restoredItems.firstIndex {
            $0.id == restored.window.anchor.cardID
        })
        let aheadOnRestore = restoredItems.count - restoredAnchorIndex - 1
        XCTAssertLessThanOrEqual(aheadOnRestore, 16,
            "a restauração deve limitar apenas a reserva à frente (\(aheadOnRestore) cards)")
        print("C01 long navigation: restored=\(restoredItems.count) behind=\(restoredAnchorIndex) ahead=\(aheadOnRestore)")

        var reachable = Set(restored.window.items.map(\.id))
        /// O teto que a decisão do dono preservou: a reserva **à frente** da âncora. O total não é mais limitado,
        /// porque a cabeça é mantida.
        func assertForwardReserveBounded(anchoredAt card: PublicationCardID, _ what: String) {
            let window = next.store.state.presentation?.window.items ?? []
            guard let anchorIndex = window.firstIndex(where: { $0.id == card }) else { return }
            let ahead = window.count - anchorIndex - 1
            XCTAssertLessThanOrEqual(ahead, 16, "\(what): a reserva à frente tinha \(ahead) cartas, acima do teto de 16")
        }
        /// A cabeça da janela: só anda para trás — um avanço nunca a remove.
        var windowHead = restored.window.items.first?.id
        func observe(_ activity: RunwayActivity, at card: PublicationCardID) async throws -> [PublicationCardID] {
            let previous = next.store.state.presentation?.window.items.map(\.id) ?? []
            next.store.submitViewport(
                ViewportObservation(anchor: PresentationAnchor(cardID: card, placement: .top)), activity: activity)
            var seen = previous
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                seen = next.store.state.presentation?.window.items.map(\.id) ?? []
                if seen != previous { break }
                try await Task.sleep(for: .milliseconds(120))
            }
            return seen
        }

        // **Percurso FRENTE → TRÁS → FRENTE**, na ordem que o arquiteto pediu, com o teto afirmado nas duas
        // direções: ele decidiu que crescer para frente sem limite também é defeito, e o produto passou a cortar nos
        // dois lados. A rede continua rejeitada, então tudo o que aparecer é **rematerialização offline** do store.
        for _ in 0..<10 {
            guard let tail = next.store.state.presentation?.window.items.last else { break }
            let ids = try await observe(.explicitTailApproach, at: tail.id)
            reachable.formUnion(ids)
            let window = next.store.state.presentation?.window.items ?? []
            XCTAssertEqual(window.first?.id, windowHead,
                "frente: a cabeça da janela não se move — nada acima do leitor é removido")
            assertForwardReserveBounded(anchoredAt: tail.id, "frente")
            windowHead = window.first?.id
        }
        // Anda para trás **até não haver novidade**, e não um número fixo de passos: com uma edição de ~190 cartas e
        // oito por passo, dez passos não percorrem o histórico — foi assim que a versão anterior deste teste acusou
        // 24 cartas "inacessíveis" que eram, na verdade, cartas que a caminhada nunca visitou.
        var step = 0
        while step < 40 {
            guard let head = next.store.state.presentation?.window.items.first else { break }
            let ids = try await observe(.backward, at: head.id)
            reachable.formUnion(ids)
            // Andar para trás estende a janela para trás; a carta que era a cabeça continua nela — nada acima do
            // leitor é removido. A reserva à frente só é limitada por uma admissão, e aqui a âncora é a cabeça.
            let window = next.store.state.presentation?.window.items ?? []
            if let windowHead { XCTAssertTrue(window.contains(where: { $0.id == windowHead }),
                "passo \(step + 1) para trás: a cabeça anterior saiu da janela") }
            windowHead = window.first?.id
            step += 1
            // Previously visited IDs still need to be crossed on the way to older history.
            // Stop at the actual boundary, not when this step overlaps the earlier forward walk.
            if ids.first == head.id { break }
        }
        // E de volta para frente: a cabeça continua onde estava e a reserva à frente continua limitada.
        for _ in 0..<10 {
            guard let tail = next.store.state.presentation?.window.items.last else { break }
            let ids = try await observe(.explicitTailApproach, at: tail.id)
            reachable.formUnion(ids)
            let window = next.store.state.presentation?.window.items ?? []
            XCTAssertEqual(window.first?.id, windowHead,
                "volta para frente: a cabeça da janela não se move — nada acima do leitor é removido")
            assertForwardReserveBounded(anchoredAt: tail.id, "volta para frente")
            windowHead = window.first?.id
        }
        // **Acesso preservado**: tudo o que o leitor alcançava antes de fechar continua re-alcançável por gesto,
        // mesmo depois de a janela ter reciclado as cartas — sair da janela não é perder o conteúdo.
        let lost = publishedWhileOpen.subtracting(reachable)
        XCTAssertTrue(lost.isEmpty,
            "\(lost.count) cartas ficaram inacessíveis depois da navegação longa: "
                + lost.map(\.rawValue.uuidString).sorted().joined(separator: ", "))
        await next.close()
    }

    func testS6NewerReverseProjectionAccepted() async throws {
        let (_, association) = try await launched()
        try await produceAndAdmit(association)
        let first = try XCTUnwrap(association.store.state.presentation)
        let later = try XCTUnwrap(first.window.items.dropFirst().first)
        let forwardResult = try await association.session.submitViewport(.init(anchor: .init(cardID: later.id, placement: .top)))
        let forward = try XCTUnwrap(forwardResult)
        try association.install(.init(presentation: forward))
        let reverseResult = try await association.session.submitViewport(.init(anchor: first.window.anchor))
        let reverse = try XCTUnwrap(reverseResult)
        XCTAssertGreaterThan(reverse.provenance.position, forward.provenance.position)
        try association.install(.init(presentation: reverse))
        XCTAssertEqual(association.store.state.presentation?.window.anchor, first.window.anchor)
        await association.close()
    }

    /// U1-P2: the approved V1 branding imagesets resolve by their exact catalog names from the
    /// application bundle, and no palette-constructed name resolves. V1 built names such as
    /// `Placeholder-Article-<palette>` that did not exist in its own catalog; U1 must not
    /// reproduce that, so the exact names live in the token authority and nowhere else.
    @MainActor
    func testU1ApprovedBrandingAssetsResolveFromTheApplicationBundle() throws {
        let approved = ["Wordmark-Light", "Wordmark-Dark", "Symbol-Gradient", "Symbol-Ink",
            "Splash-Dark", "Placeholder-Article", "Placeholder-Podcast", "Placeholder-Forum", "Placeholder-Video"]
        for name in approved {
            XCTAssertNotNil(UIImage(named: name), "approved imageset must resolve: \(name)")
        }
        for constructed in ["Placeholder-Article-amber", "Placeholder-Video-blue", "Wordmark-Light-Dark"] {
            XCTAssertNil(UIImage(named: constructed), "no constructed asset name may resolve: \(constructed)")
        }
        // U1 does not touch the distribution icon or its iPad variants. App icons are not named
        // images, so the proof reads the built Info.plist instead of UIImage(named: "AppIcon").
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertEqual(primary["CFBundleIconFiles"] as? [String], ["AppIcon60x60"])
        // `CFBundleIcons~ipad` is not readable through Bundle on an iPhone-idiom process, so the
        // iPad variant is proven by its bundled file, which has existed since build 22.
        XCTAssertNotNil(Bundle.main.path(forResource: "AppIcon76x76@2x~ipad", ofType: "png"),
            "the iPad app icon variant must stay in the bundle")
        XCTAssertEqual(FeedDesignTokens.AssetName.wordmark(for: .light), "Wordmark-Light")
        XCTAssertEqual(FeedDesignTokens.AssetName.wordmark(for: .dark), "Wordmark-Dark")
        XCTAssertEqual(FeedDesignTokens.AssetName.symbolGradient, "Symbol-Gradient")
    }

    /// U1-P1: the token palette is adaptive by construction. `simctl ui appearance` **does** reach apps on this
    /// host: measured 2026-10-17 on the iOS 26.5 simulator, the system Settings app's own surface reads `#1C1C1E`
    /// in dark and `#FFFFFF` in light. Adaptation is still proven here by resolving the tokens under both trait
    /// collections, because that is the token's own contract and it needs no device state; the presentation's
    /// appearance is measured in pixels by `FeedMineUITests/AppearanceLegibilityUITests`.
    @MainActor
    func testU1TokenPaletteAdaptsToAppearanceWithoutAnOverlay() throws {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func resolved(_ color: Color, _ traits: UITraitCollection) -> [CGFloat] {
            let values = UIColor(color).resolvedColor(with: traits).cgColor.components ?? []
            return values.map { ($0 * 1000).rounded() / 1000 }
        }
        for (name, token) in [("cardSurface", FeedDesignTokens.Palette.cardSurface),
            ("mediaPlaceholder", FeedDesignTokens.Palette.mediaPlaceholder)] {
            let lightValue = resolved(token, light)
            let darkValue = resolved(token, dark)
            XCTAssertNotEqual(lightValue, darkValue, "\(name) must adapt to the appearance")
            XCTAssertFalse(lightValue.isEmpty, "\(name) must resolve to real components")
        }
        // The text roles follow the same system labels, so contrast comes from the system rather
        // than from a darkening overlay.
        XCTAssertNotEqual(resolved(.primary, light), resolved(.primary, dark))
        XCTAssertNotEqual(resolved(FeedDesignTokens.Palette.accent, light), resolved(FeedDesignTokens.Palette.accent, dark))
    }

    /// U2: saved articles come from the existing bookmark authority (no second store, no schema
    /// change) and a saved article resolves its frozen action even though it is not in the
    /// presented window — while the feed's own open guard stays exactly as it was.
    @MainActor
    func testU2SavedArticlesUseTheBookmarkAuthorityAndOpenOutsideTheWindow() async throws {
        let (root, association) = try await launched()
        let publication = PublicationStore(database: association.database)
        let window = try XCTUnwrap(association.store.state.presentation?.window.items)
        let linked = try XCTUnwrap(window.first { item in
            (try? publication.card(id: item.id))?.primaryActionKind == "externalURL"
        }, "a real published card must carry an external action")
        try publication.toggleBookmark(cardID: linked.id, at: Date())
        let saved = try association.savedArticles()
        XCTAssertEqual(saved.map(\.id), [linked.id])
        XCTAssertEqual(saved.first?.title, linked.title)
        XCTAssertEqual(saved.first?.source, linked.sourceDisplayName)
        // The composition resolves the URL and hands it to the host; the UI never sees a URL.
        var opened: URL?
        root.onExternalURL = { opened = $0 }
        association.openSaved(linked.id)
        let record = try XCTUnwrap(publication.card(id: linked.id))
        XCTAssertEqual(opened?.absoluteString, record.primaryActionReference)
        // Removing the bookmark removes the row.
        try publication.toggleBookmark(cardID: linked.id, at: Date())
        let emptyRead = try association.savedArticles()
        XCTAssertTrue(emptyRead.isEmpty)
        await association.close()
    }

    /// F01, the product's own promise: a reader who named interests and a language gets **sources they never
    /// named**, out of the bundled catalogue, acquired together with their own selection. B01's precondition is
    /// fifty distinct sources entering the acquisition set without a single manual choice.
    func testAProfileOfInterestsSuppliesSourcesTheReaderNeverNamed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = root(directory: directory)
        var recipe = FeedRecipeDefinition.neutral(languages: ["pt"])
        recipe.topicPreferences = ["topic:90_countries/brazil": .more,
            "topic:01-news-current-affairs": .more]
        let preset = try XCTUnwrap(root.saveCuratedFeed(recipe, named: "Descoberta"))

        try await root.activateSavedPreset(preset.key)
        let association = try XCTUnwrap(root.association)
        XCTAssertGreaterThanOrEqual(association.discovery.count, 50,
            "B01: at least fifty distinct sources must enter the acquisition set automatically")
        guard case .selectedSources(let eligible) = association.policy.eligibility else {
            return XCTFail("a discovery session is eligible by its own sources")
        }
        XCTAssertTrue(association.discovery.allSatisfy { eligible.contains($0.sourceID) },
            "and the session may read from every one of them")

        // The reader's own selection is untouched by discovery: they still chose nothing, and the sources screen
        // states exactly that.
        XCTAssertTrue(root.feeds.isEmpty || Set(root.feeds.map(\.principal))
            .isSubset(of: Set(association.feeds.map(\.principal))))
        XCTAssertFalse(try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
            .load()?.sourceKeys.contains { $0.hasPrefix("http") } ?? true,
            "discovery never writes itself into the reader's selection")

        // A profile with no interests discovers nothing: the promise belongs to the profile, not to the launch.
        let plain = try XCTUnwrap(try root.makeAddFeedStore())
        XCTAssertNotNil(plain)
        await association.close()
    }

    /// F02, where the answers live: the discovery preferences page — and the invitations answered inside the feed
    /// — store one profile, and that profile is what discovery reads. No curated feed and no manual source: the
    /// reader's own selection is never written to, and an answer they took back stops shaping the pool.
    func testTheReadersOwnDiscoveryAnswersDriveDiscoveryWithoutACuratedFeed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        var profile = FeedRecipeDefinition.neutral(languages: ["pt"])
        profile.topicPreferences = ["topic:90_countries/brazil": .more,
            "topic:01-news-current-affairs": .more]
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        // The row a launch creates; `setSettings` updates it rather than inventing it.
        _ = try preferences.initialize(sourceKeys: [])
        var settings = try preferences.load()?.settings ?? .standard
        settings.discoveryProfile = profile
        _ = try preferences.setSettings(settings)

        let root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let key = try XCTUnwrap(association.contextKey)

        // The derivation itself: the stored answers are the profile, in the catalogue's vocabulary.
        let derived = root.discoveryProfile(for: key)
        XCTAssertEqual(derived.languages, ["pt"])
        XCTAssertEqual(derived.topicNodeKeys, ["90_countries/brazil", "01-news-current-affairs"])
        XCTAssertTrue(derived.excludedTopicNodeKeys.isEmpty)

        // And the consequence B01 asks for: at least fifty distinct sources enter the acquisition set, none of
        // them written into the reader's selection.
        XCTAssertGreaterThanOrEqual(association.discovery.count, 50,
            "B01: at least fifty distinct sources must enter the acquisition set automatically")
        XCTAssertTrue(root.feeds.isEmpty, "discovery never writes itself into the reader's selection")

        // An answer taken back stops shaping discovery: "menos desse assunto" is an exclusion, not a preference.
        settings.discoveryProfile.topicPreferences["topic:01-news-current-affairs"] = .less
        _ = try preferences.setSettings(settings)
        let after = root.discoveryProfile(for: key)
        XCTAssertEqual(after.excludedTopicNodeKeys, ["01-news-current-affairs"])
        XCTAssertEqual(after.topicNodeKeys, ["90_countries/brazil"])
        await association.close()
    }

    /// F02's first run, end to end at the composition's own level: the answers become the reader's discovery
    /// profile, the feed they enter is built from them, and **nothing is created to be activated** — no curated
    /// feed, no name asked for, no source chosen by hand.
    func testTheFirstRunAnswersBecomeTheFeedTheReaderEnters() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = root(directory: directory)
        await root.launch()
        XCTAssertTrue(try XCTUnwrap(root.association).discovery.isEmpty,
            "before the reader answers anything, discovery has nothing to work from")

        var answers = FeedRecipeDefinition.neutral(languages: ["pt"])
        answers.topicPreferences = ["topic:90_countries/brazil": .more]
        await root.completeFirstRun(discovery: answers)

        let association = try XCTUnwrap(root.association)
        XCTAssertGreaterThanOrEqual(association.discovery.count, 50,
            "B01: the first run's own answers put at least fifty distinct sources in the acquisition set")
        XCTAssertEqual(Set(association.discovery.map(\.sourceID)).count, association.discovery.count,
            "and they are distinct sources, not the same one registered twice")
        let key = try XCTUnwrap(association.contextKey)
        XCTAssertEqual(root.discoveryProfile(for: key).languages, ["pt"])
        XCTAssertEqual(root.discoveryProfile(for: key).topicNodeKeys, ["90_countries/brazil"])

        // Nothing was created to be activated, and the reader's own selection is still empty.
        let presets = try root.makeCuratedCoordinator()?.curatedPresets() ?? []
        XCTAssertTrue(presets.isEmpty, "the first run creates no feed to activate")
        let stored = try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
            .load()
        XCTAssertEqual(stored?.settings.hasSeenOnboarding, true, "and the reader has met the app")
        XCTAssertEqual(stored?.settings.discoveryProfile.languages, ["pt"], "the answers are a preference")
        XCTAssertFalse(stored?.sourceKeys.contains { $0.hasPrefix("http") } ?? true,
            "discovery never writes itself into the reader's selection")
        await association.close()
    }

    /// Item C, the owner's decision: the first run **asks** the reader's language instead of inferring it from the
    /// system. The answer is persisted as the discovery profile — the language scope acquisition reads — and the
    /// next launch does not ask again. `Locale.current` is not on this path at all: the only language here is the
    /// one the test (standing for the reader) wrote.
    func testTheFirstRunAsksTheLanguageAndTheAnswerClosesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        XCTAssertTrue(composition.needsOnboarding, "a fresh reader meets the first run — the language question included")
        await composition.launch()
        XCTAssertTrue(try XCTUnwrap(composition.association).discoveryProfile.isEmpty,
            "no language is inferred before the reader answers — not even the device's")

        await composition.completeFirstRun(discovery: .neutral(languages: ["pt"]))

        let stored = try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
            .load()
        XCTAssertEqual(stored?.settings.discoveryProfile.languages, ["pt"], "the answer is the language scope")
        XCTAssertEqual(stored?.settings.hasSeenOnboarding, true, "and it is the answer that closes the first run")
        XCTAssertFalse(stored?.sourceKeys.contains { $0.hasPrefix("http") } ?? true,
            "the answer never writes into the reader's own selection")
        let association = try XCTUnwrap(composition.association)
        XCTAssertEqual(association.discoveryProfile.languages, ["pt"],
            "acquisition reads the answer as the scope it acquires in")
        XCTAssertFalse(composition.needsOnboarding)
        await association.close()

        let secondLaunch = root(directory: directory)
        XCTAssertFalse(secondLaunch.needsOnboarding, "a second launch does not ask again")
        await secondLaunch.association?.close()
    }

    /// The settings surface writes through a backend of its own, and the feed reads a cached snapshot of the same
    /// values on every candidate card of every render. A write through the surface has to reach that snapshot:
    /// measured 2026-10-20, the reader re-enabled the suggestions in the preferences page and the feed kept
    /// refusing every offer with `.hidden` for the rest of the session, because the composition never learned what
    /// the database now held.
    func testASettingsWriteThroughTheSurfaceReachesWhatTheFeedReads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        await composition.launch()
        let association = try XCTUnwrap(composition.association)
        XCTAssertFalse(composition.editorialTipsHidden, "the reader has not hidden anything yet")
        XCTAssertNil(composition.declaredLevel(forNode: "90_countries/brazil"),
            "and has not answered about Brazil")

        let store = try XCTUnwrap(composition.makeReaderSettingsStore())
        await store.load()
        await store.update { settings in
            settings.editorialTipsHidden = true
            settings.discoveryProfile.topicPreferences["topic:90_countries/brazil"] = .more
        }

        XCTAssertTrue(store.settings.editorialTipsHidden, "the surface shows what the backend accepted")
        XCTAssertTrue(composition.editorialTipsHidden,
            "the feed reads the value the settings surface wrote, without a relaunch")
        XCTAssertEqual(composition.declaredLevel(forNode: "90_countries/brazil"), .more,
            "and the per-subject answers cached beside it are the stored ones too")

        // The same session, the same cadence the feed drives: hidden refuses, and only the composed value can
        // change that.
        let cadence = EditorialInvitationCadence()
        cadence.setHidden(composition.editorialTipsHidden)
        XCTAssertEqual(cadence.decision(subject: "90_countries/brazil", isAnswered: false, cardsTraversed: 400),
            .hidden, "while hidden, the cadence refuses every card")

        // Re-enable through the real adapter, as the preferences page does.
        await store.update { $0.editorialTipsHidden = false }
        XCTAssertFalse(store.settings.editorialTipsHidden)
        XCTAssertFalse(composition.editorialTipsHidden,
            "re-enabling in the surface reaches the feed's snapshot in the same session")
        cadence.setHidden(composition.editorialTipsHidden)
        XCTAssertNotEqual(cadence.decision(subject: "90_countries/brazil", isAnswered: false, cardsTraversed: 400),
            .hidden, "and the cadence can place an offer again")
        await association.close()
    }

    /// **D5**: "Falha ao atualizar o feed" may only speak for a feed update. A save, a copy, a share or opening a
    /// card is a local action: it states itself, never the feed's failure, and never replaces what the reader had.
    func testALocalActionFailureNeverSpeaksForTheFeed() {
        XCTAssertNil(FeedAssociation.FailureOperation.feedRefresh.statement,
            "the feed's own message belongs to the feed state, not to a toast")
        let locals: [FeedAssociation.FailureOperation] = [.openCard, .save, .copy, .share]
        let statements = locals.compactMap(\.statement)
        XCTAssertEqual(statements.count, locals.count, "every local operation states itself")
        XCTAssertEqual(Set(statements).count, statements.count, "and they are distinct, not one generic sentence")
        for statement in statements {
            XCTAssertNotEqual(statement, "Falha ao atualizar o feed",
                "a local action may never present the feed's failure")
        }
        XCTAssertEqual(FeedAssociation.operation(for: .copyLink), .copy)
        XCTAssertEqual(FeedAssociation.operation(for: .share), .share)
        XCTAssertEqual(FeedAssociation.operation(for: .save), .save)
        XCTAssertEqual(FeedAssociation.operation(for: .open), .openCard)
        XCTAssertEqual(FeedAssociation.operation(for: .openMedia), .openCard)
    }

    /// The signal a write sends states **that** a write happened, not the value: the composition drops its cache,
    /// so two writers reaching the main actor in either order cannot install an older value. A write the store
    /// refuses sends nothing.
    func testSettingsWritesAreAnnouncedOnlyWhenStored() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: [])
        let announcements = Mutex<Int>(0)
        let adapter = ReaderSettingsBackendAdapter(database: database) {
            announcements.withLock { $0 += 1 }
        }
        var first = ReaderSettings.standard
        first.editorialTipsHidden = true
        try await adapter.update(first)
        var second = first
        second.editorialTipsHidden = false
        try await adapter.update(second)
        XCTAssertEqual(announcements.withLock { $0 }, 2, "each accepted write is announced")

        // The store now cannot accept a write at all: an attempt must throw and must not be announced.
        try await database.write { db in try db.execute(sql: "DROP TABLE reader_preferences") }
        var third = second
        third.editorialTipsHidden = true
        var refused = false
        do { try await adapter.update(third) } catch { refused = true }
        XCTAssertTrue(refused, "a write the store cannot accept throws")
        XCTAssertEqual(announcements.withLock { $0 }, 2, "and a refused write states nothing")
    }

    /// The other answer to the same question: the reader skips. Nothing is named, so acquisition stays
    /// unrestricted, the stored profile names nothing, and the `.main` context keeps the plain identity it always
    /// had — the skip cannot change what the reader is reading.
    func testSkippingTheLanguageQuestionLeavesAcquisitionUnrestricted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        XCTAssertTrue(composition.needsOnboarding)
        await composition.launch()

        // What the gate's own way out writes: the neutral recipe, no language named.
        await composition.completeFirstRun(discovery: .neutral())

        let stored = try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
            .load()
        XCTAssertEqual(stored?.settings.discoveryProfile.languages, [], "the skip names no language")
        XCTAssertFalse(AppComposition.namesAnything(try XCTUnwrap(stored?.settings.discoveryProfile)),
            "and it names nothing at all — a neutral profile is 'no answers yet'")
        XCTAssertEqual(stored?.settings.hasSeenOnboarding, true)
        let association = try XCTUnwrap(composition.association)
        XCTAssertTrue(association.discoveryProfile.isEmpty, "so acquisition is unrestricted")
        XCTAssertEqual(try XCTUnwrap(association.contextKey).filter.languages, [],
            "the .main key still means the plain surface, exactly as before")
        XCTAssertFalse(composition.needsOnboarding)
        await association.close()

        let secondLaunch = root(directory: directory)
        XCTAssertFalse(secondLaunch.needsOnboarding, "a second launch does not ask again")
        await secondLaunch.association?.close()
    }

    /// The explicit "Todos os idiomas" answer, with no place named ("Mundo todo"), is a profile and must reach
    /// discovery. Before this, the empty language set was read as "no answer yet": `namesAnything` was false, the
    /// stored recipe was ignored, the pool was empty and the reader landed on "Escolher fontes". The two facts are
    /// now distinct — the gate's close still discovers nothing, the explicit answer searches the whole catalogue.
    func testTheExplicitAllLanguagesAnswerReachesDiscovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // No default feeds: this is the first run the surface's question exists for. The development feeds other
        // cases seed would make `hasSelectedSources` true before any answer and hide the distinction being tested.
        let composition = root(directory: directory, feeds: [])
        await composition.launch()
        XCTAssertFalse(composition.hasSelectedSources, "before any answer the reader selects sources")

        await composition.completeFirstRun(discovery: .neutral(hasLanguageAnswer: true))

        let stored = try ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
            .load()
        XCTAssertEqual(stored?.settings.discoveryProfile.languages, [],
            "the answer names no language restriction")
        XCTAssertEqual(stored?.settings.discoveryProfile.hasLanguageAnswer, true,
            "but it is an answer, not the absence of one")
        XCTAssertTrue(AppComposition.namesAnything(try XCTUnwrap(stored?.settings.discoveryProfile)))
        let association = try XCTUnwrap(composition.association)
        XCTAssertFalse(association.discoveryProfile.isEmpty,
            "discovery has the whole catalogue to work with")
        XCTAssertTrue(association.discoveryProfile.namesAllLanguages)
        XCTAssertEqual(association.discoveryProfile.languages, [], "and no language restriction was invented")
        XCTAssertGreaterThanOrEqual(association.discovery.count, 50,
            "the explicit answer reaches the pool instead of the empty selection surface")
        XCTAssertTrue(composition.hasSelectedSources, "so the reader is not told to choose sources")
        await association.close()
    }

    /// F02, the door back to a feed of the reader's own: the rules are stated once in the discovery preferences and
    /// a feed is created from them — and **creating does not activate it, does not move the reading**, and the
    /// library keeps it. Opening it is the reader's own next step.
    func testCreatingAFeedWithThePreferencesDoesNotActivateIt() async throws {
        let (root, association) = try await launched()
        let before = try XCTUnwrap(association.contextKey)
        var recipe = FeedRecipeDefinition.neutral(languages: ["pt"])
        recipe.topicPreferences = ["topic:04-technology-science": .more]
        let preset = try XCTUnwrap(root.saveCuratedFeed(recipe, named: "Ciência e tecnologia"))

        XCTAssertEqual(root.association?.contextKey, before,
            "creating a feed with these preferences does not move what the reader is reading")
        XCTAssertNotEqual(preset.key, before, "and it is its own context, not the one in use")
        XCTAssertEqual(try root.makeCuratedCoordinator()?.curatedPresets().map(\.key), [preset.key],
            "the library is where created feeds are found")
        XCTAssertEqual(try root.makeCuratedCoordinator()?.curatedPresets().first?.recipe, recipe,
            "and it carries the rules it was created from")

        // The reader's own next step: opening it really switches the session.
        try await root.activateSavedPreset(preset.key)
        XCTAssertEqual(root.association?.contextKey, preset.key)
        await root.association?.close()
    }

    /// F02's thematic phase: answering **inside the feed** changes what discovery looks for next — and nothing
    /// else. The context's identity, the admitted edition and the reader's own selection stay where they were:
    /// a person who says where they want more of must not lose the story they were reading.
    /// The architect's question (2026-10-11): persisting the answer does not prove it already affects new
    /// acquisition. The answer is a preference about **future discovery** — the block says so in as many words —
    /// and this is the moment it is consumed: the next session built for that context reads it from the stored
    /// profile and pulls the pool that matches it.
    func testTheAnswerIsConsumedWhenTheNextSessionOfTheContextIsBuilt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        var answers = FeedRecipeDefinition.neutral(languages: ["pt"])
        answers.topicPreferences = ["topic:90_countries/brazil": .more]
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: [])
        var stored = try preferences.load()?.settings ?? .standard
        stored.discoveryProfile = answers
        _ = try preferences.setSettings(stored)

        let root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let key = try XCTUnwrap(association.contextKey)
        let poolBefore = Set(association.discovery.map(\.sourceID))
        XCTAssertGreaterThanOrEqual(poolBefore.count, 50, "discovery is running from the answers")

        // The reader answers here, and the session they are reading is untouched.
        await root.voteOnTopic(nodeKey: "04-technology-science", level: .more)
        XCTAssertTrue(root.association === association, "answering does not rebuild what the reader is reading")

        // The next session of that context is where the answer starts to work.
        try await root.replaceSession()
        let next = try XCTUnwrap(root.association)
        let catalog = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let expected = try ReaderDiscoveryBuilder(catalogURL: catalog).pool(for: .init(languages: ["pt"],
            topicNodeKeys: ["04-technology-science", "90_countries/brazil"],
            excludedTopicNodeKeys: []), limit: AppComposition.discoverySourceLimit)
        XCTAssertEqual(Set(next.discovery.map(\.sourceID)), Set(expected.entries.map { $0.source.id }),
            "the next session pulls the pool the answer asks for")
        await next.close()
    }

    /// The product owner's criterion (2026-10-11): **an explicit refresh that produces a new edition must also
    /// honour the preference** the reader gave since the session was built — while an internal rebuild of the UI
    /// is never treated as a new session just to anticipate its application. The refresh is the reader asking for
    /// movement, so a rebuild there is legitimate; nothing is rebuilt when nothing changed.
    func testAnExplicitRefreshHonoursAnAnswerGivenAfterTheSessionWasBuilt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        var answers = FeedRecipeDefinition.neutral(languages: ["pt"])
        answers.topicPreferences = ["topic:90_countries/brazil": .more]
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: [])
        var stored = try preferences.load()?.settings ?? .standard
        stored.discoveryProfile = answers
        _ = try preferences.setSettings(stored)

        let root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let editionBefore = try XCTUnwrap(association.store.state.presentation).editionID
        let presentationBefore = association.store.state.presentation?.window.items
        await root.voteOnTopic(nodeKey: "04-technology-science", level: .more)
        await root.refreshFromTheReader()
        let refreshed = try XCTUnwrap(root.association)
        XCTAssertFalse(refreshed === association,
            "the explicit refresh rebuilds the session, because the stored profile is no longer the one the pool was built from")
        let catalog = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let expected = try ReaderDiscoveryBuilder(catalogURL: catalog).pool(for: .init(languages: ["pt"],
            topicNodeKeys: ["04-technology-science", "90_countries/brazil"],
            excludedTopicNodeKeys: []), limit: AppComposition.discoverySourceLimit)
        XCTAssertEqual(Set(refreshed.discovery.map(\.sourceID)), Set(expected.entries.map { $0.source.id }),
            "the refreshed session pulls the pool the answer asks for")
        // What the reader was reading is not retracted by a refresh either: the same edition, and the cards they
        // already had as a prefix of the new window.
        XCTAssertEqual(try XCTUnwrap(refreshed.store.state.presentation).editionID, editionBefore,
            "the refresh does not retract the edition the reader was reading")
        let beforeItems = (presentationBefore ?? []).map { $0.id }
        let nowItems = refreshed.store.state.presentation?.window.items.map(\.id) ?? []
        XCTAssertEqual(Array(nowItems.prefix(beforeItems.count)), beforeItems,
            "not one presented card was retracted or reordered by the refresh")

        // Nothing changed since: the next explicit refresh rebuilds nothing.
        await root.refreshFromTheReader()
        XCTAssertTrue(root.association === refreshed,
            "an explicit refresh with no pending answer rebuilds nothing")
        await refreshed.close()
    }

    func testAnsweringInTheFeedChangesDiscoveryWithoutMovingTheReader() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        var answers = FeedRecipeDefinition.neutral(languages: ["pt"])
        answers.topicPreferences = ["topic:90_countries/brazil": .more]
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: [])
        var stored = try preferences.load()?.settings ?? .standard
        stored.discoveryProfile = answers
        _ = try preferences.setSettings(stored)

        let root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let key = try XCTUnwrap(association.contextKey)
        let editionBefore = try XCTUnwrap(association.store.state.presentation).editionID
        XCTAssertGreaterThanOrEqual(association.discovery.count, 50, "discovery is running from the answers")

        // The reader answers a subject the feed presented.
        await root.voteOnTopic(nodeKey: "04-technology-science", level: .more)
        let after = try XCTUnwrap(root.association)
        XCTAssertTrue(after === association,
            "the answer does not rebuild the session: the rebuild retired the association and restored it from a checkpoint that carries no offset inside the card, which moved the reader 139 pt in one device run and 912 pt in another (2026-10-11)")
        XCTAssertEqual(try XCTUnwrap(after.contextKey), key, "the context's identity does not change")
        XCTAssertEqual(try XCTUnwrap(after.store.state.presentation).editionID, editionBefore,
            "the admitted presentation is the same edition: nothing the reader was reading was retracted")
        // The edition identity alone is not the whole promise (the reviewer's point): the **cards and their
        // order** must be the same ones, in the same order, with nothing inserted or removed above the reader.
        // F06-A publishes only what each opportunity can present, so the *tail* of the window may differ while the
        // cards the reader already has must not: the old window is a **prefix** of the new one, nothing retracted,
        // nothing reordered.
        let before = association.store.state.presentation?.window.items.map(\.id) ?? []
        let now = after.store.state.presentation?.window.items.map(\.id) ?? []
        XCTAssertEqual(Array(now.prefix(before.count)), before,
            "not one presented card was retracted, inserted or reordered by the answer")
        XCTAssertEqual(root.declaredLevel(forNode: "04-technology-science"), .more,
            "the answer is what the settings hold")
        XCTAssertEqual(root.discoveryProfile(for: key).topicNodeKeys.sorted(),
            ["04-technology-science", "90_countries/brazil"],
            "and discovery reads it as an interest")

        // "Menos desse assunto" is an exclusion, not a quieter preference.
        await root.voteOnTopic(nodeKey: "90_countries/brazil", level: .less)
        XCTAssertEqual(root.discoveryProfile(for: key).excludedTopicNodeKeys, ["90_countries/brazil"])
        XCTAssertEqual(root.discoveryProfile(for: key).topicNodeKeys, ["04-technology-science"])

        // Taking an answer back is answering again: the subject leaves both sets.
        await root.voteOnTopic(nodeKey: "04-technology-science", level: .neutral)
        XCTAssertNil(root.declaredLevel(forNode: "04-technology-science"))
        XCTAssertTrue(root.discoveryProfile(for: key).topicNodeKeys.isEmpty)
        await root.association?.close()
    }

    /// B01's own promise, and the defect recorded in `docs/v1-study/PORT_LOG.md` §19: a reader who has chosen
    /// **no source at all** must still receive a feed, supplied by discovery. Measured before this test existed:
    /// zero sources registered, zero cards published, nothing in the trace.
    func testDiscoveryFeedsAReaderWhoChoseNothing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // The reader's answers, and nothing else: no selected source anywhere.
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: [])
        var answers = FeedRecipeDefinition.neutral(languages: ["pt"])
        answers.topicPreferences = ["topic:90_countries/brazil": .more]
        var settings = try preferences.load()?.settings ?? .standard
        settings.discoveryProfile = answers
        _ = try preferences.setSettings(settings)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 60
        let root = AppComposition(directory: directory, feeds: [], transportConfiguration: configuration)
        await root.launch()
        if let failure = root.startupFailure {
            XCTFail("the app failed to start for a reader who chose nothing: \(failure)")
        }
        let association = try XCTUnwrap(root.association)
        XCTAssertGreaterThanOrEqual(association.discovery.count, 50,
            "discovery supplies the reader who chose nothing")
        XCTAssertTrue(root.hasSelectedSources,
            "and the surface offers a feed: the reader is not sent to choose sources they never wanted")
        XCTAssertNotNil(association.store.state.presentation,
            "the feed really publishes for a reader who chose nothing")
        await association.close()
    }

    /// The ceiling is not allowed to swallow evidence in silence. `batchSize` and `lineCeiling` existed before this
    /// test and could absorb thousands of events; a run whose trace was truncated that way reads exactly like a run
    /// where nothing happened — and the oracle would then report the absence as a fact about the product. It now
    /// counts what it refused, states the first refusal, and states the totals when the trace is flushed.
    func testTheTraceRecordsItsOwnDiscardInsteadOfGoingSilent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let trace = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 3)
        // A journey event on purpose: this case measures the hard ceiling itself, not the context reserve that
        // protects journey events from context (the case below covers that partition).
        for index in 0..<10 { trace.record("advance", ["index": String(index)]) }
        trace.flushAndWait()
        let url = directory.appendingPathComponent("trace.jsonl")
        let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(records.filter { $0["event"] as? String == "advance" }.count, 3,
            "the ceiling holds: only the events under it were written")
        let truncated = records.filter { $0["event"] as? String == "trace_truncated" }
        XCTAssertEqual(truncated.count, 2, "the first refusal, and the totals at flush")
        let first = try XCTUnwrap(truncated.first?["fields"] as? [String: String])
        XCTAssertEqual(first["reason"], "line_ceiling")
        XCTAssertEqual(first["dropped_by_ceiling"], "1")
        XCTAssertEqual(first["ceiling"], "3")
        let totals = try XCTUnwrap(truncated.last?["fields"] as? [String: String])
        XCTAssertEqual(totals["reason"], "flush_total")
        XCTAssertEqual(totals["dropped_by_ceiling"], "7", "all seven refused events are accounted for")
        XCTAssertEqual(totals["written"], "3")
        // The monotonic clock every interval is measured on, beside the wall clock the oracle already reads.
        XCTAssertTrue(records.allSatisfy { $0["mono"] as? Double != nil && $0["at"] as? Double != nil })
        // Nothing new to say means nothing written: the announcement does not become a second kind of noise.
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count
        trace.flushAndWait()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, lines)
    }

    /// Measured failure, replayed. Bench run `20261021T033520Z` wrote 40.060 lines in 1.854 s and exhausted the
    /// 40.000-line ceiling exactly at the last advance: the admission recorded right after it never reached the
    /// file, and the oracle — which reads "advance with no admission in the following second" as a visible stall —
    /// failed B03 on an artifact of the instrument, not on a stall of the feed. The event census below is that
    /// run's own trace (`advance` 2.944, `admitted` 7.742, `candidate` 2.535, `position_checkpoint` 579,
    /// `runway_completed` 2.871, context 23.389) replayed on one clock in the run's order: admissions before the
    /// advance they make possible, and the admission that answers the last advance at the very end. The oracle's
    /// own rule is applied to what the file retained, so the case proves the capture, not the product.
    func testTheTraceRetainsTheJourneyUnderTheMeasuredBenchmarkLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let trace = RunwayTrace(directory: directory, name: "trace.jsonl")
        let start = Date(timeIntervalSince1970: 1_792_555_828)
        // The run's own pace: 2.944 advances across 1.854 s.
        let period = 1_854.0 / 2_944.0
        let contextEvents = ["replenishment_requested", "replenishment_arrived", "window", "editorial_refusal",
            "media_preparation_settled", "media_card_published", "frames", "replenishment_concluded"]
        func moment(_ index: Int) -> Double { Double(index) * period }
        func record(_ event: String, _ fields: [String: String] = [:], _ offset: Double) {
            trace.record(event, fields, at: start.addingTimeInterval(offset))
        }
        // The run's whole-file context is 23.389 lines: these seven, 23.322 inside the walk, and 60 more at the
        // tail — they are what crowded the journey's last admission out of the old ceiling.
        record("host_started", [:], -0.50)
        record("first_frame", [:], -0.40)
        record("first_frame", [:], -0.30)
        record("editorial_offer", [:], -0.20)
        record("editorial_offer", [:], -0.10)
        record("answer_applied", [:], -0.05)
        record("answer_applied", [:], -0.02)
        for index in 0..<2_944 {
            let here = moment(index)
            // 3 admissions per advance for the first 1.854, then 2; the last one waits until after the tail.
            let admissionsHere = (index < 1_854 ? 3 : 2) - (index == 2_943 ? 1 : 0)
            for _ in 0..<admissionsHere {
                record("admitted", ["anchor": UUID().uuidString], here - 0.01)
            }
            if index < 2_535 { record("candidate", ["readiness": "textOnly"], here - 0.005) }
            if index % 5 == 0, index < 2_895 {
                record("position_checkpoint", ["anchor": UUID().uuidString, "placement": "top"], here - 0.004)
            }
            // The closure the journey instrument pairs with `advance`; 73 opportunities stay open in the run.
            if index < 2_871 { record("runway_completed", ["activity": "forward"], here - 0.002) }
            for step in 0..<(index < 2_714 ? 8 : 7) {
                record(contextEvents[(index + step) % contextEvents.count], ["n": String(index)], here - 0.001)
            }
            record("advance", ["activity": "forward"], here)
        }
        for index in 0..<60 {
            record("replenishment_arrived", ["tail": String(index)], moment(2_943) + 0.001 * Double(index))
        }
        record("admitted", ["anchor": UUID().uuidString], moment(2_943) + 0.002)
        trace.flushAndWait()

        let url = directory.appendingPathComponent("trace.jsonl")
        let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap { line in
            try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        }
        XCTAssertEqual(records.count, 40_060, "the measured run fits the budget")
        XCTAssertFalse(records.contains { $0["event"] as? String == "trace_truncated" },
            "and it fits whole: no event of the measured run was refused")
        let advances = records.filter { $0["event"] as? String == "advance" }
            .compactMap { $0["at"] as? Double }
        let admissions = records.filter { $0["event"] as? String == "admitted" }
            .compactMap { $0["at"] as? Double }
        XCTAssertEqual(advances.count, 2_944)
        XCTAssertEqual(admissions.count, 7_742)
        XCTAssertEqual(records.filter { $0["event"] as? String == "candidate" }.count, 2_535,
            "every examined candidate keeps the readiness the clause reads")
        XCTAssertEqual(records.filter { $0["event"] as? String == "runway_completed" }.count, 2_871,
            "the closures the journey instrument pairs with advances are kept too: no false open opportunity")
        // The oracle's rule, applied to the file: an advance with no admission in the following second is a stall.
        var cursor = 0
        var stalls = 0
        for moment in advances {
            while cursor < admissions.count, admissions[cursor] < moment { cursor += 1 }
            if cursor == admissions.count || admissions[cursor] - moment >= 1.0 { stalls += 1 }
        }
        XCTAssertEqual(stalls, 0, "the advance that closed the run still has its admission beside it")
    }

    /// When the budget is under pressure, the partition decides **what** is lost: telemetry, never the journey.
    /// Before it, context lines could take the whole ceiling and the last advance stood alone in the file — the
    /// same shape that failed B03, at a scale that fits in a test. Context stops at two thirds of the budget, so
    /// the reserve is still there when the journey needs it, and the refusal is announced rather than silent.
    func testContextSaturationSpendsTheReserveBeforeTheJourneyEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let trace = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 100)
        for index in 0..<40 { trace.record("advance", ["index": String(index)]) }
        for index in 0..<200 { trace.record("frames", ["index": String(index)]) }
        trace.flushAndWait()
        let url = directory.appendingPathComponent("trace.jsonl")
        let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        let advances = records.filter { $0["event"] as? String == "advance" }
        XCTAssertEqual(advances.count, 40, "the journey is whole")
        XCTAssertEqual(Set(advances.compactMap { ($0["fields"] as? [String: String])?["index"] }),
            Set((0..<40).map(String.init)), "every advance reached the file, in order")
        XCTAssertEqual(records.filter { $0["event"] as? String == "frames" }.count, 26,
            "context spends only what is left below two thirds of the ceiling")
        let truncated = records.filter { $0["event"] as? String == "trace_truncated" }
        let first = try XCTUnwrap(truncated.first?["fields"] as? [String: String])
        XCTAssertEqual(first["reason"], "context_budget")
        XCTAssertEqual(first["dropped_by_context"], "1")
        XCTAssertEqual(first["dropped_by_ceiling"], "0")
        let totals = try XCTUnwrap(truncated.last?["fields"] as? [String: String])
        XCTAssertEqual(totals["dropped_by_context"], "174", "every refused context line is accounted for")
        XCTAssertEqual(totals["written"], "66")
    }

    /// A trace belongs to the **run**, not to one process: the reopen gates read what the first launch wrote, and a
    /// relaunch is the normal case (suspend/reopen, offline reopen). Measured failure, `20261023T193301Z`: the first
    /// write of each process called `createFile(contents: nil)`, which truncates the existing file, so the first
    /// launch's `position_checkpoint` was erased by the reopen while the app's database still held it — B05 read
    /// "no durable position" from an instrument that had deleted the evidence. This case replays a relaunch: the
    /// old segment must survive and the new line must follow it, in order.
    func testTheTraceRetainsThePreviousLaunchAndAppendsTheNext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 10)
        first.record("position_checkpoint", ["anchor": "EA0E34C1", "placement": "top"])
        first.flushAndWait()

        // The reopen: a new RunwayTrace over the same directory, as a second process would build.
        let second = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 10)
        second.record("host_started", ["launch": "2"])
        second.flushAndWait()

        let url = directory.appendingPathComponent("trace.jsonl")
        let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(records.count, 2, "the reopen appends to the run's file instead of replacing it")
        XCTAssertEqual(records[0]["event"] as? String, "position_checkpoint",
            "the first launch's segment is still the first line")
        XCTAssertEqual((records[0]["fields"] as? [String: String])?["anchor"], "EA0E34C1",
            "the durable position the reopen gates read survived the relaunch")
        XCTAssertEqual(records[1]["event"] as? String, "host_started", "and the new launch follows it")
    }

    /// Fresh-file semantics are unchanged: a directory with no trace gets one, with exactly the lines this trace
    /// recorded — the append path may not depend on a file having existed before.
    func testAFreshTraceCreatesItsFileFromNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("trace.jsonl").path),
            "the case starts with no trace, in a directory that does not exist either")
        let trace = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 10)
        trace.record("admitted", ["anchor": "A1"])
        trace.flushAndWait()
        let records = try String(contentsOf: directory.appendingPathComponent("trace.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(records[0].utf8)) as? [String: Any])
        XCTAssertEqual(record["event"] as? String, "admitted")
    }

    /// A process killed mid-write (`app.terminate()` in B05) can leave the last line unterminated. The relaunch
    /// must not glue its first event onto that partial JSON: the oracle reads the file line by line, so the merged
    /// line would be discarded and with it the new event — the same silent evidence loss the append fix exists to
    /// remove. The partial line also spends one line of the file budget.
    func testARelaunchAfterATornWriteStartsANewLine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 10)
        first.record("position_checkpoint", ["anchor": "EA0E34C1"])
        first.flushAndWait()

        let url = directory.appendingPathComponent("trace.jsonl")
        let written = try Data(contentsOf: url)
        XCTAssertGreaterThan(written.count, 8)
        // What a write cut short leaves behind: the newline and the end of the JSON are gone.
        try Data(written.dropLast(8)).write(to: url)

        let second = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 10)
        second.record("host_started", ["launch": "2"])
        second.flushAndWait()

        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "the torn tail and the new event are two lines, not one")
        let event = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
        XCTAssertEqual(event["event"] as? String, "host_started",
            "the new event is readable on its own line")
    }

    /// The budget and the reserve are properties of the **file**: a relaunch that re-opened with a full budget
    /// would append another 64.000 lines (or, at a test-sized ceiling, another whole budget) on every start, and
    /// `finite disk use across process restarts` would be a property of how often the app was reopened. This case
    /// seeds an 80-line file under a 100-line ceiling, then re-opens it: context may no longer spend past the
    /// cumulative two-thirds reserve, and the journey stops at the same ceiling — with the loss stated.
    func testTheCeilingAndReserveFollowTheFileAcrossARelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let first = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 100)
        for index in 0..<80 { first.record("advance", ["index": String(index)]) }
        first.flushAndWait()

        // 80 of 100 lines already spent; the reserve is 66, i.e. the file is already past it.
        let second = RunwayTrace(directory: directory, name: "trace.jsonl", lineCeiling: 100)
        second.record("frames", ["index": "relaunch"])
        for index in 80..<120 { second.record("advance", ["index": String(index)]) }
        second.flushAndWait()

        let url = directory.appendingPathComponent("trace.jsonl")
        let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        let advances = records.filter { $0["event"] as? String == "advance" }
        XCTAssertEqual(advances.count, 100, "the ceiling is the file's 100 lines: the relaunch spent the last 20")
        XCTAssertEqual(Set(advances.compactMap { ($0["fields"] as? [String: String])?["index"] }),
            Set((0..<100).map(String.init)), "the first launch's 80 advances are still there, in order")
        XCTAssertEqual(records.filter { $0["event"] as? String == "frames" }.count, 0,
            "the reserve is cumulative too: context was already past two thirds of the file when it re-opened")
        let truncated = records.filter { $0["event"] as? String == "trace_truncated" }
        XCTAssertEqual(truncated.compactMap { ($0["fields"] as? [String: String])?["reason"] },
            ["context_budget", "line_ceiling", "flush_total"],
            "the relaunch states what it refused, by cause, and the totals at flush")
        XCTAssertEqual((truncated.last?["fields"] as? [String: String])?["written"], "100",
            "the event budget counts what the file already held")
        XCTAssertLessThanOrEqual(records.count, 109,
            "the trace is bounded by its ceiling plus its bounded announcements, across restarts")
    }

    /// Codex's review, finding 2: an invitation is only true for a source the app **went and found** in this
    /// association. A source the reader chose is not discovery, and a pool built for an earlier profile does not
    /// answer for the one being read now.
    func testAnInvitationIsOnlyOfferedForDiscoveredSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // The reader chose one of the development feeds **and** answered discovery: both supplies exist.
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: [])
        var answers = FeedRecipeDefinition.neutral(languages: ["pt"])
        answers.topicPreferences = ["topic:90_countries/brazil": .more]
        var settings = try preferences.load()?.settings ?? .standard
        settings.discoveryProfile = answers
        _ = try preferences.setSettings(settings)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 60
        let root = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        XCTAssertGreaterThanOrEqual(association.discovery.count, 50, "the fixture has a discovery pool")

        // The rule this side owns: only a source **found by this association's discovery** may be asked about, and
        // the catalogue must name a subject for it.
        // The fixture's own selected feed: a source the reader has, which discovery did not have to find.
        let chosen = try XCTUnwrap(TrustedFeed.development.first)
        XCTAssertNil(root.editorialSubject(for: chosen.sourceID, in: association),
            "a source the reader chose is never asked about as a discovery")
        XCTAssertNil(root.editorialSubject(for: SourceID(), in: association),
            "a source this association never found is not asked about either")
        if let discovered = association.discovery.first {
            XCTAssertEqual(root.editorialSubject(for: discovered.sourceID, in: association) == nil,
                !association.discovery.contains { $0.sourceID == discovered.sourceID } ,
                "a discovered source is answered by the pool's own subject map, and nothing else")
        }
        await association.close()
    }

    /// V1's own promise for a saved box: what is exported is the reader's **articles**, not the sources they came
    /// from, and only in the four formats an article list has.
    func testASavedBoxExportsItsSavedArticlesAndNotTheirSources() async throws {
        let (root, association) = try await launched()
        let publication = PublicationStore(database: association.database)
        let window = try XCTUnwrap(association.store.state.presentation?.window.items)
        let linked = try XCTUnwrap(window.first { item in
            (try? publication.card(id: item.id))?.primaryActionKind == "externalURL"
        })
        try publication.toggleBookmark(cardID: linked.id, at: Date())
        let coordinator = try XCTUnwrap(root.makeImportExportCoordinator())
        let box = ReaderExportRequest(scope: .bookmarkBox(ReaderBookmarkList.defaultID), format: .csv)

        let csv = try coordinator.preview(box)
        XCTAssertEqual(csv.split(separator: "\n").first.map(String.init), "title,url,source,date,category")
        let record = try XCTUnwrap(publication.card(id: linked.id))
        XCTAssertTrue(csv.contains(try XCTUnwrap(record.primaryActionReference)),
            "the saved article's own link is in the document")
        XCTAssertTrue(csv.contains(try XCTUnwrap(linked.title)), "and so is its own headline")
        XCTAssertFalse(csv.contains("title,url,identity,category"),
            "a box is not exported as a list of feeds")

        let markdown = try coordinator.preview(ReaderExportRequest(scope: .bookmarkBox(ReaderBookmarkList.defaultID),
            format: .markdown))
        XCTAssertTrue(markdown.contains("- [\(try XCTUnwrap(linked.title))](\(try XCTUnwrap(record.primaryActionReference)))"))
        let text = try coordinator.preview(ReaderExportRequest(scope: .bookmarkBox(ReaderBookmarkList.defaultID),
            format: .text))
        XCTAssertTrue(text.contains("• \(try XCTUnwrap(linked.title))"))
        let html = try coordinator.preview(ReaderExportRequest(scope: .bookmarkBox(ReaderBookmarkList.defaultID),
            format: .html))
        // O título vem do **mesmo bundle e do mesmo locale do contrato do produto** — não de um literal fixo. Era
        // `<title>Caixa de salvos</title>`, e num aparelho em inglês a asserção quebrava (medido; correção
        // autorizada pelo arquiteto). As verificações de que a caixa exporta **artigos salvos** e não **fontes**
        // seguem intactas abaixo, que é o que este teste existe para provar.
        let exportTitle = String(localized: "Caixa de salvos", bundle: .main,
            locale: CatalogLanguageNaming.interfaceLocale)
        XCTAssertTrue(html.contains("<title>\(exportTitle)</title>"),
            "o documento declara o que ele é, resolvido pelo contrato do produto (título: \(exportTitle))")
        XCTAssertFalse(html.contains("<title>Fontes</title>"),
            "e o título é o da caixa de salvos, não o de uma lista de fontes")

        // The file name V1 wrote for this scope, and the formats it never offered are refused rather than
        // answered with a document about something else.
        let url = try coordinator.export(box)
        XCTAssertTrue(url.lastPathComponent.contains("-bookmarks.csv"), url.lastPathComponent)
        for format in [ReaderExportFormat.opml, .json, .shareLink, .socialCard] {
            XCTAssertThrowsError(try coordinator.preview(ReaderExportRequest(scope: .bookmarkBox(ReaderBookmarkList.defaultID),
                format: format)), "\(format.rawValue) is not a saved box's document") { error in
                XCTAssertEqual(error as? ReaderImportExportError, .formatNotAvailable)
            }
        }
        XCTAssertEqual(ReaderExportFormat.available(for: .bookmarkBox("x")), [.text, .markdown, .csv, .html],
            "and the surface offers exactly what a box can be written in")
        await association.close()
    }

    /// Integrity gate for updating over the V1 app (same bundle id `com.feedmine.app`): V2's
    /// runtime store must never coincide with V1's, because a coincidence would mean V2 opening and
    /// migrating a foreign schema in place. V1 (feedmine-dev) writes
    /// `<AppSupport>/Feedmine/RuntimeV2/runtime-v2.sqlite` plus its legacy `user.sqlite`; V2 writes
    /// `<AppSupport>/FeedMine/runtime.sqlite`. The paths differ in directory name and in depth, so
    /// they stay distinct even on a case-insensitive volume.
    ///
    /// The consequence is recorded, not hidden: installing V2 over V1 leaves V1's files untouched
    /// but does NOT read them, so the V1 library (chosen sources, bookmarks) is not carried over.
    /// The V1 app has never shipped from the App Store (its 1.0 is in PREPARE_FOR_SUBMISSION), so the
    /// exposure today is limited to testers who installed V1's TestFlight builds; carrying that data
    /// over is a decision, not an accident, and needs an importer that reads V1's stores.
    @MainActor
    func testUpdateOverV1NeverSharesTheRuntimeStore() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let v2 = RuntimeDatabaseLocation.applicationSupport(support).directory
            .appendingPathComponent("runtime.sqlite")
        let v1 = support
            .appendingPathComponent("Feedmine", isDirectory: true)
            .appendingPathComponent("RuntimeV2", isDirectory: true)
            .appendingPathComponent("runtime-v2.sqlite")
        XCTAssertEqual(v2.lastPathComponent, "runtime.sqlite")
        XCTAssertEqual(v2.deletingLastPathComponent().lastPathComponent, "FeedMine")
        XCTAssertEqual(v1.lastPathComponent, "runtime-v2.sqlite")
        XCTAssertNotEqual(v1, v2)
        XCTAssertNotEqual(v1.path.lowercased(), v2.path.lowercased(),
            "the two stores must stay distinct even if the volume ignores case")
        // V2 must create its own directory rather than adopt V1's tree.
        XCTAssertFalse(v2.path.contains("/Feedmine/RuntimeV2/"))
    }

    /// A02: three real composition routes retain the same RuntimeDatabase object, not
    /// three pools over the same SQLite path. Media also reads a card published on that handle.
    func testA02MediaSourcesAndPlaybackPositionsShareRetainedDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        await composition.launch()
        XCTAssertNil(composition.startupFailure)
        let association = try XCTUnwrap(composition.association)
        let retained = association.database

        // Inspect the objects actually constructed by the public surfaces, not Swift source text.
        // RuntimeDatabase is a reference type; sharing a file would not pass the identity assertions.
        func databaseHandle(in value: Any, depth: Int = 0) -> RuntimeDatabase? {
            if let database = value as? RuntimeDatabase { return database }
            guard depth < 10 else { return nil }
            for child in Mirror(reflecting: value).children {
                if let database = databaseHandle(in: child.value, depth: depth + 1) { return database }
            }
            return nil
        }

        let sources = composition.makeSourceManagementStore()
        await sources.load()
        XCTAssertNil(sources.errorMessage)
        XCTAssertEqual(sources.selection,
            Set(try XCTUnwrap(ReaderPreferencesStore(database: retained).load()).sourceKeys))
        let sourcesDatabase = try XCTUnwrap(databaseHandle(in: sources),
            "Source management must hold the runtime database")
        XCTAssertTrue(sourcesDatabase === retained, "Source management opened a different pool")
        let secondSources = composition.makeSourceManagementStore()
        XCTAssertTrue(try XCTUnwrap(databaseHandle(in: secondSources)) === retained,
            "Opening the source screen again must reuse the same handle")

        let publication = PublicationStore(database: retained)
        let cards = try XCTUnwrap(association.store.state.presentation?.window.items)
        let cardID = try XCTUnwrap(cards.first {
            (try? publication.card(id: $0.id))?.primaryActionKind == "externalURL"
        }?.id, "The controlled feed must contain an existing, non-media card")

        let positions = try XCTUnwrap(composition.mediaAdapter.positions as? ReaderPlaybackPositionsAdapter)
        positions.save(position: 93, duration: 240, for: cardID)
        XCTAssertEqual(try PlaybackPositionStore(database: retained).position(for: cardID)?.position, 93,
            "A player position written through the adapter must reach the retained database")
        XCTAssertEqual(positions.position(for: cardID), 93)
        XCTAssertTrue(try XCTUnwrap(databaseHandle(in: positions)) === retained,
            "The position adapter must cache the retained handle after its first write")

        // The computed media coordinator is not retained by the composition. Exercise its real
        // action instead: it must find the card above through the published database. A fresh,
        // empty database would report 'card not found' rather than 'no media action'.
        await composition.toggleMedia(cardID: cardID)
        XCTAssertEqual(composition.mediaState.error, String(localized: "Este card não tem o que tocar"),
            "Media must resolve the existing card through the same persisted publication")
        await composition.association?.close()
    }

    func testA05CollectionFeedsTrackActiveSessionThroughRebuildAndRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        await composition.launch()
        let original = try XCTUnwrap(composition.association)
        let selected = composition.feeds
        XCTAssertGreaterThan(selected.count, 1)
        let chosen = selected[1]
        let collection = try XCTUnwrap(ReaderLibraryCoordinator(database: original.database)
            .collectSources(named: "Only science", sourceKeys: [chosen.principal]))
        try await composition.openCollectionFeed(id: collection.id)
        let active = try XCTUnwrap(composition.association)
        XCTAssertEqual(composition.feeds.map(\.principal), [chosen.principal],
            "The app reports the sources its active association actually uses")
        XCTAssertEqual(active.feeds.map(\.principal), [chosen.principal])
        let observed = await active.coordinator.healthSnapshot()
        let health = await composition.sourceHealth()
        let expected = Set(active.feeds.filter { observed[$0.targetID] != nil }.map(\.principal))
        XCTAssertEqual(Set(health.keys), expected, "Health must be mapped through the active session's sources")
        XCTAssertEqual(try ReaderPreferencesStore(database: active.database).load()?.sourceKeys,
            selected.map(\.principal), "Opening a collection never changes the reader's selection")

        try await composition.replaceSession()
        XCTAssertEqual(composition.feeds.map(\.principal), [chosen.principal],
            "Rebuilding an open collection must not silently switch to the reader's selection")
        await composition.association?.close()

        let reopened = root(directory: directory)
        await reopened.launch()
        XCTAssertNil(reopened.startupFailure)
        XCTAssertEqual(reopened.feeds.map(\.principal), [chosen.principal],
            "A persisted collection context must restore with its own sources")
        try await reopened.applyFilter(.unrestricted, preset: .everything)
        XCTAssertEqual(reopened.feeds.map(\.principal), selected.map(\.principal),
            "Leaving the collection recovers the selected sources without parallel state")
        await reopened.association?.close()
    }


    /// F12/S1 + D1/D2, the measured sequence. The reader starts with an **empty** selection; the surface's own
    /// owner enables one catalogue source, whose local memberships publish under the catalogue's name; the reader
    /// disables it; and then opens its row. Four product facts are asserted, each on the value the surface reads:
    /// the destination is admitted while the selection question stays false (`surfaceHasSources` vs
    /// `hasSelectedSources`, D1); the cards that appear come from that source alone and carry its name in the
    /// published attribution (D2 — the chip is not accepted as proof); opening writes no selection and changes no
    /// acquisition target; and a relaunch on the same container restores the context, the window and the
    /// attribution from the feed's own published fact, without a catalogue scan. The window is filled by the open's
    /// own launch: no `refreshFromTheReader`, no `retryNow`.
    func testF12EmptySelectionOpensTheDisabledSourceWithNamedCards() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let key = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let entry = try XCTUnwrap(LegacyCatalogImport.entry(
            try XCTUnwrap(LegacyCatalogReader(catalogURL: catalogue).source(key: key))))
        let sourceID = entry.source.id
        let expectedName = entry.source.displayName

        let composition = root(directory: directory, feeds: [])
        await composition.launch()
        let database = try XCTUnwrap(composition.association).database
        // The reader's own content, stated as the store's fact: the enabled source owns one local membership and
        // one other source owns another. Acquisition is not what discriminates here — the state is.
        let date = Date()
        func seed(_ headline: String, source: SourceID, value: String) throws {
            let origin = OriginRecordID(), revision = OriginRevisionID()
            try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
                externalObjectIdentity: .init(connectorKind: .syndication, namespace: "f12-empty",
                    value: value, role: .object),
                revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                    headline: headline, summary: "Summary", bodyText: "Body", authoredAt: date, modifiedAt: nil,
                    observedAt: date, language: "en", primaryLink: nil, searchProjection: nil, providerID: nil),
                mediaCandidates: [], availability: .available, observedAt: date, expectedCurrent: .none,
                currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: date)]))
        }
        try seed("Only this source", source: sourceID, value: "f12-empty-s")
        try seed("Another source", source: SourceID(), value: "f12-empty-t")

        func cards() -> [PresentationCard] {
            composition.association?.store.state.presentation?.window.items ?? []
        }
        func waitForCards(_ atLeast: Int, timeout: TimeInterval) async throws -> [PresentationCard] {
            let deadline = Date().addingTimeInterval(timeout)
            var found = cards()
            while Date() < deadline, found.count < atLeast {
                try await Task.sleep(for: .milliseconds(100))
                found = cards()
            }
            return found
        }

        // Control: with nothing selected, the main surface is the honest empty-selection surface and the reader
        // has no feeds. This is the T7/F02 question, and the source destination must not be confused with it.
        XCTAssertTrue(composition.feeds.isEmpty)
        XCTAssertFalse(composition.hasSelectedSources)
        XCTAssertFalse(composition.surfaceHasSources,
            "an empty selection on `.main` still asks the reader to enable sources")

        // R4's own act, through the surface's owner: the source is enabled and publishes under a selection version.
        let coordinator = SourceManagementCoordinator(catalogURL: catalogue, database: database)
        try coordinator.setSourceEnabled(key: key, enabled: true)
        await composition.adoptSelectionChange()
        // UX12-C/R4: the act was "follow this source", not "go somewhere". The destination stays what it was; the
        // choice appears in the selection and in what the plain feed publishes.
        XCTAssertEqual(composition.currentContextKey.request, .main,
            "enabling a source is a management act, not a navigation")
        XCTAssertEqual(composition.feeds.map(\.sourceID), [sourceID], "premise: the enable reached the session")
        let enabledCards = try await waitForCards(1, timeout: 60)
        XCTAssertGreaterThan(enabledCards.count, 0, "the enabled source publishes its local memberships")
        XCTAssertEqual(Set(enabledCards.compactMap(\.sourceID)), [sourceID])
        XCTAssertTrue(enabledCards.allSatisfy { $0.sourceDisplayName == expectedName },
            "control: while selected, the feed attributes its own name; got \(enabledCards.map(\.sourceDisplayName))")

        let preferences = ReaderPreferencesStore(database: database)
        let targetBefore = try AcquisitionTargetStore(database: database).target(id: entry.targetID)
        try coordinator.setSourceEnabled(key: key, enabled: false)
        await composition.adoptSelectionChange()
        XCTAssertEqual(composition.currentContextKey.request, .main)
        XCTAssertFalse(composition.hasSelectedSources, "the reader chose nothing; that empty is honest for `.main`")
        XCTAssertFalse(composition.surfaceHasSources)
        XCTAssertTrue(composition.feeds.isEmpty)
        XCTAssertEqual(try preferences.load()?.sourceKeys, [])

        // The row still names its destination. Opening it is not enabling it.
        let opened = try await composition.openSourceFeed(forKey: key)
        XCTAssertTrue(opened, "the catalogue row still resolves its key")
        XCTAssertEqual(composition.currentContextKey.request, .source(sourceID))
        XCTAssertEqual(try preferences.load()?.sourceKeys, [], "opening writes no selection")
        XCTAssertTrue(composition.feeds.isEmpty,
            "the session keeps the reader's own feeds, so no endpoint is enabled")
        XCTAssertEqual(try AcquisitionTargetStore(database: database).target(id: entry.targetID), targetBefore,
            "opening registers nothing and changes no acquisition target")
        XCTAssertFalse(composition.hasSelectedSources, "the destination did not become a selection")
        XCTAssertTrue(composition.surfaceHasSources,
            "a source context is a destination even with an empty selection (D1)")
        XCTAssertEqual(composition.sourceContextDisplayName, expectedName,
            "the chip's one owner names the source the reader opened")

        // D1+D2 on the product's own publication: the disabled source's cards, named, and no other source's.
        let openedCards = try await waitForCards(1, timeout: 60)
        XCTAssertGreaterThan(openedCards.count, 0,
            "the disabled source's published material reaches its surface (D1); cards=\(openedCards.count)")
        XCTAssertEqual(Set(openedCards.compactMap(\.sourceID)), [sourceID],
            "only that source's memberships reach this surface")
        XCTAssertTrue(openedCards.allSatisfy { $0.sourceDisplayName == expectedName },
            "the published cards attribute the destination even though it is not in the selection (D2): "
                + "\(openedCards.map(\.sourceDisplayName))")
        await composition.association?.close()

        // A new process on the same container, with the selection still empty: the source context is the reading
        // place, named from the attribution the feed itself published — no catalogue walk at launch.
        let reopened = root(directory: directory, feeds: [])
        await reopened.launch()
        XCTAssertNil(reopened.startupFailure)
        XCTAssertEqual(reopened.currentContextKey.request, .source(sourceID),
            "the saved source context survives the relaunch")
        XCTAssertFalse(reopened.hasSelectedSources)
        XCTAssertTrue(reopened.surfaceHasSources, "the relaunch draws the destination, not the selection prompt")
        XCTAssertEqual(reopened.sourceContextDisplayName, expectedName,
            "a relaunch names the source from the attribution the feed itself published")
        var restored = reopened.association?.store.state.presentation?.window.items ?? []
        let restoreDeadline = Date().addingTimeInterval(60)
        while Date() < restoreDeadline, restored.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
            restored = reopened.association?.store.state.presentation?.window.items ?? []
        }
        XCTAssertFalse(restored.isEmpty, "the relaunch restores the source's own window")
        XCTAssertEqual(Set(restored.compactMap(\.sourceID)), [sourceID])
        XCTAssertTrue(restored.allSatisfy { $0.sourceDisplayName == expectedName },
            "the restored cards keep their attribution: \(restored.map(\.sourceDisplayName))")
        await reopened.association?.close()
    }

    /// F12/R6: opening a catalogue source and coming back preserves the Edition the reader already had — visiting a
    /// source must not substitute it. A→B→A through the same owner the chip uses.
    func testF12ReturningFromASourceKeepsTheEditionsIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        await composition.launch()
        func presentation() -> FeedPresentationSnapshot? {
            composition.association?.store.state.presentation
        }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, presentation() == nil { await Task.yield() }
        let before = try XCTUnwrap(presentation(), "the main feed presents")
        let edition = before.editionID

        let key = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let openedSource = try await composition.openSourceFeed(forKey: key)
        XCTAssertTrue(openedSource)
        XCTAssertEqual(composition.currentContextKey.request.isSource, true)
        try await composition.selectContext(.main)
        let returnedBy = Date().addingTimeInterval(30)
        while Date() < returnedBy, presentation()?.editionID != edition { await Task.yield() }
        XCTAssertEqual(presentation()?.editionID, edition,
            "coming back is the same Edition, not a substitute")
        XCTAssertEqual(composition.currentContextKey.request, .main)
        await composition.association?.close()
    }

    /// F12/R2: with **no verified snapshot installed**, the composition serves the bundled catalogue unverified and
    /// the source surface must show that same catalogue instead of declaring it unavailable — measured on the
    /// simulator: the sheet said "The source catalogue isn't available." while the feed was reading the bundle.
    func testF12DegradedCatalogueStillExposesTheBundledTree() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let manifest = try XCTUnwrap(Bundle.main.url(forResource: "catalog.manifest", withExtension: "json"))
        let installation = CatalogInstallation(directory: directory, bundledCatalogue: bundled,
            bundledManifest: manifest)
        XCTAssertNil(installation.activeSnapshot(), "a fresh directory has no verified snapshot")
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let coordinator = SourceManagementCoordinator(installation: installation, database: database)
        XCTAssertTrue(coordinator.hasCatalog, "the bundled catalogue is still a catalogue, served unverified")
        let sections = try coordinator.sections()
        XCTAssertFalse(sections.isEmpty, "the reader's surface lists the bundled tree")
        XCTAssertTrue(sections.contains { $0.key == "15-nature-animals" })
    }

    /// F12/UX12-B, the two destinations a row can have. A key the **catalogue cannot resolve** returns `false`:
    /// nothing is derived here and the reader is not moved to a context that would fall back to the main feed. A
    /// key the reader has selected opens the ordinary source context and never rewrites the selection.
    func testF12RefusesAnUnresolvableKeyAndOpensTheSelectedSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        await composition.launch()
        let association = try XCTUnwrap(composition.association)
        let preferences = ReaderPreferencesStore(database: association.database)
        let before = try XCTUnwrap(try preferences.load())
        let selected = composition.feeds
        XCTAssertGreaterThanOrEqual(selected.count, 2)
        let science = try XCTUnwrap(selected.first { $0.principal == "bbc-science" })

        let original = composition.currentContextKey
        let refused = try await composition.openSourceFeed(forKey: "https://not-selected.example/feed")
        XCTAssertFalse(refused, "a key the catalogue cannot resolve has no destination")
        XCTAssertEqual(composition.currentContextKey, original, "the refusal moves nothing")
        XCTAssertEqual(try preferences.load()?.sourceKeys, before.sourceKeys,
            "a refusal never rewrites the selection")

        let opened = try await composition.openSourceFeed(forKey: science.principal)
        XCTAssertTrue(opened)
        XCTAssertEqual(composition.currentContextKey.request, .source(science.sourceID),
            "the destination is the selection's own resolved source")
        XCTAssertEqual(try preferences.load()?.sourceKeys, before.sourceKeys,
            "opening a source never rewrites the selection")
        XCTAssertEqual(composition.association?.contextKey, composition.currentContextKey)
        await composition.association?.close()
    }

    /// F12/UX12-B (the case the PRD names): a catalogued source the reader has **not** enabled still opens its own
    /// feed. The identity is the catalogue's own (`LegacyCatalogImport`), the session keeps the reader's own feeds
    /// (so the source's endpoint stays disabled and nothing is enabled), the selection is not written, and the only
    /// cards that can appear are that source's own memberships — the other source seeded in the same database never
    /// reaches this feed. The ordinary `selectContext` keeps refusing a source outside the selection; this is the
    /// explicit owner path, not a relaxation of that guard.
    func testF12OpensAnUnselectedCatalogueSourceWithOnlyItsLocalMemberships() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let key = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let record = try XCTUnwrap(try LegacyCatalogReader(catalogURL: catalogue).source(key: key))
        let entry = try XCTUnwrap(LegacyCatalogImport.entry(record))
        let sourceID = entry.source.id

        let composition = root(directory: directory)
        await composition.launch()
        let association = try XCTUnwrap(composition.association)
        let other = SourceID()
        // A published occurrence is subject to the reader's freshness eligibility: a 1970 date is excluded
        // before it can be selected, so the seed states now and carries a body a card can show.
        let date = Date()
        func seed(_ headline: String, source: SourceID, value: String) throws {
            let origin = OriginRecordID(), revision = OriginRevisionID()
            try ContentStore(database: association.database).commitCanonicalChange(.init(recordID: origin,
                externalObjectIdentity: .init(connectorKind: .syndication, namespace: "f12",
                    value: value, role: .object),
                revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                    headline: headline, summary: "Summary", bodyText: "Body", authoredAt: date, modifiedAt: nil,
                    observedAt: date, language: "en", primaryLink: nil, searchProjection: nil, providerID: nil),
                mediaCandidates: [], availability: .available, observedAt: date, expectedCurrent: .none,
                currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: date)]))
        }
        try seed("Only this source", source: sourceID, value: "s")
        try seed("Another source", source: other, value: "t")

        let preferences = ReaderPreferencesStore(database: association.database)
        let before = try XCTUnwrap(try preferences.load())
        let feedsBefore = composition.feeds.map(\.principal)
        XCTAssertFalse(before.sourceKeys.contains(key), "the reader has not enabled this source")
        XCTAssertFalse(feedsBefore.contains(key))

        let openedUnselected = try await composition.openSourceFeed(forKey: key)
        XCTAssertTrue(openedUnselected)
        XCTAssertEqual(composition.currentContextKey.request, .source(sourceID),
            "the context is the catalogue's own identity, never a silent fallback to main")
        XCTAssertEqual(try preferences.load()?.sourceKeys, before.sourceKeys,
            "opening never writes the selection")
        XCTAssertEqual(composition.feeds.map(\.principal), feedsBefore,
            "the session keeps exactly the reader's own feeds: the endpoint is not enabled")

        do {
            try await composition.selectContext(.source(sourceID))
            XCTFail("the ordinary source context still requires the reader's selection")
        } catch {
            XCTAssertTrue(error is ReaderPreferencesError, "refused as an invalid selection: \(error)")
        }
        XCTAssertEqual(composition.currentContextKey.request, .source(sourceID),
            "the refusal did not disturb the opened source")

        // The reader's own opportunity: a local slice publishes what the store already holds, without enabling
        // any endpoint (the session's feeds did not change).
        await composition.refreshFromTheReader()
        let deadline = Date().addingTimeInterval(60)
        var cards: [PresentationCard] = []
        while Date() < deadline, cards.isEmpty {
            cards = composition.association?.store.state.presentation?.window.items ?? []
            if cards.isEmpty { await composition.association?.retryNow() }
            await Task.yield()
        }
        XCTAssertFalse(cards.isEmpty, "the source's local membership is published; cards=\(cards.count)")
        XCTAssertEqual(Set(cards.compactMap(\.sourceID)), [sourceID],
            "no other source's membership reaches this feed")
        await composition.association?.close()

        // R6 and "no silent fallback": a new process on the same container keeps the source context. The launch and
        // every rebuild honor it with the same rule the open used, so `sessionState` cannot rewrite it to `main`.
        let reopened = root(directory: directory)
        await reopened.launch()
        XCTAssertEqual(reopened.currentContextKey.request, .source(sourceID),
            "a relaunch keeps the source context instead of falling back to main")
        let reopenedDatabase = try XCTUnwrap(reopened.association).database
        XCTAssertEqual(try ReaderPreferencesStore(database: reopenedDatabase).load()?.sourceKeys,
            before.sourceKeys, "the relaunch wrote no selection")
        XCTAssertEqual(reopened.feeds.map(\.principal), feedsBefore,
            "the relaunch keeps exactly the reader's own feeds")
        await reopened.association?.close()
    }

    /// F12/R1 + S1: the **card** of a source the reader disabled still has a destination. The id frozen on the card
    /// is traced back to the reader's durable key by the owner that minted it, and the composition opens the same
    /// canonical context the taxonomy row opens — without enabling the source, writing the selection or touching an
    /// acquisition target. Before this, the card path consulted the selection and answered with a toast inside the
    /// very feed the reader was reading.
    func testF12ViewSourceOnADormantSourcesCardOpensItsCanonicalContext() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let (composition, card, entry, sourceID, database) = try await dormantSourceCard(directory: directory)

        let preferences = ReaderPreferencesStore(database: database)
        XCTAssertEqual(try preferences.load()?.sourceKeys, [], "premise: the source is dormant")
        XCTAssertNotNil(try PublicationStore(database: database).card(id: card),
            "premise: the published card still exists (an older Edition still shows it)")
        let targetBefore = try AcquisitionTargetStore(database: database).target(id: entry.targetID)

        let association = try XCTUnwrap(composition.association)
        association.perform(.viewSource, cardID: card)
        let opened = await Self.waitUntil(10) {
            composition.currentContextKey.request == .source(sourceID)
        }
        XCTAssertTrue(opened, "the card of a dormant source opens that source's canonical context key")
        XCTAssertEqual(try preferences.load()?.sourceKeys, [],
            "opening never enables the source nor writes the selection")
        XCTAssertTrue(composition.feeds.isEmpty, "the session keeps the reader's own (empty) feeds")
        XCTAssertEqual(try AcquisitionTargetStore(database: database).target(id: entry.targetID), targetBefore,
            "opening registers nothing and changes no acquisition target")
        XCTAssertNil(composition.association?.store.toast,
            "nothing was refused: \(composition.association?.store.toast?.text ?? "nil")")
        await composition.association?.close()
    }

    /// F12/R1, the other terminal: a card whose source id this reader never resolved has **no** destination. The
    /// composition answers `false` and the card path states it; no context, selection or target moves, and nothing
    /// else is opened in its place.
    func testF12ViewSourceWithoutAResolvedKeyStatesNoDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let (composition, card, _, _, database) = try await dormantSourceCard(directory: directory)
        // The state a database written before identities were pinned has: the card exists, the key does not.
        try database.write { db in try db.execute(sql: "DELETE FROM reader_source_identity") }

        let original = composition.currentContextKey
        let association = try XCTUnwrap(composition.association)
        association.perform(.viewSource, cardID: card)
        let stated = await Self.waitUntil(5) {
            association.store.toast?.text == String(localized: "Não foi possível abrir a fonte")
        }
        XCTAssertTrue(stated, "an unresolvable key is stated: \(association.store.toast?.text ?? "no toast")")
        XCTAssertEqual(composition.currentContextKey, original, "the refusal moves nothing")
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.sourceKeys, [])
        await composition.association?.close()
    }

    /// F12/R1: the identity table records an authority the binding **states**, and only a declared one. The first
    /// visit pins the row (`INSERT OR IGNORE`), so a namespace this build does not know must record nothing rather
    /// than be guessed as the catalogue's — the guess would then be permanent. The control is the catalogue's own
    /// binding (no namespace), which records `catalog`.
    func testF12AnUndeclaredNamespaceRecordsNoAuthority() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let undeclared = "https://undeclared.example/feed"
        let catalogueBound = "https://catalogue-bound.example/feed"
        let database = try RuntimeDatabase(location: .init(directory: directory))
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: [undeclared, catalogueBound])
        let feeds = [undeclared, catalogueBound].map { key in
            TrustedFeed(targetID: AcquisitionTargetID(), sourceID: SourceID(), bindingID: SourceBindingID(),
                principal: key, endpoint: URL(string: key)!, displayName: "Fonte \(key)",
                principalNamespace: key == undeclared ? "feedmine-future-authority" : nil)
        }
        let composition = root(directory: directory, feeds: feeds)
        await composition.launch()
        let association = try XCTUnwrap(composition.association)
        let links = try ReaderLibraryStore(database: association.database).sourceLinks()
        XCTAssertNil(links[undeclared],
            "an undeclared namespace records no authority instead of guessing the catalogue's")
        XCTAssertEqual(links[catalogueBound]?.authority, "catalog",
            "the catalogue's own binding is recorded as the catalogue's")
        await association.close()
    }

    /// One published card of a catalogue source the reader **disabled**: the reader enables it through the
    /// surface's own owner (so a real card is published), then disables it. The identity row the owner wrote is
    /// what survives, not a selection.
    private func dormantSourceCard(directory: URL) async throws -> (AppComposition, PublicationCardID,
        LegacyCatalogEntry, SourceID, RuntimeDatabase) {
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let key = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let entry = try XCTUnwrap(LegacyCatalogImport.entry(
            try XCTUnwrap(LegacyCatalogReader(catalogURL: catalogue).source(key: key))))
        let sourceID = entry.source.id
        let composition = root(directory: directory, feeds: [])
        await composition.launch()
        let database = try XCTUnwrap(composition.association).database
        let date = Date()
        let origin = OriginRecordID(), revision = OriginRevisionID()
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "f12-card",
                value: "dormant", role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "Dormant source", summary: "Summary", bodyText: "Body", authoredAt: date,
                modifiedAt: nil, observedAt: date, language: "en", primaryLink: nil, searchProjection: nil,
                providerID: nil),
            mediaCandidates: [], availability: .available, observedAt: date, expectedCurrent: .none,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: sourceID, kind: .direct, observedAt: date)]))

        let coordinator = SourceManagementCoordinator(catalogURL: catalogue, database: database)
        try coordinator.setSourceEnabled(key: key, enabled: true)
        await composition.adoptSelectionChange()
        XCTAssertEqual(composition.currentContextKey.request, .main,
            "premise: the enable is a management act and does not move the reader")
        XCTAssertEqual(composition.feeds.map(\.sourceID), [sourceID], "premise: the enable reached the session")
        var published: [PresentationCard] = []
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, published.isEmpty {
            published = composition.association?.store.state.presentation?.window.items ?? []
            if published.isEmpty { await composition.association?.retryNow() }
            await Task.yield()
        }
        let card = try XCTUnwrap(published.first?.id, "the enabled source publishes its local membership")
        XCTAssertEqual(published.first?.sourceID, sourceID)

        try coordinator.setSourceEnabled(key: key, enabled: false)
        await composition.adoptSelectionChange()
        XCTAssertEqual(composition.currentContextKey.request, .main)
        XCTAssertTrue(composition.feeds.isEmpty)
        return (composition, card, entry, sourceID, database)
    }

    /// S1: an explicit open of a source the reader did not select pulls **only** that source's endpoint, through the
    /// existing coordinator and the existing admission, and creates no durable target: the licence and the cursor
    /// belong to the visit. The transport journal is the evidence ("requests feitos por ação explícita"), and the
    /// relaunch is the negative control — a restored reading place issues nothing until a new gesture.
    func testF12OpeningAnUnselectedSourcePullsOnlyItsOwnEndpointByExplicitGesture() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let key = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let entry = try XCTUnwrap(LegacyCatalogImport.entry(
            try XCTUnwrap(LegacyCatalogReader(catalogURL: catalogue).source(key: key))))
        let sourceID = entry.source.id
        let composition = root(directory: directory, feeds: [])
        await composition.launch()
        let database = try XCTUnwrap(composition.association).database

        FixtureTransport.requests.withLock { $0 = [] }
        let openedSource = try await composition.openSourceFeed(forKey: key)
        XCTAssertTrue(openedSource)
        let association = try XCTUnwrap(composition.association)
        XCTAssertEqual(association.contextKey.request, .source(sourceID))
        XCTAssertTrue(association.visitAuthority.isArmed, "the explicit open armed this session's visit")

        // Eligibility names exactly the visited target — and only inside its own context. A `.main` opportunity is
        // not the gesture that licensed it.
        let eligible = try association.acquisition.eligibleTargets(for: FeedContext(key: association.contextKey))
        XCTAssertEqual(eligible.map(\.id), [entry.targetID],
            "the visit is the one target this source surface may pull")
        XCTAssertTrue(try association.acquisition.eligibleTargets(for: FeedContext(request: .main)).isEmpty,
            "the visit never leaks into the reader's own feed")

        _ = try? await association.driver.drive(resources: association.resources)
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline,
            !FixtureTransport.requests.withLock({ $0 }).contains(where: { $0.contains("science_and_environment") }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        let requestsAfterOpening = FixtureTransport.requests.withLock { $0 }
        XCTAssertTrue(requestsAfterOpening.contains { $0.contains("science_and_environment") },
            "the explicit open is the act that requests that endpoint: \(requestsAfterOpening)")
        XCTAssertNil(try AcquisitionTargetStore(database: database).target(id: entry.targetID),
            "opening registers no durable target: visiting is not enabling")
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.sourceKeys, [],
            "opening writes no selection")
        let published = association.store.state.presentation?.window.items ?? []
        XCTAssertFalse(published.isEmpty, "the visited source's admitted payload reaches its surface")

        // The retired scope issues nothing: the arming dies with the association, and a later drive on it is inert.
        await association.close()
        XCTAssertFalse(association.visitAuthority.isArmed, "close revokes the visit")
        FixtureTransport.requests.withLock { $0 = [] }
        _ = try? await association.driver.drive(resources: association.resources)
        XCTAssertTrue(FixtureTransport.requests.withLock { $0 }.isEmpty,
            "a retired scope issues no request: \(FixtureTransport.requests.withLock { $0 })")

        // Relaunch on the same container: the reading place is restored, the licence is not. The local payload is
        // what the reader sees; zero requests until a new explicit gesture.
        FixtureTransport.requests.withLock { $0 = [] }
        let reopened = root(directory: directory, feeds: [])
        await reopened.launch()
        let restored = try XCTUnwrap(reopened.association)
        XCTAssertEqual(reopened.currentContextKey.request, .source(sourceID),
            "the saved source context survives the relaunch")
        XCTAssertFalse(restored.visitAuthority.isArmed, "relaunching is not a gesture")
        _ = try? await restored.driver.drive(resources: restored.resources)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(FixtureTransport.requests.withLock { $0 }.contains { $0.contains("science_and_environment") },
            "a restored visit issues no request until the reader opens it again: \(FixtureTransport.requests.withLock { $0 })")
        XCTAssertNil(try AcquisitionTargetStore(database: try XCTUnwrap(reopened.association).database)
            .target(id: entry.targetID), "and the relaunch enabled nothing durable either")

        // The same gesture again is what licenses the next pull.
        FixtureTransport.requests.withLock { $0 = [] }
        let openedAgain = try await reopened.openSourceFeed(forKey: key)
        XCTAssertTrue(openedAgain)
        let again = try XCTUnwrap(reopened.association)
        _ = try? await again.driver.drive(resources: again.resources)
        let rearmDeadline = Date().addingTimeInterval(30)
        while Date() < rearmDeadline,
            !FixtureTransport.requests.withLock({ $0 }).contains(where: { $0.contains("science_and_environment") }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(FixtureTransport.requests.withLock { $0 }.contains { $0.contains("science_and_environment") },
            "the new gesture re-arms the visit: \(FixtureTransport.requests.withLock { $0 })")
        await reopened.association?.close()
    }

    /// F12/UX12-C (B1): toggling another source while reading a source that was **never** in the selection is a
    /// management act, not a navigation. The reader stays on that source's surface, and its Edition, cards and anchor
    /// keep their identity — the case the previous rule ejected to `.main` because it only recognised selected
    /// sources.
    func testF12TogglingAnotherSourceWhileReadingADormantOneKeepsTheVisit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let seeds = try TrustedFeed.catalog(limit: 2, resourceURL: catalogue)
        let composition = root(directory: directory, feeds: seeds)
        await composition.launch()
        let database = try XCTUnwrap(composition.association).database
        let dormantKey = "https://feeds.npr.org/1001/rss.xml"
        let dormant = try XCTUnwrap(LegacyCatalogImport.entry(
            try XCTUnwrap(LegacyCatalogReader(catalogURL: catalogue).source(key: dormantKey))))
        // A real local card of the dormant source, so its surface has published history to preserve.
        let date = Date()
        let origin = OriginRecordID(), revision = OriginRevisionID()
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "f12-b1",
                value: "dormant-b1", role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "Dormant B1", summary: "Summary", bodyText: "Body", authoredAt: date, modifiedAt: nil,
                observedAt: date, language: "en", primaryLink: nil, searchProjection: nil, providerID: nil),
            mediaCandidates: [], availability: .available, observedAt: date, expectedCurrent: .none,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: dormant.source.id, kind: .direct, observedAt: date)]))

        let openedDormant = try await composition.openSourceFeed(forKey: dormantKey)
        XCTAssertTrue(openedDormant)
        let visited = try XCTUnwrap(composition.association)
        let opened = await Self.waitUntil(30) {
            (visited.store.state.presentation?.window.items.count ?? 0) > 0
        }
        XCTAssertTrue(opened, "premise: the dormant source's surface publishes its local card")
        let before = try XCTUnwrap(visited.store.state.presentation)
        XCTAssertEqual(Set(before.window.items.compactMap(\.sourceID)), [dormant.source.id])

        // The reader manages another source from the sources surface: the selection really changes.
        try await composition.searchSources("")
        try await composition.toggleSource(seeds[0].sourceID)
        XCTAssertEqual(composition.currentContextKey.request, .source(dormant.source.id),
            "toggling another source does not eject the reader from the visit")
        XCTAssertFalse(composition.feeds.contains { $0.sourceID == seeds[0].sourceID },
            "premise: the toggle reached the selection")
        let after = try XCTUnwrap(composition.association)
        XCTAssertEqual(after.contextKey.request, .source(dormant.source.id))
        let presentation = try XCTUnwrap(after.store.state.presentation)
        XCTAssertEqual(presentation.editionID, before.editionID, "the Edition the reader was reading is not replaced")
        XCTAssertEqual(presentation.window.items.map(\.id), before.window.items.map(\.id),
            "the published cards keep their identity and order")
        XCTAssertEqual(presentation.window.anchor, before.window.anchor, "and so does the reader's anchor")
        XCTAssertEqual(try after.acquisition.eligibleTargets(for: FeedContext(key: after.contextKey)).map(\.id),
            [dormant.targetID], "the visit is still the surface's own target")
        await after.close()
    }

    /// F12/UX12-C (B3): an emptied selection is not a reason to destroy published history. The original requirement
    /// is explicit — disabling a source "não remove/reordena os cards já publicados" — and the reader's own surface
    /// is what states the empty selection (`surfaceHasSources`). The Edition, its cards and the anchor survive the
    /// transition and a relaunch; only future supply is empty.
    func testF12AnEmptiedSelectionKeepsPublishedHistoryAndStatesTheEmptySelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let seeds = try TrustedFeed.catalog(limit: 1, resourceURL: catalogue)
        let composition = root(directory: directory, feeds: seeds)
        await composition.launch()
        let database = try XCTUnwrap(composition.association).database
        let presented = await Self.waitUntil(60) {
            !(composition.association?.store.state.presentation?.window.items.isEmpty ?? true)
        }
        XCTAssertTrue(presented, "premise: the selected source published")
        let before = try XCTUnwrap(composition.association?.store.state.presentation)
        XCTAssertFalse(composition.currentContextKey.request.isSource)

        try SourceManagementCoordinator(catalogURL: catalogue, database: database).setSelection([])
        await composition.adoptSelectionChange()
        XCTAssertTrue(composition.feeds.isEmpty)
        XCTAssertFalse(composition.hasSelectedSources)
        XCTAssertFalse(composition.surfaceHasSources,
            "the reader's own surface states that nothing is selected")
        XCTAssertEqual(composition.currentContextKey.request, .main,
            "emptying the selection is a management act, not a navigation")
        let after = try XCTUnwrap(composition.association?.store.state.presentation)
        XCTAssertEqual(after.editionID, before.editionID, "the published Edition is preserved")
        XCTAssertEqual(after.window.items.map(\.id), before.window.items.map(\.id),
            "no published card is removed or reordered")
        XCTAssertEqual(after.window.anchor, before.window.anchor, "the reader's position is preserved")
        await composition.association?.close()

        let reopened = root(directory: directory, feeds: [])
        await reopened.launch()
        XCTAssertTrue(reopened.feeds.isEmpty)
        let restored = try XCTUnwrap(reopened.association?.store.state.presentation)
        XCTAssertEqual(restored.editionID, before.editionID, "the relaunch restores that same history")
        XCTAssertEqual(restored.window.items.map(\.id), before.window.items.map(\.id))
        XCTAssertEqual(restored.window.anchor, before.window.anchor)
        await reopened.association?.close()
    }

    /// F12/UX12-D: a source the reader opened that has **no local payload** and whose network is refused states the
    /// absence in its own terms. It does not invent cards, does not substitute the main feed's Edition and does not
    /// claim the end of content (an outage is not "you have read everything"). `surfaceHasSources` stays true, so the
    /// surface asks about *this source*, never about an empty selection.
    func testF12AConstrainedVisitStatesAbsenceWithoutInventingOrSubstituting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let key = "https://feeds.npr.org/1001/rss.xml"
        let entry = try XCTUnwrap(LegacyCatalogImport.entry(
            try XCTUnwrap(LegacyCatalogReader(catalogURL: catalogue).source(key: key))))
        FixtureTransport.rejecting.withLock { $0 = true }
        addTeardownBlock { FixtureTransport.rejecting.withLock { $0 = false } }
        let composition = root(directory: directory, feeds: [])
        await composition.launch()
        let database = try XCTUnwrap(composition.association).database
        XCTAssertNil(composition.association?.store.state.presentation, "premise: nothing local to restore")

        let opened = try await composition.openSourceFeed(forKey: key)
        XCTAssertTrue(opened)
        let association = try XCTUnwrap(composition.association)
        _ = try? await association.driver.drive(resources: association.resources)
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(association.contextKey.request, .source(entry.source.id),
            "the surface is the source the reader opened, not a repaired `.main`")
        XCTAssertTrue(composition.surfaceHasSources,
            "the absence belongs to this source, not to an empty selection")
        XCTAssertFalse(composition.hasSelectedSources, "and opening it selected nothing")
        XCTAssertTrue(composition.feeds.isEmpty)
        XCTAssertNil(association.store.state.presentation,
            "no card is invented and no other Edition is substituted for an outage")
        XCTAssertNotEqual(association.store.work, .endOfContent,
            "an unreachable source is not the end of its content")
        XCTAssertNil(composition.startupFailure, "a constrained feed is not a startup failure")
        XCTAssertEqual(composition.sourceContextDisplayName, entry.source.displayName,
            "the chip still names the source it is about")
        XCTAssertNil(try AcquisitionTargetStore(database: database).target(id: entry.targetID),
            "the constrained visit registered nothing durable either")
        await association.close()
    }

    /// F12/R1: a card from a **collection's** source, which the reader has not selected, opens that source's own
    /// context. `feeds` inside a collection holds the collection's sources, so a "is this id readable here?" guard
    /// admits it and `sessionState` rewrites the request to `.main` — the silent fallback class this fix exists to
    /// remove. The selection is untouched.
    func testF12ACollectionSourcesCardOpensItsOwnContext() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let key = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let entry = try XCTUnwrap(LegacyCatalogImport.entry(
            try XCTUnwrap(LegacyCatalogReader(catalogURL: catalogue).source(key: key))))
        let sourceID = entry.source.id
        let composition = root(directory: directory)
        await composition.launch()
        let database = try XCTUnwrap(composition.association).database
        let date = Date()
        let origin = OriginRecordID(), revision = OriginRevisionID()
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "f12-collection",
                value: "collection-card", role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "Collection source", summary: "Summary", bodyText: "Body", authoredAt: date,
                modifiedAt: nil, observedAt: date, language: "en", primaryLink: nil, searchProjection: nil,
                providerID: nil),
            mediaCandidates: [], availability: .available, observedAt: date, expectedCurrent: .none,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: sourceID, kind: .direct, observedAt: date)]))

        // The reader puts the catalogue source in a collection **without selecting it**, then opens the collection.
        let selectedBefore = composition.feeds.map(\.principal)
        XCTAssertFalse(selectedBefore.contains(key), "premise: the source is not selected")
        let collection = try ReaderLibraryCoordinator(database: database)
            .collectSources(named: "Catalogue only", sourceKeys: [key])
        try await composition.openCollectionFeed(id: collection.id)
        XCTAssertEqual(composition.feeds.map(\.sourceID), [sourceID],
            "premise: the collection presents that source's feed")
        var published: [PresentationCard] = []
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, published.isEmpty {
            published = composition.association?.store.state.presentation?.window.items ?? []
            if published.isEmpty { await composition.association?.retryNow() }
            await Task.yield()
        }
        let card = try XCTUnwrap(published.first?.id, "the collection publishes its source's card")
        XCTAssertEqual(published.first?.sourceID, sourceID)

        let preferences = ReaderPreferencesStore(database: database)
        let association = try XCTUnwrap(composition.association)
        association.perform(.viewSource, cardID: card)
        let opened = await Self.waitUntil(10) {
            composition.currentContextKey.request == .source(sourceID)
        }
        XCTAssertTrue(opened,
            "the destination is that source's own context, never a silent `.main`: "
                + "\(composition.currentContextKey.request)")
        XCTAssertEqual(try preferences.load()?.sourceKeys, selectedBefore,
            "opening never writes the selection")
        await composition.association?.close()
    }

    /// A changed persisted selection is a plain/source context, not an intersection with the
    /// collection previously open. A is selected, B is in the collection, and A never belongs to B.
    func testA05AdoptingSelectionOutsideCollectionExitsCollectionPreset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory)
        await composition.launch()
        let original = try XCTUnwrap(composition.association)
        let selected = composition.feeds
        XCTAssertGreaterThanOrEqual(selected.count, 2)
        let a = selected[0], b = selected[1]
        let library = ReaderLibraryCoordinator(database: original.database)
        let collection = try library.collectSources(named: "Only B", sourceKeys: [b.principal])
        try await composition.openCollectionFeed(id: collection.id)
        XCTAssertEqual(composition.feeds.map(\.principal), [b.principal])

        let preferences = ReaderPreferencesStore(database: original.database)
        _ = try preferences.updateSources([a.principal])
        await composition.adoptSelectionChange()
        XCTAssertNil(composition.startupFailure)
        XCTAssertEqual(composition.currentContextKey.preset, .everything)
        XCTAssertEqual(composition.currentContextKey.request, .main,
            "leaving a collection keeps the plain feed; one remaining source is not a destination")
        XCTAssertEqual(composition.feeds.map(\.principal), [a.principal])
        XCTAssertEqual(composition.association?.feeds.map(\.principal), [a.principal])
        XCTAssertEqual(try preferences.load()?.activeContextKey, composition.currentContextKey)
        XCTAssertEqual(try preferences.load()?.sourceKeys, [a.principal])
        await composition.association?.close()
    }

    /// Deletion and removal of the final membership both make the stored collection context
    /// unusable. The app must reopen the reader's persisted selection and repair the saved key.
    func testA05DeletedOrEmptiedCollectionRestoresSelectionInsteadOfFailingLaunch() async throws {
        for deleteCollection in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let composition = root(directory: directory)
            await composition.launch()
            let original = try XCTUnwrap(composition.association)
            let selected = composition.feeds
            XCTAssertGreaterThanOrEqual(selected.count, 2)
            let b = selected[1]
            let library = ReaderLibraryCoordinator(database: original.database)
            let collection = try library.collectSources(named: "Temporary B", sourceKeys: [b.principal])
            try await composition.openCollectionFeed(id: collection.id)
            XCTAssertEqual(composition.currentContextKey.preset, .collection(collection.id))

            if deleteCollection {
                XCTAssertTrue(try library.deleteCollection(id: collection.id))
            } else {
                try library.setCollectionMembership(sourceKey: b.principal,
                    collectionID: collection.id, included: false)
                XCTAssertTrue(try library.sourceKeys(inCollection: collection.id).isEmpty)
            }
            await composition.association?.close()
            let restored = root(directory: directory)
            await restored.launch()
            XCTAssertNil(restored.startupFailure, "An unavailable collection must not break cold restore")
            XCTAssertNotNil(restored.association)
            XCTAssertEqual(restored.currentContextKey.preset, .everything)
            XCTAssertEqual(restored.currentContextKey.request, .main)
            XCTAssertEqual(restored.feeds.map(\.principal), selected.map(\.principal))
            XCTAssertEqual(try ReaderPreferencesStore(database: try XCTUnwrap(restored.association).database)
                .load()?.activeContextKey, restored.currentContextKey, "Reconciliation must be durable")
            await restored.association?.close()
        }
    }

    /// B is a real catalog source kept only in a collection: it is NOT part of the saved
    /// selection A. The source(B) context must validate against the collection on relaunch.
    func testA05RestoresSourceExclusiveToCollectionWithoutDiscardingPreset() async throws {
        let catalog = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let available = try TrustedFeed.catalog(limit: 2, resourceURL: catalog)
        XCTAssertEqual(available.count, 2)
        let a = available[0], b = available[1]
        XCTAssertNotEqual(a.sourceID, b.sourceID)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let composition = root(directory: directory, feeds: available)
        await composition.launch()
        let original = try XCTUnwrap(composition.association)
        let preferences = ReaderPreferencesStore(database: original.database)
        _ = try preferences.updateSources([a.principal])
        await composition.adoptSelectionChange()
        XCTAssertEqual(composition.feeds.map(\.principal), [a.principal])
        let library = ReaderLibraryCoordinator(database: original.database)
        let collection = try library.collectSources(named: "Only B", sourceKeys: [b.principal])
        try await composition.openCollectionFeed(id: collection.id)
        XCTAssertEqual(composition.feeds.map(\.principal), [b.principal])
        try await composition.selectContext(.source(b.sourceID))
        XCTAssertEqual(composition.currentContextKey.request, .source(b.sourceID))
        XCTAssertEqual(composition.currentContextKey.preset, .collection(collection.id))
        await composition.association?.close()

        let reopened = root(directory: directory, feeds: available)
        await reopened.launch()
        XCTAssertNil(reopened.startupFailure)
        XCTAssertEqual(reopened.currentContextKey.request, .source(b.sourceID))
        XCTAssertEqual(reopened.currentContextKey.preset, .collection(collection.id))
        XCTAssertEqual(reopened.feeds.map(\.principal), [b.principal])
        XCTAssertEqual(try ReaderPreferencesStore(database: try XCTUnwrap(reopened.association).database)
            .load()?.sourceKeys, [a.principal], "Collection navigation never rewrites the reader's selection")
        await reopened.association?.close()
    }

    // MARK: - A fronteira restauração ↔ descoberta

    /// A container the reader has already used, with a durable window: one real launch over the development
    /// feeds, its position written as durable. What comes after it is the relaunch these smokes are about — the
    /// only path in which the pool a profile names is read **behind** the reader's own window.
    private func containerWithADurableWindow(answering topic: String) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 60
        let first = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
        await first.launch()
        XCTAssertNil(first.startupFailure)
        let association = try XCTUnwrap(first.association, "the first launch has to build a session")
        XCTAssertNotNil(association.store.state.presentation, "and there has to be a window to leave durable")
        // The reader's answers are a preference, and the relaunch reads them: without them there is no profile,
        // and therefore no read to stage.
        await first.voteOnTopic(nodeKey: topic, level: .more)
        _ = try await association.session.checkpointCurrentPosition(at: Date())
        await association.close()
        return directory
    }

    /// Two default-enabled text sources of the shipped catalogue, far past any first page, as the entries a read
    /// could bring. The walk examines the catalogue in **key order**; these sit at positions 300 and 301, which is
    /// what makes "eligible without examining the pages in between" a claim with a measurement behind it.
    private func catalogueEntriesOutsideTheWalkFirstPage() throws -> (catalogue: URL, records: [LegacyCatalogSourceRecord],
        first: LegacyCatalogEntry, second: LegacyCatalogEntry) {
        let catalogue = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let records = try LegacyCatalogReader(catalogURL: catalogue)
            .sources(after: nil, limit: 400, onlyDefaultEnabled: true, mediaKinds: ["text"])
        XCTAssertGreaterThan(records.count, 302, "the shipped catalogue is deeper than the positions this uses")
        return (catalogue, records,
            try XCTUnwrap(LegacyCatalogImport.entry(records[300])),
            try XCTUnwrap(LegacyCatalogImport.entry(records[301])))
    }

    /// **Smoke (a).** A seed read **behind** the reader's window is supply, and only for the sources the authority
    /// still allows. Two catalogue sources far past the walk's first page are what the read brings; one of them is
    /// revoked **while the read is out**, which is the case a warm launch has to survive. What has to hold after
    /// the await: the revoked source is not discovery, not eligible for acquisition and not in the effective
    /// policy; the healthy one is all three, and became so **without** the walk examining the pages before it;
    /// the reader's window and its anchor are exactly what they were.
    @MainActor
    func testAWarmSeedOutsideTheWalkFirstPageIsSupplyOnlyIfTheAuthorityStillAllowsIt() async throws {
        let entries = try catalogueEntriesOutsideTheWalkFirstPage()
        // The profile names the **root** placement of the catalogue's first default-enabled text record. That is
        // what makes "the walk still begins at the first record" observable: the walk examines records in key order
        // and reports the ones the profile admits, and the first record is admitted by the profile derived from its
        // own placement — so a cursor faked past the pool would come back with a page that does not contain it.
        let walkFirst = try XCTUnwrap(entries.records[0].nodeKeys.first?.split(separator: "/").first.map(String.init),
            "the catalogue's first record has to be placed somewhere for the walk to admit it")
        let directory = try await containerWithADurableWindow(answering: walkFirst)
        let gate = DiscoveryGate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 60
        let warm = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration, discoveryQuery: gate.query)

        // The window and the anchor this launch starts from, read **before** anything discovery does with it: the
        // claim that the adoption leaves them alone is about exactly this value.
        let before = try XCTUnwrap(warm.association?.store.state.presentation,
            "a launch with a durable window starts from the reader's own window")
        let cardsBefore = before.window.items.map(\.id)
        let anchorBefore = before.window.anchor.cardID
        XCTAssertFalse(cardsBefore.isEmpty)

        // ...and the walk the adoption will find, read here for the same reason: it is at its **first page**, so
        // what the pool brings is supply it has not reached. The two sources sit at positions 300 and 301 of the
        // catalogue, and one page examines 120 records from where the walk is — so "eligible without crossing the
        // pages in between" is a fact about this walk and not about a cursor someone moved.
        //
        // (That adopting a pool does **not** move this cursor is asserted where it is observable without a driver
        // in the middle — `ReaderDiscoveryPoolTests.testAPoolReadBesideTheWalkBecomesSupplyWithoutMovingTheCursor`,
        // the package smoke of the same boundary. Here the launch's own first opportunity advances the walk
        // legitimately, which is its mechanism and not the adoption's doing.)
        let starting = try XCTUnwrap(warm.association)
        let context = FeedContext(key: starting.contextKey)
        let firstPage = try XCTUnwrap(starting.acquisition.advanceDiscovery(for: context, examinedCapacity: 2))
        let admittedFirstRecords = Set(entries.records.prefix(2)
            .filter { $0.nodeKeys.contains { $0 == walkFirst || $0.hasPrefix(walkFirst + "/") } }.map(\.key))
        XCTAssertGreaterThan(admittedFirstRecords.count, 0, "the profile admits the catalogue's first records")
        XCTAssertEqual(Set(firstPage.entries.map(\.principal)), admittedFirstRecords,
            "the walk begins at the catalogue's first records: \(firstPage.entries.map(\.principal))")
        XCTAssertFalse(firstPage.entries.contains { $0.targetID == entries.first.targetID },
            "and it has not reached the source the pool brings")
        print("BOUNDARY_WITNESS profile=\(walkFirst) walk_first_page=\(firstPage.entries.map(\.principal).sorted())"
            + " seed=\(entries.first.principal) revoked=\(entries.second.principal)")

        // The reader's window is what the host is drawing, and this launch's own read is out — it concludes only
        // when the test says.
        let launching = Task { await warm.launch() }
        let read = await gate.nextRead()
        XCTAssertEqual(read.profile.topicNodeKeys, [walkFirst],
            "the read answers for the profile this session is on")
        // **The revocation happens while the read is out.**
        let association = try XCTUnwrap(warm.association)
        let authority = AcquisitionTargetAuthority(database: association.database)
        let doomed = try authority.register(id: entries.second.targetID, connectorKind: .syndication,
            authorizedSources: [entries.second.source.id])
        _ = try authority.revoke(id: doomed.id, expectedGeneration: doomed.generation)
        gate.answer(read, entries: [entries.second, entries.first],
            subjects: [entries.first.source.id: .init(nodeKey: "smoke/seed", name: "Semente")])
        await launching.value

        XCTAssertTrue(association.active)
        XCTAssertFalse(association.discovery.contains { $0.sourceID == entries.second.source.id },
            "a source the authority revoked is not discovery this session brought")
        XCTAssertTrue(association.discovery.contains { $0.sourceID == entries.first.source.id },
            "the healthy source the read brought is discovery, at position 301 of the catalogue")
        XCTAssertNil(association.subjects[entries.second.source.id])
        XCTAssertEqual(association.subjects[entries.first.source.id]?.name, "Semente")
        XCTAssertNotNil(warm.editorialSubject(for: entries.first.source.id, in: association),
            "the invitation may be asked about the source discovery brought")
        XCTAssertNil(warm.editorialSubject(for: entries.second.source.id, in: association),
            "and never about the revoked one")

        // Supply, not decoration: the target is eligible for acquisition and enters the **effective** policy.
        let eligible = try association.acquisition.eligibleTargets(for: context)
        XCTAssertTrue(eligible.contains { $0.id == entries.first.targetID },
            "a read behind the window is supply: the healthy source is acquirable")
        XCTAssertFalse(eligible.contains { $0.id == entries.second.targetID },
            "and a revoked one is not")
        guard case .selectedSources(let sources) = try association.acquisition
            .policyIncludingDiscovery(association.policy).eligibility else {
            return XCTFail("discovery preserves the selected-source policy")
        }
        XCTAssertTrue(sources.contains(entries.first.source.id))
        XCTAssertFalse(sources.contains(entries.second.source.id),
            "a revoked discovery cannot publish cards")

        let after = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(after.window.items.map(\.id), cardsBefore, "the adoption changed no card")
        XCTAssertEqual(after.window.anchor.cardID, anchorBefore, "nor the anchor")
        await association.close()
    }

    /// **Smoke (b).** A→B with A concluding last. The reader answers again while the pool of the session they are
    /// reading is out, so a second session is built for the new answers; then the first read concludes, after the
    /// session it was for is retired. What has to hold: the session reading now keeps **its own** facts — the
    /// subject its own read stated and the supply its own read materialized — and the stale read adopts nothing
    /// and activates nothing. Both answers bring the **same** catalogue source with a different subject, which is
    /// exactly the collision a composition-level map of subjects could not tell apart.
    @MainActor
    func testAReadConcludingAfterTheReaderMovedChangesNothingOfTheSessionReadingNow() async throws {
        let entries = try catalogueEntriesOutsideTheWalkFirstPage()
        let directory = try await containerWithADurableWindow(answering: "04-technology-science")
        let gate = DiscoveryGate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 60
        let warm = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration, discoveryQuery: gate.query)
        let shared = entries.first

        let launching = Task { await warm.launch() }
        let readOfA = await gate.nextRead()
        XCTAssertEqual(readOfA.profile.topicNodeKeys, ["04-technology-science"])
        let a = try XCTUnwrap(warm.association)

        // The reader moves while that read is out: an answer about discovery is a preference, and the session is
        // rebuilt around it — B, on B's own profile.
        await warm.voteOnTopic(nodeKey: "90_countries/brazil", level: .more)
        let replacing = Task { try await warm.replaceSession() }
        let readOfB = await gate.nextRead()
        XCTAssertNotEqual(readOfB.profile, readOfA.profile, "B reads its own profile, not the one A was reading")
        gate.answer(readOfB, entries: [shared],
            subjects: [shared.source.id: .init(nodeKey: "smoke/b", name: "Assunto B")])
        try await replacing.value
        let b = try XCTUnwrap(warm.association)
        XCTAssertFalse(b === a, "the reader's new session is the one reading now")
        XCTAssertFalse(a.active, "the retired session is not active")

        // A's read concludes **last**.
        gate.answer(readOfA, entries: [shared],
            subjects: [shared.source.id: .init(nodeKey: "smoke/a", name: "Assunto A")])
        await launching.value

        XCTAssertTrue(warm.association === b)
        XCTAssertEqual(b.subjects[shared.source.id]?.name, "Assunto B",
            "the subject of the session being read is the one its own read stated")
        XCTAssertEqual(warm.editorialSubject(for: shared.source.id, in: b)?.name, "Assunto B")
        XCTAssertTrue(b.discovery.contains { $0.sourceID == shared.source.id })
        XCTAssertTrue(try b.acquisition.eligibleTargets(for: FeedContext(key: b.contextKey))
            .contains { $0.id == shared.targetID }, "B's supply is B's own read")
        XCTAssertTrue(a.subjects.isEmpty, "a read that arrives after the reader moved states nothing for A")
        XCTAssertTrue(a.discovery.isEmpty, "and A is not adopted: it brought nothing after it was retired")
        await b.close()
    }

    /// **Uma resposta não constrói uma segunda sessão, nem quando a construção está em curso.** O B04 (2026-10-18)
    /// mediu o custo da versão anterior: a resposta chegava com `replacingSession` verdadeiro, o laço de
    /// reconstrução repetia, o `FeedAssociation` era trocado **depois** do toque (novo store, nova `sequenceID`,
    /// `position` de volta a 1), o `UIScrollView` era recriado e a carta sob o leitor andava 316 pt (610 → 294).
    /// A resposta é uma preferência sobre a **próxima** descoberta; a construção em curso não é refeita por ela.
    ///
    /// A condição é determinística: `replaceSession()` constrói pelo construtor de `FeedAssociation`, e o
    /// `DiscoveryGate` segura a leitura dessa construção — então a resposta cai comprovadamente **durante** ela.
    /// O que se afirma é a **sessão**: uma construção (`sessionConstructions`, o único construtor) e uma única
    /// troca de identidade. Sem a correção o laço pede uma segunda construção; responder a leitura dela faz a
    /// asserção ser sobre a sessão construída, não sobre uma tarefa presa — e o contador anda dois.
    @MainActor
    func testAnAnswerWhileTheSessionIsBeingBuiltDoesNotConstructAnotherSession() async throws {
        let directory = try await containerWithADurableWindow(answering: "04-technology-science")
        print("B04TEST container prepared")
        let entries = try catalogueEntriesOutsideTheWalkFirstPage()
        let gate = DiscoveryGate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 60
        let warm = AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration, discoveryQuery: gate.query)

        // O launch desta instância (com o portão na query de discovery): responder o que ele pedir, ou seguir.
        let launching = Task { await warm.launch() }
        if let launchRead = await readOrNil(gate, within: 20) {
            print("B04TEST launch read")
            gate.answer(launchRead, entries: [entries.first],
                subjects: [entries.first.source.id: .init(nodeKey: "smoke/a", name: "Assunto A")])
        }
        let launched = XCTestExpectation(description: "launch conclui")
        Task { await launching.value; launched.fulfill() }
        await fulfillment(of: [launched], timeout: 30)
        print("B04TEST launched constructions=\(warm.sessionConstructions) association=\(warm.association != nil)")

        // Um perfil novo: a substituição seguinte lê discovery de verdade, e é essa leitura que o portão segura.
        await warm.voteOnTopic(nodeKey: "90_countries/brazil", level: .more)
        let replacing = Task { try? await warm.replaceSession() }
        guard let buildRead = await readOrNil(gate, within: 20) else {
            return XCTFail("a substituição não chegou a ler discovery; não há construção em curso para medir")
        }
        let constructionsAtBuild = warm.sessionConstructions
        print("B04TEST build in flight constructions=\(constructionsAtBuild)")

        // A resposta que costumava marcar `pendingRebuild`, caindo **enquanto** a construção está em curso.
        await warm.voteOnTopic(nodeKey: "04-technology-science", level: .less)
        print("B04TEST answer in flight returned")
        gate.answer(buildRead, entries: [], subjects: [:])

        // Sem a correção o laço pede outra construção; responder a leitura dela torna a asserção sobre a sessão
        // construída. Com a correção não há segunda leitura (a corrida devolve nil).
        if let secondBuildRead = await readOrNil(gate, within: 2) {
            print("B04TEST second build read")
            gate.answer(secondBuildRead, entries: [], subjects: [:])
        }

        let concluded = XCTestExpectation(description: "a substituição conclui")
        Task { await replacing.value; concluded.fulfill() }
        await fulfillment(of: [concluded], timeout: 20)
        print("B04TEST done constructions=\(warm.sessionConstructions)")

        XCTAssertEqual(warm.sessionConstructions, constructionsAtBuild + 1,
            "a resposta não constrói outra sessão: uma construção para a substituição, nenhuma para a resposta")
        XCTAssertNotNil(warm.association, "a substituição entregou a sessão — uma, e só uma")
        try? await warm.association?.close()
    }

    /// A próxima leitura de discovery, ou `nil` quando nenhuma chega dentro do prazo. Consulta o portão **sem**
    /// esperar continuamente: uma leitura presa só é retomada por uma resposta, e uma espera estruturada por ela
    /// penduraria a suíte em vez de deixar a asserção falhar.
    private func readOrNil(_ gate: DiscoveryGate, within seconds: Double) async -> DiscoveryGate.Read? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let read = gate.takeArrivedRead() { return read }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return gate.takeArrivedRead()
    }

}

/// §5.3/PD-6: the media window is a **per-operation** limit derived from facts the run measures, never a fraction
/// of the transport's timeout. The derivation is the precedent, so it is pinned here: unmeasured states the run's
/// declared tolerance (12 s since PM-018; 5 s before it, when three arms measured 32,2% / 40,0% / 41,1% of published
/// cards carrying an image at ~5 s / 20 s / 60 s), measured follows the runway's own tolerance for one request, and
/// the transport timeout stays what it is — an operational ceiling, which is what PD-6 rule 4 allows it to be.
final class MediaWaitDerivationTests: XCTestCase {
    private let inputs = RunwayPolicyInputs(safetyFactor: 1.2, releaseMarginSeconds: 2)!

    func testUnmeasuredStatesTheBootstrapAndIsStillBoundedByTheTransportCeiling() {
        // The 12 s is the run's declared tolerance (PM-018), not `timeoutIntervalForRequest / 4`.
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: nil, inputs: inputs, transportCeiling: 60), 12)
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: nil, inputs: inputs, transportCeiling: 3), 3)
    }

    func testMeasuredFollowsTheRunsOwnToleranceSoAFasterSourceWaitsLess() {
        // p95 = 2 s → 2 × 1,2 + 2 = 4,4 s: the derivation has **no** floor, so a fast source waits less.
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 2, inputs: inputs, transportCeiling: 60),
            4.4, accuracy: 1e-9)
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 4, inputs: inputs, transportCeiling: 60),
            6.8, accuracy: 1e-9)
        // A source slower than the transport tolerates does not hold an operation open past the ceiling.
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 600, inputs: inputs, transportCeiling: 30), 30)
    }

    func testUnusableMeasurementsFallBackRatherThanPoisonTheDeadline() {
        for bad in [0.0, -1, Double.nan, Double.infinity] {
            XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: bad, inputs: inputs, transportCeiling: 60), 12,
                "\(bad) is not a measurement, so the bootstrap applies")
        }
        // A ceiling a misconfigured transport cannot provide leaves the derived value bounded by the bootstrap
        // rather than producing a deadline in the past.
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 2, inputs: inputs, transportCeiling: 0),
            4.4, accuracy: 1e-9)
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 600, inputs: inputs, transportCeiling: -1), 12)
    }
}

// Test-only: why a wiring run did not publish, from the run's own facts. The decisive one is whether the
// controlled transport was called at all — zero requests means the fetch was refused *before* the transport,
// which is exactly the host policy (K-01) and not a setup problem.
extension AppComposition {
    func diagnosticsForTheWiringTest(_ association: FeedAssociation) -> String {
        let requested = FixtureTransport.requests.withLock { $0.count }
        return "transport-requests=\(requested) sources=\(feeds.count) "
            + "failure=\(String(describing: startupFailure)) "
            + "presentation=\(association.store.state.presentation == nil ? "nil" : "present")"
    }
}


// NN-06 declaration proof. System scheduling, expiration and force quit require physical iOS.
final class BackgroundRefreshCapabilityTests: XCTestCase {
    func testNN06SinglePermittedRefreshPreservesAudioAndEnablesFetch() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String],
            [BackgroundFeedRefresh.identifier])
        XCTAssertEqual(Set(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []),
            Set(["audio", "fetch"]))
    }
}

/// O orçamento de quadro é do **display**, e não uma constante — e é um número só: o registro e os buckets leem a
/// mesma função (`FeedFrameMeter.budgetMilliseconds(target:)`), que é o alvo que o próprio `CADisplayLink` publica
/// por quadro.
///
/// Medido em 2026-10-16, nas duas pontas: o alvo do display é 16,67 ms tanto no simulador desta máquina
/// (`budget_ms=16.67` na série que a jornada publicou) quanto no iPhone 14 Plus do dono (`budget_ms=16.67` na
/// linha do console capturada com `devicectl device process launch --console`). É por isso que a constante
/// `1000/60` que o `flush` escrevia *parecia* certa: nos dois ambientes em uso os dois números coincidem, e a
/// divergência só aparece num painel de 120 Hz — onde o registro declararia 16,67 ms enquanto os buckets julgavam
/// 8,33 ms, ou seja, o mesmo quadro viraria "no orçamento" no traço e "dois orçamentos perdidos" na contagem. É o
/// defeito latente que estes casos fixam, já que nenhum painel de 120 Hz está nesta mesa para ser medido ao vivo.
@MainActor
final class FeedFrameBudgetTests: XCTestCase {
    func testTheBudgetIsTheDisplaysOwnTarget() {
        XCTAssertEqual(FeedFrameMeter.budgetMilliseconds(target: 1.0 / 60), 16.667, accuracy: 0.01)
        XCTAssertEqual(FeedFrameMeter.budgetMilliseconds(target: 1.0 / 120), 8.333, accuracy: 0.01)
        // O piso declarado no medidor: um alvo degenerado julga contra 1/120 em vez de contra zero.
        XCTAssertEqual(FeedFrameMeter.budgetMilliseconds(target: 0), 8.333, accuracy: 0.01)
    }

    func testTheSameIntervalIsJudgedByTheDisplayItArrivedOn() {
        let seventeenAt120 = FeedFrameMeter.bucket(intervalMilliseconds: 17,
            budgetMilliseconds: FeedFrameMeter.budgetMilliseconds(target: 1.0 / 120))
        XCTAssertTrue(seventeenAt120.bad, "17 ms são dois orçamentos num painel de 120 Hz")
        let seventeenAt60 = FeedFrameMeter.bucket(intervalMilliseconds: 17,
            budgetMilliseconds: FeedFrameMeter.budgetMilliseconds(target: 1.0 / 60))
        XCTAssertFalse(seventeenAt60.late || seventeenAt60.bad || seventeenAt60.severe,
            "e nada num painel de 60 Hz — as fronteiras são 1,5/2/3 orçamentos")
        // A fronteira é o `>` **estrito**, e medido no valor exato: 50 ms são exatamente três orçamentos de 16,67 ms,
        // e um quadro dessa duração perde **dois** quadros — por isso é `bad`, e 51 ms é `severe`. (A primeira
        // versão deste caso afirmava `severe` para 50 ms: errava o caso exato, não a fronteira.)
        let exactlyThreeAt60 = FeedFrameMeter.bucket(intervalMilliseconds: 50,
            budgetMilliseconds: FeedFrameMeter.budgetMilliseconds(target: 1.0 / 60))
        XCTAssertTrue(exactlyThreeAt60.bad && !exactlyThreeAt60.severe,
            "50 ms são exatamente três orçamentos e o `>` estrito os deixa em `bad`")
        let aboveThreeAt60 = FeedFrameMeter.bucket(intervalMilliseconds: 51,
            budgetMilliseconds: FeedFrameMeter.budgetMilliseconds(target: 1.0 / 60))
        XCTAssertTrue(aboveThreeAt60.severe, "51 ms passam de três orçamentos num painel de 60 Hz")
        let twentySixAt60 = FeedFrameMeter.bucket(intervalMilliseconds: 26,
            budgetMilliseconds: FeedFrameMeter.budgetMilliseconds(target: 1.0 / 60))
        XCTAssertTrue(twentySixAt60.late, "26 ms passam de um orçamento e meio")
    }

    func testTheRecordStatesTheBudgetThatJudgedTheWindow() {
        var window = FeedFrameMeter.Window()
        window.frames = 41
        window.severe = 2
        window.worstMilliseconds = 235.6
        let onSixty = FeedFrameMeter.recordFields(window, budgetMilliseconds: 
            FeedFrameMeter.budgetMilliseconds(target: 1.0 / 60))
        let onOneTwenty = FeedFrameMeter.recordFields(window, budgetMilliseconds:
            FeedFrameMeter.budgetMilliseconds(target: 1.0 / 120))
        // A constante que este arquivo escrevia antes declararia 16,67 ms nos dois casos: no painel de 120 Hz o
        // traço diria o dobro do orçamento que de fato julgou.
        XCTAssertEqual(onSixty["budget_ms"], "16.67")
        XCTAssertEqual(onOneTwenty["budget_ms"], "8.33")
        XCTAssertEqual(Double(onOneTwenty["budget_ms"] ?? "") ?? 0,
            FeedFrameMeter.budgetMilliseconds(target: 1.0 / 120), accuracy: 0.005)
        XCTAssertEqual(onOneTwenty["severe"], "2")
        XCTAssertEqual(onOneTwenty["worst_ms"], "235.6")
    }
}

/// NF-04 on the app/simulator surface (round 4). The package's OCR test renders the view through `NSHostingView`
/// on macOS; this one hosts the same public view in a real `UIHostingController` inside the app's own test host on
/// the simulator and reads the **pixels it draws there**. What it proves: the deferred surface, as the app target
/// renders it on iOS, states the wait, states that nothing is being searched, and offers the retry control.
///
/// What it does not prove, stated honestly: a unit-test host has no accessibility client, so SwiftUI does not
/// materialise its AX tree (`accessibilityElementCount() == 0` — measured) and the control cannot be activated
/// from here. The retry's **action** plumbing is shared with the connection-failure surface through the same
/// `recoveryActions → actions(tryAgain:)` path and the same host closure, and that path is proven end-to-end on
/// the device by `FeedVisibleExperienceUITests.testConnectionFailureSurfaceOffersARetryThatBringsContent`.
@MainActor
final class DeferredWorkSurfaceTests: XCTestCase {
    private func renderedText(_ view: UIView) throws -> [String] {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        view.frame = window.bounds
        host.view.addSubview(view)
        window.layoutIfNeeded()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["pt-BR", "en-US"]
        try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    func testDeferredSurfaceRendersTheWaitAndItsRetryOnTheAppHost() throws {
        // The host locale is the run's; the product's source language is pt-BR. Pinning the locale makes the
        // assertion deterministic and proves the sentence the catalogue holds for the source language.
        let hosting = UIHostingController(rootView: FeedLoadingView(work: .deferred, onTryAgain: {})
            .environment(\.locale, Locale(identifier: "pt_BR")))
        let text = try renderedText(hosting.view)
        XCTAssertTrue(text.contains { $0.contains("Aguardando nova oportunidade") },
            "the absence surface states the wait; text=\(text)")
        XCTAssertTrue(text.contains { $0.contains("Nada está sendo buscado agora") },
            "and states that nothing is being searched; text=\(text)")
        XCTAssertTrue(text.contains { $0.contains("Tentar novamente") },
            "the host's attempt is offered; text=\(text)")
        XCTAssertFalse(text.contains { $0.localizedCaseInsensitiveContains("procurando") },
            "a deferred attempt is never a search in flight; text=\(text)")
    }
}

/// H1 and the UX12-D copy, stated as values: the app's one binding derivation must give the durable and the visit
/// registration the same namespace and the same SourceID for one feed, and the source-surface note must appear
/// exactly where an absence belongs to a source.
@MainActor
final class S1SourceSurfaceTests: XCTestCase {
    private func feed(principal: String, namespace: String?) -> TrustedFeed {
        TrustedFeed(targetID: AcquisitionTargetID(), sourceID: SourceID(), bindingID: SourceBindingID(),
            principal: principal, endpoint: URL(string: "https://example.test/rss")!,
            displayName: "Fonte", principalNamespace: namespace)
    }

    /// A feed with no stated namespace is a catalogue feed (the only producer that leaves it nil), so the binding
    /// carries the catalogue namespace even when the principal's text is not a URL. Deriving it from the text is
    /// what H1 measured: a second namespace the promotion revalidation would not recognise.
    func testACatalogueFeedWithNoStatedNamespaceUsesTheCatalogueNamespace() throws {
        let feed = feed(principal: "chave-sem-esquema", namespace: nil)
        let binding = try XCTUnwrap(FeedAssociation.binding(for: feed))
        XCTAssertEqual(binding.externalPrincipal.namespace, LegacyCatalogImport.principalNamespace)
        XCTAssertEqual(binding.sourceID, feed.sourceID, "the binding states the feed's own SourceID")
        XCTAssertEqual(binding.id, feed.bindingID)
        XCTAssertEqual(binding.externalPrincipal.value, feed.principal)
    }

    /// A reader's own source states its namespace explicitly, and the one derivation preserves it verbatim.
    func testAReaderFeedKeepsItsReaderNamespace() throws {
        let feed = feed(principal: "https://reader.example/rss", namespace: ReaderSourceIdentity.principalNamespace)
        let binding = try XCTUnwrap(FeedAssociation.binding(for: feed))
        XCTAssertEqual(binding.externalPrincipal.namespace, ReaderSourceIdentity.principalNamespace)
        XCTAssertEqual(binding.sourceID, feed.sourceID)
    }

    func testTheSourceScopeNoteStatesTheFeedBoundaryOnlyForASourceAbsence() throws {
        // The runtime note is localized; its language follows the host. The **copy criterion** is the shipped value
        // in each language, so both are read from the app's own strings tables instead of depending on the runner's
        // preferred language.
        XCTAssertTrue(FeedLoadingView.sourceScopeNote(sourceContextName: "BBC News").contains("BBC News"),
            "the note names the source it is about")

        let key = "Você está vendo os itens que %@ publica no feed. O arquivo completo do site não faz parte dele."
        // The translation is a shipped artifact, read from the app's own table (the source language is the key).
        let en = try XCTUnwrap(localized(key, language: "en"), "an English value ships")
        XCTAssertTrue(en.contains("%@"), "the English value keeps the source slot: \(en)")
        XCTAssertTrue(en.localizedCaseInsensitiveContains("publishes in its feed"),
            "the English value states the feed as the origin: \(en)")
        XCTAssertTrue(en.localizedCaseInsensitiveContains("complete archive"),
            "and states the archive it is not: \(en)")

        // The runtime note must be one of the two **shipped** sentences with the name in the slot. A copy change
        // that never reached the catalogue, or a view that ignored the localized value, fails here; asserting the
        // literal alone would not.
        let note = FeedLoadingView.sourceScopeNote(sourceContextName: "BBC News")
        let english = en.replacingOccurrences(of: "%@", with: "BBC News")
        XCTAssertTrue(note == english || note.contains("arquivo completo do site"),
            "the drawn note is the shipped copy with the source named; observed: \(note)")

        for work in [FeedPresentationState.Work.unavailable, .unreachable, .deferred,
            .failed(message: "falha"), .endOfContent] {
            XCTAssertTrue(FeedLoadingView.showsSourceScopeNote(work: work, sourceContextName: "BBC News"),
                "an absence of a source draws the note: \(work)")
            XCTAssertFalse(FeedLoadingView.showsSourceScopeNote(work: work, sourceContextName: nil),
                "the main feed has no source boundary to state: \(work)")
        }
        for work in [FeedPresentationState.Work.idle, .pending] {
            XCTAssertFalse(FeedLoadingView.showsSourceScopeNote(work: work, sourceContextName: "BBC News"),
                "a surface that is still working states no bounded set: \(work)")
        }
    }

    /// One key from one shipped language, read from the app bundle's own table.
    private func localized(_ key: String, language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path) else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }
}
