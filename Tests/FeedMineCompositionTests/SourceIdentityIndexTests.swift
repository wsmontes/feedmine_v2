//
// File: SourceIdentityIndexTests.swift
// Module: FeedMineCompositionTests
//
// Responsibility:
// Pin the lookup that turns a card's frozen `SourceID` back into the reader's durable key, including the state a
// catalogue rename leaves behind: `reconcile` records the same source under two keys (`anchor_key`, which the cards
// published before the rename carry, and `current_key`, which the catalogue resolves now), so both ids must answer,
// and both must answer with the same key regardless of the order the rows are read in.
//
// The catalogues here are compiled on disk from the same shape the persistence tests use: two revisions, one
// endpoint, two keys — no network, no live source and no second identity mapping.
import Foundation
import GRDB
import XCTest
import FeedMineDomain
import FeedMinePersistence
@testable import FeedMineComposition

final class SourceIdentityIndexTests: XCTestCase {
    private let oldKey = "https://old.example/rss"
    private let newKey = "https://new.example/rss"
    private let endpoint = "https://actual.example/feed?token=keep"

    /// The reader's cards carry the id that was minted when they were published. After a rename there are two such
    /// ids for one source; both must land on the key the catalogue resolves today, and the answer must not depend on
    /// which row of the alias is consulted.
    func testAVerifiedAliasAnswersBothTheCardBeforeAndAfterTheRename() throws {
        let (links, proofWasWritten) = try reconciledLinks()
        XCTAssertTrue(proofWasWritten, "premise: the alias reached the write boundary")
        XCTAssertEqual(links.count, 2, "premise: one row per key of the verified alias: \(links.keys.sorted())")

        let beforeRename = LegacyCatalogImport.sourceID(forKey: oldKey)
        let afterRename = LegacyCatalogImport.sourceID(forKey: newKey)
        XCTAssertNotEqual(beforeRename, afterRename, "premise: the rename minted a different id")

        XCTAssertEqual(SourceIdentityIndex.key(for: beforeRename, links: links), newKey,
            "a card published before the rename opens the key the catalogue resolves now")
        XCTAssertEqual(SourceIdentityIndex.key(for: afterRename, links: links), newKey,
            "a card published after the rename opens the same key")

        // Order independence, stated per row rather than argued from one dictionary: every row of the alias answers
        // both ids with the same key, so no read order can change the result.
        for (filed, link) in links {
            let single = [filed: link]
            XCTAssertEqual(SourceIdentityIndex.key(for: beforeRename, links: single), newKey,
                "row filed under \(filed) answers the pre-rename card")
            XCTAssertEqual(SourceIdentityIndex.key(for: afterRename, links: single), newKey,
                "row filed under \(filed) answers the post-rename card")
        }
    }

    /// The absence the card path turns into its own message: an id no row minted has no key, and neither does an
    /// empty table.
    func testAnUnresolvedIDHasNoKey() throws {
        let (links, _) = try reconciledLinks()
        XCTAssertNil(SourceIdentityIndex.key(for: SourceID(rawValue: UUID()), links: links))
        XCTAssertNil(SourceIdentityIndex.key(for: LegacyCatalogImport.sourceID(forKey: "https://never.example/rss"),
            links: links))
        XCTAssertNil(SourceIdentityIndex.key(for: LegacyCatalogImport.sourceID(forKey: oldKey), links: [:]))
    }

    /// The reader's own key is a different namespace: the same text minted by the other derivation is not the same
    /// source, so a catalogue id can never answer a reader key (and the reverse).
    func testTheDerivationFollowsTheAuthorityTheRowStates() throws {
        let database = try libraryDatabase()
        let store = ReaderLibraryStore(database: database)
        try store.rememberResolvedSources([(key: newKey, authority: "reader")])
        let links = try store.sourceLinks()
        XCTAssertEqual(SourceIdentityIndex.key(for: ReaderSourceIdentity.sourceID(forKey: newKey), links: links),
            newKey, "the reader's authority is read as the reader's")
        XCTAssertNil(SourceIdentityIndex.key(for: LegacyCatalogImport.sourceID(forKey: newKey), links: links),
            "the same text minted by the catalogue derivation names nothing this row knows")
    }

    // MARK: - Fixtures

    /// One verified old→new alias in a real runtime database, read back through the owner that wrote it.
    private func reconciledLinks() throws -> ([String: ReaderLibraryStore.SourceLink], Bool) {
        let old = try catalogue(revision: 5, sources: [(oldKey, endpoint)])
        let new = try catalogue(revision: 6, sources: [(newKey, endpoint)])
        let proof = try VerifiedSourceAlias(old: old, new: new, oldKey: oldKey, newKey: newKey)
        let database = try libraryDatabase()
        let store = ReaderLibraryStore(database: database)
        try store.rememberResolvedSources([(key: oldKey, authority: "catalog")])
        let written = try store.reconcile(proof)
        return (try store.sourceLinks(), written)
    }

    private func libraryDatabase() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    /// A compiled fixture catalogue with the columns the reader and the alias verifier read.
    private func catalogue(revision: Int, sources: [(String, String)]) throws -> LegacyCatalogReader {
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
                    VALUES (?, ?, 'Renamed feed', ?, 'text', 1)
                    """, arguments: [index + 1, source.0, source.1])
            }
        }
        return try LegacyCatalogReader(catalogURL: url)
    }
}
