import XCTest
import Foundation
import UIKit
import SwiftUI
import Synchronization
import CryptoKit
import FeedMinePersistence
import FeedMineDomain
import FeedMineRuntime
import FeedMineUI
import FeedMineComposition
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMine

// Controlled transport exists only in this test target; all admission and publication are real.
final class FixtureTransport: URLProtocol, @unchecked Sendable {
    static let rejecting = Mutex(false)
    static let holdingScience = Mutex(false)
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
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.rejecting.withLock({ $0 }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if Self.holdingScience.withLock({ $0 }), request.url?.path.contains("science") == true {
            Self.held.append(self)
            return
        }
        respond()
    }
    private func respond() {
        FixtureTransport.requests.withLock { $0.append(request.url?.absoluteString ?? "") }
        // The shape is the default (`shortSummary`) unless a test set another one, and the default payload is the
        // exact document this transport always served.
        let payload = ReadingFixture.payload()
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

@MainActor
final class CompositionTests: XCTestCase {

    private func root(requestTimeout: TimeInterval = 60, directory: URL? = nil,
        feeds: [TrustedFeed] = TrustedFeed.development) -> AppComposition {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = requestTimeout
        return AppComposition(directory: directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            feeds: feeds, transportConfiguration: configuration)
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
        _ = try await association.driver.drive(resources: FeedAssociation.resources)
        guard let anchor = association.store.state.presentation?.window.items.last else { return }
        await association.viewport(.init(anchor: .init(cardID: anchor.id, placement: .top)), activity: .explicitTailApproach)
    }

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

    func testSourceSelectionSurvivesRelaunchAndFiltersCanonicalSupply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root(directory: directory)
        await first.launch()
        try await first.searchSources("")
        try await first.toggleSource(TrustedFeed.development[0].sourceID)
        XCTAssertEqual(first.feeds.map(\.sourceID), [TrustedFeed.development[1].sourceID])
        XCTAssertEqual(first.currentContext, .source(TrustedFeed.development[1].sourceID))
        XCTAssertTrue(try XCTUnwrap(first.association?.store.state.presentation).window.items.allSatisfy { $0.sourceDisplayName == "BBC Science" })
        await first.association?.background()
        await first.association?.close()
        let reopened = root(directory: directory)
        XCTAssertEqual(reopened.feeds.map(\.sourceID), first.feeds.map(\.sourceID))
        await reopened.launch()
        XCTAssertEqual(reopened.currentContext, first.currentContext)
        XCTAssertEqual(reopened.association?.store.state.presentation?.editionID, first.association?.store.state.presentation?.editionID)
        try await reopened.searchSources("")
        do { try await reopened.toggleSource(TrustedFeed.development[1].sourceID); XCTFail("Empty selection") }
        catch { XCTAssertEqual(reopened.feeds.count, 1) }
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

    /// T6: the compatibility predicate is the whole decision — identity first, then the policy versions that
    /// make a restored Edition reusable. A foreign identity is refused even when everything else matches.
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
        XCTAssertTrue(FeedAssociation.mayShow(revision(key), for: key, selectionVersion: 7))
        XCTAssertFalse(FeedAssociation.mayShow(revision(foreign), for: key, selectionVersion: 7),
            "an edition from another filter is never shown")
        XCTAssertFalse(FeedAssociation.mayShow(revision(ContextKey(request: .main)), for: key, selectionVersion: 7),
            "the plain identity is not the filtered one either")
        XCTAssertFalse(FeedAssociation.mayShow(revision(key, selection: 6), for: key, selectionVersion: 7),
            "an older selection version is refused")
        XCTAssertFalse(FeedAssociation.mayShow(revision(key, eligibility: 1), for: key, selectionVersion: 7),
            "an older eligibility policy is refused")
        // Equivalent selections are the same identity, so they are compatible.
        let equivalent = ContextKey(request: .main, filter: ReaderFilter(languages: ["pt"], mood: .all))
        XCTAssertTrue(FeedAssociation.mayShow(revision(equivalent), for: key, selectionVersion: 7))
    }

    /// R2 review: the mapping is exact, never a threshold. A version this build does not know must not be
    /// silently treated as v3, and v2 must keep the behavior its Editions were published under.
    func testSequencingVersionMappingIsExplicit() throws {
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 1)), .recencyDescending)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 2)), .recencyAlternatingSources)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 3)), .recencyAlternatingSourcesBySupplyShare)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 4)), .recencyAlternatingSourcesByWeightedSupplyShare)
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 5)), .recencyDescending,
            "an unknown future version is not v4")
        XCTAssertEqual(FeedAssociation.sequencingBehavior(for: PolicyVersion(rawValue: 99)), .recencyDescending)
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

    /// R2: a fresh session declares the proportional sequencing behavior, and a v2 revision stays usable
    /// for the Editions already published under it.
    func testFreshSessionDeclaresSupplyShareSequencingAndStillAcceptsV2Editions() async throws {
        let root = root()
        await root.launch()
        let association = try XCTUnwrap(root.association)
        XCTAssertEqual(association.policy.sequencingPolicyVersion, PolicyVersion(rawValue: 3))
        XCTAssertEqual(association.policy.sequencing, .recencyAlternatingSourcesBySupplyShare)
        let v2 = EditorialRevision(id: EditorialRevisionID(), contextKey: ContextKey(request: .main),
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 2),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 1),
            sequencingPolicyVersion: PolicyVersion(rawValue: 2), exposurePolicyVersion: PolicyVersion(rawValue: 2),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))
        XCTAssertTrue(FeedAssociation.mayShow(v2, for: ContextKey(request: .main), selectionVersion: 2),
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

    /// U1-P1: the token palette is adaptive by construction. The iOS 26.5 simulator does not
    /// apply `simctl ui appearance` to any app (the system Settings app also stayed light while
    /// the device reported dark), so appearance adaptation is proven by resolving the tokens
    /// under both trait collections instead of by a screenshot.
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
        let saved = association.savedArticles()
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
        XCTAssertTrue(association.savedArticles().isEmpty)
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
        for index in 0..<10 { trace.record("event", ["index": String(index)]) }
        trace.flushAndWait()
        let url = directory.appendingPathComponent("trace.jsonl")
        let records = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(records.filter { $0["event"] as? String == "event" }.count, 3,
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
        XCTAssertEqual(composition.currentContextKey.request, .source(a.sourceID))
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

}

/// §5.3/PD-6: the media window is a **per-operation** limit derived from facts the run measures, never a fraction
/// of the transport's timeout. The derivation is the precedent, so it is pinned here: unmeasured states the run's
/// bootstrap, measured follows the runway's own tolerance for one request, and the transport timeout stays what it
/// is — an operational ceiling, which is the one thing PD-6 rule 4 allows it to be.
final class MediaWaitDerivationTests: XCTestCase {
    private let inputs = RunwayPolicyInputs(safetyFactor: 1.2, releaseMarginSeconds: 2)!

    func testUnmeasuredStatesTheBootstrapAndIsStillBoundedByTheTransportCeiling() {
        // The 5 s is the run's declared tolerance, not `timeoutIntervalForRequest / 4` (≈15 s with the 60 s default).
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: nil, inputs: inputs, transportCeiling: 60), 5)
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: nil, inputs: inputs, transportCeiling: 3), 3)
    }

    func testMeasuredFollowsTheRunsOwnToleranceSoAFasterSourceWaitsLess() {
        // p95 = 2 s → 2 × 1,2 + 2 = 4,4 s. A slower replenishment earns a longer window; a fast one does not pay for it.
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 2, inputs: inputs, transportCeiling: 60),
            4.4, accuracy: 1e-9)
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 4, inputs: inputs, transportCeiling: 60),
            6.8, accuracy: 1e-9)
        // A source slower than the transport tolerates does not hold an operation open past the ceiling.
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 600, inputs: inputs, transportCeiling: 30), 30)
    }

    func testUnusableMeasurementsFallBackRatherThanPoisonTheDeadline() {
        for bad in [0.0, -1, Double.nan, Double.infinity] {
            XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: bad, inputs: inputs, transportCeiling: 60), 5,
                "\(bad) is not a measurement, so the bootstrap applies")
        }
        // A ceiling a misconfigured transport cannot provide leaves the derived value bounded by the bootstrap
        // rather than producing a deadline in the past.
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 2, inputs: inputs, transportCeiling: 0),
            4.4, accuracy: 1e-9)
        XCTAssertEqual(FeedAssociation.mediaWaitSeconds(p95Replenishment: 600, inputs: inputs, transportCeiling: -1), 5)
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
