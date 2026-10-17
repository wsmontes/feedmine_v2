// File: AcquisitionTargetOrdering.swift
// Module: FeedMineComposition
//
// Responsibility:
//   Order the eligible targets a composition hands to `AcquisitionPlanner`, using the catalogue's own
//   quality/activity facts and any measured per-target latency.
//
// Owns:
//   The ranking function and its score. It orders only; it never filters, admits or plans.
//
// Does not own:
//   Planning. `AcquisitionPlanner` still walks exactly the supplied order ("Targets are never reordered by
//   pressure", "Supplied order remains priority" — docs/architecture/ACQUISITION_DESIGN.md:300). This is the
//   composition's decision about *which* order to supply, not a second planner.
//
// Status:
//   Spec "Estabilidade de coleta e UI", item D: V1 ranked sources by quality and activity before fetching; V2
//   supplied registration order.

import Foundation
import FeedMineDomain
import FeedMineAcquisition

/// What one source is worth as a first request. Every field is optional evidence: a source the catalogue does
/// not describe has no rank, and therefore keeps the supplied order.
public struct AcquisitionTargetSignal: Hashable, Sendable {
    /// The catalogue's `quality_score` (0…100). Absent is not zero: the editorial assessment's own default (70)
    /// applies only when computing a score for a source that has *some* other evidence.
    public let catalogueQualityScore: Int?
    /// The catalogue's activity class (`prolific`, `active`, `quiet`, `dormant`).
    public let catalogueActivity: String?
    /// Measured per-target latency, when a composition actually has one. Never invented.
    public let measuredLatencySeconds: Double?

    public init(catalogueQualityScore: Int? = nil, catalogueActivity: String? = nil,
        measuredLatencySeconds: Double? = nil) {
        self.catalogueQualityScore = catalogueQualityScore
        self.catalogueActivity = catalogueActivity
        self.measuredLatencySeconds = measuredLatencySeconds
    }

    /// Whether this signal says anything at all. A signal with only `measuredLatencySeconds` does.
    public var hasEvidence: Bool {
        catalogueQualityScore != nil || catalogueActivity != nil || measuredLatencySeconds != nil
    }

    /// The ranking score. The quality default and the activity factors are the editorial assessment's own
    /// (`FeedEditorialAssessment`: quality defaults to 70; prolific 1, active 0.94, quiet 0.76, dormant 0.35,
    /// otherwise 0.82), so the order the acquisition uses and the score the reader's feed uses cannot drift
    /// apart. Latency is neutral (1) when unmeasured.
    public var score: Double? {
        guard hasEvidence else { return nil }
        let quality = min(1, max(0, Double(catalogueQualityScore ?? 70) / 100))
        let activity: Double = switch catalogueActivity?.lowercased() {
        case "prolific": 1
        case "active": 0.94
        case "quiet": 0.76
        case "dormant": 0.35
        default: 0.82
        }
        let latency = measuredLatencySeconds.map { value in
            value.isFinite ? 1 / (1 + max(0, value)) : 1
        } ?? 1
        return quality * 0.55 + activity * 0.30 + latency * 0.15
    }
}

public enum AcquisitionTargetOrdering {
    /// Orders `targets` by their best signal, stable on the supplied order.
    ///
    /// - Parameters:
    ///   - targets: exactly the targets eligibility produced; nothing is added or removed.
    ///   - sourcesByTarget: the sources each target is authorized for, from the composition's registrations.
    ///   - signals: catalogue and measured facts per source.
    /// - Returns: `targets` unchanged when no target carries evidence (the fallback), otherwise the same
    ///   targets sorted by score descending; targets without evidence keep their supplied order and follow the
    ///   scored ones, and equal scores keep the supplied order.
    public static func ordered(_ targets: [AcquisitionTarget],
        sourcesByTarget: [AcquisitionTargetID: [SourceID]] = [:],
        signals: [SourceID: AcquisitionTargetSignal] = [:]) -> [AcquisitionTarget] {
        guard !targets.isEmpty, !signals.isEmpty else { return targets }
        struct Ranked {
            let index: Int
            let target: AcquisitionTarget
            let score: Double?
        }
        let ranked = targets.enumerated().map { index, target in
            Ranked(index: index, target: target,
                score: (sourcesByTarget[target.id] ?? []).compactMap { signals[$0]?.score }.max())
        }
        guard ranked.contains(where: { $0.score != nil }) else { return targets }
        return ranked.sorted(by: { (left: Ranked, right: Ranked) -> Bool in
            switch (left.score, right.score) {
            case let (leftScore?, rightScore?):
                return leftScore == rightScore ? left.index < right.index : leftScore > rightScore
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.index < right.index
            }
        }).map(\.target)
    }
}
