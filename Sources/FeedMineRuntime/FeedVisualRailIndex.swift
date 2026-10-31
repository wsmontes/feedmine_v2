// A virtual index of retained publication slots, not a drawable SwiftUI list.
// The visual adapter must separately manage pixel re-entry and stable geometry.
import Foundation
import FeedMineDomain

/// Read-only, bounded access to one causal presentation's historical positions.
/// No I/O, layout height estimates, extra bitmap decodes or replacement IDs.
public struct FeedVisualRailIndex: Sendable {
    public enum Slot: Equatable, Sendable {
        case ready(index: Int, card: PresentationCard)
        case deferred(index: Int, id: PublicationCardID)

        public var index: Int {
            switch self {
            case .ready(let index, _), .deferred(let index, _): return index
            }
        }

        public var id: PublicationCardID {
            switch self {
            case .ready(_, let card): return card.id
            case .deferred(_, let id): return id
            }
        }

        public var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    // Copy-on-write storage shares the original immutable card array; creating
    // the index never decodes images or materializes an additional history list.
    private let historicalItems: [PresentationCard]
    public let provenance: FeedProjectionProvenance
    public let logicalAnchor: PresentationAnchor
    public let logicalAnchorIndex: Int

    public init(snapshot: FeedPresentationSnapshot) {
        historicalItems = snapshot.window.items
        provenance = snapshot.provenance
        logicalAnchor = snapshot.window.anchor
        // FeedWindowSnapshot guarantees unique IDs and anchor membership.
        logicalAnchorIndex = snapshot.window.items.firstIndex {
            $0.id == snapshot.window.anchor.cardID
        }!
    }

    public var logicalCount: Int { historicalItems.count }

    /// A saved historical image is not a valid visual scroll target until its
    /// bitmap can be materialized. Never silently persist a sibling instead.
    public var visualAnchorID: PublicationCardID? {
        let anchor = historicalItems[logicalAnchorIndex]
        return anchor.isRenderReady ? anchor.id : nil
    }

    public func slot(at index: Int) -> Slot? {
        guard historicalItems.indices.contains(index) else { return nil }
        let card = historicalItems[index]
        return card.isRenderReady
            ? .ready(index: index, card: card)
            : .deferred(index: index, id: card.id)
    }

    /// Only the requested band is constructed. Deferred slots retain logical
    /// indices; they are NOT placeholder cells and have no fabricated height.
    public func slice(around index: Int, backward: Int, forward: Int) -> [Slot] {
        guard historicalItems.indices.contains(index),
            backward >= 0, forward >= 0 else { return [] }
        let first = index - min(index, backward)
        let last = index + min(historicalItems.count - index - 1, forward)
        return (first...last).compactMap { slot(at: $0) }
    }
}
