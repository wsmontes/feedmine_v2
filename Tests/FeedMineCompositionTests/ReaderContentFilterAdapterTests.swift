import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineComposition
import FeedMineUI

final class ReaderContentFilterAdapterTests: XCTestCase {
    actor Notifications {
        var count = 0
        func note() { count += 1 }
    }

    func testSourceEditsPreserveOtherSettingsAndNotifyBeforeReturning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: .init(directory: root))
        let preferences = ReaderPreferencesStore(database: db)
        _ = try preferences.initialize(sourceKeys: ["selected-source"])
        var settings = try ReaderSettingsCoordinator(database: db).settings()
        settings.contentFilterRules = ["word"]
        settings.contentFilterTemplates = ["politics"]
        try ReaderSettingsCoordinator(database: db).update(settings)
        let before = try preferences.load()
        let notifications = Notifications()
        let adapter = ReaderContentFilterAdapter(database: db, templates: [],
            onSourceExclusionsChanged: { await notifications.note() })
        let rule = ReaderSourceExclusion(sourceID: SourceID(), displayName: "Removed catalogue source")
        try await adapter.setSourceExclusions([rule])
        let added = try await adapter.state()
        XCTAssertEqual(added.sourceExclusions, [rule])
        XCTAssertEqual(added.rules, ["word"])
        XCTAssertEqual(added.enabledTemplates, ["politics"])
        let addedCount = await notifications.count
        XCTAssertEqual(addedCount, 1)
        let after = try preferences.load()
        XCTAssertEqual(after?.sourceKeys, before?.sourceKeys)
        XCTAssertEqual(after?.selectionVersion, before?.selectionVersion)
        XCTAssertEqual(after?.activeContextKey, before?.activeContextKey)
        try await adapter.setEnabled(false)
        let disabled = try await adapter.state()
        XCTAssertEqual(disabled.sourceExclusions, [rule])
        XCTAssertFalse(disabled.isEnabled)
        let disabledCount = await notifications.count
        XCTAssertEqual(disabledCount, 2)
        try await adapter.setSourceExclusions([])
        let removed = try await adapter.state()
        XCTAssertEqual(removed.sourceExclusions, [])
        XCTAssertEqual(removed.rules, ["word"])
        XCTAssertEqual(removed.enabledTemplates, ["politics"])
        let finalCount = await notifications.count
        XCTAssertEqual(finalCount, 2, "removing a masked rule does not change the effective policy")
    }
}

private actor SourceRuleBackend: ReaderContentFilterBackend {
    var sources: [ReaderSourceExclusion] = []
    var fails = false
    func failWrites() { fails = true }
    func state() async throws -> ReaderContentFilterState {
        .init(isEnabled: true, rules: ["word"], enabledTemplates: ["politics"], templates: [],
            sourceExclusions: sources)
    }
    func setEnabled(_ enabled: Bool) async throws {}
    func setRules(_ words: [String]) async throws {}
    func setTemplates(_ keys: [String]) async throws {}
    func setSourceExclusions(_ rules: [ReaderSourceExclusion]) async throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        sources = rules
    }
}

extension ReaderContentFilterAdapterTests {
    @MainActor
    func testStoreRestoresDurableSourceRulesOnFailedWrite() async {
        let backend = SourceRuleBackend()
        let store = ReaderContentFilterStore(backend: backend)
        await store.load()
        let a = ReaderSourceExclusion(sourceID: SourceID(), displayName: "Same label")
        let b = ReaderSourceExclusion(sourceID: SourceID(), displayName: "Same label")
        let addedA = await store.addSourceExclusion(a)
        let addedB = await store.addSourceExclusion(b)
        XCTAssertTrue(addedA)
        XCTAssertTrue(addedB)
        XCTAssertEqual(Set(store.sourceExclusions.map(\.sourceID)), [a.sourceID, b.sourceID])
        await backend.failWrites()
        let removed = await store.removeSourceExclusion(a.sourceID)
        XCTAssertFalse(removed)
        XCTAssertEqual(Set(store.sourceExclusions.map(\.sourceID)), [a.sourceID, b.sourceID])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.rules, ["word"])
        XCTAssertEqual(store.enabledTemplates, ["politics"])
    }
}

extension ReaderContentFilterAdapterTests {
    func testGeneralSettingsMasterSwitchAwaitsEffectiveSourcePolicyNotification() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: .init(directory: root))
        _ = try ReaderPreferencesStore(database: db).initialize(sourceKeys: ["source"])
        let coordinator = ReaderSettingsCoordinator(database: db)
        var settings = try coordinator.settings()
        let rule = ReaderSourceExclusion(sourceID: SourceID(), displayName: "Source")
        settings.contentSourceExclusions = [rule]
        try coordinator.update(settings)
        let notifications = Notifications()
        let adapter = ReaderSettingsBackendAdapter(database: db,
            onSourceExclusionsChanged: { await notifications.note() }, onWrite: {})
        settings.contentFiltersEnabled = false
        try await adapter.update(settings)
        let offCount = await notifications.count
        XCTAssertEqual(offCount, 1)
        XCTAssertEqual(try coordinator.settings().contentSourceExclusions, [rule])
        settings.nightMode.toggle()
        try await adapter.update(settings)
        let appearanceCount = await notifications.count
        XCTAssertEqual(appearanceCount, 1)
        settings.contentFiltersEnabled = true
        try await adapter.update(settings)
        let onCount = await notifications.count
        XCTAssertEqual(onCount, 2)
    }
}

extension ReaderContentFilterAdapterTests {
    @MainActor
    func testGeneralSettingsEditDoesNotOverwriteRulesChangedInTheChildEditor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: .init(directory: root))
        _ = try ReaderPreferencesStore(database: db).initialize(sourceKeys: ["source"])
        let general = ReaderSettingsStore(backend: ReaderSettingsBackendAdapter(database: db, onWrite: {}))
        await general.load()
        let filters = ReaderContentFilterAdapter(database: db, templates: [])
        let rule = ReaderSourceExclusion(sourceID: SourceID(), displayName: "Source")
        try await filters.setSourceExclusions([rule])
        try await filters.setRules(["word"])
        try await filters.setTemplates(["politics"])
        await general.update { $0.contentFiltersEnabled = false }
        let stored = try ReaderSettingsCoordinator(database: db).settings()
        XCTAssertFalse(stored.contentFiltersEnabled)
        XCTAssertEqual(stored.contentSourceExclusions, [rule])
        XCTAssertEqual(stored.contentFilterRules, ["word"])
        XCTAssertEqual(stored.contentFilterTemplates, ["politics"])
        XCTAssertNil(general.errorMessage)
        XCTAssertEqual(general.settings, stored)
    }
}
