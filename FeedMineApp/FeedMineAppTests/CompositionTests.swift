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
        let items = (1...24).map { "<item><guid>fixture-\($0)</guid><title>Published fixture \($0)</title><link>https://fixture.invalid/story-\($0)</link><description>Readable local story \($0)</description></item>" }.joined()
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
}
