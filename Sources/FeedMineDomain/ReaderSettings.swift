//
// File: ReaderSettings.swift
// Module: FeedMineDomain
//
// Responsibility:
// The reader's own preferences as one value: what the app looks like and how it behaves. V1 kept them in
// `UserDefaults`, one key per setting (`Services/AppSettings.swift`); V2 states them as a versioned envelope so a
// migration can be written once and a key this build does not know can be carried forward instead of destroyed.
//
// The separation the plan demands is structural, not cosmetic: every field here is either **appearance** (what
// the reader sees, which never changes what is being read) or **behaviour** (what the app does). Nothing in it
// can move the reader to another context — a clock is not an identity.
import Foundation

public struct ReaderSettings: Hashable, Codable, Sendable {
    /// Bumped only when the meaning of a field changes; a stored envelope carries the version it was written
    /// with so a future build can decide what to do with it.
    public static let currentSchemaVersion = 1

    // MARK: - Appearance

    /// V1's `circadianPaletteOn`: the palette follows the hour.
    public var followsClock: Bool
    /// V1's `paletteFamily` raw value (`warmEarth`, `coolSky`, …). The UI knows the vocabulary; this value keeps
    /// whatever it was given so an unknown family survives a round trip.
    public var paletteFamily: String
    /// V1's `circadianTypographyOn`: the type scale follows the hour.
    public var followsClockTypography: Bool
    /// V1's `fontStyle` raw value.
    public var fontStyle: String
    /// V1's `fontSize` (the type scale).
    public var typeScale: String
    /// V1's `nightMode`: the reader pinned the night palette.
    public var nightMode: Bool

    // MARK: - Behaviour

    /// V1's `prefetchImages`: warm the images of what is coming.
    public var prefetchesImages: Bool
    /// V1's `contentFiltersEnabled`: whether the reader's content exclusions hide anything at all.
    public var contentFiltersEnabled: Bool
    /// V1's `filterAutoExpire`: the four-hour rule on the overlay selection (T6 owns the record it drives).
    public var filterAutoExpires: Bool

    // MARK: - Onboarding

    /// V1's `hasSeenOnboarding`. T11 reads it; nothing else does.
    public var hasSeenOnboarding: Bool

    // MARK: - Envelope

    public var schemaVersion: Int
    /// The V1 keys this build does not understand, kept verbatim. A migration that dropped them would silently
    /// delete a reader's preference the day a future build learns what it meant.
    public var carriedLegacyKeys: [String: String]

    public init(followsClock: Bool = true, paletteFamily: String = "warmEarth",
        followsClockTypography: Bool = true, fontStyle: String = "system", typeScale: String = "medium",
        nightMode: Bool = false, prefetchesImages: Bool = true, contentFiltersEnabled: Bool = true,
        filterAutoExpires: Bool = true, hasSeenOnboarding: Bool = false,
        schemaVersion: Int = ReaderSettings.currentSchemaVersion, carriedLegacyKeys: [String: String] = [:]) {
        self.followsClock = followsClock
        self.paletteFamily = paletteFamily
        self.followsClockTypography = followsClockTypography
        self.fontStyle = fontStyle
        self.typeScale = typeScale
        self.nightMode = nightMode
        self.prefetchesImages = prefetchesImages
        self.contentFiltersEnabled = contentFiltersEnabled
        self.filterAutoExpires = filterAutoExpires
        self.hasSeenOnboarding = hasSeenOnboarding
        self.schemaVersion = schemaVersion
        self.carriedLegacyKeys = carriedLegacyKeys
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A stored envelope missing a field is a value written by an older build: the field takes its default,
        // never a fabricated one.
        let standard = ReaderSettings.standard
        self.init(
            followsClock: try container.decodeIfPresent(Bool.self, forKey: .followsClock) ?? standard.followsClock,
            paletteFamily: try container.decodeIfPresent(String.self, forKey: .paletteFamily) ?? standard.paletteFamily,
            followsClockTypography: try container.decodeIfPresent(Bool.self, forKey: .followsClockTypography)
                ?? standard.followsClockTypography,
            fontStyle: try container.decodeIfPresent(String.self, forKey: .fontStyle) ?? standard.fontStyle,
            typeScale: try container.decodeIfPresent(String.self, forKey: .typeScale) ?? standard.typeScale,
            nightMode: try container.decodeIfPresent(Bool.self, forKey: .nightMode) ?? standard.nightMode,
            prefetchesImages: try container.decodeIfPresent(Bool.self, forKey: .prefetchesImages)
                ?? standard.prefetchesImages,
            contentFiltersEnabled: try container.decodeIfPresent(Bool.self, forKey: .contentFiltersEnabled)
                ?? standard.contentFiltersEnabled,
            filterAutoExpires: try container.decodeIfPresent(Bool.self, forKey: .filterAutoExpires)
                ?? standard.filterAutoExpires,
            hasSeenOnboarding: try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding)
                ?? standard.hasSeenOnboarding,
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? ReaderSettings.currentSchemaVersion,
            carriedLegacyKeys: try container.decodeIfPresent([String: String].self, forKey: .carriedLegacyKeys) ?? [:])
    }

    /// V1's own defaults (`Services/AppSettings.swift`): circadian palette and typography on, warm earth, the
    /// system font at medium, image prefetch on, content filters on, the four-hour filter rule on, onboarding
    /// unseen.
    public static let standard = ReaderSettings()
}

/// The keys V1 wrote, and which of them this build understands. Kept in one place so the migration and its test
/// cannot disagree about a name.
public enum ReaderSettingsLegacyKey: String, CaseIterable, Sendable {
    case circadianPaletteOn
    case paletteFamily
    case circadianTypographyOn
    case fontStyle
    case fontSize
    case nightMode
    case prefetchImages
    case contentFiltersEnabled
    case filterAutoExpire
    case hasSeenOnboarding

    /// V1 keys that belong to other deliveries or are deliberately not ported. Naming them keeps a migration
    /// honest about what it is leaving alone — each is carried forward like any unknown key.
    public static let notPorted: Set<String> = [
        // T11 owns onboarding's own state beyond the flag.
        "hasInitializedLanguageDefault", "hasInitializedSourceDefaults",
        // DEBUG-only in V1 and deliberately not transferred (T1's matrix records it).
        "showDebugBar",
        // V1's own session telemetry and maintenance bookkeeping; V2 keeps no equivalent and invents none.
        "sessionStreak", "sessionMinutesToday", "daysWithAppTotal", "lastOpenDate",
        "lastWhatsNewSeenAt", "lastHeavyMaintenance",
        // V1's own filter *state*, not a preference: T6 owns it as an identity.
        "filterRegion", "filterTaxonomyNodes", "filterContentType", "filterMood", "filterSetAt",
        "filterLanguages", "activePreset",
        // V1's player position, which V2 states from the player itself.
        "lastPodcastItemID", "lastPodcastPosition",
        // V1's source toggles, which V2 keeps as a selection (T7).
        "toggleDisabled", "toggleEnabledOverrides",
    ]
}

public enum ReaderSettingsMigration {
    /// Carries V1's preferences, as a reader's device holds them, into one settings value. A key this build
    /// knows is read with V1's own default when absent; a key it does not know — including V1's own keys that
    /// another delivery owns — is **carried verbatim**, so nothing a reader set is destroyed by an upgrade.
    ///
    /// Values arrive as strings because V1's store is a property list: the app that has such a plist stringifies
    /// it, and this mapping stays a pure function of names to values.
    public static func fromLegacy(_ legacy: [String: String]) -> ReaderSettings {
        let standard = ReaderSettings.standard
        var settings = ReaderSettings(
            followsClock: bool(legacy[ReaderSettingsLegacyKey.circadianPaletteOn.rawValue]) ?? standard.followsClock,
            paletteFamily: legacy[ReaderSettingsLegacyKey.paletteFamily.rawValue] ?? standard.paletteFamily,
            followsClockTypography: bool(legacy[ReaderSettingsLegacyKey.circadianTypographyOn.rawValue])
                ?? standard.followsClockTypography,
            fontStyle: legacy[ReaderSettingsLegacyKey.fontStyle.rawValue] ?? standard.fontStyle,
            typeScale: legacy[ReaderSettingsLegacyKey.fontSize.rawValue] ?? standard.typeScale,
            nightMode: bool(legacy[ReaderSettingsLegacyKey.nightMode.rawValue]) ?? standard.nightMode,
            prefetchesImages: bool(legacy[ReaderSettingsLegacyKey.prefetchImages.rawValue])
                ?? standard.prefetchesImages,
            contentFiltersEnabled: bool(legacy[ReaderSettingsLegacyKey.contentFiltersEnabled.rawValue])
                ?? standard.contentFiltersEnabled,
            filterAutoExpires: bool(legacy[ReaderSettingsLegacyKey.filterAutoExpire.rawValue])
                ?? standard.filterAutoExpires,
            hasSeenOnboarding: bool(legacy[ReaderSettingsLegacyKey.hasSeenOnboarding.rawValue])
                ?? standard.hasSeenOnboarding)
        let known = Set(ReaderSettingsLegacyKey.allCases.map(\.rawValue))
        settings.carriedLegacyKeys = legacy.filter { !known.contains($0.key) }
        return settings
    }

    /// V1 wrote booleans into a property list, and a missing key meant "the reader never touched it". A string
    /// form is accepted too, because that is what survives a plist round trip through text.
    private static func bool(_ raw: String?) -> Bool? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}
