import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition

/// T8's legacy import: V1's `user.sqlite` into V2's library. The V1 side is built here exactly as V1's own
/// migrations create it, so the import is exercised against the real shape rather than a convenient one.
final class LegacyUserStateImportTests: XCTestCase {
    private func legacyUserState() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE bookmark_list (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
                    is_default INTEGER NOT NULL DEFAULT 0, search_query TEXT, search_region TEXT,
                    search_category TEXT, search_active INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE bookmark_item (list_id INTEGER NOT NULL REFERENCES bookmark_list(id) ON DELETE CASCADE,
                    item_id TEXT NOT NULL, added_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (list_id, item_id));
                CREATE TABLE source_collection (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
                CREATE TABLE source_collection_member (collection_id INTEGER NOT NULL
                        REFERENCES source_collection(id) ON DELETE CASCADE,
                    source_url TEXT NOT NULL, title_snapshot TEXT NOT NULL,
                    media_kind TEXT NOT NULL DEFAULT 'text', added_at INTEGER NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (collection_id, source_url));
                CREATE TABLE smart_feed (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    definition_json TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
                CREATE TABLE curated_feed (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    definition_json TEXT NOT NULL, recipe_json TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
                CREATE TABLE bookmark_snapshot (
                    list_id INTEGER NOT NULL, item_id TEXT NOT NULL,
                    title TEXT, url TEXT, source_title TEXT, source_url TEXT,
                    excerpt TEXT, media_url TEXT, authored_at REAL, captured_at REAL,
                    PRIMARY KEY(list_id, item_id));
                INSERT INTO bookmark_list (id, name, sort_order, created_at, is_default) VALUES
                    (1, 'Favorites', 0, 100, 1),
                    (2, 'Longreads', 1, 101, 0);
                INSERT INTO bookmark_item (list_id, item_id, added_at) VALUES
                    (1, 'article-1', 200), (2, 'article-2', 201), (2, 'article-3', 202);
                INSERT INTO bookmark_snapshot (list_id, item_id, title, url, source_title,
                    source_url, excerpt, media_url, authored_at, captured_at)
                    VALUES (2, 'article-2', 'Artigo offline', 'https://article.example/2',
                        'Fonte A', 'https://a.example/feed', 'Texto preservado', NULL, 180, 205);
                INSERT INTO source_collection (id, name, sort_order, created_at) VALUES (7, 'Ciência', 0, 300);
                INSERT INTO source_collection_member (collection_id, source_url, title_snapshot, added_at) VALUES
                    (7, 'https://a.example/feed', 'Alpha', 301),
                    (7, 'https://b.example/feed', 'Beta', 302);
                INSERT INTO smart_feed (id, name, definition_json, sort_order, created_at, updated_at) VALUES
                    (5, 'Clima', '{"query":"clima","requiredSearchTerms":["clima","oceano"],"excludedSearchTerms":["horóscopo"],"includeSources":true,"includeContents":false,"languages":["pt"],"contentType":"Articles","mood":"Serious","sourceCollectionID":7,"excludedKeywords":["spam"]}', 0, 400, 400),
                    (6, 'Vazio', '{"query":"","includeSources":true,"includeContents":true}', 1, 401, 401),
                    (8, 'Quebrado', 'not json at all', 2, 402, 402);
                INSERT INTO curated_feed (id, name, definition_json, recipe_json, sort_order, created_at, updated_at)
                    VALUES (9, 'Minha curadoria', '{}', '{}', 0, 500, 500);
                """)
        }
        return url
    }

    /// The V2 side is an ordinary runtime database; the library tables come from its own migrations.
    private func libraryDatabase() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    /// The whole import, then the same import again: nothing duplicates, and the V1 file is not written to.
    func testImportCarriesBoxesCollectionsAndSmartFeedsOnce() throws {
        let legacyURL = try legacyUserState()
        let before = try Data(contentsOf: legacyURL)
        let database = try libraryDatabase()
        let reader = try LegacyUserStateReader(url: legacyURL)
        XCTAssertTrue(try reader.isLegacyUserState())
        let report = try LegacyUserStateImport.run(reader: reader, into: database, at: Date(timeIntervalSince1970: 900))

        let library = ReaderLibraryStore(database: database)
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos", "Longreads"],
            "V1's default box is V2's own default box, and the reader's other boxes come across")
        XCTAssertEqual(report.skippedBoxItems, 0, "V1 bookmarks use a separate typed authority")
        XCTAssertEqual(report.carriedCollections, 1)
        XCTAssertEqual(report.carriedSmartFeeds, 0)
        XCTAssertEqual(report.skippedSmartFeeds, 3, "scoped, empty and invalid remain archived")
        XCTAssertEqual(report.skippedCuratedFeeds, 1, "curated feeds are counted, not approximated")
        XCTAssertEqual(report.droppedCollectionScopes, 1, "the smart feed's collection scope is reported as dropped")

        let collection = try XCTUnwrap(try library.collections().first)
        XCTAssertEqual(collection.name, "Ciência")
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id),
            ["https://a.example/feed", "https://b.example/feed"])
        XCTAssertTrue(try library.presets().isEmpty)
        let archived = try library.legacyArchive()
        XCTAssertEqual(archived.filter { $0.category == "smart_feed" }.count, 3)
        XCTAssertEqual(archived.filter { $0.category == "curated_feed" }.count, 1)
        XCTAssertEqual(try library.legacyBookmarks().count, 3)
        let recovered = try XCTUnwrap(try library.legacyBookmarks(inList: "v1:list:2").first {
            $0.itemID == "article-2"
        })
        XCTAssertTrue(recovered.hasSnapshot)
        XCTAssertEqual(recovered.title, "Artigo offline")
        XCTAssertEqual(recovered.excerpt, "Texto preservado")
        XCTAssertEqual(try library.legacyBookmarkListCounts(), ["saved": 1, "v1:list:2": 2])
        XCTAssertNotNil(try library.legacyReceipt())
        let publishedCount = try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM published_cards")
        }
        XCTAssertEqual(publishedCount, 0)

        // The second run is a no-op: ids are stable, so nothing duplicates and nothing moves.
        let again = try LegacyUserStateImport.run(reader: reader, into: database, at: Date(timeIntervalSince1970: 901))
        XCTAssertEqual(again.inserted.insertedBookmarkLists, 0)
        XCTAssertEqual(again.inserted.insertedCollections, 0)
        XCTAssertEqual(again.inserted.insertedPresets, 0)
        XCTAssertEqual(again.inserted.insertedMemberships, 0)
        XCTAssertEqual(try library.bookmarkLists().count, 2)
        XCTAssertEqual(try library.collections().count, 1)
        XCTAssertEqual(try library.presets().count, 0)
        XCTAssertEqual(try Data(contentsOf: legacyURL), before, "the imported database is never written to")
    }

    /// An import into a library that already has the reader's own work appends and never reorders or overwrites.
    func testImportAppendsToWhatTheReaderAlreadyHas() throws {
        let legacyURL = try legacyUserState()
        let database = try libraryDatabase()
        let library = ReaderLibraryStore(database: database)
        let mine = try library.createBookmarkList(named: "Meus")
        let myCollection = try library.createCollection(named: "Minhas fontes")
        try library.addToCollection(id: myCollection.id, sourceKeys: ["https://mine/feed"], at: Date())
        _ = try LegacyUserStateImport.run(reader: try LegacyUserStateReader(url: legacyURL), into: database, at: Date())
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos", "Meus", "Longreads"])
        XCTAssertEqual(try library.collections().map(\.name), ["Minhas fontes", "Ciência"])
        XCTAssertEqual(try library.sourceKeys(inCollection: myCollection.id), ["https://mine/feed"])
        XCTAssertEqual(try library.bookmarkLists().first?.id, ReaderBookmarkList.defaultID)
        XCTAssertNotEqual(try library.bookmarkLists().last?.id, mine.id)
    }

    /// A file that is not V1's user state at all is refused before anything is written.
    func testANonLegacyFileIsNotImported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in try db.execute(sql: "CREATE TABLE unrelated (id INTEGER PRIMARY KEY)") }
        let reader = try LegacyUserStateReader(url: url)
        XCTAssertFalse(try reader.isLegacyUserState())
        XCTAssertThrowsError(try reader.bookmarkLists())
    }
    func testImportRetainsUnresolvedItemsAndSurvivesOfflineDatabaseReopen() throws {
        let source = try legacyUserState()
        let reader = try LegacyUserStateReader(url: source)
        // The fixture defines three distinct (list,item) memberships but only
        // ONE bookmark_snapshot row. A LEFT JOIN row is not proof of a snapshot.
        let inventory = try reader.personalState().bookmarks
        XCTAssertEqual(inventory.count, 3)
        XCTAssertEqual(inventory.filter(\.hasSnapshot).count, 1)
        XCTAssertEqual(inventory.filter { !$0.hasSnapshot }.count, 2)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let loc = RuntimeDatabaseLocation(directory: root)
        do {
            let db = try RuntimeDatabase(location: loc)
            _ = try LegacyUserStateImport.run(reader: reader, into: db)
        }

        let reopened = try RuntimeDatabase(location: loc)
        let library = ReaderLibraryStore(database: reopened)
        let bookmarks = try library.legacyBookmarks()
        XCTAssertEqual(bookmarks.count, 3)
        XCTAssertEqual(bookmarks.filter(\.hasSnapshot).count, 1)
        XCTAssertEqual(bookmarks.filter { !$0.hasSnapshot }.count, 2)
        XCTAssertEqual(bookmarks.map(\.id).count, Set(bookmarks.map(\.id)).count)

        // Verify the actual persisted CHECK-domain values, not just a derived UI flag.
        let statuses = try reopened.read { db in
            try String.fetchAll(db, sql: """
                SELECT item_id || ':' || status FROM reader_legacy_bookmarks ORDER BY item_id
                """)
        }
        XCTAssertEqual(statuses, ["article-1:unresolved", "article-2:snapshot",
            "article-3:unresolved"])
        XCTAssertEqual(try library.legacyBookmarks(inList: "saved").map(\.itemID), ["article-1"])
        XCTAssertEqual(Set(try library.legacyBookmarks(inList: "v1:list:2").map(\.itemID)),
            Set(["article-2", "article-3"]))
        let receipt = try XCTUnwrap(try library.legacyReceipt())
        let counters = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(receipt.totalsJSON.utf8)) as? [String: Int])
        XCTAssertEqual(counters["bookmarks"], 3)
        XCTAssertEqual(counters["snapshots"], 1)
        XCTAssertEqual(counters["unresolved_bookmarks"], 2)
        let publicationCount = try reopened.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM published_cards")
        }
        XCTAssertEqual(publicationCount, 0, "V1 snapshots are not published card occurrences")
    }

    func testFailedImportRollsBackEveryV2WriteAndReceipt() throws {
        let source = try legacyUserState()
        let db = try libraryDatabase()
        try db.write { sql in
            try sql.execute(sql: """
                INSERT INTO reader_legacy_bookmarks
                    (legacy_list_id, item_id, list_id, added_at, sort_order, status)
                VALUES (2, 'article-2', 'saved', 1, 0, 'unresolved')
                """)
        }
        XCTAssertThrowsError(try LegacyUserStateImport.run(
            reader: LegacyUserStateReader(url: source), into: db))
        let library = ReaderLibraryStore(database: db)
        XCTAssertNil(try library.legacyReceipt())
        XCTAssertEqual(try library.bookmarkLists().count, 1)
        XCTAssertTrue(try library.collections().isEmpty)
        XCTAssertEqual(try library.legacyBookmarks().count, 1)
    }

    func testLegacyExplicitDisabledSourceIsAppliedOnlyToAnEmptyV2Preference() throws {
        let source = try legacyUserState()
        let db = try libraryDatabase()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MIG-V1V2-B-" + UUID().uuidString))
        defaults.set(["url:https://a.example/feed"], forKey: "toggleDisabled")
        defaults.set(["url:https://b.example/feed"], forKey: "toggleEnabledOverrides")
        let initial = ["https://a.example/feed", "https://b.example/feed"]
        _ = try LegacyUserStateImport.run(reader: LegacyUserStateReader(url: source),
            into: db, defaults: defaults, initialSourceKeys: initial)
        let prefs = ReaderPreferencesStore(database: db)
        XCTAssertEqual(try prefs.load()?.sourceKeys, ["https://b.example/feed"])
        XCTAssertTrue(try ReaderLibraryStore(database: db).legacyArchive().contains {
            $0.category == "user_defaults" && $0.key == "toggleDisabled"
        })
        _ = try prefs.updateSources(["https://a.example/feed"])
        _ = try LegacyUserStateImport.run(reader: LegacyUserStateReader(url: source),
            into: db, defaults: defaults, initialSourceKeys: initial)
        XCTAssertEqual(try prefs.load()?.sourceKeys, ["https://a.example/feed"],
            "relaunch never replays V1 against the reader's later V2 choice")

    }


    func testPreexistingV2SourceSelectionWinsOverLegacyImport() throws {
        let source = try legacyUserState()
        let db = try libraryDatabase()
        let preferences = ReaderPreferencesStore(database: db)
        _ = try preferences.initialize(sourceKeys: ["https://my-v2-selection.example/feed"])
        _ = try LegacyUserStateImport.run(reader: LegacyUserStateReader(url: source),
            into: db, initialSourceKeys: ["https://legacy.example/feed"])
        XCTAssertEqual(try preferences.load()?.sourceKeys, ["https://my-v2-selection.example/feed"])
    }

}
