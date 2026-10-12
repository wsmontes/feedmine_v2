import Foundation
import FeedMineDomain

/// Transient geometry of the currently admitted window only. No historical height ledger.
struct FeedWindowOffsetCorrection {
    private var ids: [PublicationCardID] = []
    private var samples: [PublicationCardID: FeedVisualCardGeometry] = [:]
    private var pending: FeedVisualCardGeometry?

    var retainedCount: Int { samples.count }
    var pendingCardID: PublicationCardID? { pending?.cardID }

    mutating func updateWindow(_ next: [PublicationCardID]) {
        guard next != ids else { return }
        let kept = Set(next)
        pending = samples.values.filter {
            kept.contains($0.cardID) && $0.frame.maxY > 0 && $0.frame.minY < $0.height
        }.min {
            abs($0.frame.midY - $0.height / 2) < abs($1.frame.midY - $1.height / 2)
        }
        ids = next
        samples = samples.filter { kept.contains($0.key) }
    }

    mutating func cancel() { pending = nil }

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
