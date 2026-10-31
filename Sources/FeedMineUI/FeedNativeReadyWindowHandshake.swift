#if canImport(UIKit)
import Foundation
import UIKit
import FeedMineDomain
import FeedMineRuntime

/// A single token binds the future physical ready-only rail to the existing
/// UIKit offset writer. This is a non-rendering host seam: no LazyVStack swap,
/// no invented historical heights and no second setContentOffset call.
@MainActor
struct FeedNativeReadyWindowHandshake {
    private let owner: ObjectIdentifier
    private let native: FeedNativeScrollOffset
    private var ownership = FeedReadyWindowOwnership()
    private var before: FeedVisualWindowWitness?

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

    /// Invalid geometry or abandonment restores logical display ownership.
    /// Physical offset/list rollback must be performed by the future host
    /// while suppressing intermediate paint and user interaction.
    @discardableResult
    mutating func cancel(transaction: UUID) -> Bool {
        guard ownership.provisionalID == transaction else { return false }
        _ = native.cancelProvisionalCorrection(transaction: transaction)
        before = nil
        return ownership.cancelProvisionalHandoff(owner: owner)
    }

    /// Native gestures always win. They revoke both receipts and borrow the
    /// original installed rail; no delayed callback may resurrect the swap.
    @discardableResult
    mutating func nativeGestureBegan() -> Bool {
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
