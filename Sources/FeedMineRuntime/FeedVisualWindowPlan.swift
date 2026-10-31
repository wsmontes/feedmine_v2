import Foundation
import FeedMineDomain

/// A *plan*, not a SwiftUI array. Ready runs never bridge deferred historical
/// slots: collapsing their ordinals would silently change native scroll layout.
/// The visual adapter may install a run only after proving geometry/position.
public struct FeedVisualWindowPlan: Sendable, Equatable {
    public enum Segment: Equatable, Sendable {
        case ready(range: Range<Int>, cards: [PresentationCard])
        case deferred(range: Range<Int>, ids: [PublicationCardID])

        public var range: Range<Int> {
            switch self {
            case .ready(let range, _), .deferred(let range, _): return range
            }
        }
    }

    public let contextKey: ContextKey
    public let editionID: FeedEditionID
    public let provenance: FeedProjectionProvenance
    public let logicalCount: Int
    public let logicalAnchorIndex: Int
    public let visualAnchorID: PublicationCardID?
    public let range: Range<Int>
    public let segments: [Segment]

    public init?(snapshot: FeedPresentationSnapshot, center: Int,
        backward: Int, forward: Int) {
        let rail = FeedVisualRailIndex(snapshot: snapshot)
        guard center >= 0, center < rail.logicalCount,
            backward >= 0, forward >= 0 else { return nil }
        let slots = rail.slice(around: center, backward: backward, forward: forward)
        guard let first = slots.first, let last = slots.last else { return nil }

        var built: [Segment] = []
        for slot in slots {
            switch (built.last, slot) {
            case (.some(.ready(let previous, let cards)), .ready(let index, let card))
                where previous.upperBound == index:
                built[built.count - 1] = .ready(
                    range: previous.lowerBound..<(index + 1), cards: cards + [card])
            case (.some(.deferred(let previous, let ids)), .deferred(let index, let id))
                where previous.upperBound == index:
                built[built.count - 1] = .deferred(
                    range: previous.lowerBound..<(index + 1), ids: ids + [id])
            case (_, .ready(let index, let card)):
                built.append(.ready(range: index..<(index + 1), cards: [card]))
            case (_, .deferred(let index, let id)):
                built.append(.deferred(range: index..<(index + 1), ids: [id]))
            }
        }

        contextKey = snapshot.contextKey
        editionID = snapshot.editionID
        provenance = snapshot.provenance
        logicalCount = rail.logicalCount
        logicalAnchorIndex = rail.logicalAnchorIndex
        range = first.index..<(last.index + 1)
        segments = built
        let candidate = rail.visualAnchorID
        visualAnchorID = candidate.flatMap { anchor in
            built.contains { segment in
                if case .ready(_, let cards) = segment {
                    return cards.contains { $0.id == anchor }
                }
                return false
            } ? anchor : nil
        }
    }

    /// An adapter must not flatten multiple ready runs separated by deferred
    /// slots into one physical LazyVStack list without a measured transition.
    public var contiguousReadyCards: [PresentationCard]? {
        guard segments.count == 1,
            case .ready(_, let cards) = segments[0] else { return nil }
        return cards
    }

    public func containsReadyCard(_ id: PublicationCardID) -> Bool {
        segments.contains { segment in
            if case .ready(_, let cards) = segment {
                return cards.contains { $0.id == id }
            }
            return false
        }
    }
}

/// Exact geometry sampled from a real common rendered card. A missing value,
/// deferred card or estimated image height is not a witness of physical layout.
public struct FeedVisualWindowWitness: Sendable {
    public let cardID: PublicationCardID
    public let viewportTop: Double
    public let contentOffset: Double
    public let cardHeight: Double
    public let viewportHeight: Double

    public init(cardID: PublicationCardID, viewportTop: Double,
        contentOffset: Double, cardHeight: Double, viewportHeight: Double) {
        self.cardID = cardID
        self.viewportTop = viewportTop
        self.contentOffset = contentOffset
        self.cardHeight = cardHeight
        self.viewportHeight = viewportHeight
    }

    fileprivate var isValid: Bool {
        viewportTop.isFinite && contentOffset.isFinite && cardHeight.isFinite &&
            viewportHeight.isFinite && cardHeight > 0 && viewportHeight > 0
    }

    fileprivate var contentTop: Double { viewportTop + contentOffset }
}

/// A validated *candidate* for idle handoff, not a commit or a native offset
/// write. The host must sample the same ready card before and after layout and
/// apply any correction atomically with gesture release. This does not acquire
/// pixels, alter the reader's saved checkpoint or infer historical heights.
public struct FeedVisualWindowHandoff: Sendable {
    public let witnessID: PublicationCardID
    public let provenance: FeedProjectionProvenance
    public let offsetAdjustment: Double

    public init?(from old: FeedVisualWindowPlan, to next: FeedVisualWindowPlan,
        before: FeedVisualWindowWitness?, after: FeedVisualWindowWitness?,
        gestureActive: Bool) {
        guard !gestureActive,
            old.contextKey == next.contextKey, old.editionID == next.editionID,
            old.provenance.sequenceID == next.provenance.sequenceID,
            next.provenance.position >= old.provenance.position,
            let before, let after,
            before.cardID == after.cardID,
            before.isValid, after.isValid,
            before.cardHeight == after.cardHeight,
            before.viewportHeight == after.viewportHeight,
            old.containsReadyCard(before.cardID), next.containsReadyCard(after.cardID)
        else { return nil }

        let adjustment = after.contentTop - before.contentTop
        guard adjustment.isFinite else { return nil }
        witnessID = before.cardID
        provenance = next.provenance
        offsetAdjustment = adjustment
    }
}
