import XCTest
import Foundation
import Synchronization
import CryptoKit
import FeedMinePersistence
import FeedMineDomain
import FeedMineRuntime
import FeedMineUI
import FeedMineComposition
@testable import FeedMine

// Controlled transport exists only in this test target; all admission and publication are real.
final class FixtureTransport: URLProtocol, @unchecked Sendable {
    static let rejecting = Mutex(false)
    static let holdingScience = Mutex(false)
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
        let items = (1...24).map { "<item><guid>fixture-\($0)</guid><title>Published fixture \($0)</title><description>Readable local story \($0)</description></item>" }.joined()
        let data = Data("<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Trusted fixture</title><link>https://fixture.invalid/</link><description>Integration</description>\(items)</channel></rss>".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/rss+xml"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class CompositionTests: XCTestCase {
    private func root(requestTimeout: TimeInterval = 60, directory: URL? = nil) -> AppComposition {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = requestTimeout
        return AppComposition(directory: directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            feeds: TrustedFeed.development, transportConfiguration: configuration)
    }

    private func launched() async throws -> (AppComposition, FeedAssociation) {
        let root = root()
        await root.launch()
        XCTAssertNil(root.startupFailure)
        let association = try XCTUnwrap(root.association)
        XCTAssertNotNil(association.store.state.presentation, "Real cold acquisition must publish")
        return (root, association)
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
        let cards = try XCTUnwrap(association.store.state.presentation).window.items
        XCTAssertEqual(cards.count, 17, "Anchor plus a sixteen-card idle reserve")
        for (left, right) in zip(cards, cards.dropFirst()) {
            XCTAssertNotEqual(left.sourceDisplayName, right.sourceDisplayName)
        }
        await association.close()
    }

    func testBundledCatalogHasRealBytesAndStableBoundedDefaults() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
        let reader = try LegacyCatalogReader(catalogURL: url)
        XCTAssertEqual(try reader.sourceCount(), 77_443)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        XCTAssertEqual(hash.finalize().map { String(format: "%02x", $0) }.joined(),
            "c2ae483a7525fd2b6797855149eb6fb312abbed788549a90a7754121eb5c8629")
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

    /// OMP C1: a saved key the catalog no longer has must not brick startup.
    func testSavedKeysMissingFromCatalogAreRepairedNotFatal() throws {
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
        XCTAssertEqual(composition.feeds.map(\.principal), starter.map(\.principal))
        XCTAssertEqual(composition.currentContext, .main)
        let repaired = try XCTUnwrap(ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory))).load())
        XCTAssertEqual(repaired.sourceKeys, starter.map(\.principal))
        XCTAssertEqual(repaired.activeContext, .main)

        // Valid keys survive; only the vanished one is dropped.
        let partial = try TrustedFeed.resolveAvailable(keys: ["https://absent.example/rss", starter[1].principal], fallback: starter)
        XCTAssertEqual(partial.map(\.principal), [starter[1].principal])
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

    func testS1SameSessionStoreAcrossViewportRefreshAndLifecycle() async throws {
        let (root, association) = try await launched()
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
        XCTAssertEqual(restored.editionID, snapshot.editionID)
        XCTAssertNotEqual(restored.provenance.sequenceID, snapshot.provenance.sequenceID)
        XCTAssertEqual(restored.window, snapshot.window)
        await next.close()
    }

    func testS6NewerReverseProjectionAccepted() async throws {
        let (_, association) = try await launched()
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
}
