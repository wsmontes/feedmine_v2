import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class PublicationWordExclusionTests: XCTestCase {
    private func setWords(_ prefs: ReaderPreferencesStore, _ words: [String],
        enabled: Bool = true, templates: [String] = []) throws {
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentFiltersEnabled = enabled
        settings.contentFilterRules = words
        settings.contentFilterTemplates = templates
        _ = try prefs.setSettings(settings)
    }

    func testChangedWordsRejectBothFirstWritersWithoutPartialHistory() throws {
        for initial in [false, true] {
            let db = try StorageFixture.database(self), store = PublicationStore(database: db)
            let prefs = ReaderPreferencesStore(database: db)
            _ = try prefs.initialize(sourceKeys: ["a"])
            let expected = try prefs.wordExclusionSnapshot(templates: [])
            try setWords(prefs, ["blocked"])
            let edition = StorageFixture.edition(), card = StorageFixture.card()
            let segment = StorageFixture.segment(edition, [card])
            XCTAssertThrowsError(try {
                if initial {
                    try store.createInitialEdition(edition, firstSegment: segment, cards: [card],
                        initialCheckpoint: .init(editionID: edition.id, cardID: card.id,
                            anchorPlacement: "top", updatedAt: Date()), expectedSourceExclusions: nil,
                        expectedWordExclusions: expected)
                } else {
                    try store.createEdition(edition, firstSegment: segment, cards: [card],
                        expectedSourceExclusions: nil, expectedWordExclusions: expected)
                }
            }()) { XCTAssertEqual($0 as? PublicationStoreError, .staleWordExclusions) }
            XCTAssertNil(try store.edition(id: edition.id))
            XCTAssertNil(try store.card(id: card.id))
            XCTAssertEqual(try db.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM feed_segments WHERE edition_id = ?",
                    arguments: [PersistenceValueCoding.uuid(edition.id.rawValue)])
            }, 0)
            XCTAssertNil(try SessionStore(database: db).checkpoint())
        }
    }

    func testChangedWordsRejectBothAppendWritersAndPreserveCheckpoint() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db)
        _ = try prefs.initialize(sourceKeys: ["a"])
        let expected = try prefs.wordExclusionSnapshot(templates: [])
        let edition = StorageFixture.edition(), first = StorageFixture.card()
        let segment = StorageFixture.segment(edition, [first])
        let checkpoint = SessionStore.CheckpointRecord(editionID: edition.id, cardID: first.id,
            anchorPlacement: "top", updatedAt: Date())
        try store.createInitialEdition(edition, firstSegment: segment, cards: [first],
            initialCheckpoint: checkpoint, expectedSourceExclusions: nil, expectedWordExclusions: expected)
        let frozenCheckpoint = try SessionStore(database: db).checkpoint()
        try setWords(prefs, ["new restriction"])
        let next = StorageFixture.card(), append = StorageFixture.segment(edition, [next], ordinal: 1)
        XCTAssertThrowsError(try store.appendSegment(append, cards: [next],
            expectedSourceExclusions: nil, expectedWordExclusions: expected)) {
            XCTAssertEqual($0 as? PublicationStoreError, .staleWordExclusions)
        }
        XCTAssertThrowsError(try store.appendSegment(append, cards: [next], expectingTailCardID: first.id,
            expectedSourceExclusions: nil, expectedWordExclusions: expected)) {
            XCTAssertEqual($0 as? PublicationStoreError, .staleWordExclusions)
        }
        XCTAssertEqual(try store.edition(id: edition.id), edition)
        XCTAssertEqual(try store.segments(editionID: edition.id), [segment])
        XCTAssertEqual(try store.card(id: first.id), first)
        XCTAssertNil(try store.card(id: next.id))
        XCTAssertEqual(try SessionStore(database: db).checkpoint(), frozenCheckpoint)
    }

    func testEquivalentTemplatesAllowPublicationWithoutContextualOverlap() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db)
        _ = try prefs.initialize(sourceKeys: ["a"])
        let catalog = [ReaderWordTemplateRules(key: "one", rules: [" BLOCKED "]),
            ReaderWordTemplateRules(key: "two", rules: ["blocked"])]
        try setWords(prefs, [], templates: ["one"])
        let expected = try prefs.wordExclusionSnapshot(templates: catalog)
        try setWords(prefs, [], templates: ["two"])
        let edition = StorageFixture.edition(), first = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [first]), cards: [first],
            expectedSourceExclusions: nil, expectedWordExclusions: expected)
        let next = StorageFixture.card(), append = StorageFixture.segment(edition, [next], ordinal: 1)
        try store.appendSegment(append, cards: [next], expectingTailCardID: first.id,
            expectedSourceExclusions: nil, expectedWordExclusions: expected)
        XCTAssertEqual(try store.segments(editionID: edition.id).count, 2)
        XCTAssertEqual(try prefs.load()?.settings.contentFilterTemplates, ["two"])
    }

    func testMasterOffKeepsOverlappingContextWordsButInvalidatesGlobalOnlyPolicy() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db)
        _ = try prefs.initialize(sourceKeys: ["a"])
        try setWords(prefs, ["blocked"])
        let global = try prefs.wordExclusionSnapshot(templates: [])
        let contextual = try prefs.wordExclusionSnapshot(templates: [],
            context: .init(isEnabled: true, rules: ["blocked"]))
        try setWords(prefs, ["blocked"], enabled: false, templates: ["missing"])
        let edition = StorageFixture.edition(), card = StorageFixture.card()
        let segment = StorageFixture.segment(edition, [card])
        XCTAssertThrowsError(try store.createEdition(edition, firstSegment: segment, cards: [card],
            expectedSourceExclusions: nil, expectedWordExclusions: global)) {
            XCTAssertEqual($0 as? PublicationStoreError, .staleWordExclusions)
        }
        XCTAssertNil(try store.edition(id: edition.id))
        try store.createEdition(edition, firstSegment: segment, cards: [card],
            expectedSourceExclusions: nil, expectedWordExclusions: contextual)
        XCTAssertEqual(try store.card(id: card.id), card)
        XCTAssertEqual(try prefs.load()?.settings.contentFilterTemplates, ["missing"])
    }

    func testMissingTemplateAndCorruptionNeverFailOpen() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db)
        let expected = try prefs.wordExclusionSnapshot(templates: [])
        XCTAssertEqual(expected.exclusions, .disabled, "absent preferences use standard settings")
        _ = try prefs.initialize(sourceKeys: ["a"])
        let edition = StorageFixture.edition(), card = StorageFixture.card()
        let segment = StorageFixture.segment(edition, [card])
        try setWords(prefs, [], templates: ["missing"])
        XCTAssertThrowsError(try prefs.wordExclusionSnapshot(templates: [])) {
            XCTAssertEqual($0 as? ReaderWordExclusionSnapshot.ResolutionError, .missingTemplates(["missing"]))
        }
        XCTAssertThrowsError(try store.createEdition(edition, firstSegment: segment, cards: [card],
            expectedSourceExclusions: nil, expectedWordExclusions: expected)) {
            XCTAssertEqual($0 as? ReaderWordExclusionSnapshot.ResolutionError, .missingTemplates(["missing"]))
        }
        try db.write { db in
            try db.execute(sql: "UPDATE reader_preferences SET settings_json = ? WHERE singleton_id = 1",
                arguments: [Data(#"{"contentFilterRules":"corrupt"}"#.utf8)])
        }
        XCTAssertThrowsError(try prefs.wordExclusionSnapshot(templates: []))
        XCTAssertThrowsError(try store.createEdition(edition, firstSegment: segment, cards: [card],
            expectedSourceExclusions: nil, expectedWordExclusions: expected))
        XCTAssertNil(try store.edition(id: edition.id))
        XCTAssertNil(try store.card(id: card.id))
    }
}
