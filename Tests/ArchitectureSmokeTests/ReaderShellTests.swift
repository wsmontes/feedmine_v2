import Foundation
import XCTest
import FeedMineDomain
import FeedMineRuntime
import FeedMineUI

/// T5 — the reader shell: what it offers, what it reports, and what it must never start.
@MainActor
final class ReaderShellTests: XCTestCase {
    private func store(destinations: Set<ReaderDestination> = [],
        onSubmitSearch: @escaping @MainActor (String) -> Void = { _ in },
        onNavigate: @escaping @MainActor (ReaderDestination) -> Void = { _ in }) -> FeedScreenStore {
        FeedScreenStore(onViewport: { _, _ in }, availableDestinations: destinations,
            onSubmitSearch: onSubmitSearch, onNavigate: onNavigate)
    }

    /// V1's menu order, limited to what the host can present. A destination the host cannot present is
    /// not an entry, so the overflow menu can never contain a dead item.
    func testMenuShowsOnlyDestinationsTheHostCanPresent() {
        XCTAssertTrue(store().menuEntries.isEmpty)
        let entries = store(destinations: [.sources, .settings]).menuEntries
        XCTAssertEqual(entries.map(\.id), ["sources", "settings"],
            "V1's order is kept, and only the offered destinations appear")
        XCTAssertEqual(entries.first?.systemImage, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(entries.last?.systemImage, "gearshape")
        // The full V1 vocabulary exists as values, including the conditional items and their groups.
        XCTAssertEqual(ReaderMenuEntry.standard.count, 14)
        XCTAssertEqual(ReaderMenuEntry.standard.filter(\.isDestructive).map(\.id),
            ["delete-curated", "delete-smart-bookmark"])
        XCTAssertEqual(Set(ReaderMenuEntry.standard.map(\.id)).count, ReaderMenuEntry.standard.count,
            "menu identities are unique even where two items open the same surface")
    }

    /// The search surface is presentation state: submitting a term reports it, and the shell starts no
    /// work of any kind (no production, no context, no request).
    func testSearchSurfaceReportsOneSubmissionAndStartsNoWork() {
        var submitted: [String] = []
        let subject = store(onSubmitSearch: { submitted.append($0) })
        XCTAssertFalse(subject.isSearching)
        subject.toggleSearch()
        XCTAssertTrue(subject.isSearching)
        subject.submitSearch("   ")
        XCTAssertTrue(submitted.isEmpty, "blank input is not a submission")
        XCTAssertTrue(subject.searchQuery.isEmpty)
        subject.submitSearch("  mercado  ")
        XCTAssertEqual(submitted, ["mercado"])
        XCTAssertEqual(subject.searchQuery, "mercado")
        subject.cancelSearch()
        XCTAssertFalse(subject.isSearching)
        XCTAssertTrue(subject.searchQuery.isEmpty, "cancelling clears the query, not the presentation")
    }

    /// Navigating to a destination the host does not implement is refused here, not silently dropped
    /// by a switch in the host.
    func testNavigationIsRefusedForUnavailableDestinations() {
        var navigated: [ReaderDestination] = []
        let subject = store(destinations: [.sources], onNavigate: { navigated.append($0) })
        subject.navigate(to: .settings)
        XCTAssertTrue(navigated.isEmpty, "a destination the host did not offer is not forwarded")
        subject.navigate(to: .sources)
        XCTAssertEqual(navigated, [.sources])
    }

    /// Feedback is the host's message with the shell's lifetime.
    func testToastIsHostOwned() {
        let subject = store()
        XCTAssertNil(subject.toast)
        subject.showToast(text: "Link copiado", systemImage: "doc.on.doc")
        XCTAssertEqual(subject.toast?.text, "Link copiado")
        XCTAssertEqual(subject.toast?.systemImage, "doc.on.doc")
        subject.dismissToast()
        XCTAssertNil(subject.toast)
    }

    /// The shell measures its own chrome and nothing else: the header height comes from a layout
    /// preference, never from production, and the store's work value cannot change it.
    func testShellMeasuresOnlyItsOwnChrome() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let shell = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineUI/Reader/ReaderShell.swift"),
            encoding: .utf8)
        XCTAssertTrue(shell.contains("onPreferenceChange(ReaderHeaderHeightKey.self)"))
        XCTAssertTrue(shell.contains("headerHeight = height"))
        for forbidden in ["FeedRunwayDriver", "PublicationStore", "URLSession", "AcquisitionCoordinator",
            "RuntimeDatabase", "SessionStore"] {
            XCTAssertFalse(shell.contains(forbidden), "the shell must not reference " + forbidden)
        }
        // The reader's chrome reports intents through the store; it never owns a session or a cursor.
        XCTAssertTrue(shell.contains("store.navigate(to:"))
        XCTAssertTrue(shell.contains("store.submitSearch("))
    }

    /// V1's header controls, with V1's identifiers, and the work feedback is still non-geometric.
    func testHeaderControlsAndFeedbackAreTheV1Ones() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let header = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineUI/Reader/ReaderHeader.swift"),
            encoding: .utf8)
        for identifier in ["search-button", "bookmark-boxes-button", "filter-button", "more-menu"] {
            XCTAssertTrue(header.contains(identifier), "V1 control missing: " + identifier)
        }
        XCTAssertTrue(header.contains("44, height: 44"), "V1's header button is 44×44")
        XCTAssertTrue(header.contains("accent.opacity(0.1), in: Circle()"), "V1's tinted circle")
        XCTAssertTrue(header.contains(".ultraThinMaterial"))
        let screen = try String(contentsOf: root.appendingPathComponent("Sources/FeedMineUI/FeedScreen.swift"),
            encoding: .utf8)
        XCTAssertTrue(screen.contains("FeedWorkFeedback"))
        XCTAssertFalse(screen.contains("safeAreaInset"), "work feedback must not change the scroll geometry")
    }
}
