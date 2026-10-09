import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineSyndication
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime

private final class ReadableTextNetworkTrap: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = 0
    static var count: Int { lock.withLock { requests } }
    static func reset() { lock.withLock { requests = 0 } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "readable.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.requests += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    override func stopLoading() {}
}

final class ReadablePublishedTextIntegrationTests: XCTestCase {
    func testH15ThroughH22RSSAtomJSONCanonicalHistoryDedupAndReopen() throws {
        XCTAssertTrue(URLProtocol.registerClass(ReadableTextNetworkTrap.self))
        defer { URLProtocol.unregisterClass(ReadableTextNetworkTrap.self) }
        ReadableTextNetworkTrap.reset()
        let html = "<p>Tom &amp; Jerry</p><div>Read <a href='https://readable.test/article'>more</a><br>Olá &#x1F600;</div><script src='https://readable.test/code'>bad()</script><img src='https://readable.test/a.png'>"
        let title = "<em>Headline &amp; news</em>"
        let plain = "2 < 3 & plain\nhttps://readable.test/article"
        let json = try JSONSerialization.data(withJSONObject: ["version": "https://jsonfeed.org/version/1.1",
            "title": "Feed", "items": [["id": "stable-guid", "title": "Plain title", "summary": plain, "content_text": "Body only", "content_html": "<p>Not summary</p>"]]])
        let cases: [(SyndicationDocumentKind, Data, String, String, String, String)] = [
            (.rss, Data("<rss version='2.0'><channel><title>Feed</title><item><guid isPermaLink='false'>stable-guid</guid><title><![CDATA[\(title)]]></title><description><![CDATA[\(html)]]></description></item></channel></rss>".utf8), title, html, "Headline & news", "Tom & Jerry\n\nRead more\nOlá 😀"),
            (.atom, Data("<feed xmlns='http://www.w3.org/2005/Atom'><title>Feed</title><entry><id>stable-guid</id><title type='html'><![CDATA[\(title)]]></title><summary type='html'><![CDATA[\(html)]]></summary><content type='text'>Not summary</content></entry></feed>".utf8), title, html, "Headline & news", "Tom & Jerry\n\nRead more\nOlá 😀"),
            (.json, json, "Plain title", plain, "Plain title", plain)
        ]
        for (kind, data, canonicalTitle, canonicalSummary, readableTitle, readableSummary) in cases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let location = RuntimeDatabaseLocation(directory: root), target = AcquisitionTargetID(), source = SourceID()
            let configuration = try XCTUnwrap(SyndicationTargetConfiguration(targetID: target, endpoint: URL(string: "https://readable.test/feed")!,
                memberships: [.init(sourceID: source, kind: .direct)]))
            let context = FeedContext(request: .source(source)), version = PolicyVersion(rawValue: 1)
            let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
                userSelectionVersion: version, eligibilityPolicyVersion: version, scoringPolicyVersion: version,
                sequencingPolicyVersion: version, exposurePolicyVersion: version, selectionSchemaVersion: .init(rawValue: 1))
            let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
            let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: version, eligibilityPolicyVersion: version,
                scoringPolicyVersion: version, sequencingPolicyVersion: version, exposurePolicyVersion: version,
                selectionSchemaVersion: revision.selectionSchemaVersion, eligibility: .structuralOnly, scoring: .equal,
                sequencing: .recencyDescending, exposure: .excludePublishedRevisions)
            let oldEdition = FeedEditionID(), newEdition = FeedEditionID(), oldCardID = PublicationCardID()
            let old: PublicationStore.CardRecord, fresh: PublicationStore.CardRecord, canonical: OriginRevision
            do {
                let db = try RuntimeDatabase(location: location)
                _ = try AcquisitionTargetAuthority(database: db).register(id: target, connectorKind: .syndication, authorizedSources: [source])
                let translated = try SyndicationTranslator().translate(data: data, configuration: configuration,
                    observedAt: Date(timeIntervalSince1970: 10), startIndex: 0, itemCapacity: 1)
                XCTAssertEqual(translated.documentKind, kind); XCTAssertTrue(translated.rejections.isEmpty)
                XCTAssertEqual(translated.observations.count, 1)
                let receipt = try AdmissionPolicy(database: db).admit(.init(targetID: target, targetGeneration: 1,
                    expectedCheckpointRevision: 0, observations: translated.observations, nextCheckpoint: nil)!)
                XCTAssertTrue(receipt.selectableSupplyChanged)
                XCTAssertEqual(try AcquisitionTargetAuthority(database: db).authorizedSources(id: target), [source])
                let window = try CandidateProvider(contentStore: .init(database: db)).candidates(for: plan, after: nil, examinedCapacity: 2)
                let candidate = try XCTUnwrap(window.candidates.first)
                canonical = try XCTUnwrap(ContentStore(database: db).originRevision(id: candidate.originRevisionID))
                XCTAssertEqual(canonical.headline?.utf8.map { $0 }, Array(canonicalTitle.utf8))
                XCTAssertEqual(canonical.summary?.utf8.map { $0 }, Array(canonicalSummary.utf8))
                XCTAssertEqual(try ContentStore(database: db).memberships(originRecordID: candidate.originRecordID).map(\.sourceID), [source])
                let selected = try SelectionEngine().select(plan: plan, policy: policy, window: window,
                    exposure: .init(requestedOriginIDs: window.candidates.map(\.originRecordID), publishedOriginIDs: [])!)
                let origin = PublishedOrigin(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                    sourceID: source, providerID: nil, sourceDisplayName: "Fixture", providerDisplayName: nil)
                let input = PublicationPreparationInput(origin: origin, contentEntityID: nil, contentClusterID: nil,
                    primaryAction: .localContentDetail, presentation: .textOnly)
                // Model already-frozen pre-3R8 history by creating its exact raw draft, not by mutating a card.
                let raw = try XCTUnwrap(PublicationCardDraft(origin: origin, contentEntityID: nil, contentClusterID: nil,
                    text: .init(title: canonicalTitle, primaryText: canonicalSummary),
                    timestamp: .init(value: candidate.timestamp.value, kind: candidate.timestamp.kind == .observed ? .observed : .authored), media: .none,
                    renderContract: .init(layout: .textOnly, mediaAspectRatio: nil)!, primaryAction: .localContentDetail))
                _ = try PublicationCoordinator(database: db).createEdition(.init(selection: SelectionResult(editorialRevision: selected.editorialRevision, orderedCandidates: [Candidate(
                        originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
                        headline: canonicalTitle, summary: canonicalSummary, timestamp: candidate.timestamp,
                        language: candidate.language, providerID: candidate.providerID)], supplyReport: selected.supplyReport),
                    drafts: [raw], editionID: oldEdition,
                    publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 20),
                    segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(timeIntervalSince1970: 21), cardIDs: [oldCardID]))
                old = try XCTUnwrap(PublicationStore(database: db).card(id: oldCardID))
                let drafts = try PublicationPreparation.drafts(selection: selected, inputs: [input])
                XCTAssertEqual(drafts[0].text.title, readableTitle); XCTAssertEqual(drafts[0].text.primaryText, readableSummary)
                XCTAssertThrowsError(try PublicationCoordinator(database: db).append(.init(selection: selected, drafts: drafts,
                    editionID: oldEdition, segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(timeIntervalSince1970: 22), cardIDs: [PublicationCardID()]))) {
                    XCTAssertEqual($0 as? PublicationStoreError, .duplicateOriginInEdition)
                }
                let excluded = try LocalProductionSlice(database: db).run(.init(plan: plan, policy: policy, editionID: oldEdition,
                    after: nil, examinedCapacity: 2, segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(timeIntervalSince1970: 23))) { _ in
                        XCTFail("Existing origin must not reach preparation"); return .init(inputs: [], cardIDs: [])
                    }
                guard case .advancedWithoutPublication = excluded else { return XCTFail("Expected dedup") }
                let result = try InitialProductionSlice(database: db).run(.init(plan: plan, policy: policy, examinedCapacity: 2,
                    editionID: newEdition, publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1,
                    editionCreatedAt: Date(timeIntervalSince1970: 30), segmentID: FeedSegmentID(), segmentSeed: 1,
                    segmentCreatedAt: Date(timeIntervalSince1970: 31), anchorPlacement: .top, checkpointedAt: Date(timeIntervalSince1970: 32))) { selection in
                        XCTAssertEqual(selection.orderedCandidates.map(\.originRevisionID), [canonical.id])
                        return .init(inputs: [input], cardIDs: [PublicationCardID()])
                    }
                guard case .published(_, let published) = result else { return XCTFail("Expected clean publication") }
                fresh = try XCTUnwrap(PublicationStore(database: db).card(id: published.cardIDs[0]))
                XCTAssertEqual(fresh.title, readableTitle); XCTAssertEqual(fresh.primaryText, readableSummary)
                XCTAssertEqual(fresh.originRecordID, old.originRecordID); XCTAssertEqual(fresh.originRevisionID, old.originRevisionID)
                XCTAssertEqual(try PublicationStore(database: db).card(id: oldCardID), old)
                XCTAssertEqual(try ContentStore(database: db).originRevision(id: canonical.id), canonical)
            }
            let reopened = try RuntimeDatabase(location: location), store = PublicationStore(database: reopened)
            XCTAssertEqual(try store.card(id: oldCardID), old); XCTAssertEqual(try store.card(id: fresh.id), fresh)
            XCTAssertEqual(try store.card(id: oldCardID)?.title?.utf8.map { $0 }, Array(canonicalTitle.utf8))
            XCTAssertEqual(try store.card(id: oldCardID)?.primaryText?.utf8.map { $0 }, Array(canonicalSummary.utf8))
            XCTAssertEqual(try store.card(id: fresh.id)?.title?.utf8.map { $0 }, Array(readableTitle.utf8))
            XCTAssertEqual(try store.card(id: fresh.id)?.primaryText?.utf8.map { $0 }, Array(readableSummary.utf8))
            let reopenedCanonical = try ContentStore(database: reopened).originRevision(id: canonical.id)
            XCTAssertEqual(reopenedCanonical, canonical)
            XCTAssertEqual(reopenedCanonical?.headline?.utf8.map { $0 }, Array(canonicalTitle.utf8))
            XCTAssertEqual(reopenedCanonical?.summary?.utf8.map { $0 }, Array(canonicalSummary.utf8))
            XCTAssertEqual(try store.segments(editionID: oldEdition).flatMap(\.cardIDs), [oldCardID])
            XCTAssertEqual(try store.segments(editionID: newEdition).flatMap(\.cardIDs), [fresh.id])
            let restored = try PublicationHistory(database: reopened).restore(backwardCapacity: 1, forwardCapacity: 1)
            XCTAssertEqual(restored?.edition.id, newEdition)
            XCTAssertEqual(restored?.window.cards.first?.text, .init(title: readableTitle, primaryText: readableSummary))
        }
        XCTAssertEqual(ReadableTextNetworkTrap.count, 0)
    }
}
