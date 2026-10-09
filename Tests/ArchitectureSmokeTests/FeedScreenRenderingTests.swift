#if os(macOS)
import AppKit
import Vision
import SwiftUI
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineUI
import FeedMineComposition

@MainActor
final class FeedScreenRenderingTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let session: FeedSession
        let editionID: FeedEditionID
        let cardIDs: [PublicationCardID]
    }

    private func fixture(context: FeedContext = .init(request: .main), editionID: FeedEditionID = FeedEditionID()) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: version, eligibilityPolicyVersion: version,
            scoringPolicyVersion: version, sequencingPolicyVersion: version, exposurePolicyVersion: version,
            selectionSchemaVersion: .init(rawValue: 1))
        let candidates = (0..<4).map { index in
            Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                headline: ["Zebra headline", "Amber headline", "River headline", "Meadow headline"][index], summary: "Local content \(index)",
                timestamp: .init(value: Date(timeIntervalSince1970: Double(index)), kind: .observed), language: nil, providerID: nil)
        }
        let selection = SelectionResult(editorialRevision: revision, orderedCandidates: candidates,
            supplyReport: .init(examinedCount: 4, nextCursor: nil, exhausted: true))
        let inputs = candidates.map { candidate in
            PublicationPreparationInput(origin: .init(originRecordID: candidate.originRecordID,
                originRevisionID: candidate.originRevisionID, sourceID: nil, providerID: nil,
                sourceDisplayName: "Local source", providerDisplayName: nil), contentEntityID: nil,
                contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }
        let cardIDs = candidates.map { _ in PublicationCardID() }
        _ = try PublicationCoordinator(database: database).createEdition(.init(selection: selection,
            drafts: PublicationPreparation.drafts(selection: selection, inputs: inputs), editionID: editionID,
            publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1, editionCreatedAt: Date(timeIntervalSince1970: 10),
            segmentID: FeedSegmentID(), segmentSeed: 2, segmentCreatedAt: Date(timeIntervalSince1970: 11), cardIDs: cardIDs))
        let history = PublicationHistory(database: database)
        try history.saveCursor(.init(editionID: editionID, anchor: .init(cardID: cardIDs[0], placement: .top)),
            updatedAt: Date(timeIntervalSince1970: 12))
        return .init(database: database, session: FeedSession(publicationHistory: history), editionID: editionID, cardIDs: cardIDs)
    }

    private func snapshot(_ f: Fixture, backward: Int = 1, forward: Int = 1) async throws -> FeedPresentationSnapshot {
        let restored = try await f.session.restoreLocalPresentation(backwardCapacity: backward, forwardCapacity: forward)
        return try XCTUnwrap(restored)
    }

    private func card(layout: PublishedCardLayout = .textOnly, title: String? = "Local headline",
        text: String? = "Published local text", metadata: Bool = true,
        timestampKind: PublishedTimestampKind = .observed) throws -> PresentationCard {
        let published = try XCTUnwrap(PublishedCard(id: PublicationCardID(),
            origin: .init(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: nil, providerID: nil, sourceDisplayName: metadata ? "Local source" : nil,
                providerDisplayName: metadata ? "Local provider" : nil),
            contentEntityID: nil, contentClusterID: nil, text: .init(title: title, primaryText: text),
            timestamp: metadata ? .init(value: Date(timeIntervalSince1970: 1_700_000_000), kind: timestampKind) : nil,
            media: .none, renderContract: XCTUnwrap(RenderContract(layout: layout, mediaAspectRatio: nil)),
            primaryAction: nil))
        return PresentationCard(publishedCard: published)
    }

    private struct Hosted {
        let view: NSHostingView<AnyView>
        let window: NSWindow
    }

    private func host<V: View>(_ view: V, width: CGFloat = 720) -> Hosted {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: AnyView(view
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .frame(width: width, height: 900)
            .background(Color.white)))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        return Hosted(view: hosting, window: window)
    }

    private func renderedText<V: View>(_ view: V) throws -> [String] {
        let hosted = host(view)
        return try renderedText(hosted)
    }

    private func renderedText(_ hosted: Hosted) throws -> [String] {
        let hosting = hosted.view
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["pt-BR", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    func testU1TextOnlyCardActuallyRendersLocalFields() throws {
        let published = try card()
        let text = try renderedText(FeedCardView(card: published))
        XCTAssertTrue(text.contains("Local headline"), text.description)
        XCTAssertTrue(text.contains("Published local text"), text.description)
        XCTAssertTrue(text.contains("Local source"), text.description)
        XCTAssertTrue(text.contains("Local provider"), text.description)
    }

    func testU2AbsentOptionalContentRendersWithoutInventedText() throws {
        let empty = try card(title: nil, text: nil, metadata: false)
        XCTAssertEqual(try renderedText(FeedCardView(card: empty)), [])
    }

    func testU3HeroAndThumbnailWithoutExposedAssetRemainTextual() throws {
        for layout in [PublishedCardLayout.hero, .thumbnail] {
            let local = try card(layout: layout)
            let text = try renderedText(FeedCardView(card: local))
            XCTAssertTrue(text.contains("Local headline"), text.description)
            XCTAssertTrue(text.contains("Published local text"), text.description)
            XCTAssertEqual(text.filter { $0.contains("Local") || $0.contains("Published") }.count, 4)
        }
    }

    func testTimestampMeaningIsNotChangedToAuthorship() throws {
        for (kind, expected) in [(PublishedTimestampKind.authored, "Autoria"), (.modified, "Modificado"), (.observed, "Observado")] {
            let text = try renderedText(FeedCardView(card: card(timestampKind: kind)))
            XCTAssertTrue(text.contains { $0.contains(expected) && $0.contains("2023") }, text.description)
        }
    }

    func testU4RealViewSequenceUsesPublishedOccurrenceIDs() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in XCTFail("False viewport") }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let sequence = try XCTUnwrap(publishedSequence(in: FeedScreen(store: store).body))
        XCTAssertEqual(sequence.occurrenceIDs, Array(f.cardIDs.prefix(2)))
        XCTAssertEqual(sequence.titles, ["Zebra headline", "Amber headline"])
        let text = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertTrue(text.contains("Zebra headline"), text.description)
        XCTAssertTrue(text.contains("Amber headline"), text.description)
    }

    func testU5PublishedOrderIsRenderedRatherThanTitleSorting() async throws {
        let f = try fixture(), first = try await snapshot(f, forward: 3)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let text = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertEqual(text.filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline", "River headline", "Meadow headline"])
    }

    func testU6ImmediateLocalPresentationHasNoRemotePrerequisite() async throws {
        let f = try fixture(), first = try await snapshot(f)
        var calls = 0
        let store = FeedScreenStore { _, _ in calls += 1 }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let text = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertEqual(text.filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        XCTAssertFalse(text.contains { $0.contains("Preparando") })
        XCTAssertEqual(calls, 0)
    }

    func testU7PendingKeepsRenderedCardsWithoutLoadingSurface() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        let text = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertEqual(text.filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        XCTAssertFalse(text.contains { $0.contains("Preparando") })
    }

    func testU8FailureAndOtherWorkFactsKeepRenderedCards() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        for work in [FeedPresentationState.Work.failed(message: "External failure"), .deferred, .unavailable] {
            try store.install(FeedPresentationHandoff.report(work, into: store.state))
            let text = try renderedText(FeedScreen(store: store).frame(height: 900))
            XCTAssertEqual(text.filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
            XCTAssertFalse(text.contains { $0.contains("Preparando") })
        }
    }

    func testU9InitialPendingRendersOnlyFactualPreparation() throws {
        let store = FeedScreenStore { _, _ in XCTFail("Automatic work") }
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        let text = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertEqual(text, ["Preparando apresentação local"])
    }

    func testU10AllNonPresentationFactsRemainDistinctAndNonterminal() throws {
        let cases: [(FeedPresentationState.Work, String)] = [
            (.idle, "Nenhuma apresentação local recebida"),
            (.unavailable, "Apresentação indisponível no momento"),
            (.deferred, "Preparação adiada"),
            (.failed(message: "Falha recebida da composição"), "Falha recebida da composição")
        ]
        for (work, expected) in cases {
            let store = FeedScreenStore { _, _ in XCTFail("Automatic work") }
            try store.install(FeedPresentationHandoff.report(work, into: store.state))
            XCTAssertEqual(try renderedText(FeedScreen(store: store).frame(height: 900)), [expected])
            XCTAssertEqual(try renderedText(FeedLoadingView(work: work).frame(height: 900)), [expected])
        }
    }

    func testU11NewSameEditionWindowRendersExactReceivedSequence() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let screen = FeedScreen(store: store)
        XCTAssertEqual(try renderedText(screen.frame(height: 900)).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[1], placement: .center)))
        let next = try XCTUnwrap(moved)
        try store.install(try FeedPresentationHandoff.receive(snapshot: next, into: store.state))
        XCTAssertEqual(try renderedText(screen.frame(height: 900)).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline", "River headline"])
        let sequence = try XCTUnwrap(publishedSequence(in: screen.body))
        XCTAssertEqual(sequence.occurrenceIDs, Array(f.cardIDs.prefix(3)))
        XCTAssertEqual(store.state.presentation?.window.anchor, next.window.anchor)
        XCTAssertEqual(store.state.presentation?.editionID, first.editionID)
        XCTAssertEqual(store.state.presentation?.contextKey, first.contextKey)
    }

    func testU12DeferredViewportCaptureEmitsNoFabricatedObservation() async throws {
        let f = try fixture(), first = try await snapshot(f)
        var calls = 0
        let store = FeedScreenStore { _, _ in calls += 1 }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        _ = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(store.state.presentation, first)
    }

    func testU13RenderingPerformsNoDurableWorkOrIntentEmission() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let history = PublicationHistory(database: f.database)
        let before = try history.restore(backwardCapacity: 0, forwardCapacity: 0)
        let segments = try PublicationStore(database: f.database).segments(editionID: f.editionID)
        let store = FeedScreenStore { _, _ in XCTFail("Unrequested execution") }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        _ = try renderedText(FeedScreen(store: store).frame(height: 900))
        _ = try renderedText(FeedCardView(card: XCTUnwrap(first.window.items.first)))
        XCTAssertEqual(try history.restore(backwardCapacity: 0, forwardCapacity: 0), before)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID), segments)
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, first)
    }

    func testU14UIBoundaryHasNoProductionImportsOrHiddenEffects() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ui = root.appendingPathComponent("Sources/FeedMineUI")
        for file in try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let imports = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("import ") }
            for forbidden in ["FeedMineComposition", "FeedMinePersistence", "FeedMineAcquisition", "FeedMinePublication", "FeedMineSyndication", "FeedMineEditorial"] {
                XCTAssertFalse(imports.contains("import " + forbidden), file.lastPathComponent + ": " + forbidden)
            }
        }
        for file in ["FeedScreen.swift", "FeedCardView.swift", "FeedLoadingView.swift"] {
            let source = try String(contentsOf: ui.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["URLSession", "AsyncImage", "ContentStore", "RuntimeDatabase", "AcquisitionCoordinator", "SelectionEngine",
                "PublicationCoordinator", "PublicationStore", "Task", ".task", ".onAppear", ".onDisappear", "Timer", "sleep",
                "retry", "backoff", "scheduler", "cache", "generation", "checkpoint", "UUID(", "PublicationCardID(", "exhausted", "@State", "@Observable", "GeometryReader", "NavigationStack"] {
                if file == "FeedScreen.swift" && forbidden == "@State" { continue }
                XCTAssertFalse(source.contains(forbidden), file + ": " + forbidden)
            }
        }
        let screen = try String(contentsOf: ui.appendingPathComponent("FeedScreen.swift"), encoding: .utf8)
        let states = screen.split(separator: "\n").filter { $0.contains("@State") }
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.trimmingCharacters(in: .whitespaces), "@State private var capture = FeedVisualCapture()")
        XCTAssertTrue(screen.contains("#available(iOS 18, macOS 15, *)"))
        XCTAssertTrue(screen.contains("onScrollGeometryChange"))
        XCTAssertTrue(screen.contains("onScrollPhaseChange"))
        XCTAssertTrue(screen.contains("store.submitViewport(event.observation, activity: event.activity)"))
        FeedViewportCaptureTests.assertVisualBoundary()

    }

    func testNativeHostingObservesStoreWithoutReplacingView() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in XCTFail("Automatic viewport") }
        let hosted = host(FeedScreen(store: store))
        XCTAssertEqual(try renderedText(hosted), ["Nenhuma apresentação local recebida"])
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        XCTAssertEqual(try renderedText(hosted).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(try renderedText(hosted).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        let moved = try await f.session.submitViewport(.init(anchor: .init(cardID: f.cardIDs[1], placement: .center)))
        try store.install(try FeedPresentationHandoff.receive(snapshot: moved, into: store.state))
        XCTAssertEqual(try renderedText(hosted).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline", "River headline"])
    }

    func testCardAdaptsToNarrowAvailableWidth() throws {
        let published = try card(title: "Local headline with additional words that must wrap", text: "Published local text")
        let text = try renderedText(host(FeedCardView(card: published), width: 320))
        XCTAssertTrue(text.joined(separator: " ").contains("Local headline with additional words that must wrap"), text.description)
        XCTAssertTrue(text.contains("Published local text"), text.description)
        XCTAssertTrue(text.contains("Local source"), text.description)
    }

    // Inspect the real declarative ForEach (not a parallel rendering model).
    private func publishedSequence(in value: Any, depth: Int = 0) -> (any PublishedCardSequence)? {
        if let sequence = value as? any PublishedCardSequence { return sequence }
        guard depth < 12 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let sequence = publishedSequence(in: child.value, depth: depth + 1) { return sequence }
        }
        return nil
    }
}

@MainActor
private protocol PublishedCardSequence {
    var occurrenceIDs: [PublicationCardID] { get }
    var titles: [String?] { get }
}

extension ForEach: PublishedCardSequence where Data == [PresentationCard], ID == PublicationCardID {
    fileprivate var occurrenceIDs: [PublicationCardID] { data.map(\.id) }
    fileprivate var titles: [String?] { data.map(\.title) }
}

#endif
