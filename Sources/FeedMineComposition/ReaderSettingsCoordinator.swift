//
// File: ReaderSettingsCoordinator.swift
// Module: FeedMineComposition
//
// Responsibility:
// The reader's preferences as Composition sees them: read them, write them, and state the **appearance** they
// imply for a given hour. The appearance is derived, never stored, and it never touches a context identity: a
// clock moving the palette must not move the reader to another feed (the plan's own rule).
//
// Does not own: storage (Persistence), the surfaces (UI values) or the clock (the caller states the hour).
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime
import FeedMineUI

public struct ReaderSettingsCoordinator: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    public func settings() throws -> ReaderSettings {
        try ReaderPreferencesStore(database: database).load()?.settings ?? .standard
    }

    /// The plan's own interface: one value in, the same value out once it is stored.
    @discardableResult
    public func update(_ settings: ReaderSettings) throws -> ReaderSettings {
        try ReaderPreferencesStore(database: database).setSettings(settings).settings
    }

    /// The appearance the reader's preferences imply at this hour. An unknown palette family or font style falls
    /// back to V1's default rather than inventing one; the two clock rules decide whether the hour is read at
    /// all, and `nightMode` pins the night palette, as V1's own override did.
    public func appearance(at date: Date = Date(), calendar: Calendar = .current) -> ReaderAppearance {
        let settings = (try? settings()) ?? .standard
        let hour = calendar.component(.hour, from: date)
        let clockPeriod = ReaderPeriod.from(hour: hour)
        let period = settings.nightMode ? .night : (settings.followsClock ? clockPeriod : .morning)
        return ReaderAppearance(
            period: period,
            paletteFamily: ReaderPaletteFamily(rawValue: settings.paletteFamily) ?? .warmEarth,
            fontStyle: ReaderFontStyle(rawValue: settings.fontStyle) ?? .system,
            typeScale: ReaderTypeScale(rawValue: settings.typeScale) ?? .medium)
    }
}

/// The settings surface's backend, over the same store.
public struct ReaderSettingsBackendAdapter: ReaderSettingsBackend {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    public func settings() async throws -> ReaderSettings {
        try ReaderSettingsCoordinator(database: database).settings()
    }

    public func update(_ settings: ReaderSettings) async throws {
        _ = try ReaderSettingsCoordinator(database: database).update(settings)
    }
}
