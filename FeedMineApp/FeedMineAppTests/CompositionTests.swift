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
        let partial = try TrustedFeed.resolveAvailable(keys: ["https://absent.example/rss", starter[1].principal],
            fallback: starter, catalogueURL: Bundle.main.url(forResource: "catalog", withExtension: "sqlite"))
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

    /// Kiro K-01/K-05 **wiring** — o arquiteto foi explícito: "ter K-01/K-05 no merge não prova essa ligação". E
    /// não provava: nenhum ponto do app passava origens autorizadas, então o padrão `publicOnly` do K-01 recusaria
    /// o servidor de benchmark na LAN e a corrida não publicaria nada. Este teste teria pegado isso: configura um
    /// feed num host **não público** — exatamente a forma de um servidor de benchmark — e exige um card dele. O
    /// transporte controlado responde a qualquer URL, então o que decide aqui é a política de host, não a rede.
    func testK05TheRootAuthorizesTheNonPublicEndpointThisRunFetches() async throws {
        try await assertTheEndpointPublishes("http://10.77.0.1:8757/feed.xml",
            "o root tem de autorizar exatamente os endpoints não públicos que esta execução foi configurada para buscar")
    }

    /// O controle do teste acima: o **mesmo** cenário num host público. Ele separa "a política de host recusou" de
    /// "o arranjo do teste não chega a publicar" — sem ele, um vermelho não diz qual dos dois aconteceu. Com o
    /// par, o significado é inequívoco: o controle verde diz que o caminho funciona, e o não público verde diz que
    /// a autorização do root está ligada.
    func testK05TheSameScenarioOnAPublicHostAlsoPublishes() async throws {
        try await assertTheEndpointPublishes("https://bench.example/feed.xml",
            "controle: num host público o caminho tem de publicar")
    }

    private func assertTheEndpointPublishes(_ raw: String, _ message: String) async throws {
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
        let published = await Self.waitUntil(20) { association.store.state.presentation != nil }
        if !published {
            // Why it did not publish, instead of guessing: the run's own facts.
            let facts = root.diagnosticsForTheWiringTest(association)
            XCTFail("\(message) — \(facts)")
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
        // A posição durável antes de sair — é o que o teste de filtro faz, e é o que separa "voltar não restaura"
        // de "não havia o que restaurar". Sem esta linha, o ida-e-volta não tem checkpoint de A para recuperar.
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
        XCTAssertTrue(html.contains("<title>Caixa de salvos</title>"))

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
