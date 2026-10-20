// File: MediaPolicy.swift
// Module: FeedMineMedia
// Owns: device-aware media budget derived from measured conditions (PD-6) and the fit of a
//   measured image to the card slots of this device.
// Does not own: downloading, editorial ranking, publication layout values or SwiftUI.
//
// PD-6: "ideal is wonderful images and infinite space", but the app may run on an old or full
// iPhone on a slow or unstable network. Every bound below is derived from facts measured at
// runtime (slot size × screen scale, throughput, wait budget, free space, power and thermal state).
// Safety ceilings are operational bounds supplied by composition, never the strategy (INV-04).

import Foundation

public enum MediaNetworkPath: Hashable, Sendable {
    case unavailable
    /// Low Data Mode or an otherwise constrained path.
    case constrained
    /// Cellular or personal hotspot.
    case expensive
    case unconstrained
}

public enum MediaThermalPressure: Hashable, Sendable, Comparable {
    case nominal, fair, serious, critical
}

/// Measured facts. Composition samples them from the platform; tests construct them directly.
public struct MediaDeviceConditions: Hashable, Sendable {
    /// Rendered card-slot widths in points, measured from the actual layout.
    public let heroSlotPointWidth: Double
    public let thumbnailSlotPointWidth: Double
    public let screenScale: Double
    public let network: MediaNetworkPath
    /// Recent measured media throughput; nil when nothing has been measured yet.
    public let measuredBytesPerSecond: Double?
    /// How long this preparation may wait, supplied by the runway from measured consumption.
    public let waitBudgetSeconds: Double?
    /// Free capacity for important usage (`volumeAvailableCapacityForImportantUsage`).
    public let freeStorageBytes: Int64?
    public let lowPowerMode: Bool
    public let thermal: MediaThermalPressure

    public init?(heroSlotPointWidth: Double, thumbnailSlotPointWidth: Double, screenScale: Double,
        network: MediaNetworkPath, measuredBytesPerSecond: Double?, waitBudgetSeconds: Double?,
        freeStorageBytes: Int64?, lowPowerMode: Bool, thermal: MediaThermalPressure) {
        guard heroSlotPointWidth.isFinite, heroSlotPointWidth > 0,
            thumbnailSlotPointWidth.isFinite, thumbnailSlotPointWidth > 0,
            screenScale.isFinite, screenScale >= 1,
            measuredBytesPerSecond.map({ $0.isFinite && $0 > 0 }) ?? true,
            waitBudgetSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
            freeStorageBytes.map({ $0 >= 0 }) ?? true else { return nil }
        self.heroSlotPointWidth = heroSlotPointWidth
        self.thumbnailSlotPointWidth = thumbnailSlotPointWidth
        self.screenScale = screenScale
        self.network = network
        self.measuredBytesPerSecond = measuredBytesPerSecond
        self.waitBudgetSeconds = waitBudgetSeconds
        self.freeStorageBytes = freeStorageBytes
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
    }
}

/// Composition-supplied operational safety bounds (decode-bomb and stream caps).
public struct MediaSafetyCeilings: Hashable, Sendable {
    public let maximumDownloadBytes: Int
    public let maximumPixelSide: Int
    public let maximumPixelCount: Int
    public init?(maximumDownloadBytes: Int, maximumPixelSide: Int, maximumPixelCount: Int) {
        guard maximumDownloadBytes > 0, maximumPixelSide > 0, maximumPixelCount > 0 else { return nil }
        self.maximumDownloadBytes = maximumDownloadBytes
        self.maximumPixelSide = maximumPixelSide
        self.maximumPixelCount = maximumPixelCount
    }
}

/// Where a byte budget came from: the measured rate × wait, or the safety ceiling when nothing was measured.
public enum MediaByteBudgetSource: String, Hashable, Sendable {
    /// The measured throughput times the wait tolerance, clamped by the safety ceiling.
    case dynamic
    /// No usable measurement (or a non-finite product): the safety ceiling itself.
    case ceilingCap = "ceiling-cap"
}

/// The byte ceiling a fetch attempt is given and its provenance. `MediaPolicy.downloadByteBudget` reads
/// `ceiling`, so the number the fetch is handed and the number a trace states cannot disagree.
public struct MediaByteBudget: Hashable, Sendable {
    public let ceiling: Int
    public let source: MediaByteBudgetSource
    public let measuredBytesPerSecond: Double?
    public let waitSeconds: Double?
    /// The safety cap the budget may never exceed.
    public let maximumDownloadBytes: Int

    public init(ceiling: Int, source: MediaByteBudgetSource,
        measuredBytesPerSecond: Double?, waitSeconds: Double?, maximumDownloadBytes: Int) {
        self.ceiling = ceiling
        self.source = source
        self.measuredBytesPerSecond = measuredBytesPerSecond
        self.waitSeconds = waitSeconds
        self.maximumDownloadBytes = maximumDownloadBytes
    }
}

/// How a measured image can serve this device's card slots.
public enum MediaSlotFit: Hashable, Sendable {
    case hero
    case thumbnail
    /// Smaller than the thumbnail slot at 1x, or over a safety ceiling: publish a designed
    /// text-only card or withhold the item (PD-5), never a card missing its image.
    case unsuitable
}

public struct MediaPolicy: Hashable, Sendable {
    public let conditions: MediaDeviceConditions
    public let ceilings: MediaSafetyCeilings

    public init(conditions: MediaDeviceConditions, ceilings: MediaSafetyCeilings) {
        self.conditions = conditions
        self.ceilings = ceilings
    }

    /// Pixels that fill the hero slot exactly on this screen. Fetching more is waste (PD-6 rule 1).
    public var idealHeroPixelWidth: Int { Int((conditions.heroSlotPointWidth * conditions.screenScale).rounded(.up)) }
    public var idealThumbnailPixelWidth: Int {
        Int((conditions.thumbnailSlotPointWidth * conditions.screenScale).rounded(.up))
    }
    /// One pixel per point is the least an image may have before it looks broken in that slot.
    public var acceptableHeroPixelWidth: Int { Int(conditions.heroSlotPointWidth.rounded(.up)) }
    public var acceptableThumbnailPixelWidth: Int { Int(conditions.thumbnailSlotPointWidth.rounded(.up)) }

    /// Whether remote media work should start at all under current conditions.
    public var allowsRemoteMedia: Bool {
        conditions.network != .unavailable && conditions.thermal < .critical
    }

    /// Prefer the smallest candidate that is still acceptable (instead of the ideal) when the
    /// device is saving power, hot, or on a costly/constrained path.
    public var prefersEconomy: Bool {
        conditions.lowPowerMode || conditions.thermal >= .serious
            || conditions.network == .constrained || conditions.network == .expensive
    }

    /// Bytes that can arrive inside the runway's wait budget at the measured throughput, bounded by the safety
    /// ceiling. Without measurements only the ceiling applies. Read from `byteBudget`, so the number the fetch is
    /// handed and the provenance a trace states are one value.
    public var downloadByteBudget: Int { byteBudget.ceiling }

    /// The byte budget with its provenance: the exact ceiling a fetch attempt is given, and where it came from.
    /// `dynamic` is the measured rate times the wait tolerance (clamped by the safety ceiling); `ceilingCap` is
    /// the safety ceiling itself when no usable measurement exists.
    public var byteBudget: MediaByteBudget {
        let cap = ceilings.maximumDownloadBytes
        if let rate = conditions.measuredBytesPerSecond, let wait = conditions.waitBudgetSeconds {
            let affordable = rate * wait
            if affordable.isFinite {
                return MediaByteBudget(ceiling: max(0, min(cap, Int(affordable.rounded(.down)))),
                    source: .dynamic, measuredBytesPerSecond: rate, waitSeconds: wait,
                    maximumDownloadBytes: cap)
            }
        }
        return MediaByteBudget(ceiling: cap, source: .ceilingCap,
            measuredBytesPerSecond: conditions.measuredBytesPerSecond,
            waitSeconds: conditions.waitBudgetSeconds, maximumDownloadBytes: cap)
    }

    /// Fit of an inspected image. Uses measured dimensions only, never declared hints.
    public func fit(measuredPixelWidth width: Int, height: Int) -> MediaSlotFit {
        guard width > 0, height > 0, width <= ceilings.maximumPixelSide, height <= ceilings.maximumPixelSide,
            width.multipliedReportingOverflow(by: height).overflow == false,
            width * height <= ceilings.maximumPixelCount else { return .unsuitable }
        // A hero is a wide visual; tall images read better as thumbnails.
        if width >= acceptableHeroPixelWidth && width >= height { return .hero }
        if width >= acceptableThumbnailPixelWidth { return .thumbnail }
        return .unsuitable
    }
}
