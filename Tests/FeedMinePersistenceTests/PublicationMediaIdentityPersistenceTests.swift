import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication

/// D2 (PD-2026-10-20): the media kind is frozen with the occurrence, survives a reload, and a row published
/// before the column existed reads as unknown instead of being guessed from its action kind.
final class PublicationMediaIdentityPersistenceTests: XCTestCase {
    private let link = URL(string: "https://example.test/article")!

    private func videoCard() -> PublicationStore.CardRecord {
        .init(id: PublicationCardID(), originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
            sourceID: SourceID(), providerID: nil, sourceDisplayName: "Video News", providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil, title: "A clip", primaryText: nil,
            timestampValue: nil, timestampKind: nil,
            mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil, mediaMimeType: nil,
            renderLayout: "textOnly", renderMediaAspectRatio: nil,
            primaryActionKind: "externalURL", primaryActionReference: link.absoluteString,
            mediaIdentity: "video")
    }

    /// Write, reopen, read: the identity is the same fact, and the frozen card still opens the item's link.
    func testMediaIdentitySurvivesReloadAndStaysOutOfThePlayer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let edition = StorageFixture.edition()
        let card = videoCard()
        try PublicationStore(database: database).createEdition(edition,
            firstSegment: StorageFixture.segment(edition, [card]), cards: [card])

        let reopened = PublicationStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        let record = try XCTUnwrap(reopened.card(id: card.id))
        XCTAssertEqual(record.mediaIdentity, "video")
        let frozen = try PublicationPersistenceMapping.card(record)
        XCTAssertEqual(frozen.mediaIdentity, .video)
        XCTAssertEqual(frozen.primaryAction, .externalURL(link))
        XCTAssertNotEqual(frozen.primaryAction, .mediaPlayback(link))
    }

    /// The store's own check: a video (or empty) identity may never carry the in-app player, and the vocabulary is
    /// closed. Unknown (nil) remains valid history.
    func testValidationRefusesAPlayerForVideoAndAnUnknownWord() throws {
        let database = try StorageFixture.database(self), store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        var card = videoCard()
        card = .init(id: card.id, originRecordID: card.originRecordID, originRevisionID: card.originRevisionID,
            sourceID: card.sourceID, providerID: card.providerID, sourceDisplayName: card.sourceDisplayName,
            providerDisplayName: card.providerDisplayName, contentEntityID: card.contentEntityID,
            contentClusterID: card.contentClusterID, title: card.title, primaryText: card.primaryText,
            timestampValue: card.timestampValue, timestampKind: card.timestampKind,
            mediaKey: card.mediaKey, mediaPixelWidth: card.mediaPixelWidth, mediaPixelHeight: card.mediaPixelHeight,
            mediaMimeType: card.mediaMimeType, renderLayout: card.renderLayout,
            renderMediaAspectRatio: card.renderMediaAspectRatio,
            primaryActionKind: "mediaPlayback", primaryActionReference: link.absoluteString,
            mediaIdentity: "video")
        XCTAssertThrowsError(try store.createEdition(edition,
            firstSegment: StorageFixture.segment(edition, [card]), cards: [card])) {
            XCTAssertEqual($0 as? PublicationStoreError, .invalidRepresentation("media identity action"))
        }
        var misspelled = videoCard()
        misspelled = .init(id: misspelled.id, originRecordID: misspelled.originRecordID,
            originRevisionID: misspelled.originRevisionID, sourceID: misspelled.sourceID,
            providerID: misspelled.providerID, sourceDisplayName: misspelled.sourceDisplayName,
            providerDisplayName: misspelled.providerDisplayName, contentEntityID: misspelled.contentEntityID,
            contentClusterID: misspelled.contentClusterID, title: misspelled.title, primaryText: misspelled.primaryText,
            timestampValue: misspelled.timestampValue, timestampKind: misspelled.timestampKind,
            mediaKey: misspelled.mediaKey, mediaPixelWidth: misspelled.mediaPixelWidth,
            mediaPixelHeight: misspelled.mediaPixelHeight, mediaMimeType: misspelled.mediaMimeType,
            renderLayout: misspelled.renderLayout, renderMediaAspectRatio: misspelled.renderMediaAspectRatio,
            primaryActionKind: misspelled.primaryActionKind, primaryActionReference: misspelled.primaryActionReference,
            mediaIdentity: "vídeo")
        XCTAssertThrowsError(try store.createEdition(edition,
            firstSegment: StorageFixture.segment(edition, [misspelled]), cards: [misspelled])) {
            XCTAssertEqual($0 as? PublicationStoreError, .invalidRepresentation("media identity"))
        }
    }

    /// A card published by a build that had no such column: after the additive migration the column is NULL, the
    /// record reads as unknown, and the frozen card is never `nil`-to-audio — its action kind is not consulted.
    func testACardPublishedBeforeTheColumnReadsAsUnknown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let location = RuntimeDatabaseLocation(directory: root)
        let edition = UUID().uuidString.lowercased(), segment = UUID().uuidString.lowercased()
        let card = UUID().uuidString.lowercased(), origin = UUID().uuidString.lowercased()
        let revision = UUID().uuidString.lowercased()
        do {
            let queue = try DatabaseQueue(path: location.databaseURL.path)
            try RuntimeMigrations.current.migrate(queue, upTo: "reader-legacy-upgrade-receipt-v1")
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO feed_editions (id, editorial_revision_id, context_kind, catalog_generation,
                        user_selection_version, eligibility_policy_version, scoring_policy_version,
                        sequencing_policy_version, exposure_policy_version, selection_schema_version,
                        publication_schema_version, selection_seed, created_at)
                    VALUES (?, ?, 'main', 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)
                    """, arguments: [edition, UUID().uuidString.lowercased()])
                try db.execute(sql: "INSERT INTO feed_segments VALUES (?, ?, 0, 1, 1, 1)", arguments: [segment, edition])
                try db.execute(sql: """
                    INSERT INTO published_cards (id, segment_id, ordinal, origin_record_id, origin_revision_id,
                        render_layout, primary_action_kind, primary_action_reference)
                    VALUES (?, ?, 0, ?, ?, 'textOnly', 'externalURL', 'https://example.test/old')
                    """, arguments: [card, segment, origin, revision])
            }
        }
        let database = try RuntimeDatabase(location: location)
        try database.read { db in
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('published_cards') ORDER BY cid").suffix(2),
                ["diversity_facts", "media_identity"])
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT media_identity FROM published_cards WHERE id = ?",
                arguments: [card]))
        }
        let cardID = PublicationCardID(rawValue: try XCTUnwrap(UUID(uuidString: card)))
        let record = try XCTUnwrap(PublicationStore(database: database).card(id: cardID))
        XCTAssertNil(record.mediaIdentity, "absence is unknown, not audio")
        let frozen = try PublicationPersistenceMapping.card(record)
        XCTAssertNil(frozen.mediaIdentity)
        XCTAssertEqual(frozen.primaryAction, .externalURL(try XCTUnwrap(URL(string: "https://example.test/old"))))
    }
}
