import Foundation
import FeedMineDomain

/// Transient geometry of the currently admitted window only. No historical height ledger.
struct FeedWindowOffsetCorrection {
    private var ids: [PublicationCardID] = []
    private var samples: [PublicationCardID: FeedVisualCardGeometry] = [:]
    private var pending: FeedVisualCardGeometry?

    /// Read-only identity of the window reported by the native probe.
    /// Historical membership lives elsewhere; these IDs are physical-rail evidence.
    var currentWindowIDs: [PublicationCardID] { ids }
    var retainedCount: Int { samples.count }
    var pendingCardID: PublicationCardID? { pending?.cardID }
    var pendingProof: FeedVisualCardGeometry? { pending }

    @discardableResult
    mutating func updateWindow(_ next: [PublicationCardID], allowingCorrection: Bool = true) -> Bool {
        guard next != ids else { return false }
        let kept = Set(next)
        pending = allowingCorrection ? samples.values.filter {
            kept.contains($0.cardID) && $0.frame.maxY > 0 && $0.frame.minY < $0.height
        }.min {
            abs($0.frame.midY - $0.height / 2) < abs($1.frame.midY - $1.height / 2)
        } : nil
        ids = next
        samples = allowingCorrection ? samples.filter { kept.contains($0.key) } : [:]
        return true
    }

    mutating func cancel(discardingSamples: Bool = false) {
        pending = nil
        if discardingSamples { samples.removeAll(keepingCapacity: true) }
    }

    mutating func observe(_ proof: FeedVisualCardGeometry) -> CGFloat? {
        guard ids.contains(proof.cardID) else { return nil }
        samples[proof.cardID] = proof
        guard let before = pending, before.cardID == proof.cardID else { return nil }
        pending = nil
        guard before.height == proof.height, before.frame.size == proof.frame.size else { return nil }
        let delta = proof.frame.minY + proof.offset - before.frame.minY - before.offset
        return delta.isFinite && abs(delta) > 0.5 ? delta : nil
    }
}
