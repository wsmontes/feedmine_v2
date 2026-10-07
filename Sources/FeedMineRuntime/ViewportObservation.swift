// File: ViewportObservation.swift
// Module: FeedMineRuntime
// Owns: logical anchor observation and durable checkpoint metadata time.
// Does not own: loading commands, geometry or exposure telemetry.

import Foundation

public struct ViewportObservation: Hashable, Sendable {
    public let anchor: PresentationAnchor
    public let observedAt: Date

    public init?(anchor: PresentationAnchor, observedAt: Date) {
        guard observedAt.timeIntervalSince1970.isFinite else { return nil }
        self.anchor = anchor
        self.observedAt = observedAt
    }
}
