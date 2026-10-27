import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineRuntime
import FeedMineUI

/// A filter/source change asks for the new feed's page. These pin the two races measured on 2026-10-27:
///
/// 1. the request must live on the **association's own store**, so a later appearance that re-states the policy (the
///    app host's `prepareFirstScreen`) cannot clear it — the old composition-level stamp compared an *applied* key
///    with the host's *raw* `currentContextKey`, never matched when the selection carried a global exclusion, and
///    `filter_page` stayed 0;
/// 2. the request must be bound **before** anything measures the new screen: a warm projection can lay out and make
///    the reading surface sticky, and "already exposed" then bypassed the page forever.
///
/// The store is given a **real** installed projection (distinct sources, text cards) so the gate is judged on the
/// facts it is judged on in the app; an empty store is the absence surface by design and could not state this.
@MainActor
final class FirstScreenPreparationRequestTests: XCTestCase {
    private func install(_ store: FeedScreenStore, cards: Int = 3) throws -> [PublicationCardID] {
        let ids = (0..<cards).map { _ in PublicationCardID() }
        let items = ids.map { id in
            PresentationCard(id: id, title: "Card \(id.rawValue.uuidString.prefix(4))", primaryText: nil,
                timestamp: nil, sourceID: SourceID(), sourceDisplayName: "Fonte", providerDisplayName: nil,
                layout: .textOnly, mediaAspectRatio: nil, primaryActionKind: nil, mediaIdentity: nil, image: nil)
        }
        let window = try XCTUnwrap(FeedWindowSnapshot(items: items,
            anchor: PresentationAnchor(cardID: ids[0], placement: .top)))
        let snapshot = FeedPresentationSnapshot(contextKey: ContextKey(request: .main),
            editionID: FeedEditionID(), window: window,
            provenance: FeedProjectionProvenance(sequenceID: UUID(), position: 1))
        try store.install(FeedPresentationState(presentation: snapshot))
        return ids
    }

    private func layout(_ store: FeedScreenStore, cardID: PublicationCardID, covering: Bool = true) {
        store.noteFirstScreenLayout(cardID: cardID, contentBottom: covering ? 900 : 300, viewportHeight: 800)
    }

    /// A requested page is drawn even when the measured layout already covers the viewport — and it is the page's own
    /// drawing, not a timer, that resolves the request and records the exposure.
    func testARequestedPageIsNotBypassedByAnEarlyMeasurement() throws {
        let store = FeedScreenStore { _, _ in XCTFail("the first-screen tests never submit a viewport") }
        let ids = try install(store)
        store.noteFirstScreenPreparationRequested()
        XCTAssertTrue(store.requestsPreparationPage)
        layout(store, cardID: ids[0])
        XCTAssertEqual(store.firstScreenSurface, .preparation,
            "a measured layout cannot expose the old feed over a page the reader just asked for")
        XCTAssertTrue(store.requestsPreparationPage)
        store.notePreparationPageDrawn()
        XCTAssertEqual(store.firstScreenSurface, .reading, "the request is honoured once the page was drawn")
        XCTAssertFalse(store.requestsPreparationPage, "the acknowledgement settles the request at that instant")
    }

    /// The host's appearance pass re-states policy only: it must not clear a request that was already bound.
    func testAnAppearanceRestatingPolicyKeepsTheRequest() throws {
        let store = FeedScreenStore { _, _ in XCTFail("the first-screen tests never submit a viewport") }
        let ids = try install(store)
        store.noteFirstScreenPreparationRequested()
        store.noteFirstScreenAppeared(hasSources: true, maximumWait: .seconds(5), ceiling: .seconds(30),
            eligibleProviders: 3)
        XCTAssertTrue(store.requestsPreparationPage, "the appearance re-states policy; it does not decide the request")
        layout(store, cardID: ids[0])
        XCTAssertEqual(store.firstScreenSurface, .preparation)
    }

    /// An ordinary resume (no request) is immediate: one covering layout is the reading surface, as before.
    func testAnOrdinaryResumeIsImmediate() throws {
        let store = FeedScreenStore { _, _ in XCTFail("the first-screen tests never submit a viewport") }
        let ids = try install(store)
        store.noteFirstScreenAppeared(hasSources: true, maximumWait: .seconds(5), ceiling: .seconds(30),
            eligibleProviders: 3)
        layout(store, cardID: ids[0])
        XCTAssertEqual(store.firstScreenSurface, .reading)
        XCTAssertFalse(store.requestsPreparationPage)
    }
}
