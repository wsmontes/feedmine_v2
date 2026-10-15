import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

/// T8: the reader's own library — boxes, collections and saved presets — as storage.
///
/// The acceptance this file carries: CRUD, persisted ordering, an empty box being a state and not an error,
/// several boxes holding the same card, deleting a collection without deleting a source or an article, a
/// relaunch reading the same library back, and a refused write leaving no partial membership behind.
final class ReaderLibraryStoreTests: XCTestCase {
    private func seeded() throws -> (RuntimeDatabase, PublicationStore, [PublicationStore.CardRecord]) {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        let cards = (0..<3).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
        return (database, store, cards)
    }

    /// The default box exists from the migration on, and it cannot be deleted: the control on a card needs
    /// somewhere to put a bookmark.
    func testTheDefaultBoxExistsAndIsTheOnlyUndeletableOne() throws {
        let (database, _, cards) = try seeded()
        let library = ReaderLibraryStore(database: database)
        XCTAssertEqual(try library.bookmarkLists().map(\.id), [ReaderBookmarkList.defaultID])
        try library.setBookmarkMembership(cardID: cards[0].id, listID: ReaderBookmarkList.defaultID,
            included: true, at: Date())
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), [cards[0].id])
        XCTAssertFalse(try library.deleteBookmarkList(id: ReaderBookmarkList.defaultID))
        XCTAssertEqual(try library.bookmarkLists().count, 1)
        // The plain card control reads the same membership.
        XCTAssertEqual(try PublicationStore(database: database).bookmarkedCardIDs(), [cards[0].id])
    }

    /// Several boxes, one card in two of them, and an empty box that is a state rather than an error.
    func testSeveralBoxesHoldTheSameCardAndAnEmptyBoxIsAState() throws {
        let (database, _, cards) = try seeded()
        let library = ReaderLibraryStore(database: database)
        let reading = try library.createBookmarkList(named: "  Para ler  ")
        XCTAssertEqual(reading.name, "Para ler", "names are trimmed")
        let empty = try library.createBookmarkList(named: "Depois")
        XCTAssertTrue(try library.bookmarkedCardIDs(inList: empty.id).isEmpty)
        try library.setBookmarkMembership(cardID: cards[1].id, listID: ReaderBookmarkList.defaultID,
            included: true, at: Date())
        try library.setBookmarkMembership(cardID: cards[1].id, listID: reading.id, included: true, at: Date())
        XCTAssertEqual(try library.bookmarkListIDs(forCard: cards[1].id),
            [ReaderBookmarkList.defaultID, reading.id])
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: reading.id), [cards[1].id])
        // Removing it from one box leaves the other alone, and the control still reads "saved".
        try library.setBookmarkMembership(cardID: cards[1].id, listID: ReaderBookmarkList.defaultID,
            included: false, at: Date())
        XCTAssertEqual(try library.bookmarkListIDs(forCard: cards[1].id), [reading.id])
        XCTAssertEqual(try PublicationStore(database: database).bookmarkedCardIDs(), [cards[1].id])
        // Deleting a box removes its memberships and nothing else.
        XCTAssertTrue(try library.deleteBookmarkList(id: reading.id))
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos", "Depois"])
        XCTAssertTrue(try library.bookmarkListIDs(forCard: cards[1].id).isEmpty)
        XCTAssertEqual(try PublicationStore(database: database).bookmarkedCardIDs(), [])
        XCTAssertEqual(try PublicationStore(database: database).card(id: cards[1].id), cards[1],
            "the article itself is untouched by a box deletion")
    }

    func testNamingAndOrderingRules() throws {
        let (database, _, _) = try seeded()
        let library = ReaderLibraryStore(database: database)
        XCTAssertThrowsError(try library.createBookmarkList(named: "   ")) {
            XCTAssertEqual($0 as? ReaderLibraryError, .invalidName)
        }
        let a = try library.createBookmarkList(named: "A")
        let b = try library.createBookmarkList(named: "B")
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos", "A", "B"])
        let reordered = try library.reorderBookmarkLists([b.id, a.id])
        XCTAssertEqual(reordered.map(\.name), ["B", "A", "Salvos"],
            "positions follow the order given, and an unnamed box keeps its own place after them")
        XCTAssertEqual(reordered.map(\.position), [0, 1, 2])
        // A reorder that names nothing is still a valid request: everything keeps its relative order.
        XCTAssertEqual(try library.reorderBookmarkLists([]).map(\.name), ["B", "A", "Salvos"])
        // Renaming refuses an empty name and reports a missing box instead of inventing one.
        XCTAssertThrowsError(try library.renameBookmarkList(id: a.id, to: " ")) {
            XCTAssertEqual($0 as? ReaderLibraryError, .invalidName)
        }
        XCTAssertThrowsError(try library.renameBookmarkList(id: "nope", to: "X")) {
            XCTAssertEqual($0 as? ReaderLibraryError, .missingLibraryItem)
        }
    }

    /// A collection groups catalog keys. Deleting it never deletes a source: the reader's selection in
    /// `reader_preferences` is what owns sources, and it must be exactly as it was.
    func testCollectionsGroupSourcesAndDeletingOneKeepsThem() throws {
        let (database, _, _) = try seeded()
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: ["https://a.example/feed", "https://b.example/feed"])
        let before = try XCTUnwrap(try preferences.load())
        let library = ReaderLibraryStore(database: database)
        let collection = try library.createCollection(named: "Ciência")
        XCTAssertEqual(try library.addToCollection(id: collection.id,
            sourceKeys: ["https://a.example/feed", "https://b.example/feed", "https://b.example/feed"], at: Date()), 2,
            "a repeated key is not a second membership")
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id),
            ["https://a.example/feed", "https://b.example/feed"])
        // A membership can be removed on its own.
        try library.setCollectionMembership(sourceKey: "https://b.example/feed", collectionID: collection.id,
            included: false, at: Date())
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id), ["https://a.example/feed"])
        XCTAssertTrue(try library.deleteCollection(id: collection.id))
        XCTAssertTrue(try library.collections().isEmpty)
        XCTAssertEqual(try preferences.load(), before, "no collection operation touches the reader's selection")
        // The default box and the selection both survive a collection being made and destroyed.
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos"])
    }

    func testCollectionOrderingAndNamingBehaveLikeBoxes() throws {
        let (database, _, _) = try seeded()
        let library = ReaderLibraryStore(database: database)
        XCTAssertThrowsError(try library.createCollection(named: "")) {
            XCTAssertEqual($0 as? ReaderLibraryError, .invalidName)
        }
        let first = try library.createCollection(named: "Primeira")
        let second = try library.createCollection(named: "Segunda")
        XCTAssertEqual(try library.collections().map(\.name), ["Primeira", "Segunda"])
        XCTAssertEqual(try library.reorderCollections([second.id, first.id]).map(\.name), ["Segunda", "Primeira"])
        XCTAssertThrowsError(try library.addToCollection(id: "missing", sourceKeys: ["https://a/feed"], at: Date())) {
            XCTAssertEqual($0 as? ReaderLibraryError, .missingLibraryItem)
        }
    }

    /// A preset is a named T6 identity: its key — including the search scope and the content exclusions it
    /// was saved from — must come back byte-identical, because activating it is an ordinary transition.
    func testPresetsRoundTripTheirIdentityAndAreKindOrdered() throws {
        let (database, _, _) = try seeded()
        let library = ReaderLibraryStore(database: database)
        let search = try XCTUnwrap(SearchContext(query: "clima"))
        let key = ContextKey(request: .search(search),
            preset: .smartFeed("ignored-by-the-preset-itself"),
            filter: ReaderFilter(languages: ["pt"], exclusions: .init(isEnabled: true, rules: ["Horóscopo"])),
            searchScope: .contents)
        let smart = try library.createPreset(named: "Clima", kind: .smartBookmark, key: key)
        XCTAssertEqual(smart.presetID, ReaderPresetID.smartFeed(smart.id),
            "the saved context names itself when activated")
        let curated = try library.createPreset(named: "Minha curadoria", kind: .curatedFeed,
            key: ContextKey(request: .main, preset: .curatedFeed("x")))
        XCTAssertEqual(curated.presetID, ReaderPresetID.curatedFeed(curated.id))
        let read = try library.presets()
        XCTAssertEqual(read.map(\.name), ["Minha curadoria", "Clima"],
            "curated feeds draw before smart bookmarks, as V1's own picker did")
        let restored = try XCTUnwrap(read.first { $0.id == smart.id })
        XCTAssertEqual(restored.key, key)
        XCTAssertEqual(restored.key.filter.exclusions.rules, ["horóscopo"], "the stored exclusions are canonical")
        XCTAssertEqual(restored.key.searchScope, .contents)
        // Rename and delete, and a reorder inside a kind.
        XCTAssertEqual(try library.renamePreset(id: smart.id, to: "Clima e tempo").name, "Clima e tempo")
        XCTAssertThrowsError(try library.renamePreset(id: "missing", to: "X")) {
            XCTAssertEqual($0 as? ReaderLibraryError, .missingLibraryItem)
        }
        XCTAssertTrue(try library.deletePreset(id: curated.id))
        XCTAssertEqual(try library.presets().map(\.name), ["Clima e tempo"])
    }

    /// Everything above survives a relaunch: a new store on the same file reads the same library back.
    func testLibrarySurvivesReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let id: String
        do {
            let database = try RuntimeDatabase(location: location)
            let library = ReaderLibraryStore(database: database)
            let box = try library.createBookmarkList(named: "Longreads")
            let collection = try library.createCollection(named: "Áudio")
            try library.addToCollection(id: collection.id, sourceKeys: ["https://c/feed"], at: Date())
            _ = try library.createPreset(named: "Mercados", kind: .smartBookmark,
                key: ContextKey(request: .main))
            id = box.id
        }
        let reopened = ReaderLibraryStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.bookmarkLists().map(\.name), ["Salvos", "Longreads"])
        XCTAssertEqual(try reopened.bookmarkLists().last?.id, id)
        XCTAssertEqual(try reopened.collections().map(\.name), ["Áudio"])
        XCTAssertEqual(try reopened.sourceKeys(inCollection: try XCTUnwrap(try reopened.collections().first).id),
            ["https://c/feed"])
        XCTAssertEqual(try reopened.presets().map(\.name), ["Mercados"])
    }

    /// A refused write is atomic: nothing partial is left behind, and a batch either lands whole or not at all.
    func testARefusedWriteLeavesNoPartialState() throws {
        let (database, _, cards) = try seeded()
        let library = ReaderLibraryStore(database: database)
        // A card that is not a published occurrence cannot be bookmarked, in any box.
        XCTAssertThrowsError(try library.setBookmarkMembership(cardID: PublicationCardID(),
            listID: ReaderBookmarkList.defaultID, included: true, at: Date())) {
            XCTAssertEqual($0 as? ReaderLibraryError, .cardIdentityMismatch)
        }
        XCTAssertTrue(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID).isEmpty)
        // A box that does not exist cannot receive memberships, and a batch for a missing collection adds none.
        XCTAssertThrowsError(try library.setBookmarkMembership(cardID: cards[0].id, listID: "missing",
            included: true, at: Date())) {
            XCTAssertEqual($0 as? ReaderLibraryError, .missingLibraryItem)
        }
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), [])
        XCTAssertThrowsError(try library.addToCollection(id: "missing",
            sourceKeys: ["https://a/feed", "https://b/feed"], at: Date()))
        XCTAssertTrue(try library.collections().isEmpty)
    }

    /// T8's cutover: the one implicit bookmarked set V2 had becomes the default box, with its memberships, and
    /// the old table is gone. The pre-T8 shape is rebuilt here on a copy of the schema, exactly as an
    /// interrupted or older database would look.
    func testTheLegacyBookmarkSetBecomesTheDefaultBox() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let cards: [PublicationStore.CardRecord]
        do {
            let database = try RuntimeDatabase(location: location)
            let store = PublicationStore(database: database)
            let edition = StorageFixture.edition()
            cards = (0..<2).map { _ in StorageFixture.card() }
            try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
            try database.write { db in
                try db.execute(sql: "DROP TABLE reader_bookmark_memberships; DROP TABLE reader_bookmark_lists")
                try db.execute(sql: "DROP TABLE reader_collections; DROP TABLE reader_collection_memberships")
                try db.execute(sql: "DROP TABLE reader_presets")
                try db.execute(sql: """
                    CREATE TABLE publication_bookmarks (card_id TEXT PRIMARY KEY REFERENCES published_cards(id), bookmarked_at REAL NOT NULL)
                    """)
                try db.execute(sql: "INSERT INTO publication_bookmarks VALUES (?, ?)",
                    arguments: [cards[1].id.rawValue.uuidString.lowercased(), 123.5])
                try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'reader-library-v1'")
            }
        }
        // Reopening runs the library migration over that database, as it would on the reader's own device.
        let database = try RuntimeDatabase(location: location)
        let library = ReaderLibraryStore(database: database)
        XCTAssertEqual(try library.bookmarkLists().map(\.name), ["Salvos"])
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), [cards[1].id],
            "the bookmark V2 already had moved into the default box")
        XCTAssertEqual(try PublicationStore(database: database).bookmarkedCardIDs(), [cards[1].id])
        let tables = try database.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        XCTAssertFalse(tables.contains("publication_bookmarks"), "the legacy table does not survive the migration")
        // Running it again changes nothing: the migration is history, and the store is idempotent.
        let reopened = ReaderLibraryStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), [cards[1].id])
    }
    // PD10-P0D deterministic revisions. Two local compiled SQLite catalogs, no HTTP and no live source.
    private func identityCatalog(revision: Int, sources: [(String, String)]) throws -> LegacyCatalogReader {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try DatabaseQueue(path: url.path).write { db in
            try db.execute(sql: """
                CREATE TABLE catalog_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE catalog_node (id INTEGER PRIMARY KEY, key TEXT NOT NULL, name TEXT NOT NULL);
                CREATE TABLE catalog_placement (source_id INTEGER, node_id INTEGER);
                CREATE TABLE catalog_source (
                    id INTEGER PRIMARY KEY, key TEXT UNIQUE NOT NULL, title TEXT NOT NULL,
                    request_url TEXT NOT NULL, site_url TEXT, language TEXT, media_kind TEXT NOT NULL,
                    quality_score INTEGER, default_enabled INTEGER NOT NULL,
                    description TEXT, display_host TEXT, tags TEXT, nature TEXT, activity TEXT
                );
                """)
            try db.execute(sql: "INSERT INTO catalog_metadata (key,value) VALUES ('catalog_version', ?)",
                arguments: [String(revision)])
            for (index, source) in sources.enumerated() {
                try db.execute(sql: """
                    INSERT INTO catalog_source
                        (id, key, title, request_url, media_kind, default_enabled)
                    VALUES (?, ?, 'Verified feed', ?, 'text', 1)
                    """, arguments: [index + 1, source.0, source.1])
            }
        }
        return try LegacyCatalogReader(catalogURL: url)
    }

    func testPD10P0DAliasAcrossTwoCompiledRevisionsKeepsPersonalStateAndReopens() throws {
        let a = "https://old.example/rss", b = "https://new.example/rss"
        let endpoint = "https://actual.example/feed?token=keep"
        let old = try identityCatalog(revision: 5, sources: [(a, endpoint)])
        let new = try identityCatalog(revision: 6, sources: [(b, endpoint)])
        let proof = try VerifiedSourceAlias(old: old, new: new, oldKey: a, newKey: b)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let collectionID: String
        let savedVersion: UInt64
        let cardID: PublicationCardID
        do {
            let database = try RuntimeDatabase(location: location)
            let library = ReaderLibraryStore(database: database)
            let preferenceStore = ReaderPreferencesStore(database: database)
            let initial = try preferenceStore.initialize(sourceKeys: [a])
            savedVersion = initial.selectionVersion
            try library.rememberResolvedSources([(key: a, authority: "catalog")])
            let collection = try library.createCollection(named: "Minha coleção")
            collectionID = collection.id
            try library.addToCollection(id: collection.id, sourceKeys: [a, b], at: Date(timeIntervalSince1970: 12))
            let store = PublicationStore(database: database)
            let edition = StorageFixture.edition()
            let card = StorageFixture.card()
            cardID = card.id
            try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
            try library.setBookmarkMembership(cardID: cardID, listID: ReaderBookmarkList.defaultID,
                included: true, at: Date(timeIntervalSince1970: 13))
            let publishedBefore = try database.read {
                try Row.fetchAll($0, sql: "SELECT * FROM published_cards ORDER BY id").map { String(describing: $0) }
            }
            let bookmarkBefore = try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID)
            XCTAssertTrue(try library.reconcile(proof), "first verified transition must reach the write boundary")
            XCTAssertFalse(try library.reconcile(proof), "same evidence is idempotent")
            XCTAssertEqual(try library.sourceKeys(inCollection: collection.id), [a])
            XCTAssertEqual(try library.collections().first?.id, collection.id)
            XCTAssertEqual(try preferenceStore.load()?.sourceKeys, [a])
            XCTAssertEqual(try preferenceStore.load()?.selectionVersion, savedVersion)
            XCTAssertEqual(try library.sourceLinks()[a]?.currentKey, b)
            XCTAssertEqual(try library.sourceLinks()[a]?.anchorKey, a)
            XCTAssertEqual(try library.sourceLinks()[a]?.requestURL, endpoint)
            XCTAssertEqual(try library.sourceLinks()[b]?.anchorKey, a)
            let imported = ReaderImportEntry(id: b, title: "Minha cópia", requestURL: endpoint,
                categoryPath: [])
            let firstImport = try library.commitImport([imported], rejected: 0,
                collectionID: collection.id, at: Date(timeIntervalSince1970: 15))
            XCTAssertEqual(firstImport.insertedSources, 1)
            XCTAssertEqual(firstImport.alreadySelected, 1, "B maps to A, which was already selected")
            let secondImport = try library.commitImport([imported], rejected: 0,
                collectionID: collection.id, at: Date(timeIntervalSince1970: 16))
            XCTAssertEqual(secondImport.insertedSources, 0)
            XCTAssertEqual(secondImport.filedInCollection, 0)
            XCTAssertEqual(try library.sourceKeys(inCollection: collection.id), [a])
            XCTAssertEqual(try preferenceStore.load()?.sourceKeys, [a])
            XCTAssertEqual(try preferenceStore.load()?.selectionVersion, savedVersion)
            XCTAssertEqual(try library.importedSources().first?.requestURL, endpoint)
            // OPML parses the exact signed fetch URL into another canonical key. Only the
            // already-verified endpoint relation may attach it to the historical personal anchor.
            let roundTrip = ReaderImportEntry(id: "https://actual.example/feed",
                title: "Reimported", requestURL: endpoint, categoryPath: [])
            let replay = try library.commitImport([roundTrip], rejected: 0,
                collectionID: collection.id, at: Date(timeIntervalSince1970: 17))
            XCTAssertEqual(replay.insertedSources, 0)
            XCTAssertEqual(replay.alreadySelected, 1)
            XCTAssertEqual(replay.filedInCollection, 0)
            XCTAssertEqual(try library.importedSources().count, 1,
                "the OPML-recomputed key cannot become a third subscription")
            XCTAssertEqual(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), bookmarkBefore)
            XCTAssertEqual(try database.read {
                try Row.fetchAll($0, sql: "SELECT * FROM published_cards ORDER BY id")
                    .map { String(describing: $0) }
            }, publishedBefore, "not just counts: every published row must match")
        }
        let reopened = try RuntimeDatabase(location: location)
        let library = ReaderLibraryStore(database: reopened)
        XCTAssertEqual(try library.sourceLinks()[a]?.currentKey, b, "same on-disk personal database")
        XCTAssertEqual(try library.sourceKeys(inCollection: collectionID), [a])
        XCTAssertEqual(try ReaderPreferencesStore(database: reopened).load()?.sourceKeys, [a])
        XCTAssertEqual(try ReaderPreferencesStore(database: reopened).load()?.selectionVersion, savedVersion)
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), [cardID])
        XCTAssertFalse(try library.reconcile(proof))
    }

    func testPD10P0DUnprovenAmbiguousAndConflictingAliasesFailClosed() throws {
        let a = "https://old.example/rss", b = "https://new.example/rss"
        let e = "https://actual.example/feed"
        let old = try identityCatalog(revision: 5, sources: [(a, e)])
        let changed = try identityCatalog(revision: 6, sources: [(b, "https://other.example/feed")])
        XCTAssertThrowsError(try VerifiedSourceAlias(old: old, new: changed, oldKey: a, newKey: b),
            "unrelated endpoints may not be merged")
        let ambiguous = try identityCatalog(revision: 6, sources: [(b, e), ("https://other.example/rss", e)])
        XCTAssertThrowsError(try VerifiedSourceAlias(old: old, new: ambiguous, oldKey: a, newKey: b),
            "two destinations sharing one endpoint are ambiguous")
        let current = try identityCatalog(revision: 6, sources: [(b, e)])
        let proof = try VerifiedSourceAlias(old: old, new: current, oldKey: a, newKey: b)
        let database = try StorageFixture.database(self)
        let library = ReaderLibraryStore(database: database)
        try library.rememberResolvedSources([(key: a, authority: "catalog"),
            (key: b, authority: "reader")])
        let before = try library.sourceLinks()
        XCTAssertThrowsError(try library.reconcile(proof), "B already has a different personal anchor")
        XCTAssertEqual(try library.sourceLinks(), before, "no partial rows or guessed equivalence")
        let next = try identityCatalog(revision: 7, sources: [(a, e)])
        let inverse = try VerifiedSourceAlias(old: current, new: next, oldKey: b, newKey: a)
        // B was independently pinned: attempting the inverse cannot turn two owners into a cycle.
        XCTAssertThrowsError(try library.reconcile(inverse))
        XCTAssertEqual(try library.sourceLinks(), before)
        let incompatible = try identityCatalog(revision: 4, sources: [(b, e)])
        XCTAssertThrowsError(try VerifiedSourceAlias(old: old, new: incompatible, oldKey: a, newKey: b))
    }

    func testPD10P0DRollbackOnMembershipErrorKeepsAliasesAndCardsUnchanged() throws {
        let a = "https://old.example/rss", b = "https://new.example/rss", e = "https://actual.example/feed"
        let old = try identityCatalog(revision: 5, sources: [(a, e)])
        let new = try identityCatalog(revision: 6, sources: [(b, e)])
        let proof = try VerifiedSourceAlias(old: old, new: new, oldKey: a, newKey: b)
        let (database, publication, cards) = try seeded()
        let library = ReaderLibraryStore(database: database)
        try library.rememberResolvedSources([(key: a, authority: "catalog")])
        let collection = try library.createCollection(named: "Teste")
        try library.addToCollection(id: collection.id, sourceKeys: [b], at: Date())
        try library.setBookmarkMembership(cardID: cards[0].id, listID: ReaderBookmarkList.defaultID,
            included: true, at: Date())
        let before = try database.read {
            try Row.fetchAll($0, sql: "SELECT * FROM published_cards ORDER BY id")
                .map { String(describing: $0) }
        }
        try database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER refuse_identity_collection_move
                BEFORE DELETE ON reader_collection_memberships
                BEGIN SELECT RAISE(ABORT, 'fixture: refuse after alias writes'); END;
                """)
        }
        XCTAssertThrowsError(try library.reconcile(proof),
            "transaction must reach collection rewrite and fail after attempted alias insert")
        XCTAssertEqual(try library.sourceLinks()[a]?.currentKey, a)
        XCTAssertNil(try library.sourceLinks()[b])
        XCTAssertEqual(try library.sourceKeys(inCollection: collection.id), [b])
        XCTAssertEqual(try publication.card(id: cards[0].id), cards[0])
        XCTAssertEqual(try database.read {
            try Row.fetchAll($0, sql: "SELECT * FROM published_cards ORDER BY id")
                .map { String(describing: $0) }
        }, before)
        XCTAssertEqual(try library.bookmarkedCardIDs(inList: ReaderBookmarkList.defaultID), [cards[0].id])
    }


}
