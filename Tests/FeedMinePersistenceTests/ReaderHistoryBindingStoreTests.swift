import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class ReaderHistoryBindingStoreTests: XCTestCase {
    private func published(_ db: RuntimeDatabase, key: ContextKey) throws -> (PublicationStore.EditionRecord, PublicationStore.CardRecord) {
        let v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let edition = StorageFixture.edition(revision: revision), card = StorageFixture.card()
        try PublicationStore(database: db).createInitialEdition(edition,
            firstSegment: StorageFixture.segment(edition, [card]), cards: [card],
            initialCheckpoint: .init(editionID: edition.id, cardID: card.id, anchorPlacement: "top", updatedAt: Date()))
        try PublicationStore(database: db).toggleBookmark(cardID: card.id, at: Date())
        return (edition, card)
    }
    private func key(_ words: [String]) -> ContextKey {
        ContextKey(request: .main, filter: ReaderFilter(exclusions: .init(isEnabled: !words.isEmpty, rules: words)))
    }
    private func prefs(_ db: RuntimeDatabase, words: [String]) throws -> ReaderPreferencesStore {
        let prefs = ReaderPreferencesStore(database: db)
        _ = try prefs.initialize(sourceKeys: ["a"])
        var settings = try XCTUnwrap(prefs.load()).settings
        settings.contentFilterRules = words
        _ = try prefs.setSettings(settings)
        return prefs
    }

    func testFreshBindingIsStableAcrossConnectionsAndHasNoBorrowedEdition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let db = try RuntimeDatabase(location: .init(directory: directory))
        let store = ReaderHistoryBindingStore(database: db)
        let binding = try store.resolve(logicalKey: key([]))
        XCTAssertEqual(binding.logicalKey, key([]))
        XCTAssertNil(binding.activeEditionID)
        XCTAssertEqual(binding.runtimeNamespace, key([]).canonicalIdentity)
        let reopened = try RuntimeDatabase(location: .init(directory: directory))
        XCTAssertEqual(try ReaderHistoryBindingStore(database: reopened).resolve(logicalKey: key([])), binding)
    }

    func testExactAdoptionPreservesFrozenHistorySaveAndCheckpoint() throws {
        let db = try StorageFixture.database(self)
        let (edition, card) = try published(db, key: key(["own"]))
        let checkpoint = try SessionStore(database: db).checkpoint()
        let segments = try PublicationStore(database: db).segments(editionID: edition.id)
        let store = ReaderHistoryBindingStore(database: db)
        let adoption = ReaderHistoryBindingStore.Adoption(editionID: edition.id,
            publicationKey: key(["own"]), evidence: .exactContext)
        let binding = try store.resolve(logicalKey: key(["own"]), adopting: adoption)
        XCTAssertEqual(binding.activeEditionID, edition.id)
        XCTAssertEqual(try store.resolve(logicalKey: key(["own"]), adopting: adoption), binding)
        XCTAssertEqual(try PublicationStore(database: db).edition(id: edition.id), edition)
        XCTAssertEqual(try PublicationStore(database: db).card(id: card.id), card)
        XCTAssertEqual(try PublicationStore(database: db).segments(editionID: edition.id), segments)
        XCTAssertEqual(try SessionStore(database: db).checkpoint(), checkpoint)
        XCTAssertEqual(try PublicationStore(database: db).bookmarkedCardIDs(), [card.id])
    }

    func testLegacyAdoptionUsesKnownForwardUnionAndKeepsFrozenWords() throws {
        let db = try StorageFixture.database(self), logical = key(["own"]), frozen = key(["own", "global"])
        let prefs = try prefs(db, words: ["global"])
        let snapshot = try prefs.wordExclusionSnapshot(templates: [], context: logical.filter.exclusions)
        let (edition, card) = try published(db, key: frozen)
        let checkpoint = try SessionStore(database: db).checkpoint()
        let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: logical,
            adopting: .init(editionID: edition.id, publicationKey: frozen, evidence: .legacyWords(snapshot)))
        XCTAssertEqual(binding.logicalKey, logical)
        XCTAssertEqual(binding.runtimeNamespace, frozen.canonicalIdentity)
        XCTAssertEqual(binding.activeEditionID, edition.id)
        XCTAssertEqual(try PublicationStore(database: db).edition(id: edition.id), edition)
        XCTAssertEqual(try PublicationStore(database: db).card(id: card.id), card)
        XCTAssertEqual(try SessionStore(database: db).checkpoint(), checkpoint)
        XCTAssertEqual(try SessionStore(database: db).checkpoint(for: frozen), checkpoint)
        let evidence = try db.read { try Data.fetchOne($0,
            sql: "SELECT adoption_policy_json FROM reader_history_editions WHERE edition_id = ?",
            arguments: [PersistenceValueCoding.uuid(edition.id.rawValue)]) }
        let data = try XCTUnwrap(evidence)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let effective = try XCTUnwrap(json["effective"] as? [String: Any])
        XCTAssertEqual(effective["rules"] as? [String], ["global", "own"])
        _ = try self.prefs(db, words: ["changed-after-adoption"])
        let replay = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: logical,
            adopting: .init(editionID: edition.id, publicationKey: frozen, evidence: .legacyWords(snapshot)))
        XCTAssertEqual(replay, binding, "established ownership survives later global policy edits")
        XCTAssertEqual(try db.read { try Data.fetchOne($0,
            sql: "SELECT adoption_policy_json FROM reader_history_editions WHERE edition_id = ?",
            arguments: [PersistenceValueCoding.uuid(edition.id.rawValue)]) }, data)
    }

    func testUnknownWordOriginAndStalePolicyCannotClaimHistory() throws {
        let db = try StorageFixture.database(self), logical = key([]), frozen = key(["old-unknown"])
        let prefs = try prefs(db, words: ["current"])
        let (edition, _) = try published(db, key: frozen)
        let store = ReaderHistoryBindingStore(database: db)
        let snapshot = try prefs.wordExclusionSnapshot(templates: [])
        XCTAssertThrowsError(try store.resolve(logicalKey: logical,
            adopting: .init(editionID: edition.id, publicationKey: frozen, evidence: .legacyWords(snapshot)))) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .incompatibleAdoption)
        }
        XCTAssertNil(try store.binding(for: logical))
        // Use a compatible candidate, then change settings after capture: the transaction must recheck it.
        let currentFrozen = key(["current"])
        let current = StorageFixture.edition(revision: EditorialRevision(id: EditorialRevisionID(),
            contextKey: currentFrozen, catalogGeneration: .init(rawValue: 1), userSelectionVersion: .init(rawValue: 1),
            eligibilityPolicyVersion: .init(rawValue: 1), scoringPolicyVersion: .init(rawValue: 1),
            sequencingPolicyVersion: .init(rawValue: 1), exposurePolicyVersion: .init(rawValue: 1), selectionSchemaVersion: .init(rawValue: 1)))
        let card = StorageFixture.card()
        try PublicationStore(database: db).createEdition(current, firstSegment: StorageFixture.segment(current, [card]), cards: [card])
        _ = try self.prefs(db, words: ["changed"])
        XCTAssertThrowsError(try store.resolve(logicalKey: logical,
            adopting: .init(editionID: current.id, publicationKey: currentFrozen, evidence: .legacyWords(snapshot)))) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .staleAdoptionPolicy)
        }
        XCTAssertNil(try store.binding(for: logical))
    }

    func testLegacyUnionCollisionDoesNotShareEditionOrRuntimeNamespace() throws {
        let db = try StorageFixture.database(self), logical = key([]), frozen = key(["global"])
        let prefs = try prefs(db, words: ["global"])
        let (edition, _) = try published(db, key: frozen)
        let store = ReaderHistoryBindingStore(database: db)
        let owner = try store.resolve(logicalKey: logical, adopting: .init(editionID: edition.id,
            publicationKey: frozen, evidence: .legacyWords(prefs.wordExclusionSnapshot(templates: []))))
        XCTAssertThrowsError(try store.resolve(logicalKey: frozen, adopting: .init(editionID: edition.id,
            publicationKey: frozen, evidence: .exactContext))) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .editionAlreadyOwned)
        }
        XCTAssertNil(try store.binding(for: frozen), "failed adoption must roll back the new binding")
        let other = StorageFixture.edition(revision: edition.editorialRevision), otherCard = StorageFixture.card()
        try PublicationStore(database: db).createEdition(other,
            firstSegment: StorageFixture.segment(other, [otherCard]), cards: [otherCard])
        XCTAssertThrowsError(try store.resolve(logicalKey: frozen, adopting: .init(editionID: other.id,
            publicationKey: frozen, evidence: .exactContext))) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .runtimeNamespaceAlreadyOwned)
        }
        XCTAssertNil(try store.binding(for: frozen))
        let distinct = try store.resolve(logicalKey: frozen)
        XCTAssertNotEqual(distinct.id, owner.id)
        XCTAssertNotEqual(distinct.runtimeNamespace, owner.runtimeNamespace)
        XCTAssertNil(distinct.activeEditionID)
        XCTAssertEqual(try store.resolve(logicalKey: frozen), distinct)
        XCTAssertEqual(try store.binding(for: logical)?.activeEditionID, edition.id)
        XCTAssertThrowsError(try db.write { db in
            try db.execute(sql: "UPDATE reader_history_bindings SET active_edition_id = ? WHERE id = ?",
                arguments: [PersistenceValueCoding.uuid(edition.id.rawValue), PersistenceValueCoding.uuid(distinct.id)])
        }, "the database itself rejects an active Edition belonging to another binding")
        XCTAssertNil(try store.binding(for: frozen)?.activeEditionID)
    }

    func testMissingEditionAndActiveReplacementDoNotMutateOwnership() throws {
        let db = try StorageFixture.database(self), store = ReaderHistoryBindingStore(database: db)
        let logical = key([])
        XCTAssertThrowsError(try store.resolve(logicalKey: logical,
            adopting: .init(editionID: FeedEditionID(), publicationKey: logical, evidence: .exactContext))) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .missingEdition)
        }
        XCTAssertNil(try store.binding(for: logical))
        let (edition, _) = try published(db, key: logical)
        let owner = try store.resolve(logicalKey: logical, adopting: .init(editionID: edition.id,
            publicationKey: logical, evidence: .exactContext))
        let other = StorageFixture.edition(revision: edition.editorialRevision), card = StorageFixture.card()
        try PublicationStore(database: db).createEdition(other,
            firstSegment: StorageFixture.segment(other, [card]), cards: [card])
        XCTAssertThrowsError(try store.resolve(logicalKey: logical, adopting: .init(editionID: other.id,
            publicationKey: logical, evidence: .exactContext))) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .activeEditionConflict)
        }
        XCTAssertEqual(try store.binding(for: logical), owner)
    }
    func testExplicitLegacyPointUsesDurableCardEditionAndPreservesOriginalStatement() throws {
        let db = try StorageFixture.database(self), logical = key([])
        let (actual, card) = try published(db, key: logical)
        let other = StorageFixture.edition(revision: actual.editorialRevision), otherCard = StorageFixture.card()
        try PublicationStore(database: db).createEdition(other,
            firstSegment: StorageFixture.segment(other, [otherCard]), cards: [otherCard])
        try db.write { db in
            try db.execute(sql: "UPDATE session_checkpoint SET edition_id = ?, anchor_top_delta = 17, anchor_height = 240, updated_at = 1234",
                arguments: [PersistenceValueCoding.uuid(other.id.rawValue)])
        }
        let sessions = SessionStore(database: db), original = try XCTUnwrap(sessions.checkpoint())
        let store = ReaderHistoryBindingStore(database: db)
        let adoption = ReaderHistoryBindingStore.Adoption(editionID: actual.id, publicationKey: logical,
            evidence: .exactContext, checkpoint: original)
        let binding = try store.resolve(logicalKey: logical, adopting: adoption)
        let point = try XCTUnwrap(sessions.checkpoint(bindingID: binding.id))
        XCTAssertEqual(point.editionID, actual.id)
        XCTAssertEqual(point.cardID, card.id)
        XCTAssertEqual(point.updatedAt, original.updatedAt)
        XCTAssertEqual(point.anchorPlacement, original.anchorPlacement)
        XCTAssertEqual(point.topDelta, 17)
        XCTAssertEqual(point.cardHeight, 240)
        XCTAssertEqual(try sessions.checkpoint(), original, "adoption does not rewrite the source statement")
        let activation = try sessions.activateBinding(binding.id)
        let newer = SessionStore.CheckpointRecord(editionID: actual.id, cardID: card.id,
            anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 2000), topDelta: 20, cardHeight: 240)
        try sessions.saveCheckpoint(newer, bindingActivation: activation)
        XCTAssertEqual(try store.resolve(logicalKey: logical, adopting: adoption), binding)
        XCTAssertEqual(try sessions.checkpoint(bindingID: binding.id), newer, "replay cannot rewind an established reader")
    }

    func testExplicitLegacyPointRejectsStaleAndForeignCardEvidenceAtomically() throws {
        for stale in [false, true] {
            let db = try StorageFixture.database(self), logical = key([])
            let (actual, _) = try published(db, key: logical)
            let other = StorageFixture.edition(revision: actual.editorialRevision), otherCard = StorageFixture.card()
            try PublicationStore(database: db).createEdition(other,
                firstSegment: StorageFixture.segment(other, [otherCard]), cards: [otherCard])
            let sessions = SessionStore(database: db), original = try XCTUnwrap(sessions.checkpoint())
            if stale {
                try db.write { db in
                    try db.execute(sql: "UPDATE session_checkpoint SET updated_at = 9999")
                    try db.execute(sql: "UPDATE context_checkpoints SET updated_at = 9999")
                }
            }
            let before = try sessions.checkpoint(), store = ReaderHistoryBindingStore(database: db)
            XCTAssertThrowsError(try store.resolve(logicalKey: logical, adopting: .init(
                editionID: stale ? actual.id : other.id, publicationKey: logical,
                evidence: .exactContext, checkpoint: original))) {
                XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .incompatibleAdoption)
            }
            XCTAssertNil(try store.binding(for: logical))
            XCTAssertEqual(try sessions.checkpoint(), before)
            XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reader_history_editions") }, 0)
        }
    }

    func testExplicitLegacyPointCanUseRetainedContextWithoutChangingActiveReader() throws {
        let db = try StorageFixture.database(self), logical = key(["own"])
        let (actual, card) = try published(db, key: logical)
        let sessions = SessionStore(database: db)
        let point = SessionStore.CheckpointRecord(editionID: actual.id, cardID: card.id,
            anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 1200), topDelta: -12, cardHeight: 180)
        try sessions.saveCheckpoint(point)
        let v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: key(["other"]),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let other = StorageFixture.edition(revision: revision), otherCard = StorageFixture.card()
        try PublicationStore(database: db).createEdition(other,
            firstSegment: StorageFixture.segment(other, [otherCard]), cards: [otherCard])
        let active = SessionStore.CheckpointRecord(editionID: other.id, cardID: otherCard.id,
            anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: 1300))
        try sessions.saveCheckpoint(active)
        let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: logical,
            adopting: .init(editionID: actual.id, publicationKey: logical, evidence: .exactContext, checkpoint: point))
        XCTAssertEqual(try sessions.checkpoint(bindingID: binding.id), point)
        XCTAssertEqual(try sessions.checkpoint(), active)
    }

    func testExplicitLegacyPointCannotInventOffsetOrUnknownAnchor() throws {
        for unknown in [false, true] {
            let db = try StorageFixture.database(self), logical = key([])
            let (edition, card) = try published(db, key: logical)
            let sessions = SessionStore(database: db), original = try XCTUnwrap(sessions.checkpoint())
            let invented = SessionStore.CheckpointRecord(editionID: edition.id,
                cardID: unknown ? PublicationCardID() : card.id, anchorPlacement: original.anchorPlacement,
                updatedAt: original.updatedAt, topDelta: 9, cardHeight: 190)
            let store = ReaderHistoryBindingStore(database: db)
            XCTAssertThrowsError(try store.resolve(logicalKey: logical, adopting: .init(
                editionID: edition.id, publicationKey: logical, evidence: .exactContext, checkpoint: invented))) {
                XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .incompatibleAdoption)
            }
            XCTAssertNil(try store.binding(for: logical))
            XCTAssertEqual(try sessions.checkpoint(), original)
        }
    }

    func testExplicitLegacyAdoptionRetainsDamagedUnknownAndArchivedStatements() throws {
        for archived in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let location = RuntimeDatabaseLocation(directory: directory), db = try RuntimeDatabase(location: location)
            let logical = key([]), (edition, card) = try published(db, key: logical)
            let wrongEdition = StorageFixture.edition(revision: edition.editorialRevision), spareCard = StorageFixture.card()
            try PublicationStore(database: db).createEdition(wrongEdition,
                firstSegment: StorageFixture.segment(wrongEdition, [spareCard]), cards: [spareCard])
            // Reconstruct a pre-existing damaged legacy DB. Production never disables its FKs.
            var configuration = Configuration()
            configuration.foreignKeysEnabled = false
            let damagedWriter = try DatabaseQueue(path: location.databaseURL.path, configuration: configuration)
            let anchor = archived ? card.id : PublicationCardID()
            try damagedWriter.write { db in
                if archived {
                    try db.execute(sql: "INSERT INTO retired_published_cards SELECT * FROM published_cards WHERE id = ?",
                        arguments: [PersistenceValueCoding.uuid(card.id.rawValue)])
                    try db.execute(sql: "INSERT INTO retired_feed_segments SELECT * FROM feed_segments WHERE edition_id = ?",
                        arguments: [PersistenceValueCoding.uuid(edition.id.rawValue)])
                    try db.execute(sql: "DELETE FROM published_cards WHERE id = ?",
                        arguments: [PersistenceValueCoding.uuid(card.id.rawValue)])
                }
                try db.execute(sql: "UPDATE session_checkpoint SET card_id = ?, edition_id = ?, updated_at = 1234, anchor_top_delta = -14, anchor_height = 180",
                    arguments: [PersistenceValueCoding.uuid(anchor.rawValue),
                        PersistenceValueCoding.uuid((archived ? wrongEdition.id : edition.id).rawValue)])
            }
            let sessions = SessionStore(database: db), original = try XCTUnwrap(sessions.checkpoint())
            let binding = try ReaderHistoryBindingStore(database: db).resolve(logicalKey: logical,
                adopting: .init(editionID: edition.id, publicationKey: logical, evidence: .exactContext, checkpoint: original))
            let corrected = SessionStore.CheckpointRecord(editionID: edition.id, cardID: original.cardID,
                anchorPlacement: original.anchorPlacement, updatedAt: original.updatedAt,
                topDelta: original.topDelta, cardHeight: original.cardHeight)
            XCTAssertEqual(try sessions.checkpoint(bindingID: binding.id), corrected)
            XCTAssertEqual(try sessions.checkpoint(), original)
            let activation = try sessions.activateBinding(binding.id)
            XCTAssertEqual(try sessions.checkpoint(bindingActivation: activation), corrected)
            XCTAssertEqual(try sessions.checkpoint(), corrected)
        }
    }

}
