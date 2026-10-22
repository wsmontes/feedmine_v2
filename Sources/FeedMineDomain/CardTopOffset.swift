//
// File: CardTopOffset.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Represent where the viewport's top line falls relative to one published card's top edge, and
//   the measured height of that card at recording time.
//
// Owns:
//   CardTopOffset: a signed point delta plus a measured height, and the proportional fallback used
//   when the same card is laid out with a different height.
//
// Does not own:
//   Pixels, the card identity itself, restore execution, or persistence mechanics.
//
// Allowed dependencies:
//   Foundation value types only.
//
// Architectural invariants:
//   INV-07, INV-08, INV-12: the value carries no presentation and no second order; identity and
//   order stay in the published card.
//
// Status:
//   Continuity extension for the durable relative reading point (2026-10-21).
//

import Foundation

/// The reader's viewport top, relative to the card that contains it (or to the first card below it
/// when the top line sits in the spacing between cards).
///
/// `topDelta = card.top - viewport.top`. It is zero when the card's top edge is the viewport's top
/// line, negative while the reader sees the card's interior, and positive when the top line is in
/// the spacing above the card. `height` is the card's measured height at recording time and is the
/// only basis on which a changed layout may scale the point.
public struct CardTopOffset: Hashable, Sendable {
    public let topDelta: Double
    public let height: Double

    /// Nil for non-finite values, a non-positive height, and a delta that would put the top line a
    /// full card below the card's own top edge (the containing card was misidentified).
    public init?(topDelta: Double, height: Double) {
        guard topDelta.isFinite, height.isFinite, height > 0 else { return nil }
        guard topDelta > -height - Self.tolerance else { return nil }
        self.topDelta = topDelta
        self.height = height
    }

    /// One point is the existing tolerance of the viewport's own acceptance rule.
    public static let tolerance = 1.0
    /// Half a point is the existing measurement tolerance of frame proofs.
    public static let measurementTolerance = 0.5

    /// How far into the card the top line falls, as a fraction of the card's height. Nil when the
    /// line is in the spacing above the card: a point gap does not scale with the card's height.
    public var fraction: Double? {
        topDelta < 0 ? -topDelta / height : nil
    }

    /// The delta to apply against the card's **currently measured** height.
    ///
    /// Same geometry restores the exact point. A changed height keeps the same fraction of the card
    /// above the viewport and states that the recovery is approximate; a spacing gap stays a point
    /// distance.
    public func restoredTopDelta(forMeasuredHeight measuredHeight: Double) -> (topDelta: Double, exact: Bool) {
        guard measuredHeight.isFinite, measuredHeight > 0 else { return (topDelta, false) }
        if topDelta >= 0 { return (topDelta, true) }
        if abs(measuredHeight - height) <= Self.measurementTolerance { return (topDelta, true) }
        guard let fraction else { return (topDelta, false) }
        return (-fraction * measuredHeight, false)
    }
}
