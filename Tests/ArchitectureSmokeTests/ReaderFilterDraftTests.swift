import XCTest
import FeedMineDomain
import FeedMineUI

/// T6: the draft the filter sheet edits is separate from the applied selection, and editing it changes
/// nothing until the coordinator applies it (V1 commits on dismissal, so the draft is the whole state).
@MainActor
final class ReaderFilterDraftTests: XCTestCase {
    private let applied = ReaderFilter(regionIDs: ["br"], taxonomyNodeIDs: ["tech"], languages: ["pt"],
        contentType: .text, mood: .serious,
        exclusions: ReaderContentExclusions(isEnabled: true, rules: ["ads"]))

    func testHydratingDraftIsCleanAndKeepsUntouchedCriteria() {
        let draft = ReaderFilterDraft(applying: applied, preset: .collection("c1"))
        XCTAssertFalse(draft.isDirty, "a freshly hydrated draft changes nothing")
        XCTAssertEqual(draft.applied, applied, "the parts the sheet does not edit survive untouched")
        XCTAssertEqual(draft.preset, .collection("c1"))
    }

    func testEditingMakesTheDraftDirtyAndOnlyThenDoesAppliedChange() {
        var draft = ReaderFilterDraft(applying: applied)
        draft.toggleLanguage("en")
        draft.select(contentType: .audio)
        XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(draft.applied.languages, ["en", "pt"])
        XCTAssertEqual(draft.applied.contentType, .audio)
        // Everything the sheet does not own is still the base's value.
        XCTAssertEqual(draft.applied.regionIDs, ["br"])
        XCTAssertEqual(draft.applied.taxonomyNodeIDs, ["tech"])
        XCTAssertEqual(draft.applied.exclusions.rules, ["ads"])
        // V1's toggle: selecting the same value again clears the criterion.
        draft.select(contentType: .audio)
        XCTAssertEqual(draft.applied.contentType, .all)
        draft.toggleLanguage("en")
        XCTAssertEqual(draft.applied.languages, ["pt"])
    }

    func testRevertAndClearAllAreDistinct() {
        var draft = ReaderFilterDraft(applying: applied, preset: .lastClicked)
        draft.clearAll()
        // V1's "Clear All Filters" clears the criteria this sheet owns (and the region/taxonomy selections
        // it reaches through its links); content exclusions live on their own surface and survive.
        XCTAssertEqual(draft.applied.contentType, .all)
        XCTAssertEqual(draft.applied.mood, .all)
        XCTAssertTrue(draft.applied.languages.isEmpty)
        XCTAssertTrue(draft.applied.regionIDs.isEmpty)
        XCTAssertTrue(draft.applied.taxonomyNodeIDs.isEmpty)
        XCTAssertEqual(draft.applied.exclusions, applied.exclusions,
            "exclusions belong to the content-filter surface, not to this sheet")
        XCTAssertEqual(draft.preset, .everything)
        // With no exclusions applied, clearing everything really is the unrestricted default.
        var plain = ReaderFilterDraft(applying: ReaderFilter(languages: ["pt"], mood: .fun))
        plain.clearAll()
        XCTAssertTrue(plain.applied.isUnrestricted)
        XCTAssertTrue(draft.isDirty)
        draft.revert()
        XCTAssertFalse(draft.isDirty, "revert hydrates again from the applied selection")
        XCTAssertEqual(draft.applied, applied)
        XCTAssertEqual(draft.preset, .lastClicked)
    }

    func testUnavailableCriteriaAreRefusedNotSilentlyApplied() {
        var draft = ReaderFilterDraft(applying: .unrestricted, availableCriteria: [.languages])
        draft.select(contentType: .video)
        draft.select(mood: .fun)
        draft.select(regionIDs: ["us"])
        draft.toggleLanguage("pt")
        XCTAssertEqual(draft.applied.contentType, .all, "an unavailable criterion is never applied")
        XCTAssertEqual(draft.applied.mood, .all)
        XCTAssertTrue(draft.applied.regionIDs.isEmpty)
        XCTAssertEqual(draft.applied.languages, ["pt"], "the criterion the host can enforce is applied")
    }

    func testDraftIsDetectedWhenTheAppliedSelectionMovedBeneathIt() {
        var draft = ReaderFilterDraft(applying: applied)
        draft.toggleLanguage("en")
        XCTAssertFalse(draft.isStale(comparedTo: applied, preset: .everything))
        let moved = ReaderFilter(languages: ["fr"])
        XCTAssertTrue(draft.isStale(comparedTo: moved, preset: .everything),
            "a draft hydrated from another context must not be applied silently")
        XCTAssertTrue(draft.isStale(comparedTo: applied, preset: .lastClicked),
            "a preset change beneath the draft makes it stale too")
    }

    func testPresetAndCriteriaAreIndependent() {
        var draft = ReaderFilterDraft(applying: .unrestricted)
        draft.select(preset: .smartFeed("s1"))
        draft.select(mood: .inspiring)
        XCTAssertEqual(draft.preset, .smartFeed("s1"))
        XCTAssertEqual(draft.applied.mood, .inspiring)
        // V1 committed preset and overlay criteria independently; the draft keeps them that way.
        XCTAssertEqual(draft.applied.languages, [])
        XCTAssertEqual(draft.applied.contentType, .all)
    }
}
