// File: ReaderAccessibilityMetrics.swift
// Module: FeedMineUI
// Owns: the measurable accessibility minimums the UI must meet, as values tests can read.
// Does not own: layout. Views apply these numbers; they do not restate them.

import CoreGraphics

public enum ReaderAccessibilityMetrics {
    /// HIG minimum for a control a finger must hit: 44×44 pt. F-UI-5 was a control at ~12 pt.
    public static let minimumTapTarget: CGFloat = 44
}
