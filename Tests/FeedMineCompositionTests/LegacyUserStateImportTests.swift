import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition

/// D7-A: V1's `user.sqlite` upgraded into V2's library. The V1 side is built with the schema V1's own
/// `UserStateStore` migrations create (`v1_bookmarks` … `v11_user_operation`, the shape `BookmarkStore` writes):
/// `bookmark_list(id, name, sort_order, …)`, `bookmark_item(added_at, …)`, `source_collection_member` with both
/// `source_identity` and `source_url`, and `imported_source`. The older generation (the `RollbackRehearsalTests`
/// fixture: `bookmark_list(list_id, title, position)`, `source_collection(collection_id, name, source_keys)`) is
/// exercised separately: it must be reported, not crash.
final class LegacyUserStateImportTests: XCTestCase {
    /// Mechanical candidate coverage for V1's *case-collapsed* shape: on an
    /// insensitive volume Feedmine/user.sqlite lives in V2's own FeedMine folder.
    /// Build that exact file path, not a second case-variant directory: APFS/iOS
    /// simulators may refuse mkdir("feedmine") after mkdir("FeedMine") with EIO.
    /// The separate migration rehearsal exercises the true V1 folder discovery.
    func testCandidateUserStateURLsAlwaysIncludeAResolvableLocation() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let support = base.appendingPathComponent("Application Support", isDirectory: true)
        let v2Support = support.appendingPathComponent("FeedMine", isDirectory: true)
        try FileManager.default.createDirectory(at: v2Support, withIntermediateDirectories: true)
        let collapsedV1 = v2Support.appendingPathComponent("user.sqlite")
        try Data("v1".utf8).write(to: collapsedV1)

        let candidates = LegacyV1Upgrade.candidateUserStateURLs(applicationSupport: v2Support)
        XCTAssertTrue(candidates.contains(collapsedV1),
            "the collapsed V1 location must be returned explicitly")
        XCTAssertTrue(candidates.contains { FileManager.default.fileExists(atPath: $0.path) },
            "the candidate list always states a location that resolves: \(candidates.map(\.path))")
        XCTAssertTrue(candidates.allSatisfy { $0.lastPathComponent == "user.sqlite" })
    }

    /// A container shaped like the app's own: `Application Support/FeedMine` (V2) beside
    /// `Application Support/Feedmine` (V1).
    private struct Container {
        let root: URL
        var applicationSupport: URL { root.appendingPathComponent("Application Support") }
        var v2Directory: URL { applicationSupport.appendingPathComponent("FeedMine", isDirectory: true) }
        var v1Directory: URL { applicationSupport.appendingPathComponent("Feedmine", isDirectory: true) }
        var userStateURL: URL { v1Directory.appendingPathComponent("user.sqlite") }
    }

    private func container() throws -> Container {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let container = Container(root: root)
        try FileManager.default.createDirectory(at: container.v1Directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return container
    }

    /// The modern V1 generation: the one this build targets. Includes a default box, two reader boxes, one
    /// persistent-search list (no V2 surface), a collection, two personal sources (one disabled), a saved article
    /// in each box and the counts this build must report as inaccessible.
    private func seedModern(_ container: Container) throws {
        let queue = try DatabaseQueue(path: container.userStateURL.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE bookmark_list (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
                    is_default INTEGER NOT NULL DEFAULT 0, search_query TEXT, search_region TEXT,
                    search_category TEXT, search_active INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE bookmark_item (list_id INTEGER NOT NULL REFERENCES bookmark_list(id) ON DELETE CASCADE,
                    item_id TEXT NOT NULL, added_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (list_id, item_id));
                CREATE TABLE bookmark_snapshot (list_id INTEGER NOT NULL REFERENCES bookmark_list(id) ON DELETE CASCADE,
                    item_id TEXT NOT NULL, title TEXT NOT NULL, url TEXT, source_title TEXT, source_url TEXT,
                    excerpt TEXT, media_url TEXT, authored_at INTEGER, captured_at INTEGER NOT NULL,
                    PRIMARY KEY (list_id, item_id));
                CREATE TABLE source_collection (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
                CREATE TABLE source_collection_member (collection_id INTEGER NOT NULL
                        REFERENCES source_collection(id) ON DELETE CASCADE,
                    source_identity TEXT NOT NULL, source_url TEXT NOT NULL, title_snapshot TEXT NOT NULL,
                    media_kind TEXT NOT NULL DEFAULT 'text', added_at INTEGER NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (collection_id, source_identity));
                CREATE TABLE imported_source (id INTEGER PRIMARY KEY AUTOINCREMENT, source_identity TEXT NOT NULL UNIQUE,
                    request_url TEXT NOT NULL, title TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'Imported',
                    media_kind TEXT NOT NULL DEFAULT 'text', language TEXT, added_at INTEGER NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 1);
                CREATE TABLE smart_feed (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    definition_json TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
                CREATE TABLE curated_feed (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    definition_json TEXT NOT NULL, recipe_json TEXT, sort_order INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
                CREATE TABLE user_operation (operation_id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL,
                    subject_id TEXT NOT NULL, payload_json TEXT NOT NULL, state TEXT NOT NULL,
                    created_at INTEGER NOT NULL, applied_at INTEGER, failure_reason TEXT);

                INSERT INTO bookmark_list (id, name, sort_order, created_at, is_default, search_query) VALUES
                    (1, 'Favorites', 0, 100, 1, NULL),
                    (2, 'Longreads', 1, 101, 0, NULL),
                    (3, 'Projetos', 2, 102, 0, NULL),
                    (4, 'Busca antiga', 3, 103, 0, 'clima');
                INSERT INTO bookmark_item (list_id, item_id, added_at) VALUES
                    (1, 'article-1', 200),
                    (2, 'article-2', 201),
                    (3, 'article-3', 202),
                    (4, 'article-4', 203);
                INSERT INTO bookmark_snapshot (list_id, item_id, title, url, source_title, source_url, excerpt,
                    media_url, authored_at, captured_at) VALUES
                    (1, 'article-1', 'Um', 'https://a.example/one', 'Alpha', 'https://a.example/feed',
                        'resumo um', NULL, 150, 200),
                    (2, 'article-2', 'Dois', 'https://b.example/two', 'Beta', 'https://b.example/feed',
                        'resumo dois', 'https://b.example/two.jpg', 151, 201),
                    (3, 'article-3', 'Três', 'https://c.example/three', 'Gamma', 'https://c.example/feed',
                        'resumo três', NULL, 152, 202);
                INSERT INTO source_collection (id, name, sort_order, created_at) VALUES (7, 'Ciência', 0, 300);
                INSERT INTO source_collection_member (collection_id, source_identity, source_url, title_snapshot,
                    added_at, sort_order) VALUES
                    (7, 'https://a.example/feed', 'https://a.example/feed?utm_source=x', 'Alpha', 301, 0),
                    (7, 'https://b.example/feed', 'https://www.b.example/feed/', 'Beta', 302, 1);
                INSERT INTO imported_source (source_identity, request_url, title, added_at, enabled) VALUES
                    ('https://mine.example/feed', 'https://mine.example/feed?token=abc', 'Meu feed', 400, 1),
                    ('https://off.example/feed', 'https://off.example/feed', 'Desligado', 401, 0);
                INSERT INTO smart_feed (id, name, definition_json, sort_order, created_at, updated_at) VALUES
                    (5, 'Clima', '{"query":"clima"}', 0, 500, 500);
                INSERT INTO curated_feed (id, name, definition_json, recipe_json, sort_order, created_at, updated_at)
                    VALUES (9, 'Minha curadoria', '{}', '{}', 0, 501, 501);
                INSERT INTO user_operation (operation_id, kind, subject_id, payload_json, state, created_at)
                    VALUES ('op-1', 'bookmark.set', 'article-1', '{"listID":1,"wanted":true}', 'applied', 200);
                """)
        }
    }

    /// The older generation the ADR/spec and `RollbackRehearsalTests` describe: same table names, different
    /// columns. It must be recognised and reported, never queried with the modern columns.
    private func seedUnsupported(_ container: Container) throws {
        let queue = try DatabaseQueue(path: container.userStateURL.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE bookmark_list (list_id INTEGER PRIMARY KEY, title TEXT NOT NULL, position INTEGER NOT NULL);
                CREATE TABLE bookmark_item (list_id INTEGER NOT NULL, item_id TEXT NOT NULL, url TEXT NOT NULL,
                    title TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (list_id, item_id));
                CREATE TABLE source_collection (collection_id INTEGER PRIMARY KEY, name TEXT NOT NULL,
                    source_keys TEXT NOT NULL);
                INSERT INTO bookmark_list (list_id, title, position) VALUES (1, 'Read later', 0);
                INSERT INTO bookmark_item (list_id, item_id, url, title, position)
                    VALUES (1, 'legacy-saved', 'https://example.test/saved', 'Saved headline', 0);
                INSERT INTO source_collection (collection_id, name, source_keys)
                    VALUES (1, 'Antigas', '["https://old.example/feed"]');
                """)
        }
    }

    private func libraryDatabase(_ container: Container) throws -> RuntimeDatabase {
        try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: container.v2Directory))
    }

    /// Every file V1 owns, byte for byte. The upgrade must leave this map unchanged. On a case-insensitive
    /// volume `FeedMine` and `Feedmine` are the same directory, so V2's `runtime.sqlite*` sits beside V1's files;
    /// only V1's own names are compared.
    private func files(in directory: URL) throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("user.sqlite") || $0.hasPrefix("feedmine.sqlite") }
            .sorted()
        return try Dictionary(uniqueKeysWithValues: names.map { name in
            (name, try Data(contentsOf: directory.appendingPathComponent(name)))
        })
    }

    func testSameContainerUpgradeImportsSourcesBoxesAndCollectionsOnce() throws {
        let container = try container()
        try seedModern(container)
        let v1Before = try files(in: container.v1Directory)
        let database = try libraryDatabase(container)
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: ["https://seed.example/feed"])

        let outcome = LegacyV1Upgrade.runAtLaunch(applicationSupport: container.v2Directory, into: database)
        guard case .upgraded(let report) = outcome else {
            return XCTFail("expected an upgrade, got \(outcome)")
        }

        XCTAssertEqual(report.schema, .modern)
        // Sources are canonical identities, not fetch URLs; only V1's enabled source joins the selection.
        XCTAssertEqual(report.inserted.insertedSources, 2)
        XCTAssertEqual(report.inserted.selectedSources, 1)
        XCTAssertEqual(report.inserted.insertedBookmarkLists, 2, "Longreads and Projetos; the default is V2's own")
        XCTAssertEqual(report.inserted.insertedCollections, 1)
        XCTAssertEqual(report.inserted.insertedMemberships, 2)
        XCTAssertEqual(report.skippedSavedArticles, 4, "every saved article is counted and reported")
        XCTAssertTrue(report.skips.contains(.init(category: "boxes", reason: "persistentSearchListUnsupported", count: 1)))
        XCTAssertTrue(report.skips.contains(.init(category: "savedArticles", reason: "notImportedInThisBuild", count: 4)))
        XCTAssertTrue(report.skips.contains(.init(category: "smartFeeds", reason: "notImportedInThisBuild", count: 1)))
        XCTAssertTrue(report.skips.contains(.init(category: "curatedFeeds", reason: "notImportedInThisBuild", count: 1)))

        let library = ReaderLibraryStore(database: database)
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos", "Longreads", "Projetos"])
        XCTAssertEqual(try library.collections().map(\.name), ["Ciência"])
        let collection = try XCTUnwrap(try library.collections().first)
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id),
            ["https://a.example/feed", "https://b.example/feed"],
            "memberships use V1's canonical identity, never the fetch URL")
        XCTAssertEqual(try library.importedSources().map(\.title), ["Meu feed", "Desligado"])
        let selection = try XCTUnwrap(try preferences.load()).sourceKeys
        XCTAssertTrue(selection.contains("https://seed.example/feed"), "the reader's own selection survives")
        XCTAssertTrue(selection.contains("https://mine.example/feed"), "an enabled V1 source is selected")
        XCTAssertFalse(selection.contains("https://off.example/feed"), "a disabled V1 source is preserved, not selected")

        // The receipt is the marker and the queryable report. It is owed to the reader on this first open.
        let receipt = try XCTUnwrap(try library.legacyUpgradeReceipt())
        XCTAssertEqual(receipt.status, .completed)
        XCTAssertEqual(receipt.importedBoxes, 2)
        XCTAssertEqual(receipt.importedSources, 2)
        XCTAssertEqual(receipt.importedCollections, 1)
        XCTAssertEqual(receipt.skippedCount, 7)
        XCTAssertFalse(receipt.noticePresented)
        XCTAssertEqual(LegacyV1Upgrade.pendingNotice(in: database)?.status, .completed)

        // The first generation's files are untouched.
        XCTAssertEqual(try files(in: container.v1Directory), v1Before)

        // A second identical import adds nothing: ids are stable, so every inserted count is zero.
        let again = try LegacyUserStateImport.run(reader: try LegacyUserStateReader(url: container.userStateURL),
            into: database, at: Date(timeIntervalSince1970: 901))
        XCTAssertEqual(again.inserted.insertedBookmarkLists, 0)
        XCTAssertEqual(again.inserted.insertedSources, 0)
        XCTAssertEqual(again.inserted.selectedSources, 0)
        XCTAssertEqual(again.inserted.insertedCollections, 0)
        XCTAssertEqual(again.inserted.insertedMemberships, 0)
        XCTAssertEqual(try library.bookmarkLists().count, 3)
        XCTAssertEqual(try library.collections().count, 1)
        XCTAssertEqual(try library.importedSources().count, 2)
        XCTAssertEqual(try files(in: container.v1Directory), v1Before, "the V1 file is never written to")
    }

    func testASecondLaunchRunsNothingAndKeepsTheNoticePending() throws {
        let container = try container()
        try seedModern(container)
        let database = try libraryDatabase(container)
        let first = LegacyV1Upgrade.runAtLaunch(applicationSupport: container.v2Directory, into: database)
        guard case .upgraded = first else { return XCTFail("expected an upgrade, got \(first)") }
        let second = LegacyV1Upgrade.runAtLaunch(applicationSupport: container.v2Directory, into: database)
        guard case .alreadyHandled(let receipt) = second else {
            return XCTFail("expected the completed marker, got \(second)")
        }
        XCTAssertEqual(receipt.status, .completed)
        XCTAssertEqual(try ReaderLibraryStore(database: database).bookmarkLists().count, 3)
        XCTAssertEqual(LegacyV1Upgrade.pendingNotice(in: database)?.status, .completed,
            "the second launch does not import, and the notice is still owed")
        XCTAssertTrue(try ReaderLibraryStore(database: database).markLegacyUpgradeNoticePresented())
        XCTAssertNil(LegacyV1Upgrade.pendingNotice(in: database), "a presented notice is not owed again")
    }

    func testUnsupportedGenerationIsReportedAndWritesNoLibraryRows() throws {
        let container = try container()
        try seedUnsupported(container)
        let v1Before = try files(in: container.v1Directory)
        let database = try libraryDatabase(container)
        let outcome = LegacyV1Upgrade.runAtLaunch(applicationSupport: container.v2Directory, into: database)
        guard case .alreadyHandled(let receipt) = outcome else {
            return XCTFail("expected a reported unsupported generation, got \(outcome)")
        }
        XCTAssertEqual(receipt.status, .unsupported)
        XCTAssertEqual(receipt.failureReason, nil)
        XCTAssertTrue(receipt.skips.contains(.init(category: "schema", reason: "unsupportedV1Schema", count: 1)))
        XCTAssertEqual(try ReaderLibraryStore(database: database).bookmarkLists().map(\.name), ["Salvos"])
        XCTAssertTrue(try ReaderLibraryStore(database: database).collections().isEmpty)
        XCTAssertTrue(try ReaderLibraryStore(database: database).importedSources().isEmpty)
        XCTAssertEqual(LegacyV1Upgrade.pendingNotice(in: database)?.status, .unsupported)
        XCTAssertEqual(try files(in: container.v1Directory), v1Before)
    }

    func testEverySkippedRowCarriesAReason() throws {
        let container = try container()
        try seedModern(container)
        // Two genuinely unreadable rows: an address V2 cannot fetch, and a collection member that is not an
        // identity at all. Both must be reported, never silently dropped.
        let queue = try DatabaseQueue(path: container.userStateURL.path)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO imported_source (source_identity, request_url, title, added_at, enabled)
                    VALUES ('broken', 'not a url', 'Quebrado', 402, 1);
                INSERT INTO source_collection_member (collection_id, source_identity, source_url, title_snapshot,
                    added_at, sort_order) VALUES (7, 'nao-e-identidade', 'not a url', 'Quebrado', 303, 2);
                """)
        }
        let database = try libraryDatabase(container)
        let report = try LegacyUserStateImport.run(reader: try LegacyUserStateReader(url: container.userStateURL),
            into: database)
        XCTAssertTrue(report.skips.contains(.init(category: "sources", reason: "invalidSourceAddress", count: 1)))
        XCTAssertTrue(report.skips.contains(.init(category: "collections", reason: "invalidSourceIdentity", count: 1)))
        XCTAssertEqual(report.inserted.insertedSources, 2, "the two valid personal sources still land")
        let library = ReaderLibraryStore(database: database)
        XCTAssertEqual(try library.importedSources().count, 2)
        let collection = try XCTUnwrap(try library.collections().first)
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id).count, 2,
            "only the two valid memberships land")
    }

    /// An import into a library that already has the reader's own work appends and never reorders or overwrites.
    func testImportAppendsToWhatTheReaderAlreadyHas() throws {
        let container = try container()
        try seedModern(container)
        let database = try libraryDatabase(container)
        let library = ReaderLibraryStore(database: database)
        let mine = try library.createBookmarkList(named: "Meus")
        let myCollection = try library.createCollection(named: "Minhas fontes")
        try library.addToCollection(id: myCollection.id, sourceKeys: ["https://mine/feed"], at: Date())
        _ = try LegacyUserStateImport.run(reader: try LegacyUserStateReader(url: container.userStateURL),
            into: database, at: Date())
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos", "Meus", "Longreads", "Projetos"])
        XCTAssertEqual(try library.collections().map(\.name), ["Minhas fontes", "Ciência"])
        XCTAssertEqual(try library.sourceKeys(inCollection: myCollection.id), ["https://mine/feed"])
        XCTAssertEqual(try library.bookmarkLists().first?.id, ReaderBookmarkList.defaultID)
        XCTAssertNotEqual(try library.bookmarkLists().last?.id, mine.id)
    }

    /// A file that is not V1's user state at all is refused before anything is written.
    func testANonLegacyFileIsNotImported() throws {
        let container = try container()
        let queue = try DatabaseQueue(path: container.userStateURL.path)
        try queue.write { db in try db.execute(sql: "CREATE TABLE unrelated (id INTEGER PRIMARY KEY)") }
        let reader = try LegacyUserStateReader(url: container.userStateURL)
        XCTAssertFalse(try reader.isLegacyUserState())
        XCTAssertThrowsError(try reader.bookmarkLists())
    }
}
