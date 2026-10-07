//
// File: RenderContract.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Freeze self-contained semantic values for deterministic local published presentation.
//
// Owns:
//   Published layout and optional slot geometry for deterministic local presentation.
//
// Does not own:
//   RenderEnvironment, pixel materialization, acquisition or media resolution.
//
// Allowed dependencies:
//   Foundation value types and FeedMineDomain; PublishedCard also uses FeedMineMedia.
//
// Architectural invariants:
//   INV-08, INV-12; published history survives canonical eviction without live joins.
//
// Public surface:
//   Phase 2C immutable semantic values; no Codable storage blobs or execution API.
//
// Status:
//   Phase 2C frozen PublishedCard baseline implemented.
//

public enum PublishedCardLayout: String, Hashable, Sendable {
    case hero
    case thumbnail
    case textOnly
}

/// Freezes editorial slot structure, independent of device and Dynamic Type.
/// A nil media ratio uses the future renderer's deterministic default for that layout.
/// Slot geometry need not equal source asset geometry.
public struct RenderContract: Hashable, Sendable {
    public let layout: PublishedCardLayout
    public let mediaAspectRatio: Double?

    public init?(layout: PublishedCardLayout, mediaAspectRatio: Double?) {
        if let mediaAspectRatio {
            guard mediaAspectRatio.isFinite, mediaAspectRatio > 0, layout != .textOnly else { return nil }
        }
        self.layout = layout
        self.mediaAspectRatio = mediaAspectRatio
    }
}
