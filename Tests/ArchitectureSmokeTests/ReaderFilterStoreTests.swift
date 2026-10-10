import XCTest
import FeedMineDomain
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
