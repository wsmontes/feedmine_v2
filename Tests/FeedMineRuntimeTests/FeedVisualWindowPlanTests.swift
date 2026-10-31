import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineRuntime

/// Issue #7 / B05: plan bounded ready *runs* without hiding logical gaps,
/// guessing blank-card heights or committing any SwiftUI layout transition.
final class FeedVisualWindowPlanTests: XCTestCase {
    private func card(_ id: PublicationCardID = .init(), _ layout: PresentationCardLayout = .textOnly)
        -> PresentationCard {
        PresentationCard(id: id, title: "Local", primaryText: nil, timestamp: nil,
            sourceID: nil, sourceDisplayName: nil, providerDisplayName: nil,
            layout: layout, mediaAspectRatio: layout == .textOnly ? nil : 1.5,
            primaryActionKind: nil, image: nil)
    }

    private func snapshot(_ cards: [PresentationCard], anchor: PublicationCardID,
        edition: FeedEditionID = FeedEditionID(), sequence: UUID = UUID(),
        position: UInt64 = 1) throws -> FeedPresentationSnapshot {
        let window = try XCTUnwrap(FeedWindowSnapshot(items: cards,
            anchor: .init(cardID: anchor, placement: .top)))
        return FeedPresentationSnapshot(contextKey: ContextKey(request: .main),
            editionID: edition, window: window,
            provenance: FeedProjectionProvenance(sequenceID: sequence, position: position))
    }

    func testReadyTextOnBothSidesOfMissingHeroProducesSeparateRuns() throws {
        let before = card(), missing = card(.init(), .hero), after = card()
        let s = try snapshot([before, missing, after], anchor: after.id)
        let plan = try XCTUnwrap(FeedVisualWindowPlan(snapshot: s,
            center: 1, backward: 1, forward: 1))
        XCTAssertEqual(plan.logicalCount, 3)
        XCTAssertEqual(plan.visualAnchorID, after.id)
        XCTAssertEqual(plan.segments, [
            .ready(range: 0..<1, cards: [before]),
            .deferred(range: 1..<2, ids: [missing.id]),
            .ready(range: 2..<3, cards: [after])
        ])
        XCTAssertNil(plan.contiguousReadyCards,
            "A missing hero must never be silently collapsed between ready siblings")
        XCTAssertEqual(s.window.items.map(\.id), [before.id, missing.id, after.id])
    }

    func testSavedMissingAnchorHasNoInventedVisualTarget() throws {
        let before = card(), missing = card(.init(), .thumbnail), after = card()
        let s = try snapshot([before, missing, after], anchor: missing.id)
        let plan = try XCTUnwrap(FeedVisualWindowPlan(snapshot: s,
            center: 1, backward: 1, forward: 1))
        XCTAssertNil(plan.visualAnchorID)
        XCTAssertEqual(plan.logicalAnchorIndex, 1)
        XCTAssertEqual(plan.segments.count, 3)
        XCTAssertEqual(s.window.anchor.cardID, missing.id)
    }

    func testB05LongHeadIsBoundedWithoutThrowingHistoryAway() throws {
        let old = (0..<975).map { _ in card(.init(), .hero) }
        let ready = (0..<25).map { _ in card() }
        let s = try snapshot(old + ready, anchor: ready[12].id)
        let plan = try XCTUnwrap(FeedVisualWindowPlan(snapshot: s,
            center: 987, backward: 12, forward: 12))
        XCTAssertEqual(plan.logicalCount, 1000)
        XCTAssertEqual(plan.logicalAnchorIndex, 987)
        XCTAssertEqual(plan.range, 975..<1000)
        XCTAssertEqual(plan.segments, [.ready(range: 975..<1000, cards: ready)])
        XCTAssertEqual(plan.contiguousReadyCards?.map(\.id), ready.map(\.id))
        XCTAssertEqual(s.window.items.count, 1000)
        XCTAssertNil(FeedVisualWindowPlan(snapshot: s, center: 1000, backward: 1, forward: 1))
        XCTAssertNil(FeedVisualWindowPlan(snapshot: s, center: 0, backward: -1, forward: 1))
    }

    func testHandoffRequiresMeasuredSharedReadyCardAndIdleInteraction() throws {
        let a = card(), missing = card(.init(), .hero), b = card(), next = card()
        let ed = FeedEditionID(), sequence = UUID()
        let current = try snapshot([a, missing, b], anchor: b.id, edition: ed, sequence: sequence)
        let updated = try snapshot([a, missing, b, next], anchor: b.id,
            edition: ed, sequence: sequence, position: 2)
        let from = try XCTUnwrap(FeedVisualWindowPlan(snapshot: current,
            center: 2, backward: 0, forward: 0))
        let to = try XCTUnwrap(FeedVisualWindowPlan(snapshot: updated,
            center: 2, backward: 0, forward: 1))
        let before = FeedVisualWindowWitness(cardID: b.id, viewportTop: 180,
            contentOffset: 500, cardHeight: 160, viewportHeight: 650)
        let after = FeedVisualWindowWitness(cardID: b.id, viewportTop: 420,
            contentOffset: 500, cardHeight: 160, viewportHeight: 650)
        XCTAssertNil(FeedVisualWindowHandoff(from: from, to: to,
            before: before, after: after, gestureActive: true),
            "Never swap or compensate the borrowed rail while a finger owns it")
        let handoff = try XCTUnwrap(FeedVisualWindowHandoff(from: from, to: to,
            before: before, after: after, gestureActive: false))
        XCTAssertEqual(handoff.witnessID, b.id)
        XCTAssertEqual(handoff.offsetAdjustment, 240, accuracy: 0.001)
        XCTAssertEqual(handoff.provenance.position, 2)
        XCTAssertEqual(to.contiguousReadyCards?.map(\.id), [b.id, next.id])
        XCTAssertEqual(from.contiguousReadyCards?.map(\.id), [b.id])
    }

    func testScrollMotionAloneNeverInventsAnOffsetAdjustment() throws {
        let a = card(), b = card(), id = FeedEditionID(), sequence = UUID()
        let older = try snapshot([a,b],anchor: b.id,edition:id,sequence:sequence)
        let newer = try snapshot([a,b],anchor: b.id,edition:id,sequence:sequence,position:2)
        let from = try XCTUnwrap(FeedVisualWindowPlan(snapshot: older,
            center: 1,backward: 0,forward: 0))
        let to = try XCTUnwrap(FeedVisualWindowPlan(snapshot: newer,
            center: 1,backward: 0,forward: 0))
        let start = FeedVisualWindowWitness(cardID: b.id, viewportTop: 180,
            contentOffset: 500,cardHeight: 160,viewportHeight: 650)
        let scrolled = FeedVisualWindowWitness(cardID: b.id,viewportTop: 120,
            contentOffset: 560,cardHeight: 160,viewportHeight: 650)
        let value = try XCTUnwrap(FeedVisualWindowHandoff(from:from,to:to,
            before:start,after:scrolled,gestureActive:false))
        XCTAssertEqual(value.offsetAdjustment,0,accuracy:0.001)
    }

    func testHistoricalReentryNeedsAReadyContinuousRunBeforeAnyMeasuredHandoff() throws {
        let hero = card(.init(), .hero), middle = card(), reader = card()
        let edition = FeedEditionID(), sequence = UUID()
        let old = try snapshot([hero, middle, reader], anchor: reader.id,
            edition: edition, sequence: sequence)
        let oldPlan = try XCTUnwrap(FeedVisualWindowPlan(snapshot: old,
            center: 2, backward: 0, forward: 0))
        let stillMissing = try XCTUnwrap(FeedVisualWindowPlan(snapshot: old,
            center: 1, backward: 1, forward: 1))
        XCTAssertNil(stillMissing.contiguousReadyCards,
            "Do not bridge a released historical hero with ready text")

        // The re-entry operation must return a NEW snapshot whose hero has
        // real pixels, retaining the same ID and historical ordinal. The actual
        // SHA-256 materialization transition is tested in RenderReadyHistoryReturnTests.
        // Here the old snapshot cannot authorize a handoff to a gap-filled plan.
        let seen = FeedVisualWindowWitness(cardID: reader.id, viewportTop: 100,
            contentOffset: 500, cardHeight: 160, viewportHeight: 650)
        XCTAssertNil(FeedVisualWindowHandoff(from: oldPlan, to: stillMissing,
            before: seen, after: seen, gestureActive: false))
        XCTAssertEqual(oldPlan.contiguousReadyCards?.map(\.id), [reader.id],
            "A blocked re-entry must keep the reader's existing visible run")
        XCTAssertEqual(old.window.items.map(\.id), [hero.id, middle.id, reader.id])
    }

    func testHandoffRejectsOffscreenWitnessBeforeLayoutMutation() throws {
        let first = card(), reader = card()
        let edition = FeedEditionID(), sequence = UUID()
        let prior = try snapshot([first, reader], anchor: reader.id,
            edition: edition, sequence: sequence)
        let later = try snapshot([first, reader], anchor: reader.id,
            edition: edition, sequence: sequence, position: 2)
        let from = try XCTUnwrap(FeedVisualWindowPlan(snapshot: prior,
            center: 1, backward: 0, forward: 0))
        let to = try XCTUnwrap(FeedVisualWindowPlan(snapshot: later,
            center: 1, backward: 0, forward: 0))
        let offscreen = FeedVisualWindowWitness(cardID: reader.id,
            viewportTop: 900, contentOffset: 500,
            cardHeight: 160, viewportHeight: 650)
        let measuredAfter = FeedVisualWindowWitness(cardID: reader.id,
            viewportTop: 180, contentOffset: 500,
            cardHeight: 160, viewportHeight: 650)
        XCTAssertNil(FeedVisualWindowHandoff(from: from, to: to,
            before: offscreen, after: measuredAfter, gestureActive: false),
            "An offscreen historical card cannot witness the reader's scroll position")

        let above = FeedVisualWindowWitness(cardID: reader.id,
            viewportTop: -160, contentOffset: 500,
            cardHeight: 160, viewportHeight: 650)
        XCTAssertNil(FeedVisualWindowHandoff(from: from, to: to,
            before: above, after: measuredAfter, gestureActive: false))
        let visible = FeedVisualWindowWitness(cardID: reader.id,
            viewportTop: -60, contentOffset: 500,
            cardHeight: 160, viewportHeight: 650)
        XCTAssertNotNil(FeedVisualWindowHandoff(from: from, to: to,
            before: visible, after: measuredAfter, gestureActive: false),
            "A partly visible measured reader is a valid shared witness")
    }

    func testForeignScopeUnreadyWitnessAndUnmeasuredLayoutAreRejected() throws {
        let a = card(), blocked = card(.init(),.hero), b = card()
        let ed=FeedEditionID(), sequence=UUID()
        let old=try snapshot([a,blocked,b],anchor:b.id,edition:ed,sequence:sequence)
        let wrong=try snapshot([a,blocked,b],anchor:b.id,edition:FeedEditionID(),sequence:sequence)
        let same=try snapshot([a,blocked,b],anchor:b.id,edition:ed,sequence:sequence,position:2)
        let x=try XCTUnwrap(FeedVisualWindowPlan(snapshot:old,center:1,backward:1,forward:1))
        let y=try XCTUnwrap(FeedVisualWindowPlan(snapshot:wrong,center:1,backward:1,forward:1))
        let z=try XCTUnwrap(FeedVisualWindowPlan(snapshot:same,center:1,backward:1,forward:1))
        let proof=FeedVisualWindowWitness(cardID:b.id,viewportTop:100,
            contentOffset:200,cardHeight:160,viewportHeight:650)
        let unready=FeedVisualWindowWitness(cardID:blocked.id,viewportTop:100,
            contentOffset:200,cardHeight:160,viewportHeight:650)
        let resized=FeedVisualWindowWitness(cardID:b.id,viewportTop:100,
            contentOffset:200,cardHeight:161,viewportHeight:650)
        XCTAssertNil(FeedVisualWindowHandoff(from:x,to:y,before:proof,after:proof,gestureActive:false))
        XCTAssertNil(FeedVisualWindowHandoff(from:x,to:z,before:unready,after:unready,gestureActive:false))
        XCTAssertNil(FeedVisualWindowHandoff(from:x,to:z,before:proof,after:resized,gestureActive:false))
        XCTAssertNil(FeedVisualWindowHandoff(from:x,to:z,before:nil,after:proof,gestureActive:false))
        XCTAssertNil(FeedVisualWindowHandoff(from:x,to:z,before:proof,after:proof,gestureActive:false),
            "A shared ready card cannot authorize flattening a plan with deferred gaps")
    }
}
