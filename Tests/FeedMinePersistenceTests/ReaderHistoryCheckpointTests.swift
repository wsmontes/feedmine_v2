import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class ReaderHistoryCheckpointTests: XCTestCase {
    private func key(_ words: [String] = []) -> ContextKey {
        ContextKey(request: .main, filter: ReaderFilter(exclusions: .init(isEnabled: !words.isEmpty, rules: words)))
    }
    private func edition(_ key: ContextKey) -> PublicationStore.EditionRecord {
        let v = PolicyVersion(rawValue: 1)
        return StorageFixture.edition(revision: EditorialRevision(id: EditorialRevisionID(), contextKey: key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1)))
    }
    private func point(_ edition: PublicationStore.EditionRecord, _ card: PublicationStore.CardRecord,
        placement: String = "top", time: Double = 10) -> SessionStore.CheckpointRecord {
        .init(editionID: edition.id, cardID: card.id, anchorPlacement: placement,
            updatedAt: Date(timeIntervalSince1970: time), topDelta: 12, cardHeight: 100)
    }

    func testFirstPublicationAttachesOwnershipAndCheckpointAtomically() throws {
        let db = try StorageFixture.database(self), history = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), store = PublicationStore(database: db)
        let binding = try history.resolve(logicalKey: key()), active = try session.activateBinding(binding.id)
        let e = edition(key()), card = StorageFixture.card(), checkpoint = point(e, card)
        try store.createInitialEdition(e, firstSegment: StorageFixture.segment(e, [card]), cards: [card],
            initialCheckpoint: checkpoint, expectedSourceExclusions: nil,
            bindingPublication: .init(activation: active))
        XCTAssertEqual(try history.binding(for: key())?.activeEditionID, e.id)
        XCTAssertEqual(try session.checkpoint(bindingID: binding.id), checkpoint)
        XCTAssertEqual(try session.checkpoint(), checkpoint)
        XCTAssertEqual(try session.checkpoint(for: key()), checkpoint)
        XCTAssertEqual(try store.edition(id: e.id), e)
    }

    func testLateInitialCheckpointFailureRollsBackEditionMembershipAndPointer() throws {
        let db = try StorageFixture.database(self), history = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), store = PublicationStore(database: db)
        let binding = try history.resolve(logicalKey: key()), active = try session.activateBinding(binding.id)
        let e = edition(key()), card = StorageFixture.card()
        XCTAssertThrowsError(try store.createInitialEdition(e, firstSegment: StorageFixture.segment(e, [card]), cards: [card],
            initialCheckpoint: point(e, card, placement: "invalid"), expectedSourceExclusions: nil,
            bindingPublication: .init(activation: active))) {
            XCTAssertEqual($0 as? SessionStoreError, .invalidPlacement)
        }
        XCTAssertNil(try store.edition(id: e.id))
        XCTAssertNil(try store.card(id: card.id))
        XCTAssertNil(try history.binding(for: key())?.activeEditionID)
        XCTAssertNil(try session.checkpoint(bindingID: binding.id))
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reader_history_editions") }, 0)
    }

    func testCollidingLegacyHistoryHasIndependentPositionsAndActivationTokens() throws {
        let db = try StorageFixture.database(self), history = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), store = PublicationStore(database: db)
        let prefs = ReaderPreferencesStore(database: db)
        _ = try prefs.initialize(sourceKeys: ["a"])
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentFilterRules = ["global"]
        _ = try prefs.setSettings(settings)
        let frozen = key(["global"]), a = edition(frozen), ca = StorageFixture.card()
        let pa = point(a, ca)
        try store.createInitialEdition(a, firstSegment: StorageFixture.segment(a, [ca]), cards: [ca], initialCheckpoint: pa)
        let ba = try history.resolve(logicalKey: key(), adopting: .init(editionID: a.id,
            publicationKey: frozen, evidence: .legacyWords(prefs.wordExclusionSnapshot(templates: []))))
        let firstA = try session.activateBinding(ba.id)
        XCTAssertEqual(try session.checkpoint(), pa)
        let bb = try history.resolve(logicalKey: frozen), activeB = try session.activateBinding(bb.id)
        XCTAssertNil(try session.checkpoint(), "B must not borrow A's old folded-key position")
        XCTAssertNil(try session.checkpoint(for: frozen), "known empty binding must not fall back to legacy A")
        let b = edition(frozen), cb = StorageFixture.card(), pb = point(b, cb, time: 20)
        try store.createInitialEdition(b, firstSegment: StorageFixture.segment(b, [cb]), cards: [cb],
            initialCheckpoint: pb, expectedSourceExclusions: nil, bindingPublication: .init(activation: activeB))
        XCTAssertThrowsError(try session.saveCheckpoint(point(a, ca, time: 99), bindingActivation: firstA)) {
            XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding)
        }
        XCTAssertThrowsError(try session.saveCheckpoint(pa), "nil legacy token cannot bypass active ownership")
        XCTAssertThrowsError(try session.clearActiveCheckpoint(), "an unscoped retired callback cannot clear B")
        XCTAssertEqual(try session.checkpoint(), pb)
        let nextA = try session.activateBinding(ba.id)
        XCTAssertNotEqual(nextA, firstA)
        XCTAssertEqual(try session.checkpoint(), pa)
        XCTAssertThrowsError(try session.saveCheckpoint(point(a, ca, time: 100), bindingActivation: firstA))
        let movedA = point(a, ca, placement: "center", time: 30)
        try session.saveCheckpoint(movedA, bindingActivation: nextA)
        XCTAssertEqual(try session.checkpoint(bindingID: ba.id), movedA)
        XCTAssertEqual(try session.checkpoint(bindingID: bb.id), pb)
        XCTAssertEqual(try db.read { try Double.fetchOne($0,
            sql: "SELECT updated_at FROM context_checkpoints WHERE context_identity = ?",
            arguments: [frozen.canonicalIdentity]) }, pa.updatedAt.timeIntervalSince1970,
            "owned writes retain the original legacy checkpoint instead of overwriting a colliding key")
    }

    func testAppendRequiresCurrentOwnedEditionAndLiveActivation() throws {
        let db = try StorageFixture.database(self), history = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), store = PublicationStore(database: db)
        let binding = try history.resolve(logicalKey: key()), old = try session.activateBinding(binding.id)
        let e = edition(key()), c = StorageFixture.card()
        try store.createInitialEdition(e, firstSegment: StorageFixture.segment(e, [c]), cards: [c],
            initialCheckpoint: point(e, c), expectedSourceExclusions: nil, bindingPublication: .init(activation: old))
        let current = try session.activateBinding(binding.id)
        let next = StorageFixture.card(), segment = StorageFixture.segment(e, [next], ordinal: 1)
        XCTAssertThrowsError(try store.appendSegment(segment, cards: [next], expectedSourceExclusions: nil,
            bindingActivation: old)) { XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding) }
        XCTAssertThrowsError(try store.appendSegment(segment, cards: [next]))
        XCTAssertNil(try store.card(id: next.id))
        try store.appendSegment(segment, cards: [next], expectingTailCardID: c.id,
            expectedSourceExclusions: nil, bindingActivation: current)
        XCTAssertEqual(try store.segments(editionID: e.id).count, 2)
        XCTAssertEqual(try session.checkpoint()?.cardID, c.id)
    }
    func testRevisionRolloverChecksExpectedEditionAndRetainsPreviousPosition() throws {
        let db = try StorageFixture.database(self), history = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), store = PublicationStore(database: db)
        let binding = try history.resolve(logicalKey: key()), active = try session.activateBinding(binding.id)
        let a = edition(key()), ca = StorageFixture.card(), pa = point(a, ca)
        try store.createInitialEdition(a, firstSegment: StorageFixture.segment(a, [ca]), cards: [ca],
            initialCheckpoint: pa, expectedSourceExclusions: nil, bindingPublication: .init(activation: active))
        try session.clearActiveCheckpoint(bindingActivation: active, expectedEditionID: a.id)
        let b = edition(key()), cb = StorageFixture.card(), pb = point(b, cb, time: 20)
        XCTAssertThrowsError(try store.createInitialEdition(b, firstSegment: StorageFixture.segment(b, [cb]), cards: [cb],
            initialCheckpoint: pb, expectedSourceExclusions: nil, bindingPublication: .init(activation: active))) {
            XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding)
        }
        XCTAssertNil(try store.edition(id: b.id))
        XCTAssertNil(try store.card(id: cb.id))
        XCTAssertEqual(try session.checkpoint(bindingID: binding.id), pa)
        try store.createInitialEdition(b, firstSegment: StorageFixture.segment(b, [cb]), cards: [cb],
            initialCheckpoint: pb, expectedSourceExclusions: nil,
            bindingPublication: .init(activation: active, expectedActiveEditionID: a.id))
        XCTAssertEqual(try session.checkpoint(), pb)
        XCTAssertEqual(try history.binding(for: key())?.activeEditionID, b.id)
        XCTAssertThrowsError(try session.clearActiveCheckpoint(bindingActivation: active),
            "a delayed A clear must not erase B after same-binding rollover")
        XCTAssertEqual(try session.checkpoint(), pb)
        XCTAssertThrowsError(try session.clearActiveCheckpoint(bindingActivation: active, expectedEditionID: a.id)) {
            XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding)
        }
        XCTAssertEqual(try session.checkpoint(), pb)
        XCTAssertThrowsError(try session.saveCheckpoint(pa, bindingActivation: active),
            "the same activation cannot write a retired Edition after rollover")
        XCTAssertEqual(try db.read { try String.fetchOne($0,
            sql: "SELECT card_id FROM reader_history_checkpoints WHERE binding_id = ? AND edition_id = ?",
            arguments: [PersistenceValueCoding.uuid(binding.id), PersistenceValueCoding.uuid(a.id.rawValue)]) },
            PersistenceValueCoding.uuid(ca.id.rawValue))
        try session.clearActiveCheckpoint(bindingActivation: active, expectedEditionID: b.id)
        XCTAssertNil(try session.checkpoint(), "the current Edition can still clear its own singleton")
        XCTAssertEqual(try session.checkpoint(bindingID: binding.id), pb,
            "clearing the active singleton preserves the owned historical position")
    }

    func testActivationRepairsEditionColumnOnlyInsideItsEstablishedOwner() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), store = PublicationStore(database: db)
        let binding = try bindings.resolve(logicalKey: key()), active = try session.activateBinding(binding.id)
        let a = edition(key()), ca = StorageFixture.card()
        try store.createInitialEdition(a, firstSegment: StorageFixture.segment(a, [ca]), cards: [ca],
            initialCheckpoint: point(a, ca), expectedSourceExclusions: nil, bindingPublication: .init(activation: active))
        try session.clearActiveCheckpoint(bindingActivation: active, expectedEditionID: a.id)
        let b = edition(key()), cb = StorageFixture.card()
        try store.createInitialEdition(b, firstSegment: StorageFixture.segment(b, [cb]), cards: [cb],
            initialCheckpoint: point(b, cb, time: 20), expectedSourceExclusions: nil,
            bindingPublication: .init(activation: active, expectedActiveEditionID: a.id))
        try db.write { db in
            try db.execute(sql: "UPDATE reader_history_checkpoints SET card_id = ? WHERE binding_id = ? AND edition_id = ?",
                arguments: [PersistenceValueCoding.uuid(ca.id.rawValue), PersistenceValueCoding.uuid(binding.id), PersistenceValueCoding.uuid(b.id.rawValue)])
            try db.execute(sql: "UPDATE session_checkpoint SET card_id = ? WHERE edition_id = ?",
                arguments: [PersistenceValueCoding.uuid(ca.id.rawValue), PersistenceValueCoding.uuid(b.id.rawValue)])
        }
        let repaired = try session.activateBinding(binding.id)
        XCTAssertEqual(try bindings.binding(for: key())?.activeEditionID, a.id)
        let saved = try XCTUnwrap(session.checkpoint(bindingActivation: repaired))
        XCTAssertEqual(saved.editionID, a.id)
        XCTAssertEqual(saved.cardID, ca.id)
        XCTAssertEqual(saved.updatedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(saved.topDelta, 12)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reader_history_checkpoints") }, 2)
    }

    func testCrossOwnerCardInCheckpointRejectsActivationWithoutRetiringCurrentReader() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), store = PublicationStore(database: db)
        let unowned = edition(key()), unownedCard = StorageFixture.card()
        try store.createEdition(unowned, firstSegment: StorageFixture.segment(unowned, [unownedCard]), cards: [unownedCard])
        let ba = try bindings.resolve(logicalKey: key()), activeA = try session.activateBinding(ba.id)
        let a = edition(key()), ca = StorageFixture.card()
        try store.createInitialEdition(a, firstSegment: StorageFixture.segment(a, [ca]), cards: [ca],
            initialCheckpoint: point(a, ca), expectedSourceExclusions: nil, bindingPublication: .init(activation: activeA))
        let otherKey = ContextKey(request: .source(SourceID()))
        let bb = try bindings.resolve(logicalKey: otherKey), activeB = try session.activateBinding(bb.id)
        let b = edition(otherKey), cb = StorageFixture.card(), pb = point(b, cb, time: 20)
        try store.createInitialEdition(b, firstSegment: StorageFixture.segment(b, [cb]), cards: [cb],
            initialCheckpoint: pb, expectedSourceExclusions: nil, bindingPublication: .init(activation: activeB))
        try db.write { db in
            try db.execute(sql: "UPDATE reader_history_checkpoints SET card_id = ? WHERE binding_id = ?",
                arguments: [PersistenceValueCoding.uuid(cb.id.rawValue), PersistenceValueCoding.uuid(ba.id)])
        }
        XCTAssertThrowsError(try session.activateBinding(ba.id))
        XCTAssertEqual(try session.checkpoint(bindingActivation: activeB), pb)
        try session.saveCheckpoint(pb, bindingActivation: activeB)
        XCTAssertEqual(try bindings.binding(for: key())?.activeEditionID, a.id)
        try db.write { db in
            try db.execute(sql: "UPDATE reader_history_checkpoints SET card_id = ? WHERE binding_id = ?",
                arguments: [PersistenceValueCoding.uuid(unownedCard.id.rawValue), PersistenceValueCoding.uuid(ba.id)])
        }
        XCTAssertThrowsError(try session.activateBinding(ba.id), "matching context text never authorizes an unowned Edition")
        XCTAssertEqual(try session.checkpoint(bindingActivation: activeB), pb)
        XCTAssertEqual(try db.read { try Int.fetchOne($0,
            sql: "SELECT count(*) FROM reader_history_editions WHERE edition_id = ?",
            arguments: [PersistenceValueCoding.uuid(unowned.id.rawValue)]) }, 0)
    }

    func testActivePositionMigrationPreservesPresentAndClearedOwnedStatements() throws {
        for cleared in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let location = RuntimeDatabaseLocation(directory: directory)
            let bindingID: UUID, active: SessionStore.BindingActivation, saved: SessionStore.CheckpointRecord
            do {
                let db = try RuntimeDatabase(location: location), session = SessionStore(database: db)
                let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: key())
                bindingID = binding.id
                active = try session.activateBinding(binding.id)
                let e = edition(key()), c = StorageFixture.card()
                saved = point(e, c)
                try PublicationStore(database: db).createInitialEdition(e,
                    firstSegment: StorageFixture.segment(e, [c]), cards: [c], initialCheckpoint: saved,
                    expectedSourceExclusions: nil, bindingPublication: .init(activation: active))
                if cleared { try session.clearActiveCheckpoint(bindingActivation: active, expectedEditionID: e.id) }
                // Reconstruct the immediately preceding schema only in this disposable fixture.
                try db.write { db in
                    try db.execute(sql: "ALTER TABLE session_reader_binding DROP COLUMN checkpoint_present")
                    try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'reader-history-active-position-v1'")
                }
            }
            let reopened = try RuntimeDatabase(location: location), session = SessionStore(database: reopened)
            XCTAssertEqual(try session.checkpoint(), cleared ? nil : saved)
            XCTAssertEqual(try session.checkpoint(bindingActivation: active), cleared ? nil : saved)
            XCTAssertEqual(try session.checkpoint(bindingID: bindingID), saved,
                "the migration must retain the Edition's position even when it is not active")
            XCTAssertEqual(try reopened.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }, "ok")
            XCTAssertEqual(try reopened.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check").count }, 0)
        }
    }

}
