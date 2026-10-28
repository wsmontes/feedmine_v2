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
        _ = try await reopened.driver.drive(resources: reopened.resources)
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
        _ = try await association.driver.drive(resources: association.resources)
        XCTAssertTrue(published(association).isEmpty,
            "a rule that matches everything must publish nothing; published: \(published(association))")

        // The master switch off: the rule is not erased, and the feed it was hiding comes back.
        try setSettings(directory) { $0.contentFiltersEnabled = false }
        await root.reapplyReaderFilters()
        let reopened = try XCTUnwrap(root.association)
        XCTAssertFalse(reopened === association, "the session is rebuilt when what it hides changes")
        _ = try await reopened.driver.drive(resources: reopened.resources)
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
        // V1's `resolvedKeywords`: English **always**, plus the reader's own language when the catalogue carries it.
        // This fixture is deliberately bilingual — `en` and `pt` — so the count is a fact about the declared run,
        // not a constant: one rule in an English run, two in a Portuguese one. Shrinking the fixture to one
        // language would make both runs green by deleting the rule the reader's language contributes.
        let readerLanguage = Locale.current.language.languageCode?.identifier
        XCTAssertEqual(store.templates.first?.ruleCount, readerLanguage == "pt" ? 2 : 1,
            "the template states every rule it adds in \(readerLanguage ?? "the declared language"): "
                + "English plus the reader's own")

        await store.toggleTemplate("fixture")
        let root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        _ = try await association.driver.drive(resources: association.resources)
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

extension ContentFilterTests {
    func testSourceOnlyRuleKeepsTheAssociationEditionAnchorAndPublishedPrefix() async throws {
        let directory = directory(), root = root(directory: directory)
        await root.launch()
        let association = try XCTUnwrap(root.association)
        let before = try XCTUnwrap(association.store.state.presentation)
        let ids = before.window.items.map(\.id)
        XCTAssertFalse(ids.isEmpty, "the continuity proof starts with published history")
        let emptyFilters = try XCTUnwrap(root.makeContentFilterStore())
        await emptyFilters.load()
        XCTAssertTrue(emptyFilters.sourceExclusions.isEmpty)
        let emptyChange = await emptyFilters.removeSourceExclusion(SourceID())
        XCTAssertFalse(emptyChange)
        await root.noteSourceExclusionsChanged()
        XCTAssertTrue(root.association === association)
        XCTAssertEqual(association.store.state.presentation?.editionID, before.editionID)
        XCTAssertEqual(association.store.state.presentation?.window.anchor, before.window.anchor)
        XCTAssertTrue(try settings(directory).contentSourceExclusions.isEmpty)
        let rule = ReaderSourceExclusion(sourceID: TrustedFeed.development[0].sourceID, displayName: "Fixture source")
        let preferences = ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        let selectedBefore = try preferences.load()
        try await root.excludeSource(forKey: TrustedFeed.development[0].principal, displayName: rule.displayName)
        let selectedAfter = try preferences.load()
        XCTAssertEqual(selectedAfter?.sourceKeys, selectedBefore?.sourceKeys)
        XCTAssertEqual(selectedAfter?.selectionVersion, selectedBefore?.selectionVersion)
        XCTAssertEqual(selectedAfter?.activeContextKey, selectedBefore?.activeContextKey)
        await root.reapplyReaderFilters()
        XCTAssertTrue(root.association === association)
        let after = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(after.editionID, before.editionID)
        XCTAssertEqual(after.window.anchor, before.window.anchor)
        XCTAssertEqual(Array(after.window.items.map(\.id).prefix(ids.count)), ids)
        XCTAssertEqual(try settings(directory).contentSourceExclusions, [rule])
        XCTAssertTrue(root.hasActiveSourceExclusions)
        let generalSettings = try XCTUnwrap(root.makeReaderSettingsStore())
        await generalSettings.load()
        await generalSettings.update { $0.contentFiltersEnabled = false }
        XCTAssertNil(generalSettings.errorMessage)
        XCTAssertFalse(root.hasActiveSourceExclusions)
        XCTAssertEqual(try settings(directory).contentSourceExclusions, [rule])
        await root.reapplyReaderFilters()
        XCTAssertTrue(root.association === association)
        let disabled = try XCTUnwrap(association.store.state.presentation)
        XCTAssertEqual(disabled.editionID, before.editionID)
        XCTAssertEqual(disabled.window.anchor, before.window.anchor)
        XCTAssertEqual(Array(disabled.window.items.map(\.id).prefix(ids.count)), ids)
        await association.close()
    }
}

extension ContentFilterTests {
    func testImportedSourceExclusionUsesReaderAuthorityWithoutChangingSelection() async throws {
        let directory = directory(), root = root(directory: directory)
        let db = try RuntimeDatabase(location: .init(directory: directory))
        let preferences = ReaderPreferencesStore(database: db)
        _ = try preferences.initialize(sourceKeys: [])
        let key = "https://reader.example/feed"
        _ = try ReaderLibraryStore(database: db).commitImport([
            .init(id: key, title: "Imported Orchard", requestURL: key, categoryPath: [])
        ], rejected: 0, at: Date(timeIntervalSince1970: 100))
        let before = try preferences.load()
        let row = try XCTUnwrap(root.importedSourceRows.first { $0.id == key })
        try await root.excludeImportedSource(forKey: row.id, displayName: row.title)
        let after = try preferences.load()
        XCTAssertEqual(after?.sourceKeys, before?.sourceKeys)
        XCTAssertEqual(after?.selectionVersion, before?.selectionVersion)
        XCTAssertEqual(after?.activeContextKey, before?.activeContextKey)
        let rule = try XCTUnwrap(try settings(directory).contentSourceExclusions.first)
        XCTAssertEqual(rule.sourceID, ReaderSourceIdentity.sourceID(forKey: key))
        XCTAssertNotEqual(rule.sourceID, LegacyCatalogImport.sourceID(forKey: key))
        XCTAssertEqual(rule.displayName, row.title)
        do {
            try await root.excludeImportedSource(forKey: "https://unknown.example/feed", displayName: row.title)
            XCTFail("an unknown key must not mint a rule")
        } catch {}
        XCTAssertEqual(try settings(directory).contentSourceExclusions, [rule])
    }
}

extension ContentFilterTests {
    func testImportedSourceKeepsThePreviouslyEstablishedCatalogueIdentity() async throws {
        let directory = directory(), root = root(directory: directory)
        let db = try RuntimeDatabase(location: .init(directory: directory))
        _ = try ReaderPreferencesStore(database: db).initialize(sourceKeys: [])
        let key = "https://reader.example/catalogue-first"
        let library = ReaderLibraryStore(database: db)
        try library.rememberResolvedSources([(key: key, authority: "catalog")])
        _ = try library.commitImport([
            .init(id: key, title: "Imported copy", requestURL: key, categoryPath: [])
        ], rejected: 0, at: Date(timeIntervalSince1970: 100))
        let before = try library.sourceLinks()
        try await root.excludeImportedSource(forKey: key, displayName: "Imported copy")
        let rule = try XCTUnwrap(try settings(directory).contentSourceExclusions.first)
        XCTAssertEqual(rule.sourceID, LegacyCatalogImport.sourceID(forKey: key))
        XCTAssertNotEqual(rule.sourceID, ReaderSourceIdentity.sourceID(forKey: key))
        XCTAssertEqual(try library.sourceLinks(), before)
    }
}

extension ContentFilterTests {
    func testWarmRelaunchKeepsSavedHistoryAndGatesOnlyNewSourceSupply() async throws {
        let directory = directory(), firstRoot = root(directory: directory)
        await firstRoot.launch()
        let firstAssociation = try XCTUnwrap(firstRoot.association)
        let db = try RuntimeDatabase(location: .init(directory: directory))
        let publication = PublicationStore(database: db)
        let editionID = try XCTUnwrap(firstAssociation.store.state.presentation).editionID
        let initialIDs = try publication.segments(editionID: editionID).flatMap(\.cardIDs)
        let savedID = try XCTUnwrap(initialIDs.last)
        let saved = try XCTUnwrap(publication.card(id: savedID))
        let a = try XCTUnwrap(TrustedFeed.development.first { $0.sourceID == saved.sourceID })
        let b = try XCTUnwrap(TrustedFeed.development.first { $0.sourceID != a.sourceID })
        try publication.toggleBookmark(cardID: savedID, at: Date())
        try await firstRoot.excludeSource(forKey: a.principal, displayName: a.displayName)
        await firstAssociation.close()
        let frozenIDs = try publication.segments(editionID: editionID).flatMap(\.cardIDs)
        let frozen = try frozenIDs.map { try XCTUnwrap(publication.card(id: $0)) }
        XCTAssertEqual(frozen.last?.sourceID, a.sourceID, "B needs a PD-4-compatible predecessor")
        let checkpoint = try XCTUnwrap(SessionStore(database: db).checkpoint())

        let warmRoot = root(directory: directory)
        await warmRoot.launch()
        let warm = try XCTUnwrap(warmRoot.association)
        XCTAssertTrue(warmRoot.hasActiveSourceExclusions)
        let restored = try XCTUnwrap(warm.store.state.presentation)
        XCTAssertEqual(restored.editionID, editionID)
        XCTAssertEqual(restored.window.anchor.cardID, checkpoint.cardID)
        XCTAssertEqual(try publication.bookmarkedCardIDs(), [savedID])
        for card in frozen { XCTAssertEqual(try publication.card(id: card.id), card) }

        XCTAssertEqual(try SessionStore(database: db).checkpoint(), checkpoint)
        let newA = try admitWarmSupply(sourceID: a.sourceID, title: "F13 excluded new A", database: db)
        let newB = try admitWarmSupply(sourceID: b.sourceID, title: "F13 permitted new B", database: db)
        print("F13 warm proof excluded=\(a.sourceID) allowed=\(b.sourceID) newA=\(newA.id) newB=\(newB.id) published=\(frozenIDs.count)")
        await warm.driver.noteLocalSupplyFact()
        // Fresh supply does not force publication into an already stocked reader. The next opportunity
        // is a real tail approach; only this intentional reader movement may change the durable anchor.
        try await waitForWarmPublication(newB.id, association: warm, publication: publication, requestTailDemand: true, trace: warmRoot.trace, directory: directory)
        _ = try await warm.session.checkpointCurrentPosition(at: Date())
        let demandCheckpoint = try SessionStore(database: db).checkpoint()
        let demandAnchor = try XCTUnwrap(warm.store.state.presentation).window.anchor
        var ids = try publication.segments(editionID: editionID).flatMap(\.cardIDs)
        var revisions = try ids.map { try XCTUnwrap(publication.card(id: $0)).originRevisionID }
        XCTAssertFalse(revisions.contains(newA.id))
        XCTAssertEqual(revisions.filter { $0 == newB.id }.count, 1)
        XCTAssertTrue(warmRoot.association === warm)

        let filters = try XCTUnwrap(warmRoot.makeContentFilterStore())
        await filters.load()
        let removed = await filters.removeSourceExclusion(a.sourceID)
        XCTAssertTrue(removed)
        try await waitForWarmPublication(newA.id, association: warm, publication: publication)
        for _ in 0..<2 { _ = try await warm.driver.drive(resources: warm.resources) }
        ids = try publication.segments(editionID: editionID).flatMap(\.cardIDs)
        revisions = try ids.map { try XCTUnwrap(publication.card(id: $0)).originRevisionID }
        XCTAssertEqual(revisions.filter { $0 == newA.id }.count, 1)
        XCTAssertEqual(revisions.filter { $0 == newB.id }.count, 1)
        XCTAssertEqual(Array(ids.prefix(frozenIDs.count)), frozenIDs)
        XCTAssertEqual(try publication.bookmarkedCardIDs(), [savedID])
        XCTAssertEqual(try SessionStore(database: db).checkpoint(), demandCheckpoint)
        for card in frozen { XCTAssertEqual(try publication.card(id: card.id), card) }
        XCTAssertEqual(warm.store.state.presentation?.window.anchor, demandAnchor)
        XCTAssertTrue(warmRoot.association === warm)
        await warm.close()
    }

    private func admitWarmSupply(sourceID: SourceID, title: String, database: RuntimeDatabase) throws -> OriginRevision {
        let origin = OriginRecordID(), now = Date()
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin,
            externalVersionIdentity: nil, headline: title, summary: "Independent local source exclusion proof",
            bodyText: String(repeating: "Locally retained story body. ", count: 20), authoredAt: now,
            modifiedAt: nil, observedAt: now, language: "en", primaryLink: nil, searchProjection: nil, providerID: nil)
        try ContentStore(database: database).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "f13-app-proof",
                value: origin.rawValue.uuidString, role: .object), revision: revision, mediaCandidates: [],
            availability: .available, observedAt: now, expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: sourceID, kind: .direct, observedAt: now)]))
        return revision
    }

    private func waitForWarmPublication(_ revision: OriginRevisionID, association: FeedAssociation,
        publication: PublicationStore, requestTailDemand: Bool = false,
        trace: RunwayTrace? = nil, directory: URL? = nil) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var lastRequestedTail: PublicationCardID?
        while ContinuousClock.now < deadline {
            if requestTailDemand {
                // Advance through already published reserve before expecting a new publication.
                let tail = try XCTUnwrap(association.store.state.presentation?.window.items.last)
                if tail.id != lastRequestedTail {
                    lastRequestedTail = tail.id
                    await association.viewport(.init(anchor: .init(cardID: tail.id, placement: .top)), activity: .explicitTailApproach)
                }
            }
            let edition = try XCTUnwrap(association.store.state.presentation?.editionID)
            let ids = try publication.segments(editionID: edition).flatMap(\.cardIDs)
            if try ids.contains(where: { try publication.card(id: $0)?.originRevisionID == revision }) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        print("F13 wait status work=\(association.store.work) settlement=\(String(describing: await association.driver.settledEligibleOffer()))")
        trace?.flushAndWait()
        if let directory, let text = try? String(contentsOf: directory.appendingPathComponent("trace.jsonl"), encoding: .utf8) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "F13 warm publication trace"
            attachment.lifetime = .keepAlways
            add(attachment)
            let lines = text.split(separator: "\n").filter {
                $0.contains("candidate") || $0.contains("\"kind\":\"local\"")
            }
            print("F13 diagnostic local trace\n" + lines.suffix(40).joined(separator: "\n"))
        }
        XCTFail("the existing local-supply opportunity did not publish the expected allowed revision")
    }
}

extension ContentFilterTests {
    func testRemovingAColdSourceRulePublishesWithoutReplacingTheAssociation() async throws {
        let directory = directory(), root = root(directory: directory)
        try setSettings(directory) { settings in
            settings.contentSourceExclusions = TrustedFeed.development.map {
                ReaderSourceExclusion(sourceID: $0.sourceID, displayName: $0.displayName)
            }
        }
        await root.launch()
        let association = try XCTUnwrap(root.association)
        XCTAssertNil(association.store.state.presentation)
        XCTAssertEqual(association.store.work, .unavailable)
        let preferences = ReaderPreferencesStore(database: try RuntimeDatabase(location: .init(directory: directory)))
        let before = try preferences.load()
        let filters = try XCTUnwrap(root.makeContentFilterStore())
        await filters.load()
        let removed = await filters.removeSourceExclusion(TrustedFeed.development[1].sourceID)
        XCTAssertTrue(removed)
        let recovered = try XCTUnwrap(association.store.state.presentation)
        XCTAssertFalse(recovered.window.items.isEmpty)
        XCTAssertTrue(root.association === association)
        XCTAssertEqual(try preferences.load()?.sourceKeys, before?.sourceKeys)
        XCTAssertEqual(try preferences.load()?.selectionVersion, before?.selectionVersion)
        XCTAssertEqual(try settings(directory).contentSourceExclusions.map(\.sourceID), [TrustedFeed.development[0].sourceID])
        await association.close()
    }
}

extension ContentFilterTests {
    /// F13/R4: a global rule is not an explicit request to replace the reading context.
    /// Compare the presented reader separately from the frozen records; preserved rows alone do not
    /// prove that the reader can continue through the same published history.
    func testGlobalWordRuleKeepsPublishedReaderAndFrozenHistory() async throws {
        let directory = directory(), root = root(directory: directory)
        await root.launch()
        let original = try XCTUnwrap(root.association)
        let logicalContext = root.currentContextKey
        let before = try XCTUnwrap(original.store.state.presentation)
        let db = try RuntimeDatabase(location: .init(directory: directory))
        let publication = PublicationStore(database: db)
        let segments = try publication.segments(editionID: before.editionID)
        let records = try segments.flatMap(\.cardIDs).map { try XCTUnwrap(publication.card(id: $0)) }
        XCTAssertFalse(records.isEmpty)
        XCTAssertTrue(records.contains { $0.title?.lowercased().contains("published fixture") == true },
            "the rule must match a card that was actually published")
        let saved = try XCTUnwrap(records.first).id
        try publication.toggleBookmark(cardID: saved, at: Date())
        _ = try await original.session.checkpointCurrentPosition(at: Date())
        let checkpoint = try XCTUnwrap(SessionStore(database: db).checkpoint())
        let filters = try XCTUnwrap(root.makeContentFilterStore())
        await filters.load()
        func samePosition(_ value: SessionStore.CheckpointRecord?) -> Bool {
            value?.editionID == checkpoint.editionID && value?.cardID == checkpoint.cardID
                && value?.anchorPlacement == checkpoint.anchorPlacement
                && value?.topDelta == checkpoint.topDelta && value?.cardHeight == checkpoint.cardHeight
        }
        for step in ["add", "master-off", "master-on", "remove"] {
            switch step {
            case "add": await filters.addRules("published fixture")
            case "master-off": await filters.setEnabled(false)
            case "master-on": await filters.setEnabled(true)
            default: await filters.removeRule("published fixture")
            }
            XCTAssertNil(filters.errorMessage)
            let stored = try settings(directory)
            XCTAssertEqual(stored.contentFilterRules, step == "remove" ? [] : ["published fixture"])
            XCTAssertEqual(stored.contentFiltersEnabled, step != "master-off")
            // The host awaits this when the editor/settings closes. Persistence alone is not activation.
            await root.reapplyReaderFilters()

            let after = root.association?.store.state.presentation
            let activeCheckpoint = try SessionStore(database: db).checkpoint()
            let historicalCheckpoint = try SessionStore(database: db).checkpoint(for: original.contextKey)
            let frozenRecords = try records.allSatisfy { try publication.card(id: $0.id) == $0 }
            // Future publication may append; every segment that was already published stays identical.
            let currentSegments = try publication.segments(editionID: before.editionID)
            let frozenSegments = Array(currentSegments.prefix(segments.count)) == segments
            let savedUnchanged = try publication.bookmarkedCardIDs() == Set([saved])
            let prefix = after.map { Array($0.window.items.map(\.id).prefix(before.window.items.count)) }
            let facts: [String: Any] = [
                "step": step, "masterEnabled": stored.contentFiltersEnabled,
                "storedRules": stored.contentFilterRules,
                "sameLogicalUserContext": root.currentContextKey == logicalContext,
                "sameAssociation": root.association === original,
                "sameEdition": after?.editionID == before.editionID,
                "samePresentedIDs": after?.window.items.map(\.id) == before.window.items.map(\.id),
                "samePresentedPrefix": prefix == before.window.items.map(\.id),
                "sameAnchor": after?.window.anchor == before.window.anchor,
                "sameCheckpointIncludingTimestamp": activeCheckpoint == checkpoint,
                "sameActiveCheckpointPosition": samePosition(activeCheckpoint),
                "historicalCheckpointPositionPreserved": samePosition(historicalCheckpoint),
                "frozenCardRecordsPreserved": frozenRecords,
                "frozenSegmentsPreserved": frozenSegments,
                "savedCardsPreserved": savedUnchanged,
                "frozenCardCount": records.count,
                "beforeIDs": before.window.items.map { $0.id.rawValue.uuidString },
                "afterIDs": after?.window.items.map { $0.id.rawValue.uuidString } ?? [],
                "beforeContext": String(describing: original.contextKey),
                "afterContext": String(describing: root.association?.contextKey)
            ]
            let data = try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys])
            let evidence = String(decoding: data, as: UTF8.self)
            let attachment = XCTAttachment(string: evidence)
            attachment.name = "f13-r4-global-word-\(step).json"; attachment.lifetime = .keepAlways
            add(attachment)
            print("F13_R4_GLOBAL_WORD_JSON \(evidence)")
            XCTAssertEqual(root.currentContextKey, logicalContext)
            XCTAssertTrue(frozenSegments, "\(step): frozen segments")
            XCTAssertTrue(frozenRecords, "\(step): every complete CardRecord")
            XCTAssertTrue(savedUnchanged, "\(step): saved card")
            XCTAssertTrue(samePosition(historicalCheckpoint), "\(step): historical context checkpoint")
            func verifyContinuity(_ field: String, assertion: () -> Void) {
                guard step == "add" || step == "master-on" else { assertion(); return }
                let marker = "F13-R4-\(step)-\(field)"
                let options = XCTExpectedFailure.Options()
                options.isStrict = true
                options.issueMatcher = { issue in
                    issue.type == .assertionFailure && issue.compactDescription.contains(marker)
                }
                // Known product failure, not UX13 PASS. Each expectation matches one measured symptom.
                // A fix makes the strict expectation fail until it is removed. Data checks above stay normal.
                // Evidence and required follow-up: docs/reviews/2026-10-28-f13-word-history-r4.md.
                XCTExpectFailure("F13/R4 open: \(marker)", options: options, failingBlock: assertion)
            }
            verifyContinuity("edition") {
                XCTAssertEqual(after?.editionID, before.editionID, "F13-R4-\(step)-edition")
            }
            verifyContinuity("sequence") {
                XCTAssertEqual(prefix, before.window.items.map(\.id), "F13-R4-\(step)-sequence")
            }
            verifyContinuity("anchor") {
                XCTAssertEqual(after?.window.anchor, before.window.anchor, "F13-R4-\(step)-anchor")
            }
            verifyContinuity("position") {
                XCTAssertTrue(samePosition(activeCheckpoint), "F13-R4-\(step)-position")
            }
        }
        await root.association?.close()
    }
}
