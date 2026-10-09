// File: MediaResolver.swift
// Module: FeedMineMedia
// Owns: pure choice of which canonical MediaCandidate is worth preparing for this device (PD-6).
// Does not own: downloading, byte inspection, layout values, editorial ranking or SwiftUI.
//
// v1 lessons (03-media.md): identity is never the URL; declared dimensions are hints, measured
// dimensions decide; never fetch more pixels than the slot shows; a card designed without image
// beats a slow or bad image (PD-5).

import FeedMineDomain

public enum MediaResolution: Hashable, Sendable {
    /// Prepare this candidate. `fallbacks` are the remaining viable candidates in preference order.
    case prepare(MediaCandidate, fallbacks: [MediaCandidate])
    /// No candidate is worth preparing now; publish a designed text-only card or withhold (PD-5).
    case textOnly(MediaTextOnlyReason)
}

public enum MediaTextOnlyReason: Hashable, Sendable {
    case noCandidates
    case conditionsForbidRemoteMedia
    case noViableCandidate
}

public enum MediaResolver {
    public static func resolve(_ candidates: [MediaCandidate], policy: MediaPolicy) -> MediaResolution {
        guard !candidates.isEmpty else { return .textOnly(.noCandidates) }
        guard policy.allowsRemoteMedia else { return .textOnly(.conditionsForbidRemoteMedia) }
        let target = policy.prefersEconomy ? policy.acceptableHeroPixelWidth : policy.idealHeroPixelWidth
        let minimum = policy.acceptableThumbnailPixelWidth

        var sufficient: [(candidate: MediaCandidate, width: Int)] = []
        var unknown: [MediaCandidate] = []
        var undersized: [(candidate: MediaCandidate, width: Int)] = []
        for candidate in candidates where candidate.role == .cardVisual && candidate.mediaClass == .image {
            if let mime = candidate.declaredMimeType?.lowercased(), !mime.hasPrefix("image/") || mime.contains("svg") { continue }
            guard let width = candidate.declaredPixelWidth, let height = candidate.declaredPixelHeight else {
                unknown.append(candidate)
                continue
            }
            // Declared facts beyond the safety ceilings are refused before any bytes move.
            if width > policy.ceilings.maximumPixelSide || height > policy.ceilings.maximumPixelSide { continue }
            if width < minimum { continue }
            if width >= target { sufficient.append((candidate, width)) } else { undersized.append((candidate, width)) }
        }
        // Smallest image that fills the target first (no wasted bytes); feed order breaks ties.
        let ordered = sufficient.enumerated().sorted { a, b in
            a.element.width != b.element.width ? a.element.width < b.element.width : a.offset < b.offset
        }.map(\.element.candidate)
            + unknown
            // Below target but still usable in a slot: largest first.
            + undersized.enumerated().sorted { a, b in
                a.element.width != b.element.width ? a.element.width > b.element.width : a.offset < b.offset
            }.map(\.element.candidate)
        guard let first = ordered.first else { return .textOnly(.noViableCandidate) }
        return .prepare(first, fallbacks: Array(ordered.dropFirst()))
    }
}
