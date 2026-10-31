import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineRuntime

/// P0 / Issue #7: a virtual *index* of frozen historical positions, not an
/// array.filter that collapses SwiftUI scroll geometry. The UI adapter and
/// bounded re-entry policy must be tested separately before drawing slots.
final class FeedVisualRailIndexTests: XCTestCase {
    private func card(_ id: PublicationCardID = .init(),
        layout: PresentationCardLayout) -> PresentationCard {
        PresentationCard(id: id, title: "Frozen", primaryText: "Local",
            timestamp: nil, sourceID: nil, sourceDisplayName: nil,
            providerDisplayName: nil, layout: layout,
            mediaAspectRatio: layout == .textOnly ? nil : 1.5,
            primaryActionKind: nil, image: nil)
    }

    private func snapshot(_ cards: [PresentationCard],
        anchor: PublicationCardID, position: UInt64 = 1,
        sequence: UUID = UUID()) throws -> FeedPresentationSnapshot {
        let window = try XCTUnwrap(FeedWindowSnapshot(items: cards,
            anchor: PresentationAnchor(cardID: anchor, placement: .top)))
        return FeedPresentationSnapshot(contextKey: ContextKey(request: .main),
            editionID: FeedEditionID(), window: window,
            provenance: FeedProjectionProvenance(sequenceID: sequence, position: position))
    }

    func testReadySiblingsOnBothSidesOfDeferredHeroKeepHistoricalIndices() throws {
        let before = card(layout: .textOnly)
        let missing = card(layout: .hero)
        let after = card(layout: .textOnly)
        let original = try snapshot([before, missing, after], anchor: after.id)
        let rail = FeedVisualRailIndex(snapshot: original)

        XCTAssertEqual(rail.logicalCount, 3)
        XCTAssertEqual(rail.logicalAnchorIndex, 2)
        XCTAssertEqual(rail.visualAnchorID, after.id)
        XCTAssertEqual(rail.slot(at: 0), .ready(index: 0, card: before))
        XCTAssertEqual(rail.slot(at: 1), .deferred(index: 1, id: missing.id))
        XCTAssertEqual(rail.slot(at: 2), .ready(index: 2, card: after))
        XCTAssertEqual(rail.slice(around: 1, backward: 1, forward: 1).count, 3)
        XCTAssertEqual(original.window.items.map(\.id), [before.id, missing.id, after.id],
            "The original durable history remains the authority")
    }

    func testMissingCheckpointDoesNotInventVisualAnchorOrRewriteCursor() throws {
        let ready = card(layout: .textOnly)
        let blocked = card(layout: .hero)
        let original = try snapshot([ready, blocked], anchor: blocked.id)
        let rail = FeedVisualRailIndex(snapshot: original)
        XCTAssertEqual(rail.logicalAnchorIndex, 1)
        XCTAssertNil(rail.visualAnchorID,
            "A historical image cursor without pixels is not a visual scroll target")
        XCTAssertEqual(rail.slot(at: 0), .ready(index: 0, card: ready),
            "Ready content must remain discoverable while the anchor is deferred")
        XCTAssertEqual(original.window.anchor.cardID, blocked.id)
        XCTAssertEqual(rail.slot(at: 1), .deferred(index: 1, id: blocked.id))
    }

    func testHeldRailKeepsItsOwnCausalWindowAfterNewProjectionArrives() throws {
        let text = card(layout: .textOnly)
        let missing = card(layout: .thumbnail)
        let sequence = UUID()
        let before = try snapshot([text, missing], anchor: text.id,
            position: 1, sequence: sequence)
        let current = try snapshot([missing, text], anchor: text.id,
            position: 2, sequence: sequence)
        let borrowed = FeedVisualRailIndex(snapshot: before)
        let updated = FeedVisualRailIndex(snapshot: current)
        XCTAssertEqual(borrowed.provenance.position, 1)
        XCTAssertEqual(updated.provenance.position, 2)
        XCTAssertEqual(borrowed.slot(at: 0), .ready(index: 0, card: text))
        XCTAssertEqual(updated.slot(at: 0), .deferred(index: 0, id: missing.id))
        XCTAssertEqual(borrowed.logicalAnchorIndex, 0)
        XCTAssertEqual(updated.logicalAnchorIndex, 1,
            "A held gesture's geometry must not inherit the newer rail's indices")
    }

    func testDeepHistoryUsesBoundedSliceWithoutDroppingLogicalIDs() throws {
        let old = (0..<975).map { _ in card(layout: .hero) }
        let ready = (0..<25).map { _ in card(layout: .textOnly) }
        let all = old + ready
        let original = try snapshot(all, anchor: ready[12].id)
        let rail = FeedVisualRailIndex(snapshot: original)
        XCTAssertEqual(rail.logicalCount, 1000)
        XCTAssertEqual(rail.logicalAnchorIndex, 987)
        XCTAssertEqual(rail.visualAnchorID, ready[12].id)
        let bounded = rail.slice(around: 987, backward: 12, forward: 12)
        XCTAssertEqual(bounded.count, 25,
            "Virtualization should inspect only the requested local band")
        XCTAssertEqual(rail.slot(at: 974), .deferred(index: 974, id: old[974].id))
        XCTAssertEqual(rail.slot(at: 975), .ready(index: 975, card: ready[0]))
        XCTAssertEqual(rail.slot(at: 999), .ready(index: 999, card: ready[24]))
        XCTAssertNil(rail.slot(at: -1))
        XCTAssertNil(rail.slot(at: 1000))
        XCTAssertEqual(original.window.items.count, 1000,
            "The B05 retained head is not pruned to make visual admission pass")
    }
}
