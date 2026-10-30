import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication

final class PublicationOwnedHistoryTests: XCTestCase {
    private func withDatabase(_ body: (RuntimeDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(RuntimeDatabase(location: .init(directory: directory)))
    }
    private func publish(_ db: RuntimeDatabase, edition: FeedEdition, activation: SessionStore.BindingActivation) throws -> [PublishedCard] {
        let cards = try (0..<3).map { try RestoreFixture.card(index: $0) }
        let records = try PublicationPersistenceMapping.records(segment: RestoreFixture.segment(edition, cards: cards, ordinal: 0), cards: cards)
        try PublicationStore(database: db).createInitialEdition(PublicationPersistenceMapping.record(edition),
            firstSegment: records.0, cards: records.1,
            initialCheckpoint: .init(editionID: edition.id, cardID: cards[0].id, anchorPlacement: "top", updatedAt: edition.createdAt),
            expectedSourceExclusions: nil, bindingPublication: .init(activation: activation))
        return cards
    }
    func testOwnedHistoryRestoresAndSavesExactPositionAndRetainedHead() throws {
        try withDatabase { db in
            let edition = RestoreFixture.edition(), session = SessionStore(database: db)
            let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: edition.editorialRevision.contextKey)
            let active = try session.activateBinding(binding.id), cards = try publish(db, edition: edition, activation: active)
            let history = PublicationHistory(database: db, bindingActivation: active)
            let cursor = SessionCursor(editionID: edition.id, anchor: .init(cardID: cards[2].id, placement: .top),
                progress: try XCTUnwrap(CardTopOffset(topDelta: -31, height: 200)))
            try history.saveCursor(cursor, updatedAt: Date(timeIntervalSince1970: 800))
            XCTAssertEqual(try history.savedCursor(contextKey: edition.editorialRevision.contextKey), cursor)
            let restored = try XCTUnwrap(history.restore(backwardCapacity: 1, forwardCapacity: 0))
            XCTAssertEqual(restored.cursor, cursor)
            XCTAssertEqual(restored.position, .exact(cards[2].id))
            XCTAssertEqual(try history.restoreFromEditionStart(forwardCapacity: 0)?.window.cards, cards)
            try history.markSeen(editionID: edition.id, cardID: cards[2].id)
            XCTAssertEqual(try session.checkpoint(bindingID: binding.id)?.cardID, cards[2].id)
        }
    }
    func testRetiredHistoryCannotRestoreDrawSaveOrMarkAfterAnotherReaderOrReturn() throws {
        try withDatabase { db in
            let session = SessionStore(database: db), bindings = ReaderHistoryBindingStore(database: db)
            let a = RestoreFixture.edition(), ba = try bindings.resolve(logicalKey: a.editorialRevision.contextKey)
            let oldA = try session.activateBinding(ba.id), cardsA = try publish(db, edition: a, activation: oldA)
            let historyA = PublicationHistory(database: db, bindingActivation: oldA)
            let b = RestoreFixture.edition(context: .source(SourceID())), bb = try bindings.resolve(logicalKey: b.editorialRevision.contextKey)
            let activeB = try session.activateBinding(bb.id), cardsB = try publish(db, edition: b, activation: activeB)
            let pointB = try session.checkpoint()
            XCTAssertThrowsError(try historyA.restore(backwardCapacity: 0, forwardCapacity: 0))
            XCTAssertThrowsError(try historyA.savedCursor())
            XCTAssertThrowsError(try historyA.window(editionID: a.id, around: .init(cardID: cardsA[0].id, placement: .top), backwardCapacity: 0, forwardCapacity: 0))
            XCTAssertThrowsError(try historyA.saveCursor(.init(editionID: a.id, anchor: .init(cardID: cardsA[1].id, placement: .top)), updatedAt: Date()))
            XCTAssertThrowsError(try historyA.markSeen(editionID: b.id, cardID: cardsB[1].id))
            XCTAssertEqual(try session.checkpoint(), pointB)
            let currentA = try session.activateBinding(ba.id)
            XCTAssertThrowsError(try historyA.restore(backwardCapacity: 0, forwardCapacity: 0))
            let fresh = PublicationHistory(database: db, bindingActivation: currentA)
            XCTAssertEqual(try fresh.restore(backwardCapacity: 0, forwardCapacity: 0)?.edition.id, a.id)
            XCTAssertThrowsError(try fresh.restore(backwardCapacity: 0, forwardCapacity: 0, contextKey: b.editorialRevision.contextKey))
            XCTAssertThrowsError(try fresh.window(editionID: b.id, around: .init(cardID: cardsB[0].id, placement: .top), backwardCapacity: 0, forwardCapacity: 0))
        }
    }
    func testKnownEmptyBindingDoesNotBorrowThePreviousReader() throws {
        try withDatabase { db in
            let session = SessionStore(database: db), bindings = ReaderHistoryBindingStore(database: db)
            let a = RestoreFixture.edition(), ba = try bindings.resolve(logicalKey: a.editorialRevision.contextKey)
            let activeA = try session.activateBinding(ba.id)
            _ = try publish(db, edition: a, activation: activeA)
            let empty = try bindings.resolve(logicalKey: ContextKey(request: .source(SourceID())))
            let active = try session.activateBinding(empty.id)
            let history = PublicationHistory(database: db, bindingActivation: active)
            XCTAssertNil(try history.savedCursor())
            XCTAssertNil(try history.restore(backwardCapacity: 0, forwardCapacity: 0))
        }
    }
    func testOwnedArchivedAndUnknownAnchorsKeepOriginalStatementAndDropRelativeOffset() throws {
        for archived in [false, true] {
            try withDatabase { db in
                let edition = RestoreFixture.edition(), session = SessionStore(database: db)
                let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: edition.editorialRevision.contextKey)
                let first = try session.activateBinding(binding.id), cards = try publish(db, edition: edition, activation: first)
                let missing = archived ? cards[2].id : PublicationCardID()
                try session.clearActiveCheckpoint(bindingActivation: first, expectedEditionID: edition.id)
                try db.write { db in
                    try db.execute(sql: "UPDATE reader_history_checkpoints SET card_id = ?, anchor_top_delta = -31, anchor_height = 200 WHERE edition_id = ?",
                        arguments: [PersistenceValueCoding.uuid(missing.rawValue), PersistenceValueCoding.uuid(edition.id.rawValue)])
                    if archived {
                        try db.execute(sql: "INSERT INTO retired_published_cards SELECT * FROM published_cards WHERE id = ?",
                            arguments: [PersistenceValueCoding.uuid(missing.rawValue)])
                        try db.execute(sql: "INSERT INTO retired_feed_segments SELECT * FROM feed_segments WHERE edition_id = ?",
                            arguments: [PersistenceValueCoding.uuid(edition.id.rawValue)])
                        try db.execute(sql: "DELETE FROM published_cards WHERE id = ?",
                            arguments: [PersistenceValueCoding.uuid(missing.rawValue)])
                    }
                }
                let current = try session.activateBinding(binding.id)
                let original = try session.checkpoint(bindingActivation: current)
                XCTAssertEqual(try session.checkpoint(), original, "active owned statements remain readable without a live legacy card")
                let history = PublicationHistory(database: db, bindingActivation: current)
                let restored = try XCTUnwrap(history.restore(backwardCapacity: 2, forwardCapacity: 2))
                XCTAssertEqual(restored.position, archived
                    ? .nearestNeighbour(withdrawn: missing, landedOn: cards[1].id)
                    : .unknownCard(landedOn: cards[0].id))
                XCTAssertNil(restored.cursor.progress, "a substitute card must not inherit the lost card's offset")
                XCTAssertEqual(try session.checkpoint(bindingActivation: current), original,
                    "restoration does not rewrite the durable statement")
                try session.clearActiveCheckpoint(bindingActivation: current, expectedEditionID: edition.id)
                XCTAssertNil(try session.checkpoint())
                XCTAssertNil(try history.savedCursor(), "cleared active state does not fall back to retained history")
                XCTAssertEqual(try session.checkpoint(bindingID: binding.id), original)
            }
        }
    }

    func testLegacyFrozenKeyAndLogicalKeyRestoreTheSameOwnedReaderAfterGlobalWordsChange() throws {
        try withDatabase { db in
            let logical = ContextKey(request: .main)
            let frozen = ContextKey(request: .main, filter: ReaderFilter(exclusions: .init(isEnabled: true, rules: ["old-global"])))
            let original = RestoreFixture.edition(), r = original.editorialRevision
            let revision = EditorialRevision(id: r.id, contextKey: frozen, catalogGeneration: r.catalogGeneration,
                userSelectionVersion: r.userSelectionVersion, eligibilityPolicyVersion: r.eligibilityPolicyVersion,
                scoringPolicyVersion: r.scoringPolicyVersion, sequencingPolicyVersion: r.sequencingPolicyVersion,
                exposurePolicyVersion: r.exposurePolicyVersion, selectionSchemaVersion: r.selectionSchemaVersion)
            let edition = FeedEdition(id: original.id, editorialRevision: revision, publicationSchemaVersion: original.publicationSchemaVersion,
                selectionSeed: original.selectionSeed, createdAt: original.createdAt)
            let prefs = ReaderPreferencesStore(database: db)
            _ = try prefs.initialize(sourceKeys: ["a"])
            var settings = try XCTUnwrap(prefs.load()).settings
            settings.contentFilterRules = ["old-global"]
            _ = try prefs.setSettings(settings)
            let cards = try (0..<3).map { try RestoreFixture.card(index: $0) }
            let records = try PublicationPersistenceMapping.records(segment: RestoreFixture.segment(edition, cards: cards, ordinal: 0), cards: cards)
            try PublicationStore(database: db).createInitialEdition(PublicationPersistenceMapping.record(edition),
                firstSegment: records.0, cards: records.1,
                initialCheckpoint: .init(editionID: edition.id, cardID: cards[1].id, anchorPlacement: "top", updatedAt: edition.createdAt))
            let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: logical,
                adopting: .init(editionID: edition.id, publicationKey: frozen, evidence: .legacyWords(prefs.wordExclusionSnapshot(templates: []))))
            let active = try SessionStore(database: db).activateBinding(binding.id)
            let history = PublicationHistory(database: db, bindingActivation: active)
            settings.contentFilterRules = ["title"]
            _ = try prefs.setSettings(settings)
            let raw = try XCTUnwrap(history.restore(backwardCapacity: 1, forwardCapacity: 1, contextKey: logical))
            let legacy = try XCTUnwrap(history.restore(backwardCapacity: 1, forwardCapacity: 1, contextKey: frozen))
            XCTAssertEqual(raw, legacy)
            XCTAssertEqual(raw.window.cards, cards, "current global words never filter frozen history")
            XCTAssertEqual(raw.edition.editorialRevision.contextKey, frozen)
            let unrelated = ContextKey(request: .main, filter: ReaderFilter(exclusions: .init(isEnabled: true, rules: ["title"])))
            XCTAssertThrowsError(try history.savedCursor(contextKey: unrelated)) {
                XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding)
            }
        }
    }

    func testPreparedHistoryProjectsWithoutSeenOrViewportAuthorityUntilPromotion() throws {
        try withDatabase { db in
            let session = SessionStore(database: db), bindings = ReaderHistoryBindingStore(database: db)
            let a = RestoreFixture.edition(), ba = try bindings.resolve(logicalKey: a.editorialRevision.contextKey)
            let active = try session.activateBinding(ba.id)
            _ = try publish(db, edition: a, activation: active)
            let current = try session.checkpoint()
            let b = RestoreFixture.edition(context: .source(SourceID())), bb = try bindings.resolve(logicalKey: b.editorialRevision.contextKey)
            let preparation = try session.prepareBinding(bb.id), cards = try publish(db, edition: b, activation: preparation)
            let history = PublicationHistory(database: db, bindingActivation: preparation)
            XCTAssertEqual(try history.restore(backwardCapacity: 0, forwardCapacity: 2)?.edition.id, b.id)
            try history.markSeen(editionID: b.id, cardID: cards[1].id)
            XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM publication_card_usage WHERE card_id = ?",
                arguments: [cards[1].id.rawValue.uuidString.lowercased()]) }, 0)
            XCTAssertThrowsError(try history.saveCursor(.init(editionID: b.id,
                anchor: .init(cardID: cards[1].id, placement: .top)), updatedAt: Date()))
            XCTAssertEqual(try session.checkpoint(), current)
            try session.promotePreparedBinding(preparation)
            try history.markSeen(editionID: b.id, cardID: cards[1].id)
            XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM publication_card_usage WHERE card_id = ?",
                arguments: [cards[1].id.rawValue.uuidString.lowercased()]) }, 1)
            XCTAssertThrowsError(try PublicationHistory(database: db, bindingActivation: active).restore(backwardCapacity: 0, forwardCapacity: 0))
        }
    }

}
