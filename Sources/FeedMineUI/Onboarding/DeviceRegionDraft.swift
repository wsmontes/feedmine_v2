//
// File: DeviceRegionDraft.swift
// Module: FeedMineUI
//
// Responsibility:
// The place the device already states, as a draft the first run may pre-tick — never as an answer.
//
// Does not own:
// Persisting the answer (the host writes the recipe only when the reader confirms), the catalogue's place list
// (the host reads it) or a place's display name (the catalogue's own, localized where it is drawn).
//

import Foundation
import FeedMineRuntime

/// What the device says about where the reader is, before the reader has answered.
///
/// The first run pre-ticks the answers the device already states — the language it reads in, and its region —
/// and nothing is saved until the reader confirms. A region is derived only when the device states one the
/// composer can name: a device that names no region, a region the offered places do not carry, and a device whose
/// region disagrees with its language's region are all left unanswered, because pre-ticking then would put a
/// guess into a draft the reader might confirm without noticing.
public enum DeviceRegionDraft {
    /// The offered place the device's region names, or nil when the composer must leave the place unanswered.
    ///
    /// - Parameters:
    ///   - deviceRegion: the device's own region (`Locale.current.region?.identifier`).
    ///   - preferredLanguage: the reader's language choice (`Locale.preferredLanguages.first`), whose region is
    ///     the language's region (`pt-BR` → `BR`). A language that names no region does not conflict.
    ///   - places: the places the composer offers, keyed by the catalogue's own country node key.
    public static func region(deviceRegion: String?, preferredLanguage: String?,
        among places: [OnboardingRegion]) -> OnboardingRegion? {
        guard let device = normalized(deviceRegion) else { return nil }
        // A device whose region and language region disagree holds a mixed answer (a Portuguese reader whose
        // device region is the United States). Neither side is the reader's choice, so neither is pre-ticked.
        if let languageRegion = regionCode(ofLanguage: preferredLanguage),
            languageRegion.uppercased() != device { return nil }
        return places.first { place in
            CatalogRegionNaming.regionCode(forCatalogueKey: place.key)?.uppercased() == device
        }
    }

    /// The region subtag of a language identifier (`pt-BR` → `BR`); nil when the language names no region.
    static func regionCode(ofLanguage identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return Locale(identifier: identifier).region?.identifier
    }

    private static func normalized(_ code: String?) -> String? {
        guard let code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }
}
