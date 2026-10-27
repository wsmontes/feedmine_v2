//
// File: ReaderSheetPullDown.swift
// Module: FeedMineUI
// Owns: the rule that turns a deliberate pull at the top of a reader page into a dismissal request.
// Does not own: the presentation, the scroll observation, or what a dismissal does. The local page
//       (`FeedReadingSurface`) and the publisher's page (`ReaderWebSurface`, app target) each observe their own
//       scroll view and ask this one rule, so the gesture and its tests cannot disagree about a threshold.
import CoreGraphics

public enum ReaderSheetPullDown {
    /// How far the content is pulled down from its resting top edge before the gesture counts.
    ///
    /// 80 pt sits above a stray bounce — an overshoot nobody meant as a dismissal — and below a deliberate pull,
    /// which moves several hundred points. It is the only threshold: neither surface carries a constant of its
    /// own, so a test of this value is a test of both gestures.
    public static let dismissalDistance: CGFloat = 80

    /// How far the content sits below its resting top edge. Zero means "not pulled": the page is at the top or
    /// scrolled down. A downward drag that reaches the top from below is never a pull, which is what keeps a
    /// reader from dismissing the article while scrolling back up through it.
    public static func pull(contentOffsetY: CGFloat, topInset: CGFloat) -> CGFloat {
        max(0, -(contentOffsetY + topInset))
    }

    /// Whether the page is at its resting top edge, within one point.
    public static func isAtTop(contentOffsetY: CGFloat, topInset: CGFloat) -> Bool {
        contentOffsetY <= -topInset + 1
    }

    /// The gesture, once it is live.
    ///
    /// `startedAtTop` is the latch taken at touch-down — not the offset observed after the drag has already
    /// moved — so a page scrolled down can be dragged up through its own text without dismissing. `isTracking` is
    /// the platform's own dragging state, so a rubber-band settle after release, a programmatic scroll to the top
    /// and a load's own adjustment are not gestures and never qualify. `horizontalPull` keeps a sideways swipe
    /// (including a diagonal one on a page that pans horizontally) from being read as a pull.
    public static func dismisses(startedAtTop: Bool, isTracking: Bool,
        verticalPull: CGFloat, horizontalPull: CGFloat = 0) -> Bool {
        guard startedAtTop, isTracking, verticalPull >= dismissalDistance else { return false }
        return verticalPull >= abs(horizontalPull) * 1.5
    }
}
