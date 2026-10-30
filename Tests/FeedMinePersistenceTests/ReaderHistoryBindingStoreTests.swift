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

    func testLegacySingletonDoesNotOverwriteSavedLocalPositionWhenAnotherChoiceIsPromoted() throws {
        for activation in ["prepared", "binding", "context"] {
            let db = try StorageFixture.database(self), raw = key([]), frozen = key(["old"])
            _ = try prefs(db, words: [])
            let (edition, card) = try published(db, key: frozen)
            let sessions = SessionStore(database: db), store = ReaderHistoryBindingStore(database: db)
            let original = try XCTUnwrap(sessions.checkpoint())
            let local = SessionStore.CheckpointRecord(editionID: edition.id, cardID: card.id,
                anchorPlacement: "center", updatedAt: original.updatedAt.addingTimeInterval(10), topDelta: -15, cardHeight: 220)
            let previous = try store.chooseRecoveryCriteria(frozen,
                adopting: .init(editionID: edition.id, publicationKey: frozen, evidence: .exactContext, checkpoint: original),
                preservingActiveCheckpoint: original, expectedContext: raw, selectedPosition: local)
            // Activation may fail after a durable choice; selecting current criteria next must keep that saved point.
            let current = try store.chooseRecoveryCriteria(raw, preservingActiveCheckpoint: original, expectedContext: frozen)
            switch activation {
            case "prepared":
                let prepared = try sessions.prepareBinding(current.id)
                try sessions.promotePreparedBinding(prepared, expectedLegacyCheckpoint: original)
            case "binding": _ = try sessions.activateBinding(current.id)
            default: try sessions.activateContext(raw)
            }
            XCTAssertEqual(try sessions.checkpoint(bindingID: previous.id), local, activation)
            XCTAssertNil(try sessions.checkpoint())
        }
    }

    func testMisfiledLegacySingletonCannotOverwriteAnotherEditionsOwnedPosition() throws {
        for activation in ["prepared", "binding", "context"] {
            let db = try StorageFixture.database(self), store = ReaderHistoryBindingStore(database: db)
            let sessions = SessionStore(database: db), logical = key(["owned"])
            let (owned, _) = try published(db, key: logical)
            let binding = try store.resolve(logicalKey: logical, adopting: .init(editionID: owned.id,
                publicationKey: logical, evidence: .exactContext))
            let saved = try XCTUnwrap(sessions.checkpoint(bindingID: binding.id))
            let unowned = StorageFixture.edition(revision: owned.editorialRevision), card = StorageFixture.card()
            try PublicationStore(database: db).createEdition(unowned,
                firstSegment: StorageFixture.segment(unowned, [card]), cards: [card])
            try db.write { try $0.execute(sql: "UPDATE session_checkpoint SET card_id = ?, updated_at = 1234",
                arguments: [PersistenceValueCoding.uuid(card.id.rawValue)]) }
            let original = try XCTUnwrap(sessions.checkpoint())
            let current = try store.resolve(logicalKey: key([]))
            switch activation {
            case "prepared":
                let prepared = try sessions.prepareBinding(current.id)
                try sessions.promotePreparedBinding(prepared, expectedLegacyCheckpoint: original)
            case "binding": _ = try sessions.activateBinding(current.id)
            default: try sessions.activateContext(key([]))
            }
            XCTAssertEqual(try sessions.checkpoint(bindingID: binding.id), saved, activation)
            let legacy = try XCTUnwrap(store.retainedReadings().first { $0.edition.id == unowned.id })
            XCTAssertNil(legacy.owner)
            XCTAssertTrue(legacy.checkpoints.contains { $0.point == original })
        }
    }

    func testRecoveryChoiceCarriesExplicitLocalPositionWithoutReplacingOriginalValidationEvidence() throws {
        let db = try StorageFixture.database(self), raw = key([]), frozen = key(["old"])
        _ = try prefs(db, words: [])
        let (edition, card) = try published(db, key: frozen)
        let sessions = SessionStore(database: db), store = ReaderHistoryBindingStore(database: db)
        let original = try XCTUnwrap(sessions.checkpoint())
        let local = SessionStore.CheckpointRecord(editionID: edition.id, cardID: card.id,
            anchorPlacement: "center", updatedAt: original.updatedAt.addingTimeInterval(10), topDelta: -15, cardHeight: 220)
        let binding = try store.chooseRecoveryCriteria(frozen,
            adopting: .init(editionID: edition.id, publicationKey: frozen, evidence: .exactContext, checkpoint: original),
            preservingActiveCheckpoint: original, expectedContext: raw, selectedPosition: local)
        XCTAssertEqual(try sessions.checkpoint(bindingID: binding.id), local)
        XCTAssertEqual(try sessions.checkpoint(), original, "the original remains the promotion fence until cutover")
        let prepared = try sessions.prepareBinding(binding.id)
        try sessions.promotePreparedBinding(prepared, expectedLegacyCheckpoint: original)
        XCTAssertEqual(try sessions.checkpoint(), local)
    }

    func testRetainedReadingsInventoryIncludesOwnedAndUnownedSiblingsWithoutASingletonOrAuthorityChanges() throws {
        let db = try StorageFixture.database(self), frozen = key(["old"])
        let preferences = try prefs(db, words: [])
        var settings = try XCTUnwrap(preferences.load()).settings
        settings.contentFilterTemplates = ["unresolved-retained-reading-template"]
        _ = try preferences.setSettings(settings)
        XCTAssertThrowsError(try preferences.wordExclusionSnapshot(templates: []),
            "unresolved current publication policy must not prevent inspection of frozen readings")
        let (a, _) = try published(db, key: frozen)
        let b = StorageFixture.edition(revision: a.editorialRevision), card = StorageFixture.card()
        try PublicationStore(database: db).createEdition(b, firstSegment: StorageFixture.segment(b, [card]), cards: [card])
        let sessions = SessionStore(database: db), store = ReaderHistoryBindingStore(database: db)
        let aPoint = try XCTUnwrap(sessions.checkpoint())
        let bPoint = SessionStore.CheckpointRecord(editionID: b.id, cardID: card.id,
            anchorPlacement: "center", updatedAt: aPoint.updatedAt.addingTimeInterval(-10))
        try db.write { try $0.execute(sql: "UPDATE context_checkpoints SET edition_id = ?, card_id = ?, anchor_placement = ?, updated_at = ?",
            arguments: [PersistenceValueCoding.uuid(b.id.rawValue), PersistenceValueCoding.uuid(card.id.rawValue),
                bPoint.anchorPlacement, bPoint.updatedAt.timeIntervalSince1970]) }
        let empty = try store.resolve(logicalKey: key([]))
        _ = try sessions.activateBinding(empty.id)
        XCTAssertNil(try sessions.checkpoint())
        let unowned = try store.retainedReadings()
        XCTAssertEqual(Set(unowned.map { $0.edition.id }), [a.id, b.id])
        XCTAssertTrue(unowned.allSatisfy { $0.owner == nil && !$0.isSelectedPreparation })
        XCTAssertEqual(unowned.first { $0.edition.id == a.id }?.checkpoints.map(\.point), [aPoint])
        XCTAssertEqual(unowned.first { $0.edition.id == b.id }?.checkpoints.map(\.point), [bPoint])
        XCTAssertTrue(unowned.flatMap(\.checkpoints).allSatisfy { !$0.isActive })
        XCTAssertEqual(try store.retainedReadings(), unowned, "inventory order and values are stable without choosing newest")
        let owner = try store.resolve(logicalKey: frozen, adopting: .init(editionID: a.id,
            publicationKey: frozen, evidence: .exactContext, checkpoint: aPoint))
        let prepared = try sessions.prepareBinding(owner.id)
        let hidden = try store.retainedReadings()
        XCTAssertEqual(hidden.first { $0.edition.id == a.id }?.owner, owner)
        XCTAssertEqual(hidden.first { $0.edition.id == a.id }?.isSelectedPreparation, true)
        XCTAssertTrue(hidden.flatMap(\.checkpoints).allSatisfy { !$0.isActive },
            "a hidden prepared history is not the displayed reader")
        XCTAssertTrue(try sessions.isPreparedBinding(prepared), "reading inventory never revokes preparation")
        try sessions.promotePreparedBinding(prepared)
        let current = try store.retainedReadings()
        XCTAssertEqual(current.flatMap(\.checkpoints).filter(\.isActive).map(\.point), [aPoint])
        XCTAssertNil(try store.owner(ofEditionID: b.id))
        XCTAssertEqual(try sessions.checkpoint(bindingActivation: prepared), aPoint)
        let moved = SessionStore.CheckpointRecord(editionID: a.id, cardID: aPoint.cardID,
            anchorPlacement: "center", updatedAt: aPoint.updatedAt.addingTimeInterval(20))
        try sessions.saveCheckpoint(moved, bindingActivation: prepared)
        XCTAssertEqual(try store.retainedReadings().first { $0.edition.id == a.id }?.checkpoints.map(\.point), [moved, aPoint],
            "active and original statements remain separate, without replacing the original by latest")
        try sessions.clearActiveCheckpoint(bindingActivation: prepared, expectedEditionID: a.id)
        let cleared = try store.retainedReadings()
        XCTAssertTrue(cleared.flatMap(\.checkpoints).allSatisfy { !$0.isActive })
        XCTAssertEqual(cleared.first { $0.edition.id == a.id }?.checkpoints.map(\.point), [moved, aPoint])
        XCTAssertNil(try sessions.checkpoint())
    }

    func testRetainedCardAuthoritativeEvidenceSurvivesUnknownCardAndRepeatedPreservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let location = RuntimeDatabaseLocation(directory: directory), db = try RuntimeDatabase(location: location)
        let raw = key([]), frozen = key(["old"]), preferences = try prefs(db, words: [])
        let (actual, card) = try published(db, key: frozen)
        let wrong = StorageFixture.edition(revision: actual.editorialRevision), spare = StorageFixture.card()
        try PublicationStore(database: db).createEdition(wrong, firstSegment: StorageFixture.segment(wrong, [spare]), cards: [spare])
        try db.write { db in
            for table in ["session_checkpoint", "context_checkpoints"] {
                try db.execute(sql: "UPDATE \(table) SET edition_id = ?, anchor_top_delta = -14, anchor_height = 180",
                    arguments: [PersistenceValueCoding.uuid(wrong.id.rawValue)])
            }
        }
        let original = try XCTUnwrap(SessionStore(database: db).checkpoint()), store = ReaderHistoryBindingStore(database: db)
        let current = try store.chooseRecoveryCriteria(raw, preservingActiveCheckpoint: original, expectedContext: raw)
        _ = try SessionStore(database: db).activateBinding(current.id)
        // Reconstruct a legacy card which has become unknown; production never disables FKs.
        var configuration = Configuration()
        configuration.foreignKeysEnabled = false
        let damaged = try DatabaseQueue(path: location.databaseURL.path, configuration: configuration)
        try damaged.write { try $0.execute(sql: "DELETE FROM published_cards WHERE id = ?",
            arguments: [PersistenceValueCoding.uuid(card.id.rawValue)]) }
        let inventory = try store.legacyCandidates(logicalKey: frozen,
            wordExclusions: preferences.wordExclusionSnapshot(templates: [], context: frozen.filter.exclusions))
        XCTAssertEqual(inventory.first { $0.edition.id == actual.id }?.checkpoints.map(\.point), [original])
        let adopted = try store.resolve(logicalKey: frozen, adopting: .init(editionID: actual.id,
            publicationKey: frozen, evidence: .exactContext, checkpoint: original))
        let corrected = try XCTUnwrap(SessionStore(database: db).checkpoint(bindingID: adopted.id))
        XCTAssertEqual(corrected.editionID, actual.id)
        XCTAssertEqual(corrected.cardID, original.cardID)
        XCTAssertEqual(corrected.updatedAt, original.updatedAt)
        XCTAssertEqual(corrected.topDelta, original.topDelta)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reader_history_legacy_checkpoints") }, 1,
            "an unknown card cannot acquire a contradictory fallback Edition on repeated preservation")
    }

    func testChoosingCurrentCriteriaRetainsDistinctActiveAndContextLegacyStatements() throws {
        for mode in 0..<4 {
            let db = try StorageFixture.database(self), raw = key([]), frozen = key(["legacy"])
            let preferences = try prefs(db, words: [])
            let (a, _) = try published(db, key: frozen)
            let b = StorageFixture.edition(revision: a.editorialRevision), card = StorageFixture.card()
            try PublicationStore(database: db).createEdition(b, firstSegment: StorageFixture.segment(b, [card]), cards: [card])
            let original = try XCTUnwrap(SessionStore(database: db).checkpoint())
            let retained = SessionStore.CheckpointRecord(editionID: b.id, cardID: card.id,
                anchorPlacement: "center", updatedAt: original.updatedAt.addingTimeInterval(-10))
            // Historical singleton/context statements may differ; preserve both without a newest guess.
            try db.write { db in
                try db.execute(sql: "UPDATE context_checkpoints SET edition_id = ?, card_id = ?, anchor_placement = ?, updated_at = ?",
                    arguments: [PersistenceValueCoding.uuid(b.id.rawValue), PersistenceValueCoding.uuid(card.id.rawValue),
                        retained.anchorPlacement, retained.updatedAt.timeIntervalSince1970])
            }
            let store = ReaderHistoryBindingStore(database: db)
            let sessions = SessionStore(database: db)
            if mode == 3 { try sessions.activateContext(raw) }
            else {
                let binding = try mode == 0
                    ? store.chooseRecoveryCriteria(raw, preservingActiveCheckpoint: original, expectedContext: raw)
                    : store.resolve(logicalKey: raw)
                if mode == 0 {
                    XCTAssertEqual(try store.chooseRecoveryCriteria(raw, preservingActiveCheckpoint: original, expectedContext: raw), binding)
                }
                if mode == 2 { try sessions.promotePreparedBinding(sessions.prepareBinding(binding.id)) }
                else { _ = try sessions.activateBinding(binding.id) }
            }
            XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reader_history_legacy_checkpoints") }, 2)
            let candidates = try store.legacyCandidates(logicalKey: frozen,
                wordExclusions: preferences.wordExclusionSnapshot(templates: [], context: frozen.filter.exclusions))
            XCTAssertEqual(candidates.first { $0.edition.id == a.id }?.checkpoints.map(\.point), [original])
            XCTAssertEqual(candidates.first { $0.edition.id == b.id }?.checkpoints.map(\.point), [retained])
            XCTAssertNil(try store.owner(ofEditionID: a.id))
            XCTAssertNil(try store.owner(ofEditionID: b.id))
            let adopted = try store.resolve(logicalKey: frozen, adopting: .init(editionID: b.id,
                publicationKey: frozen, evidence: .exactContext, checkpoint: retained))
            XCTAssertEqual(try SessionStore(database: db).checkpoint(bindingID: adopted.id), retained,
                "the retained original remains valid adoption evidence after source context replacement")
        }
    }


    func testCurrentCriteriaRetainsLegacyPointAfterSameContextReaderWritesANewCheckpoint() throws {
        let db = try StorageFixture.database(self), raw = key([])
        let preferences = try prefs(db, words: [])
        let (oldEdition, oldCard) = try published(db, key: raw)
        let sessions = SessionStore(database: db), bindings = ReaderHistoryBindingStore(database: db)
        let original = try XCTUnwrap(sessions.checkpoint())
        let binding = try bindings.chooseRecoveryCriteria(raw, preservingActiveCheckpoint: original, expectedContext: raw)
        let active = try sessions.activateBinding(binding.id)
        let next = StorageFixture.edition(revision: oldEdition.editorialRevision), card = StorageFixture.card()
        let nextPoint = SessionStore.CheckpointRecord(editionID: next.id, cardID: card.id,
            anchorPlacement: "top", updatedAt: original.updatedAt.addingTimeInterval(10))
        try PublicationStore(database: db).createInitialEdition(next,
            firstSegment: StorageFixture.segment(next, [card]), cards: [card], initialCheckpoint: nextPoint,
            expectedSourceExclusions: nil, bindingPublication: .init(activation: active, expectedActiveEditionID: nil))
        try sessions.saveCheckpoint(.init(editionID: next.id, cardID: card.id, anchorPlacement: "center",
            updatedAt: original.updatedAt.addingTimeInterval(20)), bindingActivation: active)
        XCTAssertNotEqual(try sessions.checkpoint(for: raw), original)
        let candidates = try bindings.legacyCandidates(logicalKey: raw,
            wordExclusions: preferences.wordExclusionSnapshot(templates: []))
        let retained = try XCTUnwrap(candidates.first { $0.edition.id == oldEdition.id })
        XCTAssertEqual(retained.checkpoints.map(\.point), [original])
        XCTAssertFalse(try XCTUnwrap(retained.checkpoints.first).isActive)
        XCTAssertNil(try bindings.owner(ofEditionID: oldEdition.id))
        XCTAssertEqual(try PublicationStore(database: db).card(id: oldCard.id), oldCard)
    }

    func testRecoveryChoiceCommitsIntentAndAdoptionTogetherAndPromotionRechecksLegacyPoint() throws {
        let db = try StorageFixture.database(self), raw = key([]), frozen = key(["old"])
        let preferences = try prefs(db, words: [])
        let (edition, _) = try published(db, key: frozen)
        let sessions = SessionStore(database: db), store = ReaderHistoryBindingStore(database: db)
        let point = try XCTUnwrap(sessions.checkpoint())
        let adoption = ReaderHistoryBindingStore.Adoption(editionID: edition.id, publicationKey: frozen,
            evidence: .exactContext, checkpoint: point)
        try db.write { try $0.execute(sql: "CREATE TRIGGER reject_recovery_choice BEFORE UPDATE ON reader_preferences BEGIN SELECT RAISE(ABORT, 'choice rejected'); END") }
        XCTAssertThrowsError(try store.chooseRecoveryCriteria(frozen, adopting: adoption,
            preservingActiveCheckpoint: point, expectedContext: raw))
        XCTAssertNil(try store.owner(ofEditionID: edition.id))
        XCTAssertNil(try store.binding(for: frozen))
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reader_history_legacy_checkpoints") }, 0,
            "failed choice rolls back retained evidence too")
        XCTAssertEqual(try preferences.load()?.activeContextKey, raw)
        try db.write { try $0.execute(sql: "DROP TRIGGER reject_recovery_choice") }
        let chosen = try store.chooseRecoveryCriteria(frozen, adopting: adoption,
            preservingActiveCheckpoint: point, expectedContext: raw)
        XCTAssertEqual(chosen.activeEditionID, edition.id)
        XCTAssertEqual(try preferences.load()?.activeContextKey, frozen)
        XCTAssertEqual(try sessions.checkpoint(), point)
        let pending = try sessions.prepareBinding(chosen.id)
        try db.write { try $0.execute(sql: "UPDATE session_checkpoint SET updated_at = updated_at + 1") }
        let changed = try sessions.checkpoint()
        XCTAssertThrowsError(try sessions.promotePreparedBinding(pending, expectedLegacyCheckpoint: point)) {
            XCTAssertEqual($0 as? SessionStoreError, .staleHistoryBinding)
        }
        XCTAssertEqual(try sessions.checkpoint(), changed)
        XCTAssertTrue(try sessions.isPreparedBinding(pending))
        XCTAssertEqual(try sessions.checkpoint(bindingID: chosen.id), point)
    }

    func testExplicitCurrentCriteriaKeepsUnownedLegacyNamespaceAndRejectsStaleChoice() throws {
        let db = try StorageFixture.database(self), logical = key(["old"])
        let (edition, _) = try published(db, key: logical)
        let sessions = SessionStore(database: db), store = ReaderHistoryBindingStore(database: db)
        let point = try XCTUnwrap(sessions.checkpoint())
        let binding = try store.resolveIndependentHistory(logicalKey: logical, preservingActiveCheckpoint: point)
        XCTAssertNotEqual(binding.runtimeNamespace, logical.canonicalIdentity)
        XCTAssertNil(binding.activeEditionID)
        XCTAssertNil(try store.owner(ofEditionID: edition.id))
        XCTAssertEqual(try sessions.checkpoint(), point)
        XCTAssertEqual(try store.resolve(logicalKey: logical), binding)
        let other = key(["other"])
        try sessions.clearActiveCheckpoint()
        XCTAssertThrowsError(try store.resolveIndependentHistory(logicalKey: other, preservingActiveCheckpoint: point)) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .incompatibleAdoption)
        }
        XCTAssertNil(try store.binding(for: other), "stale recovery choice is an atomic no-op")
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
            let prefs = try self.prefs(db, words: [])
            let snapshot = try prefs.wordExclusionSnapshot(templates: [])
            let candidates = try ReaderHistoryBindingStore(database: db).legacyCandidates(logicalKey: logical, wordExclusions: snapshot)
            let candidate = try XCTUnwrap(candidates.first { $0.edition.id == edition.id })
            XCTAssertEqual(candidate.checkpoints.first(where: \.isActive)?.point, original,
                "inventory resolves archived cards before adoption, preserving the wrong column as original evidence")
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

    func testLegacyInventoryKeepsAllExactAndForwardCandidatesWithoutMutation() throws {
        let db = try StorageFixture.database(self), logical = key(["own"]), frozen = key(["own", "global"])
        let prefs = try prefs(db, words: ["global"])
        let (forward, _) = try published(db, key: frozen)
        let exact = StorageFixture.edition(revision: EditorialRevision(id: EditorialRevisionID(), contextKey: logical,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: .init(rawValue: 1),
            eligibilityPolicyVersion: .init(rawValue: 1), scoringPolicyVersion: .init(rawValue: 1),
            sequencingPolicyVersion: .init(rawValue: 1), exposurePolicyVersion: .init(rawValue: 1), selectionSchemaVersion: .init(rawValue: 1)))
        let card = StorageFixture.card(), second = StorageFixture.edition(revision: exact.editorialRevision), secondCard = StorageFixture.card()
        let publication = PublicationStore(database: db)
        try publication.createEdition(exact, firstSegment: StorageFixture.segment(exact, [card]), cards: [card])
        try publication.createEdition(second, firstSegment: StorageFixture.segment(second, [secondCard]), cards: [secondCard])
        let original = try SessionStore(database: db).checkpoint(), store = ReaderHistoryBindingStore(database: db)
        let retainedPoint = SessionStore.CheckpointRecord(editionID: exact.id, cardID: card.id,
            anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 100), topDelta: -7, cardHeight: 150)
        try SessionStore(database: db).saveCheckpoint(retainedPoint)
        try SessionStore(database: db).saveCheckpoint(try XCTUnwrap(original))
        let snapshot = try prefs.wordExclusionSnapshot(templates: [], context: logical.filter.exclusions)
        let candidates = try store.legacyCandidates(logicalKey: logical, wordExclusions: snapshot)
        XCTAssertEqual(Set(candidates.map { $0.edition.id }), [forward.id, exact.id, second.id])
        let legacy = try XCTUnwrap(candidates.first { $0.edition.id == forward.id })
        XCTAssertEqual(legacy.evidence, .legacyWords(snapshot))
        XCTAssertEqual(legacy.checkpoints.map(\.point), [try XCTUnwrap(original)])
        XCTAssertEqual(legacy.checkpoints.map(\.isActive), [true], "identical context/singleton evidence is deduplicated")
        let retainedCandidate = try XCTUnwrap(candidates.first { $0.edition.id == exact.id })
        XCTAssertEqual(retainedCandidate.evidence, .exactContext)
        XCTAssertEqual(retainedCandidate.checkpoints.map(\.point), [retainedPoint])
        XCTAssertEqual(retainedCandidate.checkpoints.map(\.isActive), [false])
        XCTAssertTrue(try XCTUnwrap(candidates.first { $0.edition.id == second.id }).checkpoints.isEmpty)
        XCTAssertEqual(try store.legacyCandidates(logicalKey: logical, wordExclusions: snapshot), candidates)
        XCTAssertNil(try store.binding(for: logical))
        XCTAssertEqual(try SessionStore(database: db).checkpoint(), original)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM session_reader_binding") }, 0)
    }

    func testLegacyInventoryResolvesActiveCardBeforeAdoptionAndExcludesOwnedEditions() throws {
        let db = try StorageFixture.database(self), logical = key([])
        let (actual, card) = try published(db, key: logical)
        let wrong = StorageFixture.edition(revision: actual.editorialRevision), spare = StorageFixture.card()
        try PublicationStore(database: db).createEdition(wrong,
            firstSegment: StorageFixture.segment(wrong, [spare]), cards: [spare])
        try db.write { try $0.execute(sql: "UPDATE session_checkpoint SET edition_id = ?, anchor_top_delta = -19, anchor_height = 200",
            arguments: [PersistenceValueCoding.uuid(wrong.id.rawValue)]) }
        let prefs = try prefs(db, words: []), snapshot = try prefs.wordExclusionSnapshot(templates: [])
        let store = ReaderHistoryBindingStore(database: db)
        let candidates = try store.legacyCandidates(logicalKey: logical, wordExclusions: snapshot)
        let candidate = try XCTUnwrap(candidates.first { $0.edition.id == actual.id })
        XCTAssertEqual(candidate.checkpoints.count, 2, "distinct active and retained original statements are both exposed")
        let active = try XCTUnwrap(candidate.checkpoints.first(where: \.isActive))
        XCTAssertEqual(active.point.editionID, wrong.id, "keep original durable evidence, not a substituted cursor")
        XCTAssertEqual(active.point.cardID, card.id)
        XCTAssertFalse(try XCTUnwrap(candidates.first { $0.edition.id == wrong.id }).checkpoints.contains(where: \.isActive))
        let binding = try store.resolve(logicalKey: logical, adopting: .init(editionID: actual.id,
            publicationKey: logical, evidence: candidate.evidence, checkpoint: active.point))
        XCTAssertEqual(try SessionStore(database: db).checkpoint(bindingID: binding.id)?.topDelta, -19)
        XCTAssertEqual(try store.legacyCandidates(logicalKey: logical, wordExclusions: snapshot).map { $0.edition.id }, [wrong.id])
    }

    func testLegacyInventoryRejectsStaleOrWrongContextPolicyWithoutGuessingWordOrigin() throws {
        let db = try StorageFixture.database(self), logical = key([])
        let prefs = try prefs(db, words: ["old"])
        let snapshot = try prefs.wordExclusionSnapshot(templates: [])
        let (edition, _) = try published(db, key: key(["unexplained"]))
        let store = ReaderHistoryBindingStore(database: db)
        XCTAssertTrue(try store.legacyCandidates(logicalKey: logical, wordExclusions: snapshot).isEmpty,
            "unexplained frozen words are not subtracted or adopted")
        XCTAssertThrowsError(try store.legacyCandidates(logicalKey: key(["own"]), wordExclusions: snapshot)) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .incompatibleAdoption)
        }
        _ = try self.prefs(db, words: ["new"])
        XCTAssertThrowsError(try store.legacyCandidates(logicalKey: logical, wordExclusions: snapshot)) {
            XCTAssertEqual($0 as? ReaderHistoryBindingStore.Failure, .staleAdoptionPolicy)
        }
        XCTAssertNil(try store.binding(for: logical))
        XCTAssertNotNil(try PublicationStore(database: db).edition(id: edition.id))
    }

    func testLegacyInventoryFindsRetainedCardDespiteWrongContextProjection() throws {
        let db = try StorageFixture.database(self), logical = key([])
        let (actual, card) = try published(db, key: logical)
        let v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: key(["other"]),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let other = StorageFixture.edition(revision: revision), otherCard = StorageFixture.card()
        try PublicationStore(database: db).createEdition(other,
            firstSegment: StorageFixture.segment(other, [otherCard]), cards: [otherCard])
        let sessions = SessionStore(database: db)
        try sessions.saveCheckpoint(.init(editionID: other.id, cardID: otherCard.id,
            anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: 2000)))
        try db.write { db in
            try db.execute(sql: "UPDATE context_checkpoints SET context_identity = 'legacy-wrong-projection', edition_id = ? WHERE card_id = ?",
                arguments: [PersistenceValueCoding.uuid(other.id.rawValue), PersistenceValueCoding.uuid(card.id.rawValue)])
        }
        XCTAssertNil(try sessions.checkpoint(for: logical))
        let active = try sessions.checkpoint(), prefs = try prefs(db, words: [])
        let store = ReaderHistoryBindingStore(database: db)
        let candidates = try store.legacyCandidates(logicalKey: logical,
            wordExclusions: prefs.wordExclusionSnapshot(templates: []))
        XCTAssertEqual(candidates.map { $0.edition.id }, [actual.id])
        let original = try XCTUnwrap(candidates.first?.checkpoints.first)
        XCTAssertFalse(original.isActive)
        XCTAssertEqual(original.point.editionID, other.id)
        XCTAssertEqual(original.point.cardID, card.id)
        let binding = try store.resolve(logicalKey: logical, adopting: .init(editionID: actual.id,
            publicationKey: logical, evidence: .exactContext, checkpoint: original.point))
        XCTAssertEqual(try sessions.checkpoint(bindingID: binding.id)?.editionID, actual.id)
        XCTAssertEqual(try sessions.checkpoint(), active)
    }

}
