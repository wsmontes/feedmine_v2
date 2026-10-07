import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence

final class PublicationSchemaTests: XCTestCase {
    func testExactlyFourDomainTablesAndDurableMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let tables = try database.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name") }
        XCTAssertEqual(tables, ["feed_editions", "feed_segments", "published_cards", "session_checkpoint"])
        let history = try database.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") }
        XCTAssertTrue(history.contains("publication-restore-v1"))
        XCTAssertEqual(history.filter { $0 == "runtime-foundation-v1" }.count, 1)
    }
    func testArchitecturalConstraintsRejectIncompleteAndContradictoryRows() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        let card = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
        try SessionStore(database: database).saveCheckpoint(.init(editionID: edition.id, cardID: card.id,
            anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 1)))
        let statements = [
            "UPDATE feed_editions SET context_source_id = 'unexpected'",
            "UPDATE feed_editions SET scoring_policy_version = -1",
            "UPDATE feed_segments SET ordinal = -1",
            "UPDATE published_cards SET timestamp_value = 1, timestamp_kind = NULL",
            "UPDATE published_cards SET media_pixel_height = NULL",
            "UPDATE published_cards SET media_key = ''",
            "UPDATE published_cards SET render_layout = 'unknown'",
            "UPDATE published_cards SET render_layout = 'textOnly'",
            "UPDATE published_cards SET primary_action_kind = NULL, primary_action_reference = 'target'",
            "UPDATE session_checkpoint SET anchor_placement = 'bottom'"
        ]
        for statement in statements {
            XCTAssertThrowsError(try database.write { try $0.execute(sql: statement) }, statement)
        }
        XCTAssertEqual(try store.card(id: card.id), card)
    }

}
