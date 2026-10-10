import XCTest
import FeedMineRuntime
import FeedMineUI

/// T7: the source surface is observable values plus intents; a failing backend is a stated message, never a
/// silently empty tree, and the selection shown is always the one the backend accepted.
@MainActor
final class SourceManagementStoreTests: XCTestCase {
    /// A backend that records every intent and can be told to fail.
    private final class Backend: SourceManagementBackend, @unchecked Sendable {
        var languages: [CatalogLanguageSummary] = [.init(code: "pt", displayName: "Português",
            enabledSources: 2, totalSources: 3, isUndeclared: false)]
        var sections: [CatalogNodeSummary] = []
        var countries: [CatalogNodeSummary] = []
        var childrenByNode: [Int64: [CatalogNodeSummary]] = [:]
        var breadcrumbByNode: [Int64: [CatalogNodeSummary]] = [:]
        var sourcesByNode: [Int64: [CatalogSourceSummary]] = [:]
        var searchResults: [CatalogSourceSummary] = []
        var selection: [String] = ["a"]
        var failEverything = false
        var failSetSelection = false
        private(set) var setEnabledCalls: [(Int64, Bool)] = []
        private(set) var searches: [String] = []

        private func guardFailure() throws {
            if failEverything { throw SourceManagementErrorDouble.unavailable }
        }

        func languages() async throws -> [CatalogLanguageSummary] { try guardFailure(); return languages }
        func sections() async throws -> [CatalogNodeSummary] { try guardFailure(); return sections }
        func countries() async throws -> [CatalogNodeSummary] { try guardFailure(); return countries }
        func children(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary] {
            try guardFailure(); return childrenByNode[node.id] ?? []
        }
        func breadcrumb(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary] {
            try guardFailure(); return breadcrumbByNode[node.id] ?? []
        }
        func sources(in node: CatalogNodeSummary) async throws -> [CatalogSourceSummary] {
            try guardFailure(); return sourcesByNode[node.id] ?? []
        }
        func searchSources(_ query: String) async throws -> [CatalogSourceSummary] {
            try guardFailure(); searches.append(query); return searchResults
        }
        var countryKeysByNode: [Int64: Set<String>] = [:]
        func countryKeys() async throws -> [Int64: Set<String>] { try guardFailure(); return countryKeysByNode }
        var childKeysByNode: [Int64: [Int64: Set<String>]] = [:]
        func childKeys(of node: CatalogNodeSummary) async throws -> [Int64: Set<String>] {
            try guardFailure(); return childKeysByNode[node.id] ?? [:]
        }
        func selection() async throws -> [String] { try guardFailure(); return selection }
        func setSelection(_ keys: [String]) async throws {
            try guardFailure(); if failSetSelection { throw SourceManagementErrorDouble.invalid }; selection = keys
        }
        func setEnabled(node: CatalogNodeSummary, enabled: Bool) async throws {
            try guardFailure(); if failSetSelection { throw SourceManagementErrorDouble.invalid }
            setEnabledCalls.append((node.id, enabled))
        }
    }

    private enum SourceManagementErrorDouble: Error { case unavailable, invalid }

    private func node(_ id: Int64, _ name: String, kind: CatalogNodeSummary.Kind = .topic,
        children: Bool = false) -> CatalogNodeSummary {
        .init(id: id, key: "k\(id)", name: name, kind: kind, sourceCount: 1, hasChildren: children)
    }

    func testLoadExposesValuesAndStatesAMissingCatalog() async {
        let backend = Backend()
        backend.sections = [node(1, "News", kind: .section)]
        backend.countries = [node(2, "Brazil", kind: .country)]
        backend.countryKeysByNode = [2: ["https://a.example/feed"]]
        let store = SourceManagementStore(backend: backend)
        await store.load()
        XCTAssertEqual(store.languages.map(\.code), ["pt"])
        XCTAssertEqual(store.sections.map(\.name), ["News"])
        XCTAssertEqual(store.countries.map(\.kind), [.country])
        XCTAssertEqual(store.selection, ["a"])
        XCTAssertEqual(store.countryKeys[2], ["https://a.example/feed"])
        XCTAssertFalse(store.isCountryEnabled(store.countries[0]),
            "a country is enabled only when every one of its sources is selected")
        XCTAssertTrue(store.hasCatalog)
        XCTAssertNil(store.errorMessage)

        backend.failEverything = true
        await store.load()
        XCTAssertFalse(store.hasCatalog, "a missing catalog is a state, not an empty tree")
        XCTAssertNotNil(store.errorMessage)
    }

    /// Opening a node shows its level, its breadcrumb and its own sources; a source list is that node's.
    func testOpeningANodeShowsItsLevelBreadcrumbAndSources() async {
        let backend = Backend()
        let brazil = node(2, "Brazil", kind: .country, children: true)
        let politics = node(3, "Politics")
        let source = CatalogSourceSummary(id: "https://a.example/feed", title: "Alpha", language: "pt-BR",
            mediaKind: "text", defaultEnabled: true)
        backend.childrenByNode[2] = [politics]
        backend.breadcrumbByNode[2] = [node(1, "Countries", kind: .section)]
        backend.sourcesByNode[2] = [source]
        let store = SourceManagementStore(backend: backend)
        await store.open(brazil)
        XCTAssertEqual(store.openNode, brazil)
        XCTAssertEqual(store.children.map(\.name), ["Politics"])
        XCTAssertEqual(store.breadcrumb.map(\.name), ["Countries"])
        XCTAssertEqual(store.sources.map(\.title), ["Alpha"])
        XCTAssertTrue(store.isSelected(store.sources[0]) == false)
    }

    /// Toggling a source and bulk-enabling a node both go through the backend, and the shown selection is the
    /// one the backend accepted.
    func testSelectionChangesAreBackendStateNotOptimistic() async {
        let backend = Backend()
        let brazil = node(2, "Brazil", kind: .country)
        let alpha = CatalogSourceSummary(id: "https://a.example/feed", title: "Alpha", language: "pt",
            mediaKind: "text", defaultEnabled: true)
        backend.sourcesByNode[2] = [alpha]
        let store = SourceManagementStore(backend: backend)
        await store.load()
        await store.open(brazil)
        await store.toggle(alpha)
        XCTAssertEqual(store.selection, ["a", "https://a.example/feed"])
        XCTAssertTrue(store.isSelected(alpha))
        // A failing write states the rule and keeps the accepted selection.
        backend.failSetSelection = true
        await store.toggle(alpha)
        XCTAssertEqual(store.selection, ["a", "https://a.example/feed"],
            "an optimistic state is never shown after a refused change")
        XCTAssertNotNil(store.errorMessage)
        backend.failSetSelection = false
        await store.toggle(alpha)
        XCTAssertEqual(store.selection, ["a"])
        await store.setEnabled(brazil, enabled: true)
        XCTAssertEqual(backend.setEnabledCalls.map(\.1), [true])
    }

    /// Search is scoped to what the reader typed and clears back to the node's own sources.
    /// T7 layout: the country rows the list draws carry the flag, the count and the country's own state, and
    /// a country is only "enabled" when every one of its sources is selected.
    func testCountryRowsCarryFlagCountAndState() {
        let brazil = CatalogNodeSummary(id: 10, key: "countries/br", name: "Brazil", kind: .country,
            sourceCount: 30, hasChildren: true)
        let portugal = CatalogNodeSummary(id: 11, key: "countries/pt", name: "Portugal", kind: .country,
            sourceCount: 10, hasChildren: false)
        let keys: [Int64: Set<String>] = [10: ["a", "b"], 11: ["c"]]
        let rows = CountriesListView.rows(countries: [brazil, portugal], selection: ["a", "b"], keys: keys)
        XCTAssertEqual(rows.map(\.name), ["Brazil", "Portugal"])
        XCTAssertEqual(rows.map(\.slug), ["br", "pt"])
        XCTAssertEqual(rows.map(\.flag), ["🇧🇷", "🇵🇹"])
        XCTAssertEqual(rows.map(\.feedCount), [30, 10])
        XCTAssertTrue(rows[0].isEnabled, "every source of Brazil is selected")
        XCTAssertFalse(rows[1].isEnabled, "Portugal has an unselected source")
        // A country the catalog did not place any source under is never reported as enabled.
        let empty = CountriesListView.rows(countries: [brazil], selection: ["a"], keys: [:])
        XCTAssertFalse(empty[0].isEnabled)
        // An unusual key shape degrades to itself, with a globe instead of a wrong flag.
        let odd = CatalogNodeSummary(id: 12, key: "worldwide", name: "Worldwide", kind: .country,
            sourceCount: 1, hasChildren: false)
        XCTAssertEqual(CountriesListView.slug(odd), "worldwide")
        XCTAssertEqual(CountriesListView.flag("worldwide"), "🌐")
    }

    /// T7 layout: a node's own sources are drawn in sections by the catalog's media kind, and a sub-node is
    /// "enabled" only when every one of its own sources is selected — read with the level, not per row.
    func testNodeSectionsAndSubNodeStateComeFromTheLevel() async {
        let backend = Backend()
        let brazil = node(10, "Brazil", kind: .country, children: true)
        let saoPaulo = node(30, "São Paulo")
        backend.countries = [brazil]
        backend.childrenByNode = [10: [saoPaulo]]
        backend.sourcesByNode = [10: [
            .init(id: "a", title: "Alpha", language: "pt", mediaKind: "text", defaultEnabled: true),
            .init(id: "b", title: "Beta", language: nil, mediaKind: "audio", defaultEnabled: true),
            .init(id: "c", title: "Gamma", language: nil, mediaKind: "video", defaultEnabled: true),
        ]]
        backend.childKeysByNode = [10: [30: ["c"]]]
        backend.selection = ["a", "c"]
        let store = SourceManagementStore(backend: backend)
        // `load` is what brings the reader's own selection in; the node's level then reads its own keys.
        await store.load()
        await store.open(brazil)
        XCTAssertEqual(store.nodeSections.map(\.id), ["audio", "video", "text"],
            "media kinds draw in one fixed order, not the catalog's row order")
        XCTAssertEqual(store.nodeSections.map(\.title), ["Podcasts", "Vídeo", "Texto"])
        XCTAssertEqual(store.nodeSections.map(\.icon), ["headphones", "play.rectangle.fill", "doc.text"])
        XCTAssertEqual(store.nodeSections.first?.rows.map(\.detail), ["b"], "the row's second line is the feed's own address")
        XCTAssertFalse(store.nodeSections.first?.rows.first?.isSelected ?? true,
            "the audio row is not selected: only the text and video sources are")
        XCTAssertTrue(store.nodeSections.last?.rows.first?.isSelected == true, "the text source is")
        // The sub-node's own keys were read with the level, and "c" alone is not all of São Paulo's… but it is
        // what the catalog placed under it, so the row states exactly that.
        XCTAssertTrue(store.isNodeEnabled(saoPaulo), "every key the catalog placed under it is selected")
        backend.childKeysByNode = [10: [30: ["c", "d"]]]
        await store.open(brazil)
        XCTAssertFalse(store.isNodeEnabled(saoPaulo), "one of its own sources is not selected")
        // A node the catalog placed nothing under is never reported as enabled.
        XCTAssertFalse(store.isNodeEnabled(node(99, "Empty")))
    }

    func testSearchTrimsAndClears() async {
        let backend = Backend()
        let alpha = CatalogSourceSummary(id: "https://a.example/feed", title: "Alpha", language: nil,
            mediaKind: "text", defaultEnabled: true)
        backend.searchResults = [alpha]
        let store = SourceManagementStore(backend: backend)
        await store.search("   ")
        XCTAssertTrue(backend.searches.isEmpty, "a blank query is not a search")
        XCTAssertTrue(store.results.isEmpty)
        await store.search("  alpha ")
        XCTAssertEqual(backend.searches, ["alpha"])
        XCTAssertEqual(store.results.map(\.title), ["Alpha"])
        await store.clearSearch()
        XCTAssertEqual(store.query, "")
        XCTAssertTrue(store.results.isEmpty)
    }
}
