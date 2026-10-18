import CryptoKit
import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineComposition

/// Owner directive 2026-10-17 §2: a save is a durable link whose content availability is stated, not assumed.
/// These tests exercise the two holes the audit found — saves that did no media work, and published cards with
/// no re-preparation path — plus the states the directive forbids lying about: pending, failure and a full disk.
final class SavedMediaCoordinatorTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!

    private struct Fixture {
        let root: URL
        let database: RuntimeDatabase
        var assets: URL { root.appendingPathComponent("Media", isDirectory: true) }
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return urls.count }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let fixture = Fixture(root: root, database: try RuntimeDatabase(location: .init(directory: root)))
        try FileManager.default.createDirectory(at: fixture.assets, withIntermediateDirectories: true)
        return fixture
    }

    private static func policy(network: MediaNetworkPath = .unconstrained) -> MediaPolicy? {
        guard let c = MediaDeviceConditions(heroSlotPointWidth: 2, thumbnailSlotPointWidth: 1, screenScale: 1,
            network: network, measuredBytesPerSecond: nil, waitBudgetSeconds: nil, freeStorageBytes: nil,
            lowPowerMode: false, thermal: .nominal),
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 1_000_000, maximumPixelSide: 10_000,
                maximumPixelCount: 10_000_000) else { return nil }
        return MediaPolicy(conditions: c, ceilings: ceilings)
    }

    /// A canonical revision with the media candidates its feed declared.
    private func admit(_ db: RuntimeDatabase, urls: [String]) throws -> (OriginRecordID, OriginRevisionID) {
        let origin = OriginRecordID(), revision = OriginRevisionID(), date = Date(timeIntervalSince1970: 100)
        let media = try urls.map { url in
            try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision, role: .cardVisual,
                mediaClass: .image, remoteURL: URL(string: url)!, declaredMimeType: nil,
                declaredPixelWidth: nil, declaredPixelHeight: nil))
        }
        try ContentStore(database: db).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "media",
                value: UUID().uuidString, role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "H", summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil, observedAt: date,
                language: nil, primaryLink: nil, searchProjection: nil, providerID: nil),
            mediaCandidates: media, availability: .available, observedAt: date, expectedCurrent: .none,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        return (origin, revision)
    }

    private static func mediaKey(_ bytes: Data) -> String {
        "sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private struct Published {
        let card: PublicationStore.CardRecord
        let editionID: FeedEditionID
        let segmentID: FeedSegmentID
    }

    /// Publishes exactly what the occurrence froze: the media key is the digest of the bytes the feed served, so
    /// a later preparation of those bytes lands on the same asset the card declares.
    private func publish(_ db: RuntimeDatabase, origin: OriginRecordID, revision: OriginRevisionID,
        mediaKey: String?, layout: String = "thumbnail",
        aspect: Double? = 2.0 / 3.0) throws -> Published {
        let card = PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: origin,
            originRevisionID: revision, sourceID: nil, providerID: nil, sourceDisplayName: "Fonte",
            providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil, title: "Título",
            primaryText: " texto ", timestampValue: nil, timestampKind: nil, mediaKey: mediaKey,
            mediaPixelWidth: mediaKey == nil ? nil : 2, mediaPixelHeight: mediaKey == nil ? nil : 3,
            mediaMimeType: nil, renderLayout: layout, renderMediaAspectRatio: aspect,
            primaryActionKind: "externalURL", primaryActionReference: "https://example.test/artigo")
        let store = PublicationStore(database: db)
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
        try store.createEdition(edition, firstSegment: segment, cards: [card])
        return Published(card: card, editionID: edition.id, segmentID: segment.id)
    }

    private func save(_ db: RuntimeDatabase, _ card: PublicationStore.CardRecord) throws {
        try PublicationStore(database: db).toggleBookmark(cardID: card.id,
            in: ReaderBookmarkList.defaultID, at: Date(timeIntervalSince1970: 1_000))
    }

    /// The same occurrence as a frozen `PublishedCard`, so the admission boundary itself can be asserted against
    /// the durable bytes: an image card is admitted only while `isRenderReady`.
    private func frozen(_ published: Published, origin: OriginRecordID, revision: OriginRevisionID,
        key: PublishedMediaKey) throws -> PublishedCard {
        try XCTUnwrap(PublishedCard(id: published.card.id,
            origin: PublishedOrigin(originRecordID: origin, originRevisionID: revision, sourceID: nil,
                providerID: nil, sourceDisplayName: "Fonte", providerDisplayName: nil),
            contentEntityID: nil, contentClusterID: nil,
            text: PublishedText(title: "Título", primaryText: " texto "), timestamp: nil,
            media: PublishedMediaSet(primary: PublishedMediaRef(key: key, pixelWidth: 2, pixelHeight: 3,
                mimeType: nil)),
            renderContract: try XCTUnwrap(RenderContract(layout: .thumbnail, mediaAspectRatio: 2.0 / 3.0)),
            primaryAction: .externalURL(URL(string: "https://example.test/artigo")!)))
    }

    private func prefetcher(_ db: RuntimeDatabase, assets: URL,
        preparation: MediaPreparation? = nil,
        fetch: @escaping MediaPrefetcher.Fetch) -> MediaPrefetcher {
        MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            preparation: preparation, fetch: fetch, conditions: { _ in Self.policy() })
    }

    // (a) Saving produces preparation work and records what the link can open.
    func testSaveTriggersPreparationAndRecordsReady() async throws {
        let f = try fixture(), calls = Calls(), png = self.png
        let (origin, revision) = try admit(f.database, urls: ["https://example.test/pic.png"])
        let published = try publish(f.database, origin: origin, revision: revision,
            mediaKey: Self.mediaKey(png))
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: try XCTUnwrap(published.card.mediaKey)))
        let media = prefetcher(f.database, assets: f.assets, fetch: { url, _ in calls.add(url); return png })
        let saved = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets, prefetcher: media)

        // No link, no work and no claim: availability belongs to a save.
        let unsaved = await saved.prepareSavedMedia(cardID: published.card.id)
        XCTAssertNil(unsaved)
        XCTAssertEqual(calls.count, 0)
        XCTAssertNil(try SavedMediaAvailabilityStore(database: f.database).availability(cardID: published.card.id))

        try save(f.database, published.card)
        let state = await saved.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(calls.count, 1, "the save starts the occurrence's media preparation")
        let record = try XCTUnwrap(SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id))
        XCTAssertEqual(record.availability, .ready)
        XCTAssertEqual(record.attempts, 1)
        XCTAssertTrue(record.availability.isAvailableOffline)
        XCTAssertNotNil(try ImageMaterializer(assetDirectory: f.assets).localBytes(for: key),
            "ready is a claim about durable bytes, not about this process")
        // The published occurrence's frozen projection decodes the unit.
        let decoder = try XCTUnwrap(PresentationImageDecoder(assetDirectory: f.assets,
            heroMaxPixel: 100, thumbnailMaxPixel: 50))
        XCTAssertNotNil(decoder.image(key: key, layout: .thumbnail))
    }

    // (b) An evicted blob is re-prepared for the published occurrence, which is not altered, and decodes again.
    func testEvictedBlobIsRepreparedAndTheCardDecodesAfterwards() async throws {
        let f = try fixture(), calls = Calls(), png = self.png
        let (origin, revision) = try admit(f.database, urls: ["https://example.test/pic.png"])
        let materialized = try ImageMaterializer(assetDirectory: f.assets).materialize(png)
        let published = try publish(f.database, origin: origin, revision: revision,
            mediaKey: materialized.key.rawValue)
        let key = materialized.key
        let publication = PublicationStore(database: f.database)
        let decoder = try XCTUnwrap(PresentationImageDecoder(assetDirectory: f.assets,
            heroMaxPixel: 100, thumbnailMaxPixel: 50))
        XCTAssertNotNil(decoder.image(key: key, layout: .thumbnail))
        let occurrence = try frozen(published, origin: origin, revision: revision, key: key)
        XCTAssertTrue(PresentationCard(publishedCard: occurrence, decoder: decoder).isRenderReady)
        // The cache pass takes the bytes — the state the audit found: a media key with no bytes.
        let digest = String(key.rawValue.dropFirst(7))
        try FileManager.default.removeItem(at: f.assets.appendingPathComponent("sha256/\(digest)"))
        XCTAssertNil(decoder.image(key: key, layout: .thumbnail))
        // INV-17: the card is excluded from admission while its bytes are missing. It keeps its image contract —
        // it is never converted into a text card under the same identity.
        let withoutBytes = PresentationCard(publishedCard: occurrence, decoder: decoder)
        XCTAssertFalse(withoutBytes.isRenderReady, "an image card without pixels is not admitted")
        XCTAssertEqual(withoutBytes.layout, .thumbnail, "exclusion is not conversion to text")

        try save(f.database, published.card)
        let media = prefetcher(f.database, assets: f.assets, fetch: { url, _ in calls.add(url); return png })
        let saved = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets, prefetcher: media)
        let state = await saved.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(calls.count, 1)
        XCTAssertNotNil(decoder.image(key: key, layout: .thumbnail), "the saved card decodes after re-preparation")
        XCTAssertTrue(PresentationCard(publishedCard: occurrence, decoder: decoder).isRenderReady,
            "the same occurrence is admitted again once its bytes are back")
        // Re-preparation changed availability only: same occurrence, same edition, same media identity.
        XCTAssertEqual(try publication.card(id: published.card.id), published.card)
        XCTAssertEqual(try publication.segments(editionID: published.editionID).map(\.id), [published.segmentID])
    }

    // (c) A failed preparation keeps the save and states the failure; the same save can succeed later.
    func testFailedPreparationKeepsTheSaveAndShowsAnHonestUnavailableState() async throws {
        let f = try fixture(), png = self.png
        let (origin, revision) = try admit(f.database, urls: ["https://example.test/pic.png"])
        let published = try publish(f.database, origin: origin, revision: revision,
            mediaKey: Self.mediaKey(png))
        try save(f.database, published.card)
        let failing = prefetcher(f.database, assets: f.assets, fetch: { _, _ in throw URLError(.timedOut) })
        let saved = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets, prefetcher: failing)
        let state = await saved.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(state, .failed)
        XCTAssertFalse(try XCTUnwrap(state).isAvailableOffline)
        XCTAssertTrue(try PublicationStore(database: f.database).bookmarkedCardIDs().contains(published.card.id),
            "a failed preparation never deletes the save")
        let record = try XCTUnwrap(SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id))
        XCTAssertEqual(record.availability, .failed)
        XCTAssertTrue(record.availability.isRecoverable)

        // Retry through a working pipeline: the failure was not final.
        let working = prefetcher(f.database, assets: f.assets, fetch: { _, _ in png })
        let retried = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets, prefetcher: working)
        let retriedState = await retried.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(retriedState, .ready)
        XCTAssertEqual(try SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id)?.attempts, 2)
        XCTAssertTrue(try PublicationStore(database: f.database).bookmarkedCardIDs().contains(published.card.id))
    }

    // (d) Text-only is a property of the published occurrence: no fetch, ever, no image promised.
    func testTextOnlyCardNeverGainsMedia() async throws {
        let f = try fixture(), calls = Calls(), png = self.png
        // The revision *has* a media candidate; the occurrence was published without media.
        let (origin, revision) = try admit(f.database, urls: ["https://example.test/pic.png"])
        let published = try publish(f.database, origin: origin, revision: revision, mediaKey: nil,
            layout: "textOnly", aspect: nil)
        try save(f.database, published.card)
        let media = prefetcher(f.database, assets: f.assets, fetch: { url, _ in calls.add(url); return png })
        let saved = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets, prefetcher: media)
        let first = await saved.prepareSavedMedia(cardID: published.card.id)
        let second = await saved.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(first, .textOnly)
        XCTAssertEqual(second, .textOnly)
        XCTAssertEqual(calls.count, 0, "a text-only publication is never given an image it did not publish")
        let record = try XCTUnwrap(SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id))
        XCTAssertEqual(record.availability, .textOnly)
        XCTAssertEqual(record.attempts, 0)
        XCTAssertTrue(record.availability.isAvailableOffline)
        XCTAssertFalse(record.availability.isRecoverable)
    }

    // (e) A full volume is its own persisted state: not ready, not text-only, save intact, retryable.
    func testFullDiskIsAVisibleStateAndTheSaveSurvives() async throws {
        let f = try fixture(), png = self.png
        let (origin, revision) = try admit(f.database, urls: ["https://example.test/pic.png"])
        let published = try publish(f.database, origin: origin, revision: revision,
            mediaKey: Self.mediaKey(png))
        try save(f.database, published.card)
        let full = MediaPreparation(materializeBytes: { _ in throw LocalMediaAssetError.insufficientSpace },
            inspectLocal: { _ in nil })
        let saved = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets,
            prefetcher: prefetcher(f.database, assets: f.assets, preparation: full,
                fetch: { _, _ in png }))
        let fullState = await saved.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(fullState, .insufficientSpace)
        let record = try XCTUnwrap(SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id))
        XCTAssertEqual(record.availability, .insufficientSpace)
        XCTAssertFalse(record.availability.isAvailableOffline)
        XCTAssertTrue(record.availability.isRecoverable)
        XCTAssertTrue(try PublicationStore(database: f.database).bookmarkedCardIDs().contains(published.card.id),
            "the save that could not hold its media is not deleted")

        // Space appears: the same save reaches readiness without a new publication.
        let working = prefetcher(f.database, assets: f.assets, fetch: { _, _ in png })
        let retried = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets, prefetcher: working)
        let recovered = await retried.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(recovered, .ready)
        XCTAssertEqual(try SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id)?.attempts, 2)
    }

    /// The resume pass re-verifies a `ready` claim instead of trusting it forever, and never resurrects a row
    /// whose link is gone.
    func testResumeRestoresLostBytesAndForgetsUnsavedCards() async throws {
        let f = try fixture(), png = self.png
        let (origin, revision) = try admit(f.database, urls: ["https://example.test/pic.png"])
        let materialized = try ImageMaterializer(assetDirectory: f.assets).materialize(png)
        let published = try publish(f.database, origin: origin, revision: revision,
            mediaKey: materialized.key.rawValue)
        try save(f.database, published.card)
        let media = prefetcher(f.database, assets: f.assets, fetch: { _, _ in png })
        let saved = SavedMediaCoordinator(database: f.database, assetDirectory: f.assets, prefetcher: media)
        let readyState = await saved.prepareSavedMedia(cardID: published.card.id)
        XCTAssertEqual(readyState, .ready)
        let digest = String(materialized.key.rawValue.dropFirst(7))
        try FileManager.default.removeItem(at: f.assets.appendingPathComponent("sha256/\(digest)"))
        await saved.resume(limit: 8)
        XCTAssertEqual(try SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id)?.availability, .ready)
        XCTAssertNotNil(try ImageMaterializer(assetDirectory: f.assets)
            .localBytes(for: materialized.key), "resume restored the bytes behind the ready claim")

        // The link is removed: the availability row goes with it, and a later resume cannot resurrect it.
        try PublicationStore(database: f.database).toggleBookmark(cardID: published.card.id,
            at: Date(timeIntervalSince1970: 2_000))
        await saved.forgetUnsaved()
        XCTAssertNil(try SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id))
        await saved.resume(limit: 8)
        XCTAssertNil(try SavedMediaAvailabilityStore(database: f.database)
            .availability(cardID: published.card.id))
    }
}
