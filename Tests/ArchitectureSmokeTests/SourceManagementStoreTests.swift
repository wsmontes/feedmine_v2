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
        var latestNodes: [String: CatalogNodeSummary] = [:]
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
        func currentNode(for node: CatalogNodeSummary) async throws -> CatalogNodeSummary? {
            try guardFailure()
            return latestNodes[node.key] ?? node
        }
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
        var healthByKey: [String: CatalogSourceHealth] = [:]
        func health() async throws -> [String: CatalogSourceHealth] { try guardFailure(); return healthByKey }
        func selection() async throws -> [String] { try guardFailure(); return selection }
        func setSelection(_ keys: [String]) async throws {
            try guardFailure(); if failSetSelection { throw SourceManagementErrorDouble.invalid }; selection = keys
        }
        func setEnabled(node: CatalogNodeSummary, enabled: Bool) async throws {
            try guardFailure(); if failSetSelection { throw SourceManagementErrorDouble.invalid }
            setEnabledCalls.append((node.id, enabled))
        }
    }

    /// Explicitly delayed backend calls, with a changing *existing* catalogue fingerprint.
    /// No clock or randomized scheduling: tests decide which rev-5/rev-6 response completes first.
    private actor DeferredBackend: SourceManagementBackend {
        private var fingerprint = "rev-5"
        private var latestNodes: [String: CatalogNodeSummary] = [:]
        private var sourceRows: [String: [CatalogSourceSummary]] = [:]
        private var heldSourceKeys: Set<String> = []
        private var sourceReads: [String: CheckedContinuation<[CatalogSourceSummary], Never>] = [:]
        private var sourceAwaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
        private var searches: [String: [CheckedContinuation<[CatalogSourceSummary], Never>]] = [:]
        private var nodes: [String: CheckedContinuation<[CatalogNodeSummary], Never>] = [:]
        private var searchAwaiters: [(query: String, count: Int, resume: CheckedContinuation<Void, Never>)] = []
        private var nodeAwaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

        func catalogueFingerprint() async -> String? { fingerprint }
        func activate(_ revision: String) { fingerprint = revision }
        func updateNode(_ node: CatalogNodeSummary) { latestNodes[node.key] = node }
        func currentNode(for node: CatalogNodeSummary) async throws -> CatalogNodeSummary? {
            latestNodes[node.key] ?? node
        }
        func setSourceRows(_ rows: [CatalogSourceSummary], for key: String) { sourceRows[key] = rows }
        func holdSourceReads(for key: String) { heldSourceKeys.insert(key) }
        func waitForSourceRead(_ key: String) async {
            if sourceReads[key] != nil { return }
            await withCheckedContinuation { sourceAwaiters[key, default: []].append($0) }
        }
        func finishSourceRead(_ key: String, rows: [CatalogSourceSummary]) {
            sourceReads.removeValue(forKey: key)?.resume(returning: rows)
        }

        func searchSources(_ query: String) async throws -> [CatalogSourceSummary] {
            await withCheckedContinuation { continuation in
                searches[query, default: []].append(continuation)
                let ready = searchAwaiters.filter { $0.query == query
                    && (searches[query]?.count ?? 0) >= $0.count }
                searchAwaiters.removeAll { $0.query == query
                    && (searches[query]?.count ?? 0) >= $0.count }
                for waiter in ready { waiter.resume.resume() }
            }
        }
        func waitForSearch(_ query: String, count: Int = 1) async {
            if (searches[query]?.count ?? 0) >= count { return }
            await withCheckedContinuation { searchAwaiters.append((query, count, $0)) }
        }
        func finishSearch(_ query: String, with values: [CatalogSourceSummary], newest: Bool = false) {
            guard var pending = searches[query], !pending.isEmpty else { return }
            let callback = newest ? pending.removeLast() : pending.removeFirst()
            if pending.isEmpty { searches.removeValue(forKey: query) }
            else { searches[query] = pending }
            callback.resume(returning: values)
        }

        func children(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary] {
            await withCheckedContinuation { continuation in
                nodes[node.key] = continuation
                for waiter in nodeAwaiters.removeValue(forKey: node.key) ?? [] { waiter.resume() }
            }
        }
        func waitForNode(_ key: String) async {
            if nodes[key] != nil { return }
            await withCheckedContinuation { nodeAwaiters[key, default: []].append($0) }
        }
        func finishNode(_ key: String, with values: [CatalogNodeSummary]) {
            nodes.removeValue(forKey: key)?.resume(returning: values)
        }

        func languages() async throws -> [CatalogLanguageSummary] { [] }
        func sections() async throws -> [CatalogNodeSummary] { [] }
        func countries() async throws -> [CatalogNodeSummary] { [] }
        func breadcrumb(of node: CatalogNodeSummary) async throws -> [CatalogNodeSummary] { [] }
        func sources(in node: CatalogNodeSummary) async throws -> [CatalogSourceSummary] {
            guard heldSourceKeys.contains(node.key) else { return sourceRows[node.key] ?? [] }
            return await withCheckedContinuation { continuation in
                sourceReads[node.key] = continuation
                for waiter in sourceAwaiters.removeValue(forKey: node.key) ?? [] { waiter.resume() }
            }
        }
        func countryKeys() async throws -> [Int64: Set<String>] { [:] }
        func childKeys(of node: CatalogNodeSummary) async throws -> [Int64: Set<String>] { [:] }
        func health() async throws -> [String: CatalogSourceHealth] { [:] }
        func selection() async throws -> [String] { [] }
        func setSelection(_ keys: [String]) async throws {}
        func setEnabled(node: CatalogNodeSummary, enabled: Bool) async throws {}
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

    /// T7's health column: only what the runtime observed reaches a row, and the summary counts exactly those.
    func testHealthReachesTheRowsAndTheSummary() async {
        let backend = Backend()
        let brazil = node(10, "Brazil", kind: .country)
        backend.countries = [brazil]
        backend.sourcesByNode = [10: [
            .init(id: "a", title: "Alpha", language: nil, mediaKind: "text", defaultEnabled: true),
            .init(id: "b", title: "Beta", language: nil, mediaKind: "text", defaultEnabled: true),
        ]]
        backend.healthByKey = ["a": .init(state: .failing(consecutive: 3))]
        let store = SourceManagementStore(backend: backend)
        await store.load()
        await store.open(brazil)
        XCTAssertEqual(store.health.count, 1, "a source never attempted carries no state")
        XCTAssertEqual(store.failingSourceCount, 1)
        let rows = try? XCTUnwrap(store.nodeSections.first?.rows)
        XCTAssertEqual(rows?.map(\.id), ["a", "b"])
        XCTAssertEqual(rows?.first?.health?.failures, 3)
        XCTAssertNil(rows?.last?.health, "the second source was never attempted")
    }

    /// PD10-B2 UI: a previously issued search for the same text must not publish a rev-5
    /// answer after activation. A new explicit search then reads and publishes rev-6 data.
    func testPD10B2SearchChecksCommittedRevisionBeforePublishing() async {
        let backend = DeferredBackend()
        let store = SourceManagementStore(backend: backend)
        let old = CatalogSourceSummary(id: "old", title: "Revision 5",
            language: "en", mediaKind: "text", defaultEnabled: true)
        let current = CatalogSourceSummary(id: "new", title: "Revision 6",
            language: "pt", mediaKind: "text", defaultEnabled: true)

        let previousRequest = Task { await store.search("same") }
        await backend.waitForSearch("same")
        await backend.activate("rev-6")
        let currentRequest = Task { await store.search("same") }
        await backend.waitForSearch("same", count: 2)
        await backend.finishSearch("same", with: [current], newest: true)
        await currentRequest.value
        await backend.finishSearch("same", with: [old])
        await previousRequest.value
        XCTAssertEqual(store.results.map(\.id), ["new"],
            "a rev-5 response arriving after the rev-6 response must never overwrite it")
    }

    /// PD10-B2 UI: changing the query while the old network/database operation is suspended
    /// must never replace the newer displayed answer, even if the first call completes last.
    func testPD10B2OldQueryCannotOverwriteNewSearch() async {
        let backend = DeferredBackend()
        let store = SourceManagementStore(backend: backend)
        let oldRequest = Task { await store.search("earlier") }
        await backend.waitForSearch("earlier")
        let newRequest = Task { await store.search("later") }
        await backend.waitForSearch("later")
        await backend.finishSearch("later", with: [
            CatalogSourceSummary(id: "later", title: "Latest", language: "pt",
                mediaKind: "text", defaultEnabled: true)
        ])
        await newRequest.value
        await backend.finishSearch("earlier", with: [
            CatalogSourceSummary(id: "earlier", title: "Stale", language: "en",
                mediaKind: "text", defaultEnabled: true)
        ])
        await oldRequest.value
        XCTAssertEqual(store.query, "later")
        XCTAssertEqual(store.results.map(\.id), ["later"])
    }

    /// PD10-B2 UI: an old node fetch must not install breadcrumbs/children after the source
    /// surface opens a different node under a promoted catalogue.
    func testPD10B2OldNodeCannotOverwriteNewNavigation() async {
        let backend = DeferredBackend()
        let store = SourceManagementStore(backend: backend)
        let earlier = node(1, "Old", children: true)
        let later = node(2, "Current", children: true)
        let child = node(3, "Current child")
        let oldRequest = Task { await store.open(earlier) }
        await backend.waitForNode(earlier.key)
        await backend.activate("rev-6")
        let newRequest = Task { await store.open(later) }
        await backend.waitForNode(later.key)
        await backend.finishNode(later.key, with: [child])
        await newRequest.value
        await backend.finishNode(earlier.key, with: [node(4, "Stale child")])
        await oldRequest.value
        XCTAssertEqual(store.openNode?.key, later.key)
        XCTAssertEqual(store.children.map(\.key), [child.key])
        XCTAssertTrue(store.breadcrumb.isEmpty)
    }

    /// PD10-B2: a node displayed as a leaf in rev 5 acquires children and a new title in rev 6.
    /// Opening that *old summary* must resolve the active identity and publish no old metadata.
    func testPD10B2OpeningStaleLeafUsesPromotedNodeAndDiscoversNewChildren() async {
        let backend = Backend()
        let stale = node(10, "Old title", children: false)
        let promoted = CatalogNodeSummary(id: 42, key: stale.key, name: "Updated title",
            kind: .topic, sourceCount: 3, hasChildren: true)
        let child = node(43, "New child")
        backend.latestNodes[stale.key] = promoted
        backend.childrenByNode[promoted.id] = [child]
        backend.sourcesByNode[promoted.id] = [
            .init(id: "active", title: "Active source", language: "pt",
                mediaKind: "text", defaultEnabled: true)
        ]
        let store = SourceManagementStore(backend: backend)
        await store.open(stale)
        XCTAssertEqual(store.openNode, promoted, "old node metadata must not be published")
        XCTAssertEqual(store.children.map(\.key), [child.key],
            "a stale hasChildren=false cannot suppress children added in the active revision")
        XCTAssertEqual(store.sources.map(\.id), ["active"])
    }

    /// PD10-B2: pending open keeps the previously published level untouched, even though the
    /// requested node summary has changed. The revision's complete answer is installed together.
    func testPD10B2OpenDoesNotPublishStaleNodeBeforeProtectedRead() async {
        let backend = DeferredBackend()
        let store = SourceManagementStore(backend: backend)
        let previous = node(1, "Previous")
        await store.open(previous)
        XCTAssertEqual(store.openNode, previous)
        let old = node(2, "Old", children: false)
        let promoted = CatalogNodeSummary(id: 20, key: old.key, name: "Promoted",
            kind: .topic, sourceCount: 2, hasChildren: true)
        await backend.activate("rev-6")
        await backend.updateNode(promoted)
        let opening = Task { await store.open(old) }
        await backend.waitForNode(promoted.key)
        XCTAssertEqual(store.openNode, previous, "do not publish the old or incomplete node")
        await backend.finishNode(promoted.key, with: [node(21, "New descendant")])
        await opening.value
        XCTAssertEqual(store.openNode, promoted)
        XCTAssertEqual(store.children.map(\.id), [21])
    }

    /// PD10-B2: a successful selection write may have started in rev 5. If its refresh returns
    /// after activation, it must not install rev-5 sources over the published node.
    func testPD10B2SetEnabledCannotInstallOldSourcesAfterActivation() async {
        let backend = DeferredBackend()
        let store = SourceManagementStore(backend: backend)
        let current = node(8, "Visible")
        let originallyVisible = CatalogSourceSummary(id: "visible", title: "Published",
            language: "pt", mediaKind: "text", defaultEnabled: true)
        let stale = CatalogSourceSummary(id: "removed", title: "Old catalogue",
            language: "en", mediaKind: "text", defaultEnabled: true)
        await backend.setSourceRows([originallyVisible], for: current.key)
        await store.open(current)
        XCTAssertEqual(store.sources.map(\.id), ["visible"])
        await backend.holdSourceReads(for: current.key)
        let toggling = Task { await store.setEnabled(current, enabled: true) }
        await backend.waitForSourceRead(current.key)
        await backend.activate("rev-6")
        await backend.finishSourceRead(current.key, rows: [stale])
        await toggling.value
        XCTAssertEqual(store.sources.map(\.id), ["visible"],
            "late rev-5 refresh cannot overwrite sources after the revision changed")
        XCTAssertEqual(store.openNode, current)
    }

    /// PD10-B2: with the catalogue fingerprint unchanged, a delayed setEnabled refresh must
    /// still respect a different node the reader opened while the previous read was suspended.
    func testPD10B2SetEnabledDoesNotReplaceAnotherOpenedNode() async {
        let backend = DeferredBackend()
        let store = SourceManagementStore(backend: backend)
        let old = node(6, "Old level")
        let next = node(7, "Current level")
        let nextSource = CatalogSourceSummary(id: "current", title: "Current source",
            language: "pt", mediaKind: "text", defaultEnabled: true)
        await backend.setSourceRows([nextSource], for: next.key)
        await store.open(old)
        await backend.holdSourceReads(for: old.key)
        let toggling = Task { await store.setEnabled(old, enabled: true) }
        await backend.waitForSourceRead(old.key)
        await store.open(next)
        XCTAssertEqual(store.sources.map(\.id), ["current"])
        await backend.finishSourceRead(old.key, rows: [
            CatalogSourceSummary(id: "old", title: "Stale refresh", language: "en",
                mediaKind: "text", defaultEnabled: true)
        ])
        await toggling.value
        XCTAssertEqual(store.openNode?.key, next.key)
        XCTAssertEqual(store.sources.map(\.id), ["current"])
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
