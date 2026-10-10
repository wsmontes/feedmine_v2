import XCTest
import FeedMineDomain
import FeedMineRuntime
import FeedMineUI

/// T6: one moment turns a draft into the applied selection, and V1's dismissal is that moment.
@MainActor
final class ReaderFilterStoreTests: XCTestCase {
    private func store(applying filter: ReaderFilter = .unrestricted, preset: ReaderPresetID = .everything,
        onApply: @escaping @MainActor (ReaderFilter, ReaderPresetID) async throws -> Void = { _, _ in })
        -> ReaderFilterStore {
        ReaderFilterStore(applying: filter, preset: preset, onApply: onApply)
    }

    /// A clean draft applies nothing: V1 committed only the parts the reader had touched.
    func testCleanDraftAppliesNothing() async throws {
        var calls = 0
        let subject = store(onApply: { _, _ in calls += 1 })
        XCTAssertFalse(subject.isDirty)
        let didApply = try await subject.dismiss()
        XCTAssertEqual(didApply, false)
        XCTAssertEqual(calls, 0)
    }

    /// Editing, then dismissing the sheet, is what applies — and the draft becomes clean again.
    func testDismissAppliesTheDirtyPartsExactlyOnce() async throws {
        var appliedCalls: [(ReaderFilter, ReaderPresetID)] = []
        let subject = store(onApply: { appliedCalls.append(($0, $1)) })
        subject.toggleLanguage("pt")
        subject.select(mood: .technical)
        XCTAssertTrue(subject.isDirty)
        let didApply = try await subject.dismiss()
        XCTAssertEqual(didApply, true)
        XCTAssertEqual(appliedCalls.count, 1)
        XCTAssertEqual(appliedCalls.first?.0.languages, ["pt"])
        XCTAssertEqual(appliedCalls.first?.0.mood, .technical)
        XCTAssertEqual(appliedCalls.first?.1, .everything)
        XCTAssertFalse(subject.isDirty, "the applied selection is now the draft's baseline")
        XCTAssertEqual(subject.applied, appliedCalls.first?.0)
        // Dismissing again changes nothing.
        let again = try await subject.dismiss()
        XCTAssertEqual(again, false)
        XCTAssertEqual(appliedCalls.count, 1)
    }

    /// A draft whose applied selection moved beneath it is refused instead of silently overwriting the
    /// context the reader is actually on.
    func testStaleDraftIsRefused() async throws {
        var calls = 0
        let subject = store(onApply: { _, _ in calls += 1 })
        subject.toggleLanguage("pt")
        subject.hydrate(applying: ReaderFilter(languages: ["fr"]), preset: .lastClicked)
        XCTAssertTrue(subject.isStale)
        do {
            _ = try await subject.dismiss()
            XCTFail("Expected the stale draft to be refused")
        } catch {
            XCTAssertEqual(error as? ReaderFilterStoreError, .staleDraft)
        }
        XCTAssertEqual(calls, 0)
        // Reverting to the new baseline clears the staleness and the edits.
        subject.revert()
        XCTAssertFalse(subject.isStale)
        XCTAssertFalse(subject.isDirty)
    }

    /// A host failure leaves the draft exactly as it was, so the reader can retry; nothing is half-applied.
    func testHostFailureLeavesTheDraftIntact() async throws {
        struct Failure: Error {}
        let subject = store(onApply: { _, _ in throw Failure() })
        subject.toggleLanguage("pt")
        do {
            _ = try await subject.apply()
            XCTFail("Expected the host failure to propagate")
        } catch {
            XCTAssertTrue(error is Failure)
        }
        XCTAssertTrue(subject.isDirty, "the edits survive a failed apply")
        XCTAssertFalse(subject.isApplying)
        XCTAssertTrue(subject.applied.isUnrestricted, "the applied selection never moved")
    }

    /// T7/T6 boundary: the topic browser selects *filter criteria* (V1's `toggleNode`), keyed by the catalog
    /// key, and the rows the browser draws are values independent of any store.
    func testTaxonomyRowsAreValuesAndSelectionIsFilterState() async throws {
        let subject = store()
        let tech = CatalogNodeSummary(id: 42, key: "technology", name: "Technology", kind: .topic,
            sourceCount: 900, hasChildren: true)
        let music = CatalogNodeSummary(id: 43, key: "music", name: "Music", kind: .topic,
            sourceCount: 300, hasChildren: false)
        let rows = TaxonomyBrowseView.rows(nodes: [tech, music], selected: ["technology"],
            breadcrumbs: [42: ["Arts & Culture", "Technology"]])
        XCTAssertEqual(rows.map(\.name), ["Technology", "Music"])
        XCTAssertEqual(rows.map(\.feedCount), [900, 300])
        XCTAssertEqual(rows.map(\.isSelected), [true, false])
        XCTAssertTrue(rows[0].hasChildren)
        XCTAssertEqual(rows[0].breadcrumb, "Arts & Culture › Technology")
        XCTAssertEqual(rows[0].key, "technology", "the draft stores catalog keys, not renumberable ids")
        // The draft's selection is what the browser shows and what a context identity later carries.
        subject.select(taxonomyNodeIDs: ["technology", "music"])
        XCTAssertEqual(subject.draft.taxonomyNodeIDs, ["technology", "music"])
        XCTAssertTrue(subject.isDirty)
        XCTAssertNotEqual(subject.draft.applied.identityText, ReaderFilter().identityText,
            "a selected topic is part of the filter's identity")
    }

    /// A criterion this build cannot enforce is refused by the draft inside the store too, and hydrating a
    /// clean draft follows a selection that changed elsewhere.
    func testUnavailableCriteriaAreRefusedAndHydrationFollows() async throws {
        let subject = ReaderFilterStore(applying: .unrestricted, availableCriteria: [.languages],
            onApply: { _, _ in })
        subject.select(mood: .fun)
        XCTAssertEqual(subject.draft.applied.mood, .all, "the criterion the host cannot enforce is refused")
        subject.toggleLanguage("pt")
        subject.hydrate(applying: ReaderFilter(mood: .serious), preset: .lastClicked)
        XCTAssertTrue(subject.isDirty, "a dirty draft is not thrown away by a hydration")
        XCTAssertTrue(subject.isStale)
        subject.revert()
        XCTAssertEqual(subject.draft.applied.mood, .serious)
        XCTAssertEqual(subject.draft.preset, .lastClicked)
    }
}
