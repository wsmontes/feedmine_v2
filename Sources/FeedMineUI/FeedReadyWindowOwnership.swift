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
    /// The candidate temporarily presented for a measured native layout transaction.
    /// This is neither a durable admission nor a committed reader position.
    private(set) var provisional: FeedReadyVisualWindow?
    private var beforeProvisional: FeedVisualWindowWitness?
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
        guard owner == requester, held == nil, provisional == nil,
            let installed else { return false }
        held = installed
        return true
    }

    /// Recording a new logical projection never changes the physical list.
    /// The borrowed run continues to own its pixels and original provenance.
    @discardableResult
    mutating func stage(_ candidate: FeedReadyVisualWindow,
        owner requester: ObjectIdentifier) -> Bool {
        guard owner == requester, provisional == nil, let installed,
            candidate.snapshot.contextKey == installed.snapshot.contextKey,
            candidate.snapshot.editionID == installed.snapshot.editionID,
            candidate.snapshot.provenance.sequenceID == installed.snapshot.provenance.sequenceID,
            candidate.snapshot.provenance.position > installed.snapshot.provenance.position,
            pending.map({ candidate.snapshot.provenance.position >
                $0.snapshot.provenance.position }) ?? true
        else { return false }
        pending = candidate
        return true
    }

    func displayed(owner requester: ObjectIdentifier) -> FeedReadyVisualWindow? {
        guard owner == requester else { return nil }
        return held ?? provisional ?? installed
    }

    mutating func endGesture(owner requester: ObjectIdentifier) {
        guard owner == requester else { return }
        held = nil
    }

    /// Phase 1: verify a physically visible old witness before letting the
    /// host provisionally draw a new ready run. During this phase native offset
    /// writes/gesture starts must be suppressed by the host.
    @discardableResult
    mutating func beginProvisionalHandoff(owner requester: ObjectIdentifier,
        before: FeedVisualWindowWitness?) -> FeedReadyVisualWindow? {
        guard owner == requester, held == nil, provisional == nil,
            let installed, let pending, let before,
            FeedVisualWindowHandoff(from: installed.plan, to: pending.plan,
                before: before, after: before, gestureActive: false) != nil
        else { return nil }
        provisional = pending
        beforeProvisional = before
        return pending
    }

    /// Phase 2: the host has actually laid out the provisional run and measured
    /// the SAME card. Failure rolls the display pointer back, leaving pending
    /// retryable and the original logical checkpoint unchanged. The host must
    /// coordinate native offset adjustment before exposing the new frame.
    @discardableResult
    mutating func commitProvisionalHandoff(owner requester: ObjectIdentifier,
        after: FeedVisualWindowWitness?) -> FeedVisualWindowHandoff? {
        guard owner == requester, held == nil,
            let installed, let pending, let provisional,
            let before = beforeProvisional else { return nil }
        guard provisional.snapshot == pending.snapshot,
            let proof = FeedVisualWindowHandoff(from: installed.plan,
                to: provisional.plan, before: before, after: after,
                gestureActive: false) else {
            self.provisional = nil
            beforeProvisional = nil
            return nil
        }
        self.installed = provisional
        self.pending = nil
        self.provisional = nil
        beforeProvisional = nil
        return proof
    }

    @discardableResult
    mutating func cancelProvisionalHandoff(owner requester: ObjectIdentifier) -> Bool {
        guard owner == requester, provisional != nil else { return false }
        provisional = nil
        beforeProvisional = nil
        return true
    }

    /// An edition/context change revokes all borrowed geometry from the
    /// previous physical scope. It does not touch any saved Runtime cursor.
    mutating func reset(owner requester: ObjectIdentifier) {
        guard owner == requester else { return }
        installed = nil
        pending = nil
        provisional = nil
        beforeProvisional = nil
        held = nil
        owner = nil
    }
}
