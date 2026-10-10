//
// File: ReaderSettingsStore.swift
// Module: FeedMineUI
//
// Responsibility:
// The reader's preferences as observable values plus one intent: change them. The backend (Composition) owns
// where they live; the store never guesses what was stored — it shows what the backend accepted.
//
// Does not own: persistence (Persistence), the appearance the app draws with (the app derives it) or layout.
import Foundation
import Observation
import FeedMineDomain

public protocol ReaderSettingsBackend: Sendable {
    func settings() async throws -> ReaderSettings
    func update(_ settings: ReaderSettings) async throws
}

@MainActor
@Observable
public final class ReaderSettingsStore {
    public private(set) var settings: ReaderSettings = .standard
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let backend: ReaderSettingsBackend

    public init(backend: ReaderSettingsBackend) { self.backend = backend }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do { settings = try await backend.settings(); errorMessage = nil }
        catch { errorMessage = String(localized: "Não foi possível ler as preferências.") }
    }

    /// One change, written and read back. A refused write restores what the backend actually has, so the
    /// screen never keeps a value the database did not take.
    public func update(_ change: (inout ReaderSettings) -> Void) async {
        var next = settings
        change(&next)
        guard next != settings else { return }
        do {
            try await backend.update(next)
            settings = try await backend.settings()
            errorMessage = nil
        } catch {
            // What the backend actually has, and what happened to the write — V1's own lesson: a refused write
            // that reloads the truth must still be visible.
            let message = String(localized: "Não foi possível salvar as preferências.")
            await load()
            errorMessage = message
        }
    }
}
