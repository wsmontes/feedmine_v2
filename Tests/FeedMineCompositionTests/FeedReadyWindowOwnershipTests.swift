import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineRuntime
@testable import FeedMineUI

/// Contract for a future SwiftUI adapter. These tests do not claim a native
/// layout swap: the host still has to measure both sides and acknowledge it.
@MainActor
final class FeedReadyWindowOwnershipTests: XCTestCase {
    private func card(_ layout: PresentationCardLayout = .textOnly) -> PresentationCard {
        PresentationCard(id: PublicationCardID(), title: "Ready", primaryText: nil,
            timestamp: nil, sourceID: nil, sourceDisplayName: nil,
            providerDisplayName: nil, layout: layout,
            mediaAspectRatio: layout == .textOnly ? nil : 1.5,
            primaryActionKind: nil, image: nil)
    }

    private func snapshot(_ cards: [PresentationCard], anchor: PublicationCardID,
        edition: FeedEditionID, sequence: UUID, position: UInt64) throws -> FeedPresentationSnapshot {
        let window = try XCTUnwrap(FeedWindowSnapshot(items: cards,
            anchor: .init(cardID: anchor, placement: .top)))
        return FeedPresentationSnapshot(contextKey: ContextKey(request: .main),
            editionID: edition, window: window,
            provenance: FeedProjectionProvenance(sequenceID: sequence, position: position))
    }

    private func witness(_ id: PublicationCardID, top: Double = 180,
        offset: Double = 500) -> FeedVisualWindowWitness {
        FeedVisualWindowWitness(cardID: id, viewportTop: top, contentOffset: offset,
            cardHeight: 160, viewportHeight: 650)
    }

    func testMissingAnchorOrDeferredGapCannotBecomePhysicalWindow() throws {
        let a = card(), missing = card(.hero), b = card()
        let edition = FeedEditionID(), sequence = UUID()
        let s = try snapshot([a, missing, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        XCTAssertNil(FeedReadyVisualWindow(snapshot: s, center: 1, backward: 1, forward: 1),
            "Do not hide the gap between ready siblings to make one physical list")
        let savedHero = try snapshot([a, missing, b], anchor: missing.id,
            edition: edition, sequence: sequence, position: 1)
        XCTAssertNil(FeedReadyVisualWindow(snapshot: savedHero,
            center: 1, backward: 0, forward: 0),
            "No physical scroll anchor may be fabricated for missing pixels")
        let valid = try XCTUnwrap(FeedReadyVisualWindow(snapshot: s,
            center: 2, backward: 0, forward: 0))
        XCTAssertEqual(valid.cards.map(\.id), [b.id])
        XCTAssertEqual(valid.logicalCount, 3)
        XCTAssertEqual(valid.logicalAnchorID, b.id)
    }

    func testGestureKeepsOriginalReadyCellsUntilReleasedAndMeasured() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let s1 = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let s2 = try snapshot([a, b, c], anchor: b.id,
            edition: edition, sequence: sequence, position: 2)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: s1,
            center: 1, backward: 1, forward: 0))
        let second = try XCTUnwrap(FeedReadyVisualWindow(snapshot: s2,
            center: 1, backward: 1, forward: 1))
        let store = FeedScreenStore(onViewport: { _, _ in })
        var ownership = FeedReadyWindowOwnership()
        let owner = ObjectIdentifier(store)
        try store.install(FeedPresentationState(presentation: s1))
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.beginGesture(owner: owner))
        try store.install(FeedPresentationState(presentation: s2))
        XCTAssertTrue(ownership.stage(second, owner: owner))
        XCTAssertEqual(ownership.displayed(owner: owner)?.cards.map(\.id), [a.id, b.id])
        XCTAssertNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)),
            "An active gesture cannot even provisionally install a physical rail")
        XCTAssertEqual(ownership.installed?.snapshot, s1)
        ownership.endGesture(owner: owner)
        XCTAssertEqual(ownership.displayed(owner: owner)?.cards.map(\.id), [a.id, b.id],
            "Ending a gesture alone does not authorize a physical swap")
        XCTAssertEqual(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id))?.snapshot, s2)
        let transition = try XCTUnwrap(ownership.commitProvisionalHandoff(owner: owner,
            transaction: ownership.provisionalID ?? UUID(), after: witness(b.id, top: 420)))
        XCTAssertEqual(transition.witnessID, b.id)
        XCTAssertEqual(transition.offsetAdjustment, 240, accuracy: 0.001)
        XCTAssertEqual(ownership.displayed(owner: owner)?.cards.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(ownership.installed?.snapshot.provenance.position, 2)
    }

    func testForeignOwnerAndForeignSessionCannotReplaceReader() throws {
        let a = card(), b = card(), edition = FeedEditionID(), sequence = UUID()
        let original = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let foreign = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: UUID(), position: 2)
        let installed = try XCTUnwrap(FeedReadyVisualWindow(snapshot: original,
            center: 1, backward: 1, forward: 0))
        let invalid = try XCTUnwrap(FeedReadyVisualWindow(snapshot: foreign,
            center: 1, backward: 1, forward: 0))
        let firstStore = FeedScreenStore(onViewport: { _, _ in })
        let otherStore = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(firstStore), stranger = ObjectIdentifier(otherStore)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(installed, owner: owner))
        XCTAssertFalse(ownership.beginGesture(owner: stranger))
        XCTAssertFalse(ownership.stage(invalid, owner: owner))
        XCTAssertFalse(ownership.stage(installed, owner: stranger))
        XCTAssertNil(ownership.beginProvisionalHandoff(owner: stranger,
            before: witness(b.id)))
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: stranger,
            transaction: UUID(), after: witness(b.id)))
        XCTAssertEqual(ownership.installed?.snapshot, original)
    }

    func testStagedCausalPositionCannotRegressOrReuseAnExistingOrdinal() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let original = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let newer = try snapshot([a, b, c], anchor: b.id,
            edition: edition, sequence: sequence, position: 3)
        let stale = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 2)
        let duplicateOrdinal = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 3)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: original,
            center: 1, backward: 1, forward: 0))
        let next = try XCTUnwrap(FeedReadyVisualWindow(snapshot: newer,
            center: 1, backward: 1, forward: 1))
        let obsolete = try XCTUnwrap(FeedReadyVisualWindow(snapshot: stale,
            center: 1, backward: 1, forward: 0))
        let duplicate = try XCTUnwrap(FeedReadyVisualWindow(snapshot: duplicateOrdinal,
            center: 1, backward: 1, forward: 0))
        let store = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(store)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.stage(next, owner: owner))
        XCTAssertFalse(ownership.stage(obsolete, owner: owner),
            "A stale result cannot supersede a newer staged physical run")
        XCTAssertFalse(ownership.stage(duplicate, owner: owner),
            "One projection ordinal cannot authorize competing visible content")
        XCTAssertEqual(ownership.pending?.snapshot, newer)
        XCTAssertEqual(ownership.installed?.snapshot, original)
    }

    func testProvisionalSwapUsesMeasuredPhysicalProofOrRollsBack() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let old = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let next = try snapshot([a, b, c], anchor: b.id,
            edition: edition, sequence: sequence, position: 2)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: old,
            center: 1, backward: 1, forward: 0))
        let candidate = try XCTUnwrap(FeedReadyVisualWindow(snapshot: next,
            center: 1, backward: 1, forward: 1))
        let store = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(store)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.stage(candidate, owner: owner))
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: owner, transaction: UUID(), after: witness(b.id)),
            "No post-layout witness is valid without a recorded provisional phase")
        XCTAssertNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id, top: 900)), "Offscreen pre-layout witness is not valid")
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, old)
        XCTAssertEqual(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id))?.snapshot, next)
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, next,
            "A physical adapter may measure only the explicitly provisional candidate")
        XCTAssertFalse(ownership.beginGesture(owner: owner),
            "Never start a new gesture while a candidate layout is provisional")
        XCTAssertFalse(ownership.stage(candidate, owner: owner),
            "A pending candidate cannot change underneath its physical measurement")
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: owner,
            transaction: ownership.provisionalID ?? UUID(), after: witness(a.id)), "A mismatched physical witness must fail")
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, old,
            "Failure must roll the provisional display back to the old reader")
        XCTAssertEqual(ownership.installed?.snapshot, old)
        XCTAssertEqual(ownership.pending?.snapshot, next,
            "Rejected physical measurement must remain retryable")
        XCTAssertEqual(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id))?.snapshot, next)
        let proof = try XCTUnwrap(ownership.commitProvisionalHandoff(owner: owner,
            transaction: ownership.provisionalID ?? UUID(), after: witness(b.id, top: 420)))
        XCTAssertEqual(proof.witnessID, b.id)
        XCTAssertEqual(proof.offsetAdjustment, 240, accuracy: 0.001)
        XCTAssertEqual(ownership.installed?.snapshot, next)
        XCTAssertNil(ownership.pending)
        XCTAssertNil(ownership.provisional)
    }

    func testProvisionalCancelAndForeignOwnerDoNotCommitReader() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let old = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let next = try snapshot([a, b, c], anchor: b.id,
            edition: edition, sequence: sequence, position: 2)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: old,
            center: 1, backward: 1, forward: 0))
        let candidate = try XCTUnwrap(FeedReadyVisualWindow(snapshot: next,
            center: 1, backward: 1, forward: 1))
        let store = FeedScreenStore(onViewport: { _, _ in })
        let foreign = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(store), stranger = ObjectIdentifier(foreign)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.stage(candidate, owner: owner))
        XCTAssertEqual(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id))?.snapshot, next)
        XCTAssertFalse(ownership.cancelProvisionalHandoff(owner: stranger))
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: stranger,
            transaction: UUID(), after: witness(b.id)))
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, next)
        XCTAssertTrue(ownership.cancelProvisionalHandoff(owner: owner))
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, old)
        XCTAssertEqual(ownership.pending?.snapshot, next)
        XCTAssertTrue(ownership.beginGesture(owner: owner))
        XCTAssertNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)), "Borrowed presentation wins during a gesture")
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, old)
        ownership.endGesture(owner: owner)
        XCTAssertTrue(ownership.cancelProvisionalHandoff(owner: owner) == false)
    }

    func testScopeResetRevokesProvisionalGeometryBeforeAnotherEditionStarts() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let original = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let next = try snapshot([a, b, c], anchor: b.id,
            edition: edition, sequence: sequence, position: 2)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: original,
            center: 1, backward: 1, forward: 0))
        let candidate = try XCTUnwrap(FeedReadyVisualWindow(snapshot: next,
            center: 1, backward: 1, forward: 1))
        let ownerStore = FeedScreenStore(onViewport: { _, _ in })
        let foreignStore = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(ownerStore)
        let foreign = ObjectIdentifier(foreignStore)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.stage(candidate, owner: owner))
        XCTAssertNotNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)))
        ownership.reset(owner: foreign)
        XCTAssertNotNil(ownership.provisional,
            "Foreign UI cannot revoke the active physical transaction")
        ownership.reset(owner: owner)
        XCTAssertNil(ownership.provisional)
        XCTAssertNil(ownership.installed)
        XCTAssertNil(ownership.pending)
        XCTAssertNil(ownership.displayed(owner: owner))
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: owner,
            transaction: ownership.provisionalID ?? UUID(), after: witness(b.id, top: 420)),
            "Old edition geometry must not commit after reset")
        let freshEdition = try snapshot([a, b], anchor: b.id,
            edition: FeedEditionID(), sequence: UUID(), position: 1)
        let fresh = try XCTUnwrap(FeedReadyVisualWindow(snapshot: freshEdition,
            center: 1, backward: 1, forward: 0))
        XCTAssertTrue(ownership.installInitial(fresh, owner: owner))
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, freshEdition)
    }

    func testStaleLayoutCallbackCannotCommitANewerProvisionalTransaction() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let old = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let next = try snapshot([a, b, c], anchor: b.id,
            edition: edition, sequence: sequence, position: 2)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: old,
            center: 1, backward: 1, forward: 0))
        let candidate = try XCTUnwrap(FeedReadyVisualWindow(snapshot: next,
            center: 1, backward: 1, forward: 1))
        let store = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(store)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.stage(candidate, owner: owner))
        XCTAssertNotNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)))
        let abandoned = try XCTUnwrap(ownership.provisionalID)
        XCTAssertTrue(ownership.cancelProvisionalHandoff(owner: owner))
        XCTAssertNotNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)))
        let active = try XCTUnwrap(ownership.provisionalID)
        XCTAssertNotEqual(abandoned, active)
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: owner,
            transaction: abandoned, after: witness(b.id, top: 420)),
            "An old geometry callback cannot acknowledge a newer physical layout")
        XCTAssertEqual(ownership.provisionalID, active)
        XCTAssertEqual(ownership.installed?.snapshot, old)
        let proof = try XCTUnwrap(ownership.commitProvisionalHandoff(owner: owner,
            transaction: active, after: witness(b.id, top: 420)))
        XCTAssertEqual(proof.offsetAdjustment, 240, accuracy: 0.001)
        XCTAssertEqual(ownership.installed?.snapshot, next)
    }

    func testNativeGestureInterruptsProvisionalSwapAndFencesLateCallback() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let old = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let next = try snapshot([a, b, c], anchor: b.id,
            edition: edition, sequence: sequence, position: 2)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: old,
            center: 1, backward: 1, forward: 0))
        let candidate = try XCTUnwrap(FeedReadyVisualWindow(snapshot: next,
            center: 1, backward: 1, forward: 1))
        let store = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(store)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.stage(candidate, owner: owner))
        XCTAssertNotNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)))
        let interruptedToken = try XCTUnwrap(ownership.provisionalID)
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, next)
        XCTAssertTrue(ownership.nativeInteractionBegan(owner: owner),
            "A real native gesture must preempt a provisional, unpainted swap")
        XCTAssertNil(ownership.provisional)
        XCTAssertNil(ownership.provisionalID)
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, old)
        XCTAssertEqual(ownership.installed?.snapshot, old)
        XCTAssertEqual(ownership.pending?.snapshot, next,
            "Interrupted transitions must retain the prepared candidate")
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: owner,
            transaction: interruptedToken, after: witness(b.id, top: 420)))
        XCTAssertNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)), "No physical swap during native drag")
        ownership.endGesture(owner: owner)
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, old)
        XCTAssertNotNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(b.id)))
        let retriedToken = try XCTUnwrap(ownership.provisionalID)
        XCTAssertNotEqual(interruptedToken, retriedToken)
        XCTAssertNil(ownership.commitProvisionalHandoff(owner: owner,
            transaction: interruptedToken, after: witness(b.id, top: 420)))
        XCTAssertEqual(ownership.provisionalID, retriedToken,
            "Late geometry must not cancel the new transaction")
    }

    func testNativeGestureFromWrongOwnerCannotInterruptExistingReader() throws {
        let a = card(), b = card()
        let edition = FeedEditionID(), sequence = UUID()
        let snapshot = try snapshot([a, b], anchor: b.id,
            edition: edition, sequence: sequence, position: 1)
        let ready = try XCTUnwrap(FeedReadyVisualWindow(snapshot: snapshot,
            center: 1, backward: 1, forward: 0))
        let store = FeedScreenStore(onViewport: { _, _ in })
        let other = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(store), stranger = ObjectIdentifier(other)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(ready, owner: owner))
        XCTAssertFalse(ownership.nativeInteractionBegan(owner: stranger))
        XCTAssertTrue(ownership.nativeInteractionBegan(owner: owner))
        XCTAssertTrue(ownership.nativeInteractionBegan(owner: owner),
            "Repeated UIKit phase notifications must be idempotent")
        XCTAssertEqual(ownership.displayed(owner: owner)?.snapshot, snapshot)
        XCTAssertFalse(ownership.beginGesture(owner: owner),
            "Duplicate gestures cannot change the borrowed provenance")
        ownership.endGesture(owner: owner)
        XCTAssertEqual(ownership.installed?.snapshot, snapshot)
    }

    func testUnmeasuredOrUnreadyHandoffNeverDisplacesInstalledReader() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let s1 = try snapshot([a, b], anchor: b.id, edition: edition,
            sequence: sequence, position: 1)
        let s2 = try snapshot([a, b, c], anchor: b.id, edition: edition,
            sequence: sequence, position: 2)
        let first = try XCTUnwrap(FeedReadyVisualWindow(snapshot: s1,
            center: 1, backward: 1, forward: 0))
        let next = try XCTUnwrap(FeedReadyVisualWindow(snapshot: s2,
            center: 1, backward: 1, forward: 1))
        let store = FeedScreenStore(onViewport: { _, _ in })
        let owner = ObjectIdentifier(store)
        var ownership = FeedReadyWindowOwnership()
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.stage(next, owner: owner))
        XCTAssertNil(ownership.beginProvisionalHandoff(owner: owner,
            before: nil))
        XCTAssertNil(ownership.beginProvisionalHandoff(owner: owner,
            before: witness(a.id, top: 900)))
        XCTAssertEqual(ownership.displayed(owner: owner)?.visualAnchorID, b.id)
        XCTAssertEqual(ownership.displayed(owner: owner)?.cards.map(\.id), [a.id, b.id])
        XCTAssertEqual(ownership.pending?.snapshot.provenance.position, 2,
            "Rejected measurement stays retryable without consuming the staged rail")
    }
}
