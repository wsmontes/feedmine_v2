// File: ReaderFilterDraft.swift
// Module: FeedMineUI
// Owns: the selection the reader is editing, kept apart from the applied selection.
// Does not own: applying it. The coordinator persists and activates a context; a draft change alone must
// never touch the feed (T6: editing a draft does not move the reader's list).
//
// V1 behaviour being transferred: `Views/FilterSheetView.swift` hydrates a local draft on appear and commits
// the dirty parts when the sheet goes away — there is no Cancel. This value is that draft.

import Foundation
import FeedMineDomain

public struct ReaderFilterDraft: Hashable, Sendable {
    /// The applied selection this draft was hydrated from. Comparing it with the currently applied values
    /// is what detects a stale draft (the reader's context changed while the sheet was open).
    public let base: ReaderFilter
    public let basePreset: ReaderPresetID

    public private(set) var languages: Set<String>
    public private(set) var contentType: ReaderContentType
    public private(set) var mood: ReaderMood
    public private(set) var preset: ReaderPresetID

    /// Criteria the host can actually enforce. A criterion the supply cannot answer is shown as
    /// unavailable, never accepted and silently ignored (T6, Codex review 2026-10-09).
    public let availableCriteria: Set<ReaderFilterCriterion>
    /// Exclusions stay where the content-filter surface owns them (no expiry, T6).
    public let exclusions: ReaderContentExclusions
    /// Region and taxonomy selections come from their own surfaces and are carried through untouched.
    public private(set) var regionIDs: Set<String>
    public private(set) var taxonomyNodeIDs: Set<String>

    public init(applying filter: ReaderFilter, preset: ReaderPresetID = .everything,
        availableCriteria: Set<ReaderFilterCriterion> = Set(ReaderFilterCriterion.allCases)) {
        base = filter
        basePreset = preset
        languages = filter.languages
        contentType = filter.contentType
        mood = filter.mood
        exclusions = filter.exclusions
        regionIDs = filter.regionIDs
        taxonomyNodeIDs = filter.taxonomyNodeIDs
        self.preset = preset
        self.availableCriteria = availableCriteria
    }

    /// True when closing the sheet would change something — V1 committed only the dirty parts.
    public var isDirty: Bool { applied != base || preset != basePreset }

    /// True when the applied selection moved while this draft was being edited: the draft is then about a
    /// context that is no longer current and must not be applied silently.
    public func isStale(comparedTo applied: ReaderFilter, preset appliedPreset: ReaderPresetID) -> Bool {
        base != applied || basePreset != appliedPreset
    }

    /// The filter this draft would apply. Parts the draft does not edit keep the base's values.
    public var applied: ReaderFilter {
        ReaderFilter(regionIDs: regionIDs, taxonomyNodeIDs: taxonomyNodeIDs, languages: languages,
            contentType: availableCriteria.contains(.contentType) ? contentType : base.contentType,
            mood: availableCriteria.contains(.mood) ? mood : base.mood,
            exclusions: exclusions)
    }

    // MARK: - Editing (the controls V1's sheet offers)

    /// V1 toggled a language on and off, and reset the set when every language was deselected.
    public mutating func toggleLanguage(_ code: String) {
        guard availableCriteria.contains(.languages) else { return }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if languages.contains(normalized) { languages.remove(normalized) } else { languages.insert(normalized) }
    }

    /// V1's content-type button: selecting the current one clears the criterion.
    public mutating func select(contentType type: ReaderContentType) {
        guard availableCriteria.contains(.contentType) else { return }
        contentType = contentType == type ? .all : type
    }

    /// V1's mood button behaves the same way.
    public mutating func select(mood value: ReaderMood) {
        guard availableCriteria.contains(.mood) else { return }
        mood = mood == value ? .all : value
    }

    public mutating func select(preset value: ReaderPresetID) { preset = value }

    /// V1's preset and criterion selections are separate: a preset change never rewrites the criteria.
    public mutating func select(regionIDs values: Set<String>) {
        guard availableCriteria.contains(.region) else { return }
        regionIDs = values
    }

    public mutating func select(taxonomyNodeIDs values: Set<String>) {
        guard availableCriteria.contains(.taxonomy) else { return }
        taxonomyNodeIDs = values
    }

    /// "Clear All Filters" without leaving the sheet: everything returns to the unrestricted default.
    public mutating func clearAll() {
        languages = []
        contentType = .all
        mood = .all
        regionIDs = []
        taxonomyNodeIDs = []
        preset = .everything
    }

    /// Discard the edits: the draft is hydrated again from the applied selection.
    public mutating func revert() {
        languages = base.languages
        contentType = base.contentType
        mood = base.mood
        regionIDs = base.regionIDs
        taxonomyNodeIDs = base.taxonomyNodeIDs
        preset = basePreset
    }
}

/// One criterion of the filter sheet. The host states which of them it can enforce.
public enum ReaderFilterCriterion: String, CaseIterable, Hashable, Sendable {
    case preset
    case region
    case taxonomy
    case contentType
    case languages
    case mood
}
