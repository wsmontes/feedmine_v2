#if canImport(UIKit)
import Observation
import SwiftUI
import UIKit
import XCTest
import FeedMineDomain
@testable import FeedMineRuntime
@testable import FeedMineUI

/// Live SwiftUI callback coverage for issue #32. This intentionally proves
/// staging, not the future measured physical swap or its rollback.
@MainActor
@Observable
private final class NativeStageCaptureBox {
    var value = FeedVisualCapture()
}

@available(iOS 18, *)
@MainActor
private struct NativeStageHost: View {
    let store: FeedScreenStore
    let captureBox: NativeStageCaptureBox

    var body: some View {
        let binding = Binding<FeedVisualCapture>(
            get: { captureBox.value },
            set: { captureBox.value = $0 })
        ScrollView {
            LazyVStack {
                ForEach(store.renderedItems, id: \.id) { card in
                    Text(card.title ?? "").frame(maxWidth: .infinity).frame(height: 150)
                }
            }
            .scrollTargetLayout()
        }
        .modifier(NativeFeedViewport(capture: binding, store: store))
        .frame(width: 360, height: 600)
    }
}

@MainActor
final class FeedNativeStageHostTests: XCTestCase {
    private func findScroll(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findScroll(child) { return scroll }
        }
        return nil
    }

    func testNativeViewportCallbacksStageThenRevokeNonPrefixWindowWithoutPhysicalSwap() async throws {
        guard #available(iOS 18, *) else { return }
        let ids = (0..<4).map { _ in PublicationCardID() }
        let cards = ids.enumerated().map { index, id in
            PresentationCard(id: id, title: "Stage \(index)",
                primaryText: "Local ready text", timestamp: nil,
                sourceID: nil, sourceDisplayName: nil, providerDisplayName: nil,
                layout: .textOnly, mediaAspectRatio: nil,
                primaryActionKind: nil, image: nil)
        }
        let edition = FeedEditionID(), sequence = UUID()
        func snapshot(_ range: Range<Int>, position: UInt64) throws -> FeedPresentationSnapshot {
            FeedPresentationSnapshot(contextKey: FeedContext(request: .main).key,
                editionID: edition,
                window: try XCTUnwrap(FeedWindowSnapshot(items: Array(cards[range]),
                    anchor: .init(cardID: ids[1], placement: .top))),
                provenance: .init(sequenceID: sequence, position: position))
        }

        var viewportEvents = 0
        let store = FeedScreenStore(onViewport: { _, _ in viewportEvents += 1 },
            onRenderedViewport: { _, _ in viewportEvents += 1 })
        try store.install(.init(presentation: snapshot(0..<3, position: 1)))
        let captureBox = NativeStageCaptureBox()
        let host = UIHostingController(rootView: NativeStageHost(store: store,
            captureBox: captureBox))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; withExtendedLifetime(window) {} }

        func layout() async {
            for _ in 0..<30 {
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                await Task.yield()
            }
        }
        await layout()
        let scroll = try XCTUnwrap(findScroll(host.view))
        let initialOffset = scroll.contentOffset.y
        XCTAssertEqual(captureBox.value.readyWindowHandshake?.displayed?.cards.map(\.id),
            Array(ids[0..<3]), "The live modifier must install the drawn physical rail")
        let beforeEvents = viewportEvents

        try store.install(.init(presentation: snapshot(1..<4, position: 2)))
        await layout()
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(ids[1..<4]))
        XCTAssertEqual(store.renderedItems.map(\.id), Array(ids[0..<3]))
        XCTAssertEqual(captureBox.value.readyWindowHandshake?.displayed?.cards.map(\.id),
            Array(ids[0..<3]), "Staging must not pretend the new rail is already painted")
        XCTAssertEqual(captureBox.value.readyWindowHandshake?.pending?.cards.map(\.id),
            Array(ids[1..<4]), "SwiftUI onChange must actually stage the semantic successor")
        XCTAssertNil(captureBox.value.readyWindowHandshake?.provisionalID)
        XCTAssertEqual(scroll.contentOffset.y, initialOffset, accuracy: 1)
        XCTAssertEqual(viewportEvents, beforeEvents,
            "A semantic projection alone cannot fabricate reader exposure")

        // A later safely append-only projection must revoke the stale proposal.
        try store.install(.init(presentation: snapshot(0..<4, position: 3)))
        await layout()
        XCTAssertEqual(store.renderedItems.map(\.id), ids)
        XCTAssertEqual(captureBox.value.readyWindowHandshake?.displayed?.cards.map(\.id), ids)
        XCTAssertNil(captureBox.value.readyWindowHandshake?.pending)
        XCTAssertNil(captureBox.value.readyWindowHandshake?.provisionalID)
    }

    /// Unlike the reduced modifier harness, this mounts FeedScreen itself.
    /// It proves the same native offset writer is attached to the actual
    /// ScrollView and receives a measured common visible card. It does not
    /// pretend the unimplemented non-prefix physical swap has happened.
    func testFullFeedScreenConnectsNativeProbeAndKeepsVisibleReaderOnStaging() async throws {
        guard #available(iOS 18, *) else { return }
        let ids = (0..<4).map { _ in PublicationCardID() }
        let cards = ids.enumerated().map { index, id in
            PresentationCard(id: id, title: "Real host \(index)",
                primaryText: String(repeating: "Published local text. ", count: 5),
                timestamp: nil, sourceID: nil, sourceDisplayName: nil,
                providerDisplayName: nil, layout: .textOnly,
                mediaAspectRatio: nil, primaryActionKind: nil, image: nil)
        }
        let edition = FeedEditionID(), sequence = UUID()
        func snapshot(_ range: Range<Int>, ordinal: UInt64) throws -> FeedPresentationSnapshot {
            FeedPresentationSnapshot(contextKey: FeedContext(request: .main).key,
                editionID: edition,
                window: try XCTUnwrap(FeedWindowSnapshot(items: Array(cards[range]),
                    anchor: .init(cardID: ids[1], placement: .top))),
                provenance: .init(sequenceID: sequence, position: ordinal))
        }

        var viewportEvents = 0
        let store = FeedScreenStore(onViewport: { _, _ in viewportEvents += 1 },
            onRenderedViewport: { _, _ in viewportEvents += 1 })
        try store.install(.init(presentation: snapshot(0..<3, ordinal: 1)))
        let host = UIHostingController(rootView:
            FeedScreen(store: store).frame(width: 390, height: 780))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 780))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; withExtendedLifetime(window) {} }

        func layout() async {
            for _ in 0..<60 {
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                await Task.yield()
            }
        }
        func findProbe(_ view: UIView) -> FeedNativeScrollProbe.Probe? {
            if let probe = view as? FeedNativeScrollProbe.Probe { return probe }
            for child in view.subviews {
                if let probe = findProbe(child) { return probe }
            }
            return nil
        }
        func ancestorScroll(_ view: UIView) -> UIScrollView? {
            var node = view.superview
            while let parent = node {
                if let scroll = parent as? UIScrollView { return scroll }
                node = parent.superview
            }
            return nil
        }

        await layout()
        let probe = try XCTUnwrap(findProbe(host.view))
        let scroll = try XCTUnwrap(ancestorScroll(probe))
        let native = probe.access
        XCTAssertTrue(native.scrollView === scroll,
            "The actual FeedScreen probe must bind the same physical UIScrollView")
        XCTAssertEqual(native.currentWindowIDs, Array(ids[0..<3]),
            "The native writer must track actual drawn IDs, not the semantic rail")
        XCTAssertTrue(native.observedVisibleCardIDs.contains(ids[1]),
            "Common card B missing from writer. Visible-native IDs: \(native.observedVisibleCardIDs.map { $0.rawValue.uuidString }.sorted()), capture probeEntries: \(FeedVisualCapture.probeEntries), probeGuards: \(FeedVisualCapture.probeGuards), cardObservations: \(FeedVisualCapture.cardObservations), physicalIDs: \(native.currentWindowIDs.count), nativeScrollAttached: \(native.scrollView != nil)")
        let offsetBefore = scroll.contentOffset.y
        let eventsBefore = viewportEvents

        try store.install(.init(presentation: snapshot(1..<4, ordinal: 2)))
        await layout()
        let currentProbe = try XCTUnwrap(findProbe(host.view))
        XCTAssertTrue(currentProbe.access === native,
            "Staging cannot silently replace the native offset owner")
        XCTAssertTrue(native.scrollView === scroll,
            "The writer must remain attached to the same native scroll view")
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(ids[1..<4]))
        XCTAssertEqual(store.renderedItems.map(\.id), Array(ids[0..<3]))
        XCTAssertEqual(native.currentWindowIDs, Array(ids[0..<3]))
        XCTAssertTrue(native.observedVisibleCardIDs.contains(ids[1]),
            "Common card B still has no native proof after semantic staging")
        XCTAssertEqual(scroll.contentOffset.y, offsetBefore, accuracy: 1,
            "Staging alone must not move the reader")
        XCTAssertEqual(viewportEvents, eventsBefore,
            "A semantic transition must not invent viewport/seen activity")
        XCTAssertEqual(native.appliedCount, 0,
            "No native offset correction is justified before a physical swap")

        try store.install(.init(presentation: snapshot(0..<4, ordinal: 3)))
        await layout()
        XCTAssertEqual(store.renderedItems.map(\.id), ids)
        XCTAssertEqual(native.currentWindowIDs, ids,
            "The same real probe must receive the safely append-only rail")
    }

}
#endif
