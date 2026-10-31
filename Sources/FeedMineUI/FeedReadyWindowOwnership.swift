import Foundation
import FeedMineDomain
import FeedMineRuntime

/// One *drawable* contiguous ready run, retaining its complete logical
/// snapshot separately for publication identity, navigation and provenance.
/// Building this value never filters or rewrites the durable publication.
struct FeedReadyVisualWindow: Sendable {
    let snapshot: FeedPresentationSnapshot
    let plan: FeedVisualWindowPlan
    let cards: [PresentationCard]
    let visualAnchorID: PublicationCardID

    init?(snapshot: FeedPresentationSnapshot, center: Int, backward: Int,
        forward: Int) {
        guard let plan = FeedVisualWindowPlan(snapshot: snapshot,
                center: center, backward: backward, forward: forward),
            let cards = plan.contiguousReadyCards,
            let visualAnchorID = plan.visualAnchorID else { return nil }
        self.snapshot = snapshot
        self.plan = plan
        self.cards = cards
        self.visualAnchorID = visualAnchorID
    }

    var logicalCount: Int { plan.logicalCount }
    var logicalAnchorID: PublicationCardID { snapshot.window.anchor.cardID }
}

/// Ownership gate for a future native SwiftUI adapter. This does NOT mutate
/// the existing FeedScreenStore or LazyVStack. A host must measure physical
/// geometry before/after installing a candidate and feed the witness back.
/// There is no guessed height, timer, bitmap acquisition or hidden scroll write.
@MainActor
struct FeedReadyWindowOwnership {
    private(set) var installed: FeedReadyVisualWindow?
    private(set) var pending: FeedReadyVisualWindow?
    private var held: FeedReadyVisualWindow?
    private var owner: ObjectIdentifier?

    @discardableResult
    mutating func installInitial(_ surface: FeedReadyVisualWindow,
        owner newOwner: ObjectIdentifier) -> Bool {
        guard installed == nil, owner == nil else { return false }
        owner = newOwner
        installed = surface
        return true
    }

    mutating func beginGesture(owner requester: ObjectIdentifier) -> Bool {
        guard owner == requester, held == nil, let installed else { return false }
        held = installed
        return true
    }

    /// Recording a new logical projection never changes the physical list.
    /// The borrowed run continues to own its pixels and original provenance.
    @discardableResult
    mutating func stage(_ candidate: FeedReadyVisualWindow,
        owner requester: ObjectIdentifier) -> Bool {
        guard owner == requester, let installed,
            candidate.snapshot.contextKey == installed.snapshot.contextKey,
            candidate.snapshot.editionID == installed.snapshot.editionID,
            candidate.snapshot.provenance.sequenceID == installed.snapshot.provenance.sequenceID,
            candidate.snapshot.provenance.position >= installed.snapshot.provenance.position
        else { return false }
        pending = candidate
        return true
    }

    func displayed(owner requester: ObjectIdentifier) -> FeedReadyVisualWindow? {
        guard owner == requester else { return nil }
        return held ?? installed
    }

    mutating func endGesture(owner requester: ObjectIdentifier) {
        guard owner == requester else { return }
        held = nil
    }

    /// Acknowledges a separately measured native layout transition. A failed
    /// proof does not consume pending state or displace the reader. This API
    /// is NOT itself the physical swap: the host must coordinate both samples
    /// without making a transient layout visible during a gesture.
    @discardableResult
    mutating func acknowledgeHandoff(owner requester: ObjectIdentifier,
        before: FeedVisualWindowWitness?, after: FeedVisualWindowWitness?)
        -> FeedVisualWindowHandoff? {
        guard owner == requester, held == nil, let installed, let pending,
            let proof = FeedVisualWindowHandoff(from: installed.plan,
                to: pending.plan, before: before, after: after,
                gestureActive: false) else { return nil }
        self.installed = pending
        self.pending = nil
        return proof
    }

    /// An edition/context change revokes all borrowed geometry from the
    /// previous physical scope. It does not touch any saved Runtime cursor.
    mutating func reset(owner requester: ObjectIdentifier) {
        guard owner == requester else { return }
        installed = nil
        pending = nil
        held = nil
        owner = nil
    }
}
