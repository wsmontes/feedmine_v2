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
        XCTAssertTrue(ownership.installInitial(first, owner: owner))
        XCTAssertTrue(ownership.beginGesture(owner: owner))
        XCTAssertTrue(ownership.stage(second, owner: owner))
        XCTAssertEqual(ownership.displayed(owner: owner)?.cards.map(\.id), [a.id, b.id])
        XCTAssertNil(ownership.acknowledgeHandoff(owner: owner,
            before: witness(b.id), after: witness(b.id, top: 420)),
            "An active gesture cannot commit a new physical rail")
        XCTAssertEqual(ownership.installed?.snapshot, s1)
        ownership.endGesture(owner: owner)
        XCTAssertEqual(ownership.displayed(owner: owner)?.cards.map(\.id), [a.id, b.id],
            "Ending a gesture alone does not authorize a physical swap")
        let transition = try XCTUnwrap(ownership.acknowledgeHandoff(owner: owner,
            before: witness(b.id), after: witness(b.id, top: 420)))
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
        XCTAssertNil(ownership.acknowledgeHandoff(owner: stranger,
            before: witness(b.id), after: witness(b.id)))
        XCTAssertEqual(ownership.installed?.snapshot, original)
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
        XCTAssertNil(ownership.acknowledgeHandoff(owner: owner,
            before: nil, after: witness(b.id)))
        XCTAssertNil(ownership.acknowledgeHandoff(owner: owner,
            before: witness(a.id, top: 900), after: witness(a.id)))
        XCTAssertEqual(ownership.displayed(owner: owner)?.visualAnchorID, b.id)
        XCTAssertEqual(ownership.displayed(owner: owner)?.cards.map(\.id), [a.id, b.id])
        XCTAssertEqual(ownership.pending?.snapshot.provenance.position, 2,
            "Rejected measurement stays retryable without consuming the staged rail")
    }
}
