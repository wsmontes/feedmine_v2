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
        let restored = try await f.session.admitPresentation(.restore(.init(backwardCapacity: backward, forwardCapacity: forward)))
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

    private func host<V: View>(_ view: V, width: CGFloat = 720, height: CGFloat = 900) -> Hosted {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: AnyView(view
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .frame(width: width, height: height)
            .background(Color.white)))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        return Hosted(view: hosting, window: window)
    }

    private func renderedText<V: View>(_ view: V, height: CGFloat = 900) throws -> [String] {
        let hosted = host(view, height: height)
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

    /// The ported V1 card, rendered with the reader's standard appearance and no action handler: the
    /// delivery is visual-only here, and no interaction is fabricated by the test.
    private func rendered(_ card: PresentationCard) -> FeedItemCardView {
        FeedItemCardView(card: card, appearance: .standard, onAction: { _ in })
    }

    func testU1TextOnlyCardActuallyRendersLocalFields() throws {
        let published = try card()
        let text = try renderedText(rendered(published))
        XCTAssertTrue(text.contains("Local headline"), text.description)
        XCTAssertTrue(text.contains("Published local text"), text.description)
        XCTAssertTrue(text.contains("Local source"), text.description)
        // V1's card never showed the provider line; the field survives in the projection for the
        // surfaces that do (recorded difference, T4).
        XCTAssertFalse(text.contains("Local provider"), text.description)
    }

    func testU2AbsentOptionalContentRendersWithoutInventedText() throws {
        let empty = try card(title: nil, text: nil, metadata: false)
        XCTAssertEqual(try renderedText(rendered(empty)), [])
    }

    func testU3HeroAndThumbnailWithoutExposedAssetRemainTextual() throws {
        for layout in [PublishedCardLayout.hero, .thumbnail] {
            let local = try card(layout: layout)
            let text = try renderedText(rendered(local))
            XCTAssertTrue(text.contains("Local headline"), text.description)
            XCTAssertTrue(text.contains("Published local text"), text.description)
            // Source row, title and summary: the V1 card draws no invented image caption.
            XCTAssertEqual(text.filter { $0.contains("Local") || $0.contains("Published") }.count, 3)
        }
    }

    func testTimestampMeaningIsNotChangedToAuthorship() throws {
        // V1 shows the published date without re-labelling its kind. The card must not invent an
        // authorship claim for a timestamp that has another meaning (T4 difference, recorded). The date itself
        // is rendered in the interface language, so this pins that a date *is* rendered, not its formatting.
        for kind in [PublishedTimestampKind.authored, .modified, .observed] {
            let text = try renderedText(rendered(card(timestampKind: kind))).joined(separator: " ")
            XCTAssertTrue(text.contains { $0.isNumber },
                "the card states a date for a timestamp of any kind: " + text)
            for claim in ["Autoria", "Modificado", "Observado"] {
                XCTAssertFalse(text.contains(claim), "the card must not label the timestamp: " + claim)
            }
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

    /// The shell is mounted over the no-item loading surface (the empty-source escape: header and context control
    /// must stay usable while a source has nothing to show), so the pending screen carries the shell's own work
    /// badge in addition to the factual preparation line. The Vision OCR in `renderedText` reads the badge's
    /// glyph as a leading bullet; the text after it is the product's own.
    func testU9InitialPendingRendersOnlyFactualPreparation() throws {
        let store = FeedScreenStore { _, _ in XCTFail("Automatic work") }
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        let text = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertEqual(text, ["• Buscando novidades", "Descobrindo histórias para você..."])
    }

    func testU10AllNonPresentationFactsRemainDistinctAndNonterminal() throws {
        let cases: [(FeedPresentationState.Work, [String], [String])] = [
            (.idle, ["Descobrindo histórias para você..."], ["Descobrindo histórias para você..."]),
            (.pending, ["• Buscando novidades", "Descobrindo histórias para você..."],
                ["Descobrindo histórias para você..."]),
            (.unavailable, ["Ainda não encontramos histórias para você.", "Tentar novamente", "Ajustar interesses"],
                ["Ainda não encontramos histórias para você."]),
            (.unreachable, ["Não foi possível conectar.", "Não conseguimos buscar novas histórias agora.", "Tentar novamente"],
                ["Não foi possível conectar.", "Não conseguimos buscar novas histórias agora."]),
            (.deferred, ["Aguardando nova oportunidade", "Nada está sendo buscado agora.", "Tentar novamente"],
                ["Aguardando nova oportunidade", "Nada está sendo buscado agora."]),
            (.failed(message: "Falha recebida da composição"),
                ["A Falha recebida da composição", "Falha recebida da composição"],
                ["Falha recebida da composição"])
        ]
        for (work, expectedScreen, expectedView) in cases {
            let store = FeedScreenStore { _, _ in XCTFail("Automatic work") }
            try store.install(FeedPresentationHandoff.report(work, into: store.state))
            XCTAssertEqual(try renderedText(FeedScreen(store: store).frame(height: 900)), expectedScreen)
            XCTAssertEqual(try renderedText(FeedLoadingView(work: work).frame(height: 900)), expectedView)
        }
    }

    /// NF-04: `deferred` is the outcome of an opportunity the engine did **not** run (resources denied or a
    /// generation conflict superseded it). The surface used to say "looking for more news" and promised a retry
    /// "in a moment" — both invented work no owner produced. It now states the wait and offers the host's retry,
    /// which really runs an opportunity (`refreshFromTheReader` → `retryNow` → `foreground`).
    func testDeferredWorkStatesTheWaitWithoutClaimingASearch() throws {
        let store = FeedScreenStore { _, _ in XCTFail("Automatic work") }
        try store.install(FeedPresentationHandoff.report(.deferred, into: store.state))
        let text = try renderedText(FeedScreen(store: store).frame(height: 900))
        XCTAssertEqual(text, ["Aguardando nova oportunidade", "Nada está sendo buscado agora.", "Tentar novamente"])
        XCTAssertFalse(text.contains { $0.localizedCaseInsensitiveContains("procurando") },
            "an opportunity that was never run is not a search in flight")
        XCTAssertFalse(text.contains { $0.localizedCaseInsensitiveContains("instantes") },
            "no surface may promise a retry instant the pipeline never committed to")
    }

    func testU11NewSameEditionWindowRendersExactReceivedSequence() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let screen = FeedScreen(store: store)
        XCTAssertEqual(try renderedText(screen.frame(height: 900)).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        _ = try await f.session.submitViewport(observation)
        let moved = try await f.session.admitPresentation(.forwardScroll(observation))
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
        _ = try renderedText(rendered(XCTUnwrap(first.window.items.first)))
        XCTAssertEqual(try history.restore(backwardCapacity: 0, forwardCapacity: 0), before)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID), segments)
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, first)
    }

    /// PO 2026-10-14: the end of the eligible offer is one more child of the list — after the last card, with
    /// the ratified copy and the three actions — and the cards the reader already had keep their order.
    func testEndOfContentBlockRendersAfterTheLastCardWithTheRatifiedActions() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in XCTFail("Automatic viewport") }
        let screen = FeedScreen(store: store)
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let admitted = try XCTUnwrap(publishedSequence(in: screen.body)).occurrenceIDs
        XCTAssertEqual(admitted, Array(f.cardIDs.prefix(2)))
        let before = try renderedText(screen, height: 1200)
        XCTAssertEqual(before.filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        XCTAssertFalse(before.contains { $0.contains("fim das histórias") }, before.description)
        try store.install(FeedPresentationHandoff.report(.endOfContent, into: store.state))
        let text = try renderedText(screen, height: 1200)
        // The PO's ratified copy and the three actions are drawn...
        XCTAssertTrue(text.joined(separator: " ").contains("Você chegou ao fim das histórias disponíveis para sua seleção"),
            text.description)
        XCTAssertTrue(text.contains { $0.contains(FeedEndOfContentView.exploreSubjectsTitle) }, text.description)
        XCTAssertTrue(text.contains { $0.contains(FeedEndOfContentView.widenSourcesTitle) }, text.description)
        XCTAssertTrue(text.contains { $0.contains(FeedEndOfContentView.returnToStartTitle) }, text.description)
        // ...and the block comes after the last card, which did not move.
        let lastCard = try XCTUnwrap(text.firstIndex(of: "Amber headline"))
        let end = try XCTUnwrap(text.firstIndex { $0.contains("fim das histórias") })
        XCTAssertGreaterThan(end, lastCard)
        XCTAssertEqual(text.filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        XCTAssertEqual(try XCTUnwrap(publishedSequence(in: screen.body)).occurrenceIDs, admitted)
    }


    func testSourceExclusionRecoveryAtEndKeepsPublishedCardsAndSequence() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in XCTFail("Automatic viewport") }
        let screen = FeedScreen(store: store, onManageSourceExclusions: {})
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let admitted = try XCTUnwrap(publishedSequence(in: screen.body)).occurrenceIDs
        XCTAssertFalse(try renderedText(screen, height: 1500).contains { $0.contains("Rever fontes excluídas") })
        try store.install(FeedPresentationHandoff.report(.endOfContent, into: store.state))
        let text = try renderedText(screen, height: 1500)
        XCTAssertTrue(text.contains { $0.contains("Rever fontes excluídas") }, text.description)
        XCTAssertEqual(text.filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        XCTAssertEqual(try XCTUnwrap(publishedSequence(in: screen.body)).occurrenceIDs, admitted)
        let unrestricted = FeedScreen(store: store)
        XCTAssertFalse(try renderedText(unrestricted, height: 1500).contains { $0.contains("Rever fontes excluídas") })
    }

    func testSourceExclusionRecoveryAlsoAppearsWhenEndHasNoPublishedHistory() throws {
        let store = FeedScreenStore { _, _ in XCTFail("Automatic viewport") }
        try store.install(FeedPresentationHandoff.report(.endOfContent, into: store.state))
        let text = try renderedText(FeedScreen(store: store, onManageSourceExclusions: {}), height: 1200)
        XCTAssertTrue(text.contains { $0.contains("Rever fontes excluídas") }, text.description)
        XCTAssertTrue(store.renderedItems.isEmpty)
        XCTAssertNil(store.state.presentation)
    }

    func testImportedSourceRemainsVisibleWhenTheCatalogueIsUnavailable() async throws {
        let f = try fixture()
        let store = SourceManagementStore(backend: SourceCatalogBackend(
            coordinator: SourceManagementCoordinator(catalogURL: nil, database: f.database)))
        let row = NodeSourceRow(id: "https://reader.example/feed", title: "Imported Orchard",
            detail: "https://reader.example/feed", isSelected: true)
        let screen = SourceManagementView(store: store, onOpenNode: { _ in }, onOpenCountries: {},
            importedSources: [row], onExcludeImportedSource: { _ in })
        await store.load()
        let hosted = host(screen)
        hosted.window.isReleasedWhenClosed = false
        hosted.window.animationBehavior = .none
        hosted.window.orderFront(nil)
        defer { hosted.window.close() }
        // Native List cells are installed on the next AppKit display cycle.
        try await Task.sleep(for: .milliseconds(100))
        let text = try renderedText(hosted)
        XCTAssertTrue(text.contains { $0.contains("Imported Orchard") }, text.description)
        XCTAssertTrue(text.contains { $0.contains("catálogo") }, text.description)
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
        // O split de `FeedScreen.swift` moveu chrome, captura visual e viewport nativo para arquivos próprios: eles
        // entram na mesma varredura, senão o guarda perderia cobertura justamente sobre o código que saiu.
        for file in ["FeedScreen.swift", "FeedScreenChrome.swift", "FeedVisualCapture.swift", "FeedNativeViewport.swift",
            "Cards/FeedItemCardView.swift", "Cards/FeedItemView.swift",
            "Cards/FeedItemRowView.swift", "FeedLoadingView.swift"] {
            let source = try String(contentsOf: ui.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["URLSession", "AsyncImage", "ContentStore", "RuntimeDatabase", "AcquisitionCoordinator", "SelectionEngine",
                "PublicationCoordinator", "PublicationStore", "Task", ".task", ".onAppear", ".onDisappear", "Timer", "sleep",
                "retry", "backoff", "scheduler", "cache", "generation", "checkpoint", "UUID(", "PublicationCardID(", "exhausted", "@State", "@Observable", "GeometryReader", "NavigationStack"] {
                if (file == "FeedScreen.swift" && forbidden == "@State") ||
                    ((file == "FeedScreen.swift" || file == "FeedNativeViewport.swift") && forbidden == ".onDisappear") {
                    continue
                }
                XCTAssertFalse(source.contains(forbidden), file + ": " + forbidden)
            }
        }
        let screen = try String(contentsOf: ui.appendingPathComponent("FeedScreen.swift"), encoding: .utf8)
        // O wiring do viewport mora agora no arquivo dele; as presenças abaixo seguem o código, não o nome do arquivo.
        let viewport = try String(contentsOf: ui.appendingPathComponent("FeedNativeViewport.swift"), encoding: .utf8)
        let states = screen.split(separator: "\n").filter { $0.contains("@State") }
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.trimmingCharacters(in: .whitespaces), "@State private var capture = FeedVisualCapture()")
        XCTAssertTrue(screen.contains("#available(iOS 18, macOS 15, *)"))
        XCTAssertTrue(viewport.contains("onScrollGeometryChange"))
        XCTAssertTrue(viewport.contains("onScrollPhaseChange"))
        XCTAssertTrue(viewport.contains("store.submitViewport(event.observation, activity: event.activity, rendered:"))
        XCTAssertTrue(viewport.contains("capture.interaction.end()"))
        XCTAssertTrue(viewport.contains("capture.nativeScrollOffset.cancel()"))
        // Lifecycle cleanup is visual only. The general forbidden list still excludes all execution.
        FeedViewportCaptureTests.assertVisualBoundary()
    }

    func testNativeHostingObservesStoreWithoutReplacingView() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in XCTFail("Automatic viewport") }
        let hosted = host(FeedScreen(store: store))
        XCTAssertEqual(try renderedText(hosted), ["Descobrindo histórias para você..."])
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        XCTAssertEqual(try renderedText(hosted).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(try renderedText(hosted).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline"])
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        _ = try await f.session.submitViewport(observation)
        let moved = try await f.session.admitPresentation(.forwardScroll(observation))
        try store.install(try FeedPresentationHandoff.receive(snapshot: moved, into: store.state))
        XCTAssertEqual(try renderedText(hosted).filter { $0.hasSuffix("headline") }, ["Zebra headline", "Amber headline", "River headline"])
    }

    func testCardAdaptsToNarrowAvailableWidth() throws {
        let published = try card(title: "Local headline with additional words that must wrap", text: "Published local text")
        let text = try renderedText(host(rendered(published), width: 320))
        XCTAssertTrue(text.joined(separator: " ").contains("Local headline with additional words that must wrap"), text.description)
        XCTAssertTrue(text.contains("Published local text"), text.description)
        XCTAssertTrue(text.contains("Local source"), text.description)
    }

    // Inspect the real declarative ForEach (not a parallel rendering model).
    private func publishedSequence(in value: Any, depth: Int = 0) -> (any PublishedCardSequence)? {
        if let sequence = value as? any PublishedCardSequence { return sequence }
        guard depth < 24 else { return nil }
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

extension ForEach: PublishedCardSequence where Data == [(offset: Int, element: PresentationCard)], ID == PublicationCardID {
    fileprivate var occurrenceIDs: [PublicationCardID] { data.map(\.element.id) }
    fileprivate var titles: [String?] { data.map(\.element.title) }
}

#endif
