// File: ReaderFilterStore.swift
// Module: FeedMineUI
// Owns: the applied filter selection, the draft the sheet edits, and the one moment a draft becomes applied.
// Does not own: persisting the selection or switching the context — the host does that through `onApply`, and
// a draft change alone never touches the feed (T6).
//
// V1 behaviour: the sheet has no Cancel. It hydrates a draft on appear and commits the dirty parts when it goes
// away, so `dismiss()` is the ordinary way a selection is applied (`Views/FilterSheetView.swift:220-297`).

import Foundation
import Observation
import FeedMineDomain

public enum ReaderFilterStoreError: Error, Equatable, Sendable {
    /// The applied selection moved while this draft was open: applying it would silently overwrite a context
    /// the reader is no longer editing.
    case staleDraft
}

@MainActor
@Observable
public final class ReaderFilterStore {
    /// The selection the reader is on.
    public private(set) var applied: ReaderFilter
    public private(set) var appliedPreset: ReaderPresetID
    /// The selection the sheet is editing.
    public private(set) var draft: ReaderFilterDraft
    /// True while the host is applying a draft, so the controls can be inert without owning a timer.
    public private(set) var isApplying = false

    @ObservationIgnored
    private let onApply: @MainActor (ReaderFilter, ReaderPresetID) async throws -> Void

    public init(applying filter: ReaderFilter = .unrestricted, preset: ReaderPresetID = .everything,
        availableCriteria: Set<ReaderFilterCriterion> = Set(ReaderFilterCriterion.allCases),
        onApply: @escaping @MainActor (ReaderFilter, ReaderPresetID) async throws -> Void = { _, _ in }) {
        applied = filter
        appliedPreset = preset
        draft = ReaderFilterDraft(applying: filter, preset: preset, availableCriteria: availableCriteria)
        self.onApply = onApply
    }

    /// Re-hydrates from a selection that changed elsewhere (another surface, another device's sync, a
    /// context switch). A clean draft follows it; a dirty draft is left alone so the reader's edits are not
    /// thrown away silently — `isStale` is what the sheet shows.
    public func hydrate(applying filter: ReaderFilter, preset: ReaderPresetID) {
        applied = filter
        appliedPreset = preset
        if !draft.isDirty { draft = ReaderFilterDraft(applying: filter, preset: preset) }
    }

    public var isDirty: Bool { draft.isDirty }
    public var isStale: Bool { draft.isStale(comparedTo: applied, preset: appliedPreset) }

    // MARK: - Editing (forwarding to the draft, so the sheet owns no state of its own)

    public func toggleLanguage(_ code: String) { draft.toggleLanguage(code) }
    public func select(contentType: ReaderContentType) { draft.select(contentType: contentType) }
    public func select(mood: ReaderMood) { draft.select(mood: mood) }
    public func select(preset: ReaderPresetID) { draft.select(preset: preset) }
    public func select(regionIDs: Set<String>) { draft.select(regionIDs: regionIDs) }
    public func select(taxonomyNodeIDs: Set<String>) { draft.select(taxonomyNodeIDs: taxonomyNodeIDs) }
    public func clearAll() { draft.clearAll() }

    /// Discards the edits and hydrates again from the *currently applied* selection, which is also what clears
    /// a stale draft (the draft's own baseline may be older than the applied one).
    public func revert() {
        draft = ReaderFilterDraft(applying: applied, preset: appliedPreset,
            availableCriteria: draft.availableCriteria)
    }

    // MARK: - Applying

    /// Applies the draft. A clean draft applies nothing (V1 committed only the dirty parts); a stale draft is
    /// refused instead of overwriting the current context; a host failure leaves the draft exactly as it was,
    /// so the reader can retry.
    @discardableResult
    public func apply() async throws -> Bool {
        guard draft.isDirty else { return false }
        guard !isStale else { throw ReaderFilterStoreError.staleDraft }
        let filter = draft.applied
        let preset = draft.preset
        isApplying = true
        defer { isApplying = false }
        try await onApply(filter, preset)
        applied = filter
        appliedPreset = preset
        draft = ReaderFilterDraft(applying: filter, preset: preset, availableCriteria: draft.availableCriteria)
        return true
    }

    /// The sheet going away: exactly V1's `onDisappear`.
    @discardableResult
    public func dismiss() async throws -> Bool {
        try await apply()
    }
}
