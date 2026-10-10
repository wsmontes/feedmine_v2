import Foundation
import XCTest
import GRDB
import FeedMineDomain
import FeedMinePublication
@testable import FeedMinePersistence

/// T6, step 3: an Edition and its checkpoint are filed under the whole context identity, so two filtered
/// contexts of the same surface keep their own positions, and a context written before T6 keeps its own.
/// Design: `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md` §6.
final class ContextIdentityPersistenceTests: XCTestCase {
    private func filteredKey(_ languages: Set<String> = ["pt"], preset: ReaderPresetID = .collection("c1")) -> ContextKey {
        ContextKey(request: .main, preset: preset, filter: ReaderFilter(languages: languages, mood: .fun))
    }

    private func revision(_ key: ContextKey) -> EditorialRevision {
        EditorialRevision(id: EditorialRevisionID(), contextKey: key, catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: PolicyVersion(rawValue: 1), eligibilityPolicyVersion: PolicyVersion(rawValue: 2),
            scoringPolicyVersion: PolicyVersion(rawValue: 3), sequencingPolicyVersion: PolicyVersion(rawValue: 4),
            exposurePolicyVersion: PolicyVersion(rawValue: 5), selectionSchemaVersion: SelectionSchemaVersion(rawValue: 6))
    }

    /// Creates an Edition with its first segment and returns its cards.
    @discardableResult
    private func publish(_ database: RuntimeDatabase, key: ContextKey) throws -> (PublicationStore.EditionRecord,
        [PublicationStore.CardRecord]) {
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition(revision: revision(key))
        let cards = (0..<2).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
        return (edition, cards)
    }

    /// The Edition round-trips its whole identity, in both persisted forms.
    func testEditionPersistsAndRestoresTheWholeContextIdentity() throws {
        let database = try StorageFixture.database(self)
        let key = filteredKey()
        let (edition, _) = try publish(database, key: key)
        let restored = try XCTUnwrap(PublicationStore(database: database).edition(id: edition.id))
        XCTAssertEqual(restored.editorialRevision.contextKey, key,
            "a filtered key must survive the write and read, not degrade to its surface")
        XCTAssertFalse(restored.editorialRevision.contextKey.isDefaultSurface)
        let raw = try database.read { db in
            (try String.fetchOne(db, sql: "SELECT context_identity FROM feed_editions WHERE id = ?",
                arguments: [edition.id.rawValue.uuidString.lowercased()]) ?? "",
             try String.fetchOne(db, sql: "SELECT context_key_json FROM feed_editions WHERE id = ?",
                arguments: [edition.id.rawValue.uuidString.lowercased()]) ?? "")
        }
        XCTAssertEqual(raw.0, key.canonicalIdentity)
        XCTAssertEqual(ContextKey.fromCanonicalJSON(raw.1), key)
    }

    /// Two filters on the same surface get their own checkpoints; neither collides with the default surface.
    func testCheckpointsAreKeyedByIdentityNotBySurface() throws {
        let database = try StorageFixture.database(self)
        let first = filteredKey(["pt"])
        let second = filteredKey(["en"], preset: .everything)
        let (firstEdition, firstCards) = try publish(database, key: first)
        let (secondEdition, secondCards) = try publish(database, key: second)
        let history = PublicationHistory(database: database)
        try history.saveCursor(.init(editionID: firstEdition.id,
            anchor: .init(cardID: firstCards[0].id, placement: .top)), updatedAt: Date(timeIntervalSince1970: 10))
        try history.saveCursor(.init(editionID: secondEdition.id,
            anchor: .init(cardID: secondCards[0].id, placement: .center)), updatedAt: Date(timeIntervalSince1970: 20))

        let session = SessionStore(database: database)
        XCTAssertEqual(try session.checkpoint(for: first)?.editionID, firstEdition.id)
        XCTAssertEqual(try session.checkpoint(for: second)?.editionID, secondEdition.id)
        XCTAssertNil(try session.checkpoint(for: ContextKey(request: .main)),
            "the plain surface is a different identity from either filtered one")
        // Both are retained and can be activated by identity, in either order.
        try session.activateContext(second)
        XCTAssertEqual(try session.checkpoint()?.editionID, secondEdition.id)
        try session.activateContext(first)
        XCTAssertEqual(try session.checkpoint()?.editionID, firstEdition.id)
        XCTAssertEqual(try session.checkpoint(for: second)?.editionID, secondEdition.id,
            "switching away does not lose the other context's position")
    }

    /// A row written before T6 (no identity) acquires its surface's default identity, and re-running the
    /// backfill changes nothing.
    func testIdentityBackfillGivesPreT6RowsTheirSurfaceIdentityAndIsIdempotent() throws {
        let database = try StorageFixture.database(self)
        let key = filteredKey()
        let (edition, cards) = try publish(database, key: key)
        try PublicationHistory(database: database).saveCursor(.init(editionID: edition.id,
            anchor: .init(cardID: cards[0].id, placement: .top)), updatedAt: Date(timeIntervalSince1970: 30))
        // Simulate a database from before the identity columns: the reduced surface text is all there is.
        try database.write { db in
            try db.execute(sql: "UPDATE feed_editions SET context_identity = '', context_key_json = ''")
            try db.execute(sql: "UPDATE context_checkpoints SET context_identity = '', context_key_json = ''")
        }
        let session = SessionStore(database: database)
        XCTAssertNil(try session.checkpoint(for: key), "without an identity the filtered key cannot match")
        try database.write { db in
            try RuntimeMigrations.backfillEditionContextIdentities(db)
            try RuntimeMigrations.backfillCheckpointContextIdentities(db)
        }
        let defaultKey = ContextKey(request: .main)
        let identity = try database.read { try String.fetchOne($0,
            sql: "SELECT context_identity FROM feed_editions WHERE id = ?",
            arguments: [edition.id.rawValue.uuidString.lowercased()]) }
        XCTAssertEqual(identity, defaultKey.canonicalIdentity,
            "the backfill can only know the surface, and says so by writing the default-surface identity")
        XCTAssertEqual(try session.checkpoint(for: defaultKey)?.editionID, edition.id,
            "the pre-T6 position is preserved under the identity it actually had")
        // Idempotent: a second run leaves the same values.
        let before = try database.read { try String.fetchOne($0,
            sql: "SELECT context_identity FROM context_checkpoints WHERE edition_id = ?",
            arguments: [edition.id.rawValue.uuidString.lowercased()]) }
        try database.write { db in
            try RuntimeMigrations.backfillEditionContextIdentities(db)
            try RuntimeMigrations.backfillCheckpointContextIdentities(db)
        }
        let after = try database.read { try String.fetchOne($0,
            sql: "SELECT context_identity FROM context_checkpoints WHERE edition_id = ?",
            arguments: [edition.id.rawValue.uuidString.lowercased()]) }
        XCTAssertEqual(before, after)
    }

    /// Restoring by the whole key finds the filtered context's own window; the default key does not.
    func testRestoreUsesTheFilteredIdentity() throws {
        let database = try StorageFixture.database(self)
        let key = filteredKey(["pt", "en"])
        let (edition, cards) = try publish(database, key: key)
        try PublicationHistory(database: database).saveCursor(.init(editionID: edition.id,
            anchor: .init(cardID: cards[1].id, placement: .center)), updatedAt: Date(timeIntervalSince1970: 40))
        let history = PublicationHistory(database: database)
        let restored = try history.restore(backwardCapacity: 1, forwardCapacity: 1, contextKey: key)
        XCTAssertEqual(restored?.edition.id, edition.id)
        XCTAssertEqual(restored?.edition.contextKey, key)
        XCTAssertEqual(restored?.window.anchor.cardID, cards[1].id)
        XCTAssertNil(try history.restore(backwardCapacity: 1, forwardCapacity: 1, contextKey: ContextKey(request: .main)),
            "an identity that never had a position has none")
    }
}
