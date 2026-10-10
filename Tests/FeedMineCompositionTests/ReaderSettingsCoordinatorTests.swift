import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineUI

/// T10: the reader's preferences, and the appearance they imply. The rule under test is the plan's own: the
/// clock may change how the app *looks*, and never which feed the reader is on.
@MainActor
final class ReaderSettingsCoordinatorTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    /// The hour is built in the same calendar the coordinator is asked to read, so the test states an hour
    /// instead of a time zone.
    private func date(hour: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 10
        components.hour = hour; components.minute = 0
        return calendar.date(from: components) ?? Date()
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// A fresh library reads V1's defaults, and one write survives a reopened store.
    func testPreferencesRoundTripThroughStorage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
            _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a/feed"])
            let coordinator = ReaderSettingsCoordinator(database: database)
            XCTAssertEqual(try coordinator.settings(), .standard)
            var next = try coordinator.settings()
            next.paletteFamily = "lavenderHour"
            next.typeScale = "large"
            next.prefetchesImages = false
            next.filterAutoExpires = false
            XCTAssertEqual(try coordinator.update(next), next)
        }
        let reopened = ReaderSettingsCoordinator(database: try RuntimeDatabase(
            location: RuntimeDatabaseLocation(directory: root)))
        let stored = try reopened.settings()
        XCTAssertEqual(stored.paletteFamily, "lavenderHour")
        XCTAssertEqual(stored.typeScale, "large")
        XCTAssertFalse(stored.prefetchesImages)
        XCTAssertFalse(stored.filterAutoExpires)
        // The four-hour rule is one fact with one home: the value and the record T6 drives agree.
        let record = try XCTUnwrap(try ReaderPreferencesStore(database: try RuntimeDatabase(
            location: RuntimeDatabaseLocation(directory: root))).load())
        XCTAssertFalse(record.filterExpiry.isEnabled)
        XCTAssertFalse(record.settings.filterAutoExpires)
    }

    /// The clock decides the period when the reader asked it to, and the three appearance vocabularies come from
    /// the stored values.
    func testTheClockMovesThePaletteAndNothingElse() throws {
        let database = try database()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a/feed"])
        let coordinator = ReaderSettingsCoordinator(database: database)
        var settings = try coordinator.settings()
        settings.paletteFamily = "coolSky"
        settings.fontStyle = "georgia"
        settings.typeScale = "small"
        settings.followsClock = true
        _ = try coordinator.update(settings)
        XCTAssertEqual(coordinator.appearance(at: date(hour: 6, calendar: utc), calendar: utc).period, .dawn)
        XCTAssertEqual(coordinator.appearance(at: date(hour: 9, calendar: utc), calendar: utc).period, .morning)
        XCTAssertEqual(coordinator.appearance(at: date(hour: 14, calendar: utc), calendar: utc).period, .afternoon)
        XCTAssertEqual(coordinator.appearance(at: date(hour: 19, calendar: utc), calendar: utc).period, .evening)
        XCTAssertEqual(coordinator.appearance(at: date(hour: 23, calendar: utc), calendar: utc).period, .night)
        let appearance = coordinator.appearance(at: date(hour: 14, calendar: utc), calendar: utc)
        XCTAssertEqual(appearance.paletteFamily, .coolSky)
        XCTAssertEqual(appearance.fontStyle, .georgia)
        XCTAssertEqual(appearance.typeScale, .small)
        // Nothing about the reader's identity moved: preferences are not a context.
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.sourceKeys, ["https://a/feed"])
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.activeContextKey,
            ContextKey(request: .main))
    }

    /// Two rules override the clock: the reader turning it off, and V1's night mode pinning the night palette.
    func testTurningTheClockOffAndNightModeOverride() throws {
        let database = try database()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a/feed"])
        let coordinator = ReaderSettingsCoordinator(database: database)
        var settings = try coordinator.settings()
        settings.followsClock = false
        _ = try coordinator.update(settings)
        XCTAssertEqual(coordinator.appearance(at: date(hour: 23, calendar: utc), calendar: utc).period, .morning,
            "with the clock off the palette does not follow the hour")
        settings.nightMode = true
        _ = try coordinator.update(settings)
        XCTAssertEqual(coordinator.appearance(at: date(hour: 9, calendar: utc), calendar: utc).period, .night,
            "night mode pins the night palette, as V1's own override did")
    }

    /// A palette family or font style this build does not know falls back to V1's default instead of inventing
    /// one — which is also what keeps a value written by a future build from breaking this one.
    func testUnknownAppearanceValuesFallBackToTheDefaults() throws {
        let database = try database()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a/feed"])
        let coordinator = ReaderSettingsCoordinator(database: database)
        var settings = try coordinator.settings()
        settings.paletteFamily = "ultraviolet"
        settings.fontStyle = "comic"
        settings.typeScale = "enormous"
        _ = try coordinator.update(settings)
        let appearance = coordinator.appearance(at: date(hour: 10, calendar: utc), calendar: utc)
        XCTAssertEqual(appearance.paletteFamily, .warmEarth)
        XCTAssertEqual(appearance.fontStyle, .system)
        XCTAssertEqual(appearance.typeScale, .medium)
        XCTAssertEqual(try coordinator.settings().paletteFamily, "ultraviolet",
            "the stored value is kept verbatim; only the drawing falls back")
    }

    /// The store the surface uses shows what the backend accepted, and a refused write reloads the truth.
    func testTheSurfaceStoreShowsWhatWasAccepted() async throws {
        final class Backend: ReaderSettingsBackend, @unchecked Sendable {
            var stored: ReaderSettings = .standard
            var refuses = false
            private(set) var writes = 0
            func settings() async throws -> ReaderSettings { stored }
            func update(_ settings: ReaderSettings) async throws {
                if refuses { throw SourceManagementErrorDouble.invalid }
                writes += 1
                stored = settings
            }
        }
        enum SourceManagementErrorDouble: Error { case invalid }
        let backend = Backend()
        let store = ReaderSettingsStore(backend: backend)
        await store.load()
        XCTAssertEqual(store.settings, .standard)
        await store.update { $0.nightMode = true }
        XCTAssertTrue(store.settings.nightMode)
        XCTAssertEqual(backend.writes, 1)
        // A change that changes nothing is not a write.
        await store.update { $0.nightMode = true }
        XCTAssertEqual(backend.writes, 1)
        // A refusal is stated, and the screen goes back to what the backend has.
        backend.refuses = true
        await store.update { $0.paletteFamily = "coolSky" }
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.settings.paletteFamily, "warmEarth")
    }
}
