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

}
