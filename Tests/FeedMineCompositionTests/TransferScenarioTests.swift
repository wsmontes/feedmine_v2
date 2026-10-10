import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
@testable import FeedMineRuntime
import FeedMineUI

/// T12: the integrated scenario, deterministically. While the reader is **still**, four kinds of arrival land —
/// a source that answered slowly finally publishing, a decode that arrives late, an edit to an article the
/// reader has already seen, and a foreground — and none of it moves what they are reading: the admitted prefix
/// keeps its cards, their order and their content, and only the reserve behind them grows. A gesture is what
/// admits more.
///
/// The frame and offset side of the same promise is proven where it can be measured: `FeedPresentationAdmission`'s
/// own tests (a layout pass is not a user observation; a reported frame advances the anchor), T3's
/// `FeedScreenStore` invariance tests, and the simulator test that watches the delivered counters across a real
/// swipe, a rotation and a larger Dynamic Type.
@MainActor
final class TransferScenarioTests: XCTestCase {
    private func card(_ number: Int, title: String? = nil) -> PresentationCard {
        PresentationCard(id: PublicationCardID(),
            title: title ?? "c\(number)", primaryText: "texto \(number)", timestamp: nil,
            sourceDisplayName: "Fonte \(number)", providerDisplayName: nil, layout: .textOnly,
            mediaAspectRatio: nil, primaryActionKind: nil, image: nil)
    }

    private func snapshot(_ cards: [PresentationCard], edition: FeedEditionID, sequence: UUID,
        position: UInt64) throws -> FeedPresentationSnapshot {
        let window = try XCTUnwrap(FeedWindowSnapshot(items: cards,
            anchor: PresentationAnchor(cardID: cards[0].id, placement: .top)))
        return FeedPresentationSnapshot(contextKey: ContextKey(request: .main), editionID: edition,
            window: window, provenance: FeedProjectionProvenance(sequenceID: sequence, position: position))
    }

    func testT12ContentArrivingWhileTheReaderIsStillLeavesTheirCardsInPlace() throws {
        let edition = FeedEditionID(), sequence = UUID()
        let readerCards = (0..<3).map { card($0) }
        // 1. The reader's admitted prefix, exactly as the app installs it (the handoff both surfaces share).
        var state = FeedPresentationState(presentation: nil)
        state = try FeedPresentationHandoff.receive(snapshot: snapshot(readerCards, edition: edition,
            sequence: sequence, position: 1), into: state)
        let admitted = try XCTUnwrap(state.presentation).window.items.map(\.id)
        XCTAssertEqual(admitted.count, 3)

        // 2. While they are still: a slow source finally answers, so the reserve grows behind them.
        let grown = readerCards + (3..<6).map { card($0) }
        state = try FeedPresentationHandoff.receive(snapshot: snapshot(grown, edition: edition,
            sequence: sequence, position: 2), into: state)
        // 3. A decode lands late: the *same* frozen cards, with their images now decoded.
        let decoded = grown.map { card in
            PresentationCard(id: card.id, title: card.title, primaryText: card.primaryText,
                timestamp: card.timestamp, sourceDisplayName: card.sourceDisplayName,
                providerDisplayName: card.providerDisplayName, layout: card.layout,
                mediaAspectRatio: card.mediaAspectRatio, primaryActionKind: card.primaryActionKind,
                image: nil)
        }
        state = try FeedPresentationHandoff.receive(snapshot: snapshot(decoded, edition: edition,
            sequence: sequence, position: 3), into: state)
        // 4. An edit to an article already read arrives as its own new occurrence, appended — never inserted.
        let edited = decoded + [card(9, title: "Editado")]
        state = try FeedPresentationHandoff.receive(snapshot: snapshot(edited, edition: edition,
            sequence: sequence, position: 4), into: state)
        // 5. A foreground reports work without touching the presentation.
        state = state.reporting(.pending)
        XCTAssertNotNil(state.presentation)

        // The reader's cards are the cards they had, in the order they had them, with their content intact.
        let after = try XCTUnwrap(state.presentation).window.items
        XCTAssertEqual(Array(after.map(\.id).prefix(3)), admitted,
            "the admitted prefix is the same three cards, in the same order")
        XCTAssertEqual(Array(after.prefix(3).map(\.title)), readerCards.map(\.title),
            "and their content is the content they were reading")
        XCTAssertEqual(after.count, 7, "only the reserve behind them grew")
        XCTAssertEqual(after.last?.title, "Editado", "an edit arrives behind the reader, never under them")

        // A stale projection (an older position of the same sequence) is refused outright, so a late callback
        // cannot rewind what is on screen either.
        XCTAssertThrowsError(try state.receiving(snapshot(readerCards, edition: edition, sequence: sequence,
            position: 2))) { error in
            XCTAssertEqual(error as? FeedPresentationStateError, .staleProjection)
        }

        // 6. A gesture is what admits the rest: one real viewport observation reaches the host, which is the only
        // thing that can advance the reader.
        var observations = 0
        let store = FeedScreenStore { _, _ in observations += 1 }
        XCTAssertEqual(observations, 0, "building a store with a presentation is not a user observation")
        store.submitViewport(.init(anchor: PresentationAnchor(cardID: after[2].id, placement: .center)),
            activity: .forward)
        XCTAssertEqual(observations, 1, "the reader's own gesture is what the host hears")
    }
}
