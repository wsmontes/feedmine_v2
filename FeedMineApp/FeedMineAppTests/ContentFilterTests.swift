import XCTest
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineComposition
import FeedMineUI
@testable import FeedMine

/// The reader's content filters, inside the app: a rule hides the cards it matches, and the master switch turns
/// the hiding off **without erasing the rule** — V1's own behaviour (`ContentFilterStore.isEnabled` gated
/// `activeFilters`; nothing was ever deleted), and the property a reader depends on when they turn the switch
/// back on.
///
/// The supply is the test target's own fixture transport, so what is asserted is the pipeline's decision and not
/// what a network happened to answer.
@MainActor
final class ContentFilterTests: XCTestCase {
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func root(directory: URL) -> AppComposition {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 5
        return AppComposition(directory: directory, feeds: TrustedFeed.development,
            transportConfiguration: configuration)
    }

    private func setSettings(_ directory: URL, _ change: (inout ReaderSettings) -> Void) throws {
        let coordinator = ReaderSettingsCoordinator(database: try RuntimeDatabase(location: .init(directory: directory)))
        var settings = try coordinator.settings()
        change(&settings)
        _ = try coordinator.update(settings)
    }

    private func settings(_ directory: URL) throws -> ReaderSettings {
        try ReaderSettingsCoordinator(database: try RuntimeDatabase(location: .init(directory: directory))).settings()
    }

    private func published(_ association: FeedAssociation?) -> [String] {
        (association?.store.state.presentation?.window.items ?? []).compactMap(\.title)
    }

    /// The exclusions a **context** carries — a smart bookmark's own words, which V1 kept per preset and the V1
    /// importer preserves — are not replaced by the reader's global filters, and the master switch masks only the
    /// global half.
    func testAContextsOwnExclusionsSurviveTheGlobalGate() async throws {
        let directory = directory()
        let root = root(directory: directory)
        try setSettings(directory) { settings in
            settings.contentFiltersEnabled = true
            settings.contentFilterRules = ["global word"]
        }
        let own = ReaderContentExclusions(isEnabled: true, rules: ["bookmark word"])
        try await root.applyFilter(ReaderFilter(exclusions: own), preset: .smartFeed("bookmark"))

        let withGate = try XCTUnwrap(root.association?.contextKey).filter.exclusions
        XCTAssertEqual(withGate.rules, ["bookmark word", "global word"],
            "what hides content is the context's own words plus the reader's global ones")

        try setSettings(directory) { $0.contentFiltersEnabled = false }
        await root.reapplyReaderFilters()
        let withoutGate = try XCTUnwrap(root.association?.contextKey).filter.exclusions
        XCTAssertEqual(withoutGate.rules, ["bookmark word"],
            "the gate masks the global rules and leaves the context's own")
        XCTAssertTrue(withoutGate.isEnabled)
        await root.association?.close()
    }

    /// The sheet and the lens write the filter they are shown, and what they are shown is the reader's own
    /// criteria — never the folded one. Otherwise applying a filter would persist the reader's global words into
    /// the context, where they would outlive the master switch that is supposed to mask them.
    func testApplyingAFilterDoesNotPersistTheGlobalRulesIntoTheContext() async throws {
        let directory = directory()
        let root = root(directory: directory)
        try setSettings(directory) { settings in
            settings.contentFiltersEnabled = true
            settings.contentFilterRules = ["published fixture"]
        }
        await root.launch()
        // What the sheet is seeded with, and what a lens chip hands back: the reader's own criteria.
        XCTAssertTrue(root.currentFilter.exclusions.rules.isEmpty,
            "the editing surface states the reader's own words, not the folded ones")
        XCTAssertEqual(try XCTUnwrap(root.association?.contextKey).filter.exclusions.rules, ["published fixture"],
            "while the session applies the global half, as the one place that folds it")

        // A criterion that hides nothing (the content type is a criterion this build cannot enforce) is applied
        // the way the sheet applies one.
        try await root.applyFilter(ReaderFilter(contentType: .video), preset: .everything)
        XCTAssertTrue(root.currentContextKey.filter.exclusions.rules.isEmpty,
            "applying a criterion did not copy the global rules into the persisted context")
        XCTAssertEqual(try XCTUnwrap(root.association?.contextKey).filter.exclusions.rules, ["published fixture"],
            "the session still applies them — from the settings, not from a copy")

        // With the gate off, nothing is hidden: the fixture supply comes back.
        try setSettings(directory) { $0.contentFiltersEnabled = false }
        await root.reapplyReaderFilters()
        let reopened = try XCTUnwrap(root.association)
        _ = try await reopened.driver.drive(resources: FeedAssociation.resources)
        XCTAssertFalse(published(reopened).isEmpty,
            "the switch that says nothing is hidden must actually hide nothing")
        await reopened.close()
    }

    /// A rule that matches the fixture's whole supply hides it; turning the gate off brings the same supply back
    /// with the rule still stored.
    func testARuleHidesTheSupplyAndTheGateOnlyMasksIt() async throws {
        let directory = directory()
        // The composition opens the reader's preferences (the row the settings live in); the rule is written
        // before the session is launched, which is what a reader setting a filter does.
        let root = root(directory: directory)
        // "published fixture" matches every headline the fixture transport serves, so the feed has nothing left
        // to publish while the filters are on.
        try setSettings(directory) { settings in
            settings.contentFiltersEnabled = true
            settings.contentFilterRules = ["published fixture"]
        }
        await root.launch()
        let association = try XCTUnwrap(root.association)
        _ = try await association.driver.drive(resources: FeedAssociation.resources)
        XCTAssertTrue(published(association).isEmpty,
            "a rule that matches everything must publish nothing; published: \(published(association))")

        // The master switch off: the rule is not erased, and the feed it was hiding comes back.
        try setSettings(directory) { $0.contentFiltersEnabled = false }
        await root.reapplyReaderFilters()
        let reopened = try XCTUnwrap(root.association)
        XCTAssertFalse(reopened === association, "the session is rebuilt when what it hides changes")
        _ = try await reopened.driver.drive(resources: FeedAssociation.resources)
        XCTAssertFalse(published(reopened).isEmpty, "with the filters off the same supply is published again")

        let stored = try settings(directory)
        XCTAssertFalse(stored.contentFiltersEnabled)
        XCTAssertEqual(stored.contentFilterRules, ["published fixture"], "the rule is still the reader's")
        await reopened.close()
    }

    /// A template the reader turns on hides what its own words match, resolved for their language: the fixture's
    /// headline carries the word "fixture", which the template below carries in English.
    func testATemplateTheReaderTurnsOnHidesWhatItsWordsMatch() async throws {
        let directory = directory()
        let catalog = [ReaderContentFilterTemplate(key: "fixture",
            names: ["en": "Fixture"], keywords: ["en": ["published fixture"], "pt": ["publicado"]]),
            ReaderContentFilterTemplate(key: "unused",
                names: ["en": "Unused"], keywords: ["en": ["nothing matches this"]])]
        let database = try RuntimeDatabase(location: .init(directory: directory))
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: [])
        let adapter = ReaderContentFilterAdapter(database: database, templates: catalog)
        let store = ReaderContentFilterStore(backend: adapter)
        await store.load()
        XCTAssertEqual(store.templates.map(\.id), ["fixture", "unused"])
        XCTAssertEqual(store.templates.first?.ruleCount, 1, "the template states how many rules it adds")

        await store.toggleTemplate("fixture")
        let root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        _ = try await association.driver.drive(resources: FeedAssociation.resources)
        XCTAssertTrue(published(association).isEmpty, "the template's words hide the fixture supply")
        XCTAssertEqual(try settings(directory).contentFilterTemplates, ["fixture"])

        // Turning the template off takes exactly its words and leaves the reader's own alone.
        await store.addRules("published fixture 7")
        await store.toggleTemplate("fixture")
        let after = try settings(directory)
        XCTAssertEqual(after.contentFilterTemplates, [])
        XCTAssertEqual(after.contentFilterRules, ["published fixture 7"],
            "the reader's own words survive a template being turned off")
        await association.close()
    }
}
