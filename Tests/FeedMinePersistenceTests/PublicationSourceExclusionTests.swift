import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class PublicationSourceExclusionTests: XCTestCase {
    private func changePolicy(_ prefs: ReaderPreferencesStore, sourceID: SourceID,
        name: String = "Blocked", enabled: Bool = true) throws {
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentSourceExclusions = [.init(sourceID: sourceID, displayName: name)]
        settings.contentFiltersEnabled = enabled
        _ = try prefs.setSettings(settings)
    }

    func testStalePolicyRejectsBothFirstPublicationWritersWithoutPartialHistory() throws {
        for initial in [false, true] {
            let db = try StorageFixture.database(self), store = PublicationStore(database: db)
            let prefs = ReaderPreferencesStore(database: db)
            _ = try prefs.initialize(sourceKeys: ["a"])
            let expected = try prefs.sourceExclusionSnapshot()
            try changePolicy(prefs, sourceID: SourceID())
            let edition = StorageFixture.edition(), card = StorageFixture.card()
            let segment = StorageFixture.segment(edition, [card])
            XCTAssertThrowsError(try {
                if initial {
                    try store.createInitialEdition(edition, firstSegment: segment, cards: [card],
                        initialCheckpoint: .init(editionID: edition.id, cardID: card.id,
                            anchorPlacement: "top", updatedAt: Date()), expectedSourceExclusions: expected)
                } else {
                    try store.createEdition(edition, firstSegment: segment, cards: [card], expectedSourceExclusions: expected)
                }
            }()) { XCTAssertEqual($0 as? PublicationStoreError, .staleSourceExclusions) }
            XCTAssertNil(try store.edition(id: edition.id))
            XCTAssertNil(try store.card(id: card.id))
            XCTAssertNil(try SessionStore(database: db).checkpoint())
        }
    }

    func testStalePolicyRejectsBothAppendWritersAndPreservesPublishedValues() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db)
        _ = try prefs.initialize(sourceKeys: ["a"])
        let expected = try prefs.sourceExclusionSnapshot()
        let edition = StorageFixture.edition(), first = StorageFixture.card()
        let segment = StorageFixture.segment(edition, [first])
        try store.createEdition(edition, firstSegment: segment, cards: [first], expectedSourceExclusions: expected)
        try changePolicy(prefs, sourceID: SourceID())
        let next = StorageFixture.card(), append = StorageFixture.segment(edition, [next], ordinal: 1)
        XCTAssertThrowsError(try store.appendSegment(append, cards: [next], expectedSourceExclusions: expected)) {
            XCTAssertEqual($0 as? PublicationStoreError, .staleSourceExclusions)
        }
        XCTAssertThrowsError(try store.appendSegment(append, cards: [next], expectingTailCardID: first.id,
            expectedSourceExclusions: expected)) { XCTAssertEqual($0 as? PublicationStoreError, .staleSourceExclusions) }
        XCTAssertEqual(try store.segments(editionID: edition.id), [segment])
        XCTAssertEqual(try store.card(id: first.id), first)
        XCTAssertNil(try store.card(id: next.id))
    }

    func testRenamingDoesNotInvalidateButChangingTheMasterSwitchDoes() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db), source = SourceID()
        _ = try prefs.initialize(sourceKeys: ["a"])
        try changePolicy(prefs, sourceID: source)
        let expected = try prefs.sourceExclusionSnapshot()
        try changePolicy(prefs, sourceID: source, name: "Renamed")
        let edition = StorageFixture.edition(), first = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [first]), cards: [first],
            expectedSourceExclusions: expected)
        try changePolicy(prefs, sourceID: source, enabled: false)
        let next = StorageFixture.card(), append = StorageFixture.segment(edition, [next], ordinal: 1)
        XCTAssertThrowsError(try store.appendSegment(append, cards: [next], expectedSourceExclusions: expected)) {
            XCTAssertEqual($0 as? PublicationStoreError, .staleSourceExclusions)
        }
        try store.appendSegment(append, cards: [next], expectedSourceExclusions: prefs.sourceExclusionSnapshot())
        XCTAssertEqual(try store.segments(editionID: edition.id).count, 2)
        XCTAssertEqual(try prefs.load()?.settings.contentSourceExclusions.count, 1)
    }

    func testMissingPreferencesAreUnrestrictedButCorruptSettingsNeverFailOpen() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db)
        XCTAssertEqual(try prefs.sourceExclusionSnapshot(), .unrestricted)
        let edition = StorageFixture.edition(), card = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card],
            expectedSourceExclusions: .unrestricted)
        _ = try prefs.initialize(sourceKeys: ["a"])
        try db.write { db in
            try db.execute(sql: "UPDATE reader_preferences SET settings_json = ? WHERE singleton_id = 1",
                arguments: [Data(#"{"contentSourceExclusions":"corrupt"}"#.utf8)])
        }
        XCTAssertThrowsError(try prefs.sourceExclusionSnapshot())
        let next = StorageFixture.card(), append = StorageFixture.segment(edition, [next], ordinal: 1)
        XCTAssertThrowsError(try store.appendSegment(append, cards: [next], expectedSourceExclusions: .unrestricted))
        XCTAssertNil(try store.card(id: next.id))
    }
}
