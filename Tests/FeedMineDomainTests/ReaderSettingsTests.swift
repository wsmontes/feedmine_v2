import XCTest
import FeedMineDomain

/// T10: the reader's preferences as one versioned value, and the migration that must never destroy a key this
/// build does not understand.
final class ReaderSettingsTests: XCTestCase {
    func testDefaultsAreV1sOwn() {
        let standard = ReaderSettings.standard
        XCTAssertTrue(standard.followsClock, "V1 shipped the circadian palette on")
        XCTAssertEqual(standard.paletteFamily, "warmEarth")
        XCTAssertTrue(standard.followsClockTypography)
        XCTAssertEqual(standard.fontStyle, "system")
        XCTAssertEqual(standard.typeScale, "medium")
        XCTAssertFalse(standard.nightMode)
        XCTAssertTrue(standard.prefetchesImages)
        XCTAssertTrue(standard.contentFiltersEnabled)
        XCTAssertTrue(standard.filterAutoExpires, "the four-hour rule is on by default (T6)")
        XCTAssertFalse(standard.hasSeenOnboarding)
        XCTAssertEqual(standard.schemaVersion, ReaderSettings.currentSchemaVersion)
        XCTAssertTrue(standard.carriedLegacyKeys.isEmpty)
    }

    /// V1's own keys, with V1's own meaning; a key the build knows and the reader never touched takes the
    /// default rather than a fabricated value.
    func testLegacyPreferencesAreCarriedByKey() {
        let migrated = ReaderSettingsMigration.fromLegacy([
            "circadianPaletteOn": "false",
            "paletteFamily": "coolSky",
            "nightMode": "1",
            "prefetchImages": "0",
            "filterAutoExpire": "false",
        ])
        XCTAssertFalse(migrated.followsClock)
        XCTAssertEqual(migrated.paletteFamily, "coolSky")
        XCTAssertTrue(migrated.nightMode)
        XCTAssertFalse(migrated.prefetchesImages)
        XCTAssertFalse(migrated.filterAutoExpires)
        // Untouched keys keep V1's defaults.
        XCTAssertTrue(migrated.followsClockTypography)
        XCTAssertEqual(migrated.typeScale, "medium")
        XCTAssertFalse(migrated.hasSeenOnboarding)
        // An empty store is V1's defaults, not an empty value.
        XCTAssertEqual(ReaderSettingsMigration.fromLegacy([:]), .standard)
    }

    /// A key this build does not understand is **carried verbatim** — including V1's own keys that belong to
    /// another delivery — while the keys it did read are not duplicated into the carried bag.
    func testUnknownKeysSurviveTheMigration() {
        let migrated = ReaderSettingsMigration.fromLegacy([
            "paletteFamily": "botanical",
            "someFutureSetting": "42",
            "sessionStreak": "9",
            "activePreset": "smartFeed:7",
        ])
        XCTAssertEqual(migrated.carriedLegacyKeys, ["someFutureSetting": "42", "sessionStreak": "9",
            "activePreset": "smartFeed:7"])
        XCTAssertFalse(migrated.carriedLegacyKeys.keys.contains("paletteFamily"),
            "a key that was read is not also carried")
        for key in ReaderSettingsLegacyKey.notPorted {
            XCTAssertFalse(ReaderSettingsLegacyKey.allCases.map(\.rawValue).contains(key),
                "\(key) belongs to another delivery and must not be read as a setting")
        }
    }

    /// A value that is not a boolean is not a decision: the default stands.
    func testUnreadableLegacyValuesFallBackToDefaults() {
        let migrated = ReaderSettingsMigration.fromLegacy([
            "circadianPaletteOn": "maybe",
            "nightMode": "",
            "filterAutoExpire": "  ",
        ])
        XCTAssertEqual(migrated, ReaderSettings.standard)
    }

    /// An envelope written by an older build is read with the fields it has, and the defaults it did not write.
    func testAPartialStoredEnvelopeTakesDefaultsForMissingFields() throws {
        let json = Data(#"{"schemaVersion":1,"paletteFamily":"lavenderHour","nightMode":true}"#.utf8)
        let decoded = try JSONDecoder().decode(ReaderSettings.self, from: json)
        XCTAssertEqual(decoded.paletteFamily, "lavenderHour")
        XCTAssertTrue(decoded.nightMode)
        XCTAssertTrue(decoded.followsClock, "a field the older build did not write keeps V1's default")
        XCTAssertEqual(decoded.typeScale, "medium")
        XCTAssertTrue(decoded.carriedLegacyKeys.isEmpty)
    }

    func testRoundingTheValueThroughJSONKeepsItWhole() throws {
        var settings = ReaderSettings.standard
        settings.paletteFamily = "monochrome"
        settings.typeScale = "large"
        settings.carriedLegacyKeys = ["future": "x"]
        let decoded = try JSONDecoder().decode(ReaderSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
}
