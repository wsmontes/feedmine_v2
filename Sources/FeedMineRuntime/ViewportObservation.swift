// File: ViewportObservation.swift
// Module: FeedMineRuntime
// Owns: logical anchor observation only.
// Does not own: loading commands, geometry or exposure telemetry.

public struct ViewportObservation: Hashable, Sendable {
    public let anchor: PresentationAnchor

    public init(anchor: PresentationAnchor) {
        self.anchor = anchor
    }
}
