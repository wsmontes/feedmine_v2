import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class ReaderHistoryPreparationTests: XCTestCase {
    private func key(_ word: String = "") -> ContextKey {
        ContextKey(request: .main, filter: ReaderFilter(exclusions: .init(isEnabled: !word.isEmpty, rules: word.isEmpty ? [] : [word])))
    }
    private func edition(_ key: ContextKey) -> PublicationStore.EditionRecord {
        let v = PolicyVersion(rawValue: 1)
        return StorageFixture.edition(revision: EditorialRevision(id: EditorialRevisionID(), contextKey: key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1)))
    }
    private func publish(_ db: RuntimeDatabase, _ key: ContextKey, _ handle: SessionStore.BindingActivation,
        expected: FeedEditionID? = nil) throws -> SessionStore.CheckpointRecord {
        let e = edition(key), card = StorageFixture.card()
        let point = SessionStore.CheckpointRecord(editionID: e.id, cardID: card.id,
            anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: 1234), topDelta: -12, cardHeight: 180)
        try PublicationStore(database: db).createInitialEdition(e, firstSegment: StorageFixture.segment(e, [card]),
            cards: [card], initialCheckpoint: point, expectedSourceExclusions: nil,
            bindingPublication: .init(activation: handle, expectedActiveEditionID: expected))
        return point
    }

    func testPreparedPublicationRetainsCurrentReaderUntilAtomicPromotion() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let activeA = try session.activateBinding(a.id), pa = try publish(db, key(), activeA)
        let b = try bindings.resolve(logicalKey: key("B")), pendingB = try session.prepareBinding(b.id)
        let pb = try publish(db, key("B"), pendingB)
        XCTAssertEqual(try session.checkpoint(), pa)
        XCTAssertNil(try bindings.binding(for: key("B"))?.activeEditionID)
        XCTAssertNil(try session.checkpoint(bindingID: b.id))
        XCTAssertEqual(try session.checkpoint(bindingActivation: pendingB), pb)
        XCTAssertTrue(try session.isPreparedBinding(pendingB))
        XCTAssertThrowsError(try session.saveCheckpoint(pb, bindingActivation: pendingB))
        XCTAssertThrowsError(try session.clearActiveCheckpoint(bindingActivation: pendingB, expectedEditionID: pb.editionID))
        XCTAssertThrowsError(try PublicationStore(database: db).markSeen(editionID: pb.editionID,
            cardID: pb.cardID, bindingActivation: pendingB))
        let movedA = SessionStore.CheckpointRecord(editionID: pa.editionID, cardID: pa.cardID,
            anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 2345), topDelta: 22, cardHeight: 180)
        try session.saveCheckpoint(movedA, bindingActivation: activeA)
        try session.promotePreparedBinding(pendingB)
        XCTAssertFalse(try session.isPreparedBinding(pendingB))
        XCTAssertEqual(try session.checkpoint(), pb)
        XCTAssertEqual(try session.checkpoint(bindingID: a.id), movedA)
        XCTAssertEqual(try bindings.binding(for: key("B"))?.activeEditionID, pb.editionID)
        XCTAssertThrowsError(try session.saveCheckpoint(pa, bindingActivation: activeA))
        try session.saveCheckpoint(pb, bindingActivation: pendingB)
    }

    func testSupersessionAndCancellationRevokeOnlyCandidateAuthorityAndRetainRetry() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let activeA = try session.activateBinding(a.id), pa = try publish(db, key(), activeA)
        let b = try bindings.resolve(logicalKey: key("B")), firstB = try session.prepareBinding(b.id)
        let pb = try publish(db, key("B"), firstB)
        let c = try bindings.resolve(logicalKey: key("C")), pendingC = try session.prepareBinding(c.id)
        XCTAssertThrowsError(try session.checkpoint(bindingActivation: firstB))
        XCTAssertThrowsError(try session.promotePreparedBinding(firstB))
        XCTAssertFalse(try session.cancelPreparedBinding(firstB))
        XCTAssertTrue(try session.cancelPreparedBinding(pendingC))
        XCTAssertFalse(try session.cancelPreparedBinding(pendingC))
        XCTAssertEqual(try session.checkpoint(), pa)
        let nextB = try session.prepareBinding(b.id)
        XCTAssertNotEqual(nextB, firstB)
        XCTAssertEqual(try session.checkpoint(bindingActivation: nextB), pb, "retry restores the explicit retained candidate, not the newest-Edition guess")
        try session.promotePreparedBinding(nextB)
        XCTAssertEqual(try session.checkpoint(), pb)
    }

    func testSameBindingRolloverDoesNotRetirePresentedEditionBeforePromotion() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let current = try session.activateBinding(a.id), old = try publish(db, key(), current)
        var next = try session.prepareBinding(a.id)
        next = try session.resetPreparedBinding(next, editionID: nil)
        let fresh = try publish(db, key(), next)
        XCTAssertEqual(try bindings.binding(for: key())?.activeEditionID, old.editionID)
        XCTAssertEqual(try session.checkpoint(bindingActivation: current), old)
        try session.saveCheckpoint(old, bindingActivation: current)
        XCTAssertEqual(try session.checkpoint(bindingActivation: next), fresh)
        try session.promotePreparedBinding(next)
        XCTAssertEqual(try session.checkpoint(), fresh)
        XCTAssertThrowsError(try session.saveCheckpoint(old, bindingActivation: current))
    }

    func testPromotionFailureRollsBackAndKeepsBothCurrentAndPreparedHandles() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let activeA = try session.activateBinding(a.id), pa = try publish(db, key(), activeA)
        let b = try bindings.resolve(logicalKey: key("B")), next = try session.prepareBinding(b.id)
        let pb = try publish(db, key("B"), next)
        try db.write { try $0.execute(sql: "CREATE TRIGGER reject_promotion BEFORE UPDATE ON session_reader_binding BEGIN SELECT RAISE(ABORT, 'promotion refused'); END") }
        XCTAssertThrowsError(try session.promotePreparedBinding(next))
        XCTAssertEqual(try session.checkpoint(bindingActivation: activeA), pa)
        XCTAssertEqual(try session.checkpoint(bindingActivation: next), pb)
        XCTAssertNil(try bindings.binding(for: key("B"))?.activeEditionID)
        try db.write { try $0.execute(sql: "DROP TRIGGER reject_promotion") }
        try session.promotePreparedBinding(next)
        XCTAssertEqual(try session.checkpoint(), pb)
    }

    func testImmediateActivationRevokesPreparationWithoutBorrowingItsCheckpoint() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let current = try session.activateBinding(a.id), pa = try publish(db, key(), current)
        let b = try bindings.resolve(logicalKey: key("B")), next = try session.prepareBinding(b.id)
        _ = try publish(db, key("B"), next)
        let returnedA = try session.activateBinding(a.id)
        XCTAssertThrowsError(try session.promotePreparedBinding(next))
        XCTAssertThrowsError(try session.checkpoint(bindingActivation: next))
        XCTAssertEqual(try session.checkpoint(bindingActivation: returnedA), pa)
    }
    func testConsumedPreparationDoesNotRewindALaterCurrentRollover() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let handle = try session.prepareBinding(a.id), first = try publish(db, key(), handle)
        try session.promotePreparedBinding(handle)
        try session.clearActiveCheckpoint(bindingActivation: handle, expectedEditionID: first.editionID)
        let latest = try publish(db, key(), handle, expected: first.editionID)
        let replacement = try session.prepareBinding(a.id)
        XCTAssertEqual(try session.checkpoint(bindingActivation: replacement), latest)
        XCTAssertEqual(try session.checkpoint(bindingActivation: handle), latest)
    }

    func testPreparedAppendKeepsVisiblePositionAndRejectsAfterCancellation() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let current = try session.activateBinding(a.id), pa = try publish(db, key(), current)
        let b = try bindings.resolve(logicalKey: key("B")), pending = try session.prepareBinding(b.id)
        let pb = try publish(db, key("B"), pending), publication = PublicationStore(database: db)
        let e = try XCTUnwrap(publication.edition(id: pb.editionID)), card = StorageFixture.card()
        let segment = StorageFixture.segment(e, [card], ordinal: 1)
        try publication.appendSegment(segment, cards: [card], expectedSourceExclusions: nil, bindingActivation: pending)
        XCTAssertEqual(try session.checkpoint(), pa)
        XCTAssertEqual(try session.checkpoint(bindingActivation: pending), pb)
        XCTAssertEqual(try publication.segments(editionID: pb.editionID).count, 2)
        try session.cancelPreparedBinding(pending)
        let stale = StorageFixture.card()
        XCTAssertThrowsError(try publication.appendSegment(StorageFixture.segment(e, [stale], ordinal: 2),
            cards: [stale], expectedSourceExclusions: nil, bindingActivation: pending))
        XCTAssertNil(try publication.card(id: stale.id))
        XCTAssertEqual(try session.checkpoint(), pa)
    }

    func testCurrentRolloverSupersedesPreparedCandidateOfTheSameBinding() throws {
        for cancelled in [false, true] {
            let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
            let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
            let active = try session.activateBinding(a.id), old = try publish(db, key(), active)
            var pending = try session.prepareBinding(a.id)
            pending = try session.resetPreparedBinding(pending, editionID: nil)
            let candidate = try publish(db, key(), pending)
            if cancelled { try session.cancelPreparedBinding(pending) }
            try session.clearActiveCheckpoint(bindingActivation: active, expectedEditionID: old.editionID)
            let current = try publish(db, key(), active, expected: old.editionID)
            if !cancelled { XCTAssertThrowsError(try session.promotePreparedBinding(pending)) }
            let fresh = try session.prepareBinding(a.id)
            XCTAssertEqual(try session.checkpoint(bindingActivation: fresh), current,
                "the displayed reader's newer Edition must win over an obsolete hidden candidate")
            XCTAssertNotNil(try PublicationStore(database: db).edition(id: candidate.editionID), "obsolete candidate history is retained")
        }
    }

    func testRetargetingPreparationCannotReviveAnOlderCandidateCallback() throws {
        let db = try StorageFixture.database(self), bindings = ReaderHistoryBindingStore(database: db)
        let session = SessionStore(database: db), a = try bindings.resolve(logicalKey: key())
        let active = try session.activateBinding(a.id), pa = try publish(db, key(), active)
        let b = try bindings.resolve(logicalKey: key("B")), original = try session.prepareBinding(b.id)
        let candidate = try publish(db, key("B"), original)
        let empty = try session.resetPreparedBinding(original, editionID: nil)
        let returned = try session.resetPreparedBinding(empty, editionID: candidate.editionID)
        XCTAssertThrowsError(try session.checkpoint(bindingActivation: original))
        XCTAssertThrowsError(try session.checkpoint(bindingActivation: empty))
        XCTAssertEqual(try session.checkpoint(bindingActivation: returned), candidate)
        let e = try XCTUnwrap(PublicationStore(database: db).edition(id: candidate.editionID)), late = StorageFixture.card()
        XCTAssertThrowsError(try PublicationStore(database: db).appendSegment(StorageFixture.segment(e, [late], ordinal: 1),
            cards: [late], expectedSourceExclusions: nil, bindingActivation: original),
            "an A→empty→A preparation cycle must not revive the first A's callback")
        XCTAssertNil(try PublicationStore(database: db).card(id: late.id))
        XCTAssertEqual(try session.checkpoint(), pa)
    }

}
