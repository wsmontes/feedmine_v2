import Foundation
import XCTest
import Observation
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
@testable import FeedMineRuntime
import FeedMineUI
import FeedMineComposition

@MainActor
final class FeedScreenStoreTests: XCTestCase {
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
                headline: "Published \(index)", summary: "Local content \(index)",
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

    @MainActor
    private final class Changes {
        var count = 0
    }

    func testS1InitialStateHasNoInventedPresentationOrWork() {
        var calls = 0
        let store = FeedScreenStore { _, _ in calls += 1 }
        XCTAssertEqual(store.state, FeedPresentationState(presentation: nil))
        XCTAssertEqual(calls, 0)
    }

    /// PO 2026-10-14: o desenho publica **onde o viewport começa** e se está em repouso nele; o store **repassa**
    /// esse fato como qualquer outra entrada explícita — ele não guarda a posição (o dono do cursor, a sessão, é
    /// quem lembra dela e decide o que ela custa). Publicar não submete observação nenhuma: é uma posição, não uma
    /// oportunidade de produção.
    func testS1aPresentedPositionIsForwardedAndNeverStored() async throws {
        let f = try fixture(), published = try await snapshot(f)
        var forwarded: [PresentationAnchor] = []
        var rests: [Bool] = []
        let store = FeedScreenStore(onViewport: { _, _ in XCTFail("Unrequested viewport") },
            onPresentedPosition: { anchor, atRest in
                forwarded.append(anchor)
                rests.append(atRest)
            })
        try store.install(FeedPresentationState(presentation: published))
        let first = try XCTUnwrap(store.renderedItems.first?.id)
        store.publishPresentedPosition(PresentationAnchor(cardID: first, placement: .top), atRest: false)
        store.publishPresentedPosition(PresentationAnchor(cardID: first, placement: .top), atRest: true)
        XCTAssertEqual(rests, [false, true], "o repouso do desenho é o fato que o host recebe")
        XCTAssertEqual(forwarded, [PresentationAnchor(cardID: first, placement: .top),
            PresentationAnchor(cardID: first, placement: .top)])
        // The physical ID is forwarded without rewriting the logical snapshot.
        XCTAssertEqual(store.state.presentation, published)
        XCTAssertEqual(store.renderedItems.first?.id, first)
        let foreign = PublicationCardID()
        store.publishPresentedPosition(.init(cardID: foreign, placement: .top), atRest: true)
        XCTAssertEqual(rests, [false, true], "offscreen historical IDs cannot become reader positions")
    }

    func testS2InstallFirstRealRestoredPresentationExactly() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in XCTFail("Unrequested viewport") }
        let delivered = try FeedPresentationHandoff.receive(snapshot: published, into: store.state)
        try store.install(delivered)
        XCTAssertEqual(store.state, delivered)
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(2)))
        XCTAssertEqual(store.state.presentation?.window.anchor, published.window.anchor)
        XCTAssertEqual(store.state.presentation?.editionID, f.editionID)
    }

    /// A restore that could not redraw the reader's own card states the substitute through the existing toast —
    /// once, and without claiming an exact resume. The field belongs to the presentation, so the shell does not
    /// need a second position record to say it.
    func testS2aInstallingASubstituteRestoreStatesTheUnavailablePositionOnce() async throws {
        let f = try fixture(), base = try await snapshot(f)
        let durable = PublicationCardID()
        let substituted = FeedPresentationSnapshot(contextKey: base.contextKey, editionID: base.editionID,
            window: base.window, provenance: base.provenance,
            unavailableImageCardIDs: [durable], unavailablePositionCardID: durable)
        let store = FeedScreenStore { _, _ in }

        try store.install(FeedPresentationState(presentation: substituted))

        XCTAssertEqual(store.state.presentation?.unavailablePositionCardID, durable)
        XCTAssertTrue(store.toast?.text.contains("não está disponível") ?? false,
            "the surface states the unavailable position instead of claiming an exact resume")
        store.dismissToast()
        try store.install(FeedPresentationState(presentation: substituted))
        XCTAssertNil(store.toast, "the same unavailable position is stated once, not on every projection")
    }

    func testS3NativeObservationNotifiesForPresentationAndWorkInstallation() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        let changes = Changes()
        withObservationTracking { _ = store.state.presentation } onChange: {
            MainActor.assumeIsolated { changes.count += 1 }
        }
        try store.install(try FeedPresentationHandoff.receive(snapshot: published, into: store.state))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(store.state.presentation, published)
        withObservationTracking { _ = store.state.work } onChange: {
            MainActor.assumeIsolated { changes.count += 1 }
        }
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(store.state.work, .pending)
    }

    func testS4PendingPreservesVisiblePresentation() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: published, into: store.state))
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(store.state.presentation, published)
        XCTAssertEqual(store.state.work, .pending)
    }

    func testS5FailurePreservesVisiblePresentation() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: published, into: store.state))
        try store.install(FeedPresentationHandoff.report(.failed(message: "External operation failed"), into: store.state))
        XCTAssertEqual(store.state.presentation, published)
        XCTAssertEqual(store.state.work, .failed(message: "External operation failed"))
    }

    func testS6SameIdentityWindowRetainsExactRuntimeOrderAndAnchor() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        // Position first, then the gesture that admits the next ready prefix (T2 boundary).
        _ = try await f.session.submitViewport(observation)
        let moved = try await f.session.admitPresentation(.forwardScroll(observation))
        let next = try XCTUnwrap(moved)
        try store.install(try FeedPresentationHandoff.receive(snapshot: next, into: store.state))
        XCTAssertEqual(store.state.presentation, next)
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(3)))
        XCTAssertEqual(store.state.presentation?.window.anchor, observation.anchor)
        XCTAssertEqual(store.state.presentation?.editionID, first.editionID)
        XCTAssertEqual(store.state.presentation?.contextKey, first.contextKey)
        XCTAssertEqual(store.state.work, .idle)
    }

    /// P2/#32 RED contract: a valid runtime trim is not an append-only physical update.
    /// The first two transitions intentionally use real persisted history and the real
    /// session's frozen bounds, not a fabricated snapshot or guessed SwiftUI heights.
    /// A host that cannot yet transfer a shared measured card must fail this acceptance
    /// rather than leave an obsolete array visible indefinitely.
    func testS6bTrimmedRuntimeWindowRequiresAnActualPhysicalHandoff() async throws {
        let f = try fixture()
        let store = FeedScreenStore { _, _ in XCTFail("A synthetic user viewport was not requested") }
        let initialValue = try await f.session.admitPresentation(
            .restore(.init(backwardCapacity: 1, forwardCapacity: 1)))
        let initial = try XCTUnwrap(initialValue)
        try store.install(.init(presentation: initial))
        XCTAssertEqual(store.renderedItems.map(\.id), Array(f.cardIDs[0...1]))

        let atB = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        _ = try await f.session.submitViewport(atB)
        let firstGrowthValue = try await f.session.admitPresentation(.forwardScroll(atB))
        let firstGrowth = try XCTUnwrap(firstGrowthValue)
        try store.install(.init(presentation: firstGrowth))
        XCTAssertEqual(firstGrowth.window.items.map(\.id), Array(f.cardIDs[0...2]))
        XCTAssertEqual(store.renderedItems.map(\.id), Array(f.cardIDs[0...2]),
            "Prefix growth already has an automatic physical installation")

        let atC = ViewportObservation(anchor: .init(cardID: f.cardIDs[2], placement: .center))
        _ = try await f.session.submitViewport(atC)
        let trimmedValue = try await f.session.admitPresentation(.forwardScroll(atC))
        let trimmed = try XCTUnwrap(trimmedValue)
        XCTAssertEqual(trimmed.window.items.map(\.id), Array(f.cardIDs[1...3]),
            "The runtime has produced a real non-prefix ready window")
        XCTAssertEqual(trimmed.window.anchor.cardID, f.cardIDs[2])
        try store.install(.init(presentation: trimmed))
        XCTAssertEqual(store.state.presentation, trimmed,
            "Semantic history must retain its accepted projection")
        XCTAssertEqual(store.renderedItems.map(\.id), Array(f.cardIDs[1...3]),
            "A measured physical handoff must replace stale [A,B,C] with [B,C,D] without inventing scroll")
    }

    func testS7HandoffRejectsAnotherEditionWithoutMutatingStore() async throws {
        let f = try fixture(), other = try fixture()
        let first = try await snapshot(f), replacement = try await snapshot(other)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let before = store.state
        XCTAssertThrowsError(try store.install(FeedPresentationHandoff.receive(snapshot: replacement, into: store.state))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(store.state, before)
        // Complete values also pass through receiving(_); installation cannot bypass its fence.
        XCTAssertThrowsError(try store.install(FeedPresentationState(presentation: replacement))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(store.state, before)
    }

    func testS7HandoffRejectsAnotherContextWithinSameEdition() async throws {
        let f = try fixture()
        let other = try fixture(context: .init(request: .source(SourceID())), editionID: f.editionID)
        let first = try await snapshot(f), replacement = try await snapshot(other)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let before = store.state
        XCTAssertEqual(first.editionID, replacement.editionID)
        XCTAssertNotEqual(first.contextKey, replacement.contextKey)
        XCTAssertThrowsError(try store.install(FeedPresentationHandoff.receive(snapshot: replacement, into: store.state))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertThrowsError(try store.install(FeedPresentationState(presentation: replacement))) {
            XCTAssertEqual($0 as? FeedPresentationStateError, .presentationIdentityMismatch)
        }
        XCTAssertEqual(store.state, before)
    }

    func testS8ViewportIntentArrivesExactlyOnceWithRealSemanticValues() async throws {
        let f = try fixture(), first = try await snapshot(f)
        var received: [(ViewportObservation, RunwayActivity)] = []
        let store = FeedScreenStore { received.append(($0, $1)) }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        for placement in [PresentationAnchorPlacement.top, .center] {
            for activity in [RunwayActivity.forward, .stationary, .backward, .explicitTailApproach] {
                let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: placement))
                let beforeCount = received.count
                store.submitViewport(observation, activity: activity)
                XCTAssertEqual(received.count, beforeCount + 1)
                XCTAssertEqual(received.last?.0, observation)
                XCTAssertEqual(received.last?.1, activity)
                XCTAssertEqual(store.state.presentation, first)
            }
        }
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, first) // Consumer recorded intent; store never moved Runtime.
    }

    func testS9CompositionReturnsObservableStateAfterExplicitIntent() async throws {
        let f = try fixture(), first = try await snapshot(f)
        var intent: ViewportObservation?
        let store = FeedScreenStore { observation, _ in intent = observation }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        store.submitViewport(observation, activity: .forward)
        XCTAssertEqual(store.state.presentation, first)
        // External consumer simulates the driver result using a real Runtime viewport projection.
        _ = try await f.session.submitViewport(XCTUnwrap(intent))
        let returned = try await f.session.admitPresentation(.forwardScroll(XCTUnwrap(intent)))
        let delivered = try FeedPresentationHandoff.receive(snapshot: returned, into: store.state)
        let changes = Changes()
        withObservationTracking { _ = store.state } onChange: {
            MainActor.assumeIsolated { changes.count += 1 }
        }
        try store.install(delivered)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(store.state, delivered)
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), Array(f.cardIDs.prefix(3)))
        XCTAssertEqual(store.state.presentation?.window.anchor, observation.anchor)
    }

    func testS10NoHiddenExecutionOrDurableMutation() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let checkpoint = try PublicationHistory(database: f.database).restore(backwardCapacity: 0, forwardCapacity: 0)
        let segments = try PublicationStore(database: f.database).segments(editionID: f.editionID)
        var calls = 0
        let store = FeedScreenStore { _, _ in calls += 1 }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(calls, 0)
        let observation = ViewportObservation(anchor: .init(cardID: f.cardIDs[1], placement: .center))
        store.submitViewport(observation, activity: .explicitTailApproach)
        XCTAssertEqual(calls, 1)
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, first)
        let after = try PublicationHistory(database: f.database).restore(backwardCapacity: 0, forwardCapacity: 0)
        XCTAssertEqual(after?.cursor, checkpoint?.cursor)
        XCTAssertEqual(try PublicationStore(database: f.database).segments(editionID: f.editionID), segments)
        XCTAssertEqual(store.state.work, .pending)
    }

    /// The one observable physical projection exists because logical state
    /// changes on every advance. It is derived from the accepted history but
    /// contains only a contiguous ready run, never deferred media descriptors.
    /// The physical rail retains the snapshot that *its cells* came from;
    /// this is visual evidence, not a second semantic cursor or session.
    private static let publishedProjection: Set<String> = ["_renderedItems", "_renderedEditionID",
        "_renderedContextKey", "_work"]

    func testS11OnlyOnePresentationValueAndNoParallelSemanticStorage() {
        let store = FeedScreenStore { _, _ in }
        let fields = Array(Mirror(reflecting: store).children)
        XCTAssertEqual(fields.filter { $0.value is FeedPresentationState }.count, 1)
        for field in fields {
            guard let label = field.label, !Self.publishedProjection.contains(label) else { continue }
            XCTAssertFalse(field.value is FeedPresentationSnapshot)
            XCTAssertFalse(field.value is [PresentationCard])
            XCTAssertFalse(field.value is FeedEditionID)
            XCTAssertFalse(field.value is ContextKey)
            XCTAssertFalse(field.value is PresentationAnchor)
            XCTAssertFalse(field.value is PublicationCardID)
        }
        // The reader's own facts the host installs (T8) are values or closures: no second presentation, no
        // stored identity, and nothing that could execute work.
        XCTAssertEqual(Set(fields.compactMap(\.label)), ["_state", "onViewport", "onAction", "availableActions",
            "_availableDestinations", "onSubmitSearch", "onNavigate", "_bookmarkedIDs", "_isSearching",
            "_searchQuery", "_toast", "_filterCount", "_bookmarkBoxActive", "_hasCommittedSearch",
            "_$observationRegistrar", "onRenderedViewport", "viewportOrdinal", "_isReadingInteractionActive",
            "_renderedItems", "physicalWindow", "_renderedEditionID", "_renderedContextKey", "_work",
            // PO 2026-10-14: a posição do **viewport desenhado** é repassada, não guardada — o dono do cursor
            // (a sessão) é quem a lembra e quem decide de quanto em quanto tempo ela vira escrita.
            "onPresentedPosition",
            // R15: cancelar a busca é uma intenção repassada ao host (que restaura a origem e o checkpoint).
            "onCancelSearch",
            // P08: the unified search owns only presentation and its completion token here; the host computes the
            // pages and executes destinations. These are values/closures, never execution mechanisms.
            "searchPresentation", "searchSourcePage", "_isSearchingResults", "_searchResultsFailed", "_searchScope",
            "onSelectSearchResult", "onRequestSearchPage", "onRequestSourcePage", "onSearchScopeChanged",
            "onRequestSearchAgain",
            // D4: the first screen's facts (measured layout, the sticky exposure, the host's inputs and bound) are
            // **one** value read by the screen and by the host's launch record, never a second presentation. Its
            // measured layout is `@ObservationIgnored`; the two sticky facts are observable so the cover leaves on
            // the pass a measurement settles the transition.
            "firstScreen"])
    }

    /// P08: a truncated source page is actionable. The surface requests the next page through the same token and
    /// replaces only the source section; the article page already shown stays where it is.
    @MainActor
    func testSourceContinuationAdvancesAndPreservesArticlePage() {
        var request: (ReaderSearchResults, Int)?
        let store = FeedScreenStore(onViewport: { _, _ in },
            onRequestSourcePage: { page, index in request = (page, index) })
        let token = store.beginUnifiedSearch(term: "x", scope: .sources)
        let source = ReaderSearchResult(id: "source:one", kind: .source, title: "One", subtitle: nil,
            destination: .source(principal: "one", sourceID: nil))
        let article = ReaderSearchResult(id: "article:one", kind: .article, title: "A", subtitle: nil,
            destination: .article(cardID: nil, originRecordID: OriginRecordID()))
        let first = ReaderSearchResults(query: "x", scope: .sources, token: token, sources: [source],
            saved: [], articles: [article], sourceTruncated: true)
        XCTAssertTrue(store.applyUnifiedSearch(first))

        store.loadMoreSources()
        XCTAssertEqual(request?.1, 1)
        XCTAssertTrue(store.isSearchingResults)

        let second = ReaderSearchResults(query: "x", scope: .sources, token: token, sources: [],
            saved: [], articles: [], sourceTruncated: false)
        XCTAssertTrue(store.appendSourcePage(second, index: 1))
        XCTAssertEqual(store.searchResults?.sources, [])
        XCTAssertEqual(store.searchResults?.articles, [article], "a página de artigos não é descartada")
        XCTAssertEqual(store.searchResults?.sourceTruncated, false)
        XCTAssertFalse(store.isSearchingResults)

        // An article continuation preserves the source page and unions the authority failures.
        let nextArticle = ReaderSearchResult(id: "article:two", kind: .article, title: "B", subtitle: nil,
            destination: .article(cardID: nil, originRecordID: OriginRecordID()))
        let articlePage = ReaderSearchResults(query: "x", scope: .sources, token: token, sources: [],
            saved: [], articles: [nextArticle], sourceTruncated: false,
            failedAuthorities: [.catalogue])
        XCTAssertTrue(store.appendSearchPage(articlePage))
        XCTAssertEqual(store.searchResults?.articles.map(\.id), ["article:one", "article:two"])
        XCTAssertEqual(store.searchResults?.sources, [], "a página de artigos não apaga a seção de fontes")
        XCTAssertEqual(store.searchResults?.failedAuthorities, [.catalogue])

        // A page from an older token cannot replace the current presentation.
        let stale = ReaderSearchResults(query: "x", scope: .sources, token: token,
            sources: [source], saved: [], articles: [], sourceTruncated: true)
        _ = store.beginUnifiedSearch(term: "y", scope: .sources)
        XCTAssertFalse(store.appendSourcePage(stale, index: 2))
    }

    /// R16/P2: a restarted search with the **same** term and scope must still reject pages from the older run.
    /// Comparing only query and scope let a late continuation from the first run enter the second one.
    @MainActor
    func testRestartedSearchWithSameTermRejectsStaleArticleAndSourcePages() {
        let store = FeedScreenStore(onViewport: { _, _ in })
        let firstToken = store.beginUnifiedSearch(term: "astro", scope: .both)
        let article = ReaderSearchResult(id: "article:first", kind: .article, title: "First", subtitle: nil,
            destination: .article(cardID: nil, originRecordID: OriginRecordID()))
        let first = ReaderSearchResults(query: "astro", scope: .both, token: firstToken,
            sources: [], saved: [], articles: [article])
        XCTAssertTrue(store.applyUnifiedSearch(first))

        // The reader restarts exactly the same query; the surface owns a new completion identity.
        let secondToken = store.beginUnifiedSearch(term: "astro", scope: .both)
        XCTAssertNotEqual(secondToken, firstToken)
        let freshArticle = ReaderSearchResult(id: "article:fresh", kind: .article, title: "Fresh", subtitle: nil,
            destination: .article(cardID: nil, originRecordID: OriginRecordID()))
        let fresh = ReaderSearchResults(query: "astro", scope: .both, token: secondToken,
            sources: [], saved: [], articles: [freshArticle])
        XCTAssertTrue(store.applyUnifiedSearch(fresh))

        let staleArticlePage = ReaderSearchResults(query: "astro", scope: .both, token: firstToken,
            sources: [], saved: [], articles: [article])
        XCTAssertFalse(store.appendSearchPage(staleArticlePage),
            "a page from the previous run cannot be appended to the restarted search")
        let staleSourcePage = ReaderSearchResults(query: "astro", scope: .both, token: firstToken,
            sources: [ReaderSearchResult(id: "source:stale", kind: .source, title: "Stale", subtitle: nil,
                destination: .source(principal: "stale", sourceID: nil))], saved: [], articles: [],
            sourceTruncated: false)
        XCTAssertFalse(store.appendSourcePage(staleSourcePage, index: 1),
            "a source page from the previous run cannot replace the restarted search's sources")
        XCTAssertEqual(store.searchResults?.articles.map(\.id), ["article:fresh"],
            "the rejected pages changed nothing")
        XCTAssertEqual(store.searchResults?.sources, [])
    }

    /// P08: cancelling while a search is in flight invalidates its completion, and a failed page's retry asks the
    /// host for a new page through the existing intention.
    @MainActor
    func testCancelInvalidatesInFlightCompletionAndRetryRestartsTheSearch() {
        var retries = 0
        let store = FeedScreenStore(onViewport: { _, _ in }, onRequestSearchAgain: { retries += 1 })
        let token = store.beginUnifiedSearch(term: "astro", scope: .both)
        store.cancelSearch()
        let inFlight = ReaderSearchResults(query: "astro", scope: .both, token: token,
            sources: [], saved: [], articles: [])
        XCTAssertFalse(store.applyUnifiedSearch(inFlight), "a conclusão em voo não reabre uma busca cancelada")
        XCTAssertNil(store.searchResults)
        XCTAssertFalse(store.isSearchingResults)

        let restarted = store.beginUnifiedSearch(term: "astro", scope: .both)
        XCTAssertTrue(store.isSearching, "a submissão reabre a superfície no store reconstruído")
        XCTAssertEqual(store.searchQuery, "astro")
        store.failUnifiedSearch(token: restarted)
        XCTAssertTrue(store.searchResultsFailed)
        XCTAssertFalse(store.isSearchingResults)
        store.requestSearchAgain()
        XCTAssertTrue(store.isSearchingResults)
        XCTAssertFalse(store.searchResultsFailed)
        XCTAssertEqual(retries, 1, "o retry é uma intenção do host, não um estado inventado pela superfície")
    }

    /// P2: a preparation that returned `.failed` without a durable row is shown as failed for this session,
    /// not as the stale pending state the missing row would otherwise imply.
    func testSavedRowStatesSessionFailureInsteadOfStalePending() {
        XCTAssertEqual(FeedSavedArticle.availability(recorded: nil, hasPublishedMedia: true,
            failedInThisSession: true), .failed)
        XCTAssertEqual(FeedSavedArticle.availability(recorded: .pending, hasPublishedMedia: true,
            failedInThisSession: true), .failed)
        XCTAssertEqual(FeedSavedArticle.availability(recorded: nil, hasPublishedMedia: true,
            failedInThisSession: false), .pending)
        XCTAssertEqual(FeedSavedArticle.availability(recorded: nil, hasPublishedMedia: false,
            failedInThisSession: false), .textOnly)
        XCTAssertEqual(FeedSavedArticle.availability(recorded: .ready, hasPublishedMedia: true,
            failedInThisSession: false), .ready)
    }

    /// The logical snapshot is the full retained history; the physical list is
    /// its anchor-containing contiguous ready run. Work-only updates keep the
    /// installed physical IDs and never rewrite the logical position.
    func testS11ThePublishedProjectionCannotDrift() async throws {
        let f = try fixture(), published = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: published, into: store.state))
        XCTAssertEqual(store.renderedItems.map(\.id), published.window.items.map(\.id),
            "This fixture is entirely ready: its physical run must match logical order")
        XCTAssertTrue(store.renderedItems.allSatisfy(\.isRenderReady))
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), published.window.items.map(\.id))
        XCTAssertEqual(store.renderedEditionID, store.state.presentation?.editionID)
        XCTAssertEqual(store.renderedContextKey, store.state.presentation?.contextKey)
        XCTAssertEqual(store.work, store.state.work)
        try store.install(FeedPresentationHandoff.report(.pending, into: store.state))
        XCTAssertEqual(store.renderedItems.map(\.id), published.window.items.map(\.id),
            "This fixture is entirely ready: its physical run must match logical order")
        XCTAssertTrue(store.renderedItems.allSatisfy(\.isRenderReady))
        XCTAssertEqual(store.state.presentation?.window.items.map(\.id), published.window.items.map(\.id))
        XCTAssertEqual(store.renderedEditionID, store.state.presentation?.editionID)
        XCTAssertEqual(store.renderedContextKey, store.state.presentation?.contextKey)
        XCTAssertEqual(store.work, store.state.work)
    }

    func testS12ModuleBoundaryAndNoExecutionMechanisms() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ui = root.appendingPathComponent("Sources/FeedMineUI")
        for file in try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let imports = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("import ") }
            for forbidden in ["FeedMineComposition", "FeedMinePersistence", "FeedMineAcquisition", "FeedMinePublication", "FeedMineSyndication", "FeedMineEditorial"] {
                XCTAssertFalse(imports.contains("import " + forbidden), file.lastPathComponent + ": " + forbidden)
            }
        }
        let source = try String(contentsOf: ui.appendingPathComponent("FeedScreenStore.swift"), encoding: .utf8)
        for forbidden in ["URLSession", "HTTP", "ContentStore", "RuntimeDatabase", "AcquisitionCoordinator", "FeedRunwayDriver",
            "RunwayController", "SelectionEngine", "PublicationCoordinator", "PublicationStore", "Task", "Timer", "sleep",
            "retry", "backoff", "scheduler", "cache", "generation", "checkpoint", "UUID(", "Date("] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        // `[PresentationCard]` is admitted in exactly one place: the published list projection. It is never a
        // second semantic store, and no other declaration, parameter or local may name it.
        let cardLines = source.split(separator: "\n").filter { $0.contains("[PresentationCard]") }
        XCTAssertEqual(cardLines.count, 1, "only the published projection may name [PresentationCard]")
        XCTAssertTrue(cardLines.first?.contains("public private(set) var renderedItems") == true,
            "the one holder of cards must be renderedItems")
    }

    func testS13ExternalAsyncConsumerMutatesOnlyOnMainActor() async throws {
        let store = FeedScreenStore { _, _ in MainActor.preconditionIsolated() }
        try await Self.deliverFromExternalConsumer(store)
        XCTAssertEqual(store.state.work, .pending)
    }

    private nonisolated static func deliverFromExternalConsumer(_ store: FeedScreenStore) async throws {
        try await MainActor.run {
            MainActor.preconditionIsolated()
            try store.install(FeedPresentationState(presentation: nil).reporting(.pending))
        }
    }

    func testMissingSnapshotCannotClearVisiblePresentationAndWorkRemainsDistinct() async throws {
        let f = try fixture(), first = try await snapshot(f)
        let store = FeedScreenStore { _, _ in }
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        for work in [FeedPresentationState.Work.idle, .pending, .unavailable, .deferred, .failed(message: "No new snapshot")] {
            try store.install(FeedPresentationState(presentation: nil).reporting(work))
            XCTAssertEqual(store.state.presentation, first)
            XCTAssertEqual(store.state.work, work)
        }
    }
}

extension FeedScreenStoreTests {
    /// Review F10/T4: a card request forwards only the occurrence and the requested action, only for an
    /// admitted card and only for an action this host declares it can execute.
    @MainActor
    func testPerformForwardsOnlyAdmittedCardsAndAvailableActions() async throws {
        let f = try fixture(), first = try await snapshot(f)
        var events: [ReaderCardActionEvent] = []
        let store = FeedScreenStore(onViewport: { _, _ in }, availableActions: [.open, .save],
            onAction: { events.append($0) })
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/FeedMineUI/FeedScreenStore.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("URL("), "action targets never cross the UI boundary")
        XCTAssertTrue(source.contains("guard availableActions.contains(event.action)"))
        store.perform(.init(action: .open, cardID: f.cardIDs[0]))
        XCTAssertTrue(events.isEmpty, "an occurrence that was never admitted cannot act")
        try store.install(try FeedPresentationHandoff.receive(snapshot: first, into: store.state))
        store.perform(.init(action: .share, cardID: f.cardIDs[0]))
        XCTAssertTrue(events.isEmpty, "an action this host cannot execute is never forwarded")
        store.perform(.init(action: .save, cardID: f.cardIDs[0]))
        XCTAssertEqual(events.map(\.action), [.save])
        XCTAssertEqual(events.last?.cardID, f.cardIDs[0])
        store.perform(.init(action: .save, cardID: PublicationCardID()))
        XCTAssertEqual(events.map(\.action), [.save], "an unknown occurrence is inert")
    }
    /// FR2: the host loop must use the limit captured when the first screen appeared. A later live composition
    /// value (5 s -> 60 s) is not read here; only a new appearance, which is the context reset, states a new limit.
    func testS14FirstScreenLimitIsCapturedAtAppearanceAndRenewedOnlyByAReset() {
        let store = FeedScreenStore(onViewport: { _, _ in }, onPresentedPosition: { _, _ in })
        store.noteFirstScreenAppeared(hasSources: true, maximumWait: .seconds(5))
        XCTAssertEqual(store.firstScreenWaitLimit, .seconds(5))
        // The composition now reports 60 s. Without a new appearance the captured limit is still 5 s, so the
        // hold cannot be renewed by the live value.
        XCTAssertEqual(store.firstScreenWaitLimit, .seconds(5))
        store.noteFirstScreenAppeared(hasSources: true, maximumWait: .seconds(60))
        XCTAssertEqual(store.firstScreenWaitLimit, .seconds(60), "a context reset captures the new limit")
    }


}