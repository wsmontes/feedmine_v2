#if canImport(UIKit)
import Foundation
import UIKit
import FeedMineDomain
import FeedMineRuntime

/// A canceled handoff may leave a native offset that belonged to a provisional
/// layout. This is a debt for the future *physical host*, not a write request:
/// the old cells and offset must be restored and measured before another swap.
struct FeedNativePhysicalRollbackRequirement: Sendable {
    let transaction: UUID
    let originalOffset: Double
    let originalIDs: [PublicationCardID]
    let originalWitness: FeedVisualWindowWitness
}

/// A single token binds the future physical ready-only rail to the existing
/// UIKit offset writer. This is a non-rendering host seam: no LazyVStack swap,
/// no invented historical heights and no second setContentOffset call.
@MainActor
struct FeedNativeReadyWindowHandshake {
    private let owner: ObjectIdentifier
    private let native: FeedNativeScrollOffset
    private var ownership = FeedReadyWindowOwnership()
    private var before: FeedVisualWindowWitness?
    private(set) var rollbackRequired: FeedNativePhysicalRollbackRequirement?

    init(owner: ObjectIdentifier, native: FeedNativeScrollOffset) {
        self.owner = owner
        self.native = native
    }

    var displayed: FeedReadyVisualWindow? { ownership.displayed(owner: owner) }
    var pending: FeedReadyVisualWindow? { ownership.pending }
    var provisionalID: UUID? { ownership.provisionalID }

    @discardableResult
    mutating func installInitial(_ window: FeedReadyVisualWindow) -> Bool {
        ownership.installInitial(window, owner: owner)
    }

    @discardableResult
    mutating func stage(_ window: FeedReadyVisualWindow) -> Bool {
        ownership.stage(window, owner: owner)
    }

    /// Step 1: the host captured an actual, visible ready witness in the
    /// installed list. Both owners must accept the SAME generated token.
    /// The returned candidate is not a durable reader acknowledgment.
    mutating func begin(before witness: FeedVisualWindowWitness)
        -> (token: UUID, window: FeedReadyVisualWindow)? {
        guard rollbackRequired == nil else { return nil }
        guard let window = ownership.beginProvisionalHandoff(
            owner: owner, before: witness),
            let token = ownership.provisionalID else { return nil }
        guard native.beginProvisionalCorrection(
            transaction: token, witness: witness.cardID) else {
            _ = ownership.cancelProvisionalHandoff(owner: owner)
            return nil
        }
        before = witness
        return (token, window)
    }

    /// Step 2: the future host supplied geometry measured *after* the sole
    /// native correction. We verify actual scroll position and causal witness
    /// before consuming the one-shot native receipt, then synchronously commit
    /// ownership. The numeric handoff delta is never written a second time.
    @discardableResult
    mutating func commit(transaction: UUID,
        after witness: FeedVisualWindowWitness) -> Bool {
        guard ownership.provisionalID == transaction,
            let installed = ownership.installed,
            let provisional = ownership.provisional,
            let before,
            let scroll = native.scrollView,
            !native.isAnimatingScroll,
            abs(Double(scroll.contentOffset.y) - witness.contentOffset) < 0.5,
            FeedVisualWindowHandoff(
                from: installed.plan, to: provisional.plan, before: before,
                after: witness, gestureActive: false) != nil,
            native.takeProvisionalConfirmation(transaction: transaction)
        else { return false }

        guard ownership.commitProvisionalHandoff(
            owner: owner, transaction: transaction, after: witness) != nil
        else {
            _ = ownership.cancelProvisionalHandoff(owner: owner)
            self.before = nil
            return false
        }
        self.before = nil
        return true
    }

    /// Every provisional phase may have replaced the physical list, even if
    /// the offset delta was zero or UIScrollView has since been detached.
    /// Conservatively require proof of the original *list and position* before
    /// another swap. This does not perform a native write.
    private mutating func recordRollbackObligation(transaction: UUID) {
        guard rollbackRequired == nil, let before,
            let installed = ownership.installed else { return }
        rollbackRequired = FeedNativePhysicalRollbackRequirement(
            transaction: transaction,
            originalOffset: before.contentOffset,
            originalIDs: installed.cards.map(\.id),
            originalWitness: before)
    }

    /// Invalid geometry or abandonment restores logical display ownership.
    /// If the native writer already moved, the host must also restore the old
    /// physical cells + offset and acknowledge the measured layout before retry.
    @discardableResult
    mutating func cancel(transaction: UUID) -> Bool {
        guard ownership.provisionalID == transaction else { return false }
        recordRollbackObligation(transaction: transaction)
        _ = native.cancelProvisionalCorrection(transaction: transaction)
        before = nil
        return ownership.cancelProvisionalHandoff(owner: owner)
    }

    /// The native host owns the actual physical restoration. Acknowledging it
    /// requires the exact previous ordered IDs, actual UIKit content offset
    /// and a freshly measured visible witness; no guessed height or second
    /// hidden offset writer is introduced here.
    @discardableResult
    mutating func acknowledgePhysicalRollback(
        restoredIDs: [PublicationCardID],
        measured: FeedVisualWindowWitness) -> Bool {
        guard let debt = rollbackRequired,
            let installed = ownership.installed,
            ownership.provisionalID == nil,
            native.canVerifyPhysicalRollback,
            let scroll = native.scrollView,
            restoredIDs == debt.originalIDs,
            installed.cards.map(\.id) == debt.originalIDs,
            measured.cardID == debt.originalWitness.cardID,
            measured.cardHeight == debt.originalWitness.cardHeight,
            measured.viewportHeight == debt.originalWitness.viewportHeight,
            abs(measured.viewportTop - debt.originalWitness.viewportTop) <= 1,
            measured.viewportTop < measured.viewportHeight,
            measured.viewportTop > -measured.cardHeight,
            abs(measured.contentOffset - debt.originalOffset) < 0.5,
            abs(Double(scroll.contentOffset.y) - debt.originalOffset) < 0.5
        else { return false }
        rollbackRequired = nil
        native.cancel(discardingSamples: true)
        return true
    }

    /// Context/edition replacement revokes every outstanding proof. This is
    /// a state reset only; the physical host is responsible for replacing the
    /// old content and must not treat the previous offset as a new reader.
    mutating func reset() {
        if let token = ownership.provisionalID {
            _ = native.cancelProvisionalCorrection(transaction: token)
        }
        native.cancel(discardingSamples: true)
        ownership.reset(owner: owner)
        rollbackRequired = nil
        before = nil
    }

    /// Native gestures always win. They revoke both receipts and borrow the
    /// original installed rail; no delayed callback may resurrect the swap.
    @discardableResult
    mutating func nativeGestureBegan() -> Bool {
        if let token = ownership.provisionalID {
            recordRollbackObligation(transaction: token)
        }
        native.setInteractionActive(true)
        before = nil
        return ownership.nativeInteractionBegan(owner: owner)
    }

    mutating func nativeGestureEnded() {
        native.setInteractionActive(false)
        ownership.endGesture(owner: owner)
    }
}
#endif
