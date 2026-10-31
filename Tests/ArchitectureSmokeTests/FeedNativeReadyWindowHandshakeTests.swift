#if canImport(UIKit)
import UIKit
import XCTest
import FeedMineDomain
@testable import FeedMineRuntime
@testable import FeedMineUI

/// One token for the borrowed UI rail and the sole UIKit offset writer.
/// The host still has to hide/protect the provisional physical frame.
@MainActor
final class FeedNativeReadyWindowHandshakeTests: XCTestCase {
    private func card() -> PresentationCard {
        PresentationCard(id: PublicationCardID(), title: "Ready",
            primaryText: "Local", timestamp: nil, sourceID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            layout: .textOnly, mediaAspectRatio: nil,
            primaryActionKind: nil, image: nil)
    }

    private func projection(_ cards: [PresentationCard], anchor: PublicationCardID,
        edition: FeedEditionID, sequence: UUID, ordinal: UInt64)
        throws -> FeedPresentationSnapshot {
        let window = try XCTUnwrap(FeedWindowSnapshot(items: cards,
            anchor: .init(cardID: anchor, placement: .top)))
        return FeedPresentationSnapshot(contextKey: ContextKey(request: .main),
            editionID: edition, window: window,
            provenance: .init(sequenceID: sequence, position: ordinal))
    }

    private func offset() -> (FeedNativeScrollOffset, UIScrollView) {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 650))
        scroll.contentSize = CGSize(width: 320, height: 2_000)
        scroll.contentOffset = CGPoint(x: 0, y: 500)
        let native = FeedNativeScrollOffset()
        native.scrollView = scroll
        return (native, scroll)
    }

    private func physical(_ id: PublicationCardID, top: CGFloat,
        offset: CGFloat) -> FeedVisualCardGeometry {
        FeedVisualCardGeometry(cardID: id,
            frame: CGRect(x: 0, y: top, width: 320, height: 160),
            offset: offset, height: 650)
    }

    private func witness(_ id: PublicationCardID, top: Double, offset: Double)
        -> FeedVisualWindowWitness {
        FeedVisualWindowWitness(cardID: id, viewportTop: top,
            contentOffset: offset, cardHeight: 160, viewportHeight: 650)
    }

    /// P0 / issue #7: prepend a ready card ABOVE the user's visible card.
    /// A real native correction must retain exactly the same on-screen Y,
    /// without treating the new logical sequence as fresh reading.
    func testOverlappingReadyPrependNeedsMeasuredSingleNativeCorrection() throws {
        let prepended = card(), a = card(), reader = card()
        let edition = FeedEditionID(), sequence = UUID()
        let prior = try projection([a, reader], anchor: reader.id,
            edition: edition, sequence: sequence, ordinal: 1)
        let candidate = try projection([prepended, a, reader], anchor: reader.id,
            edition: edition, sequence: sequence, ordinal: 2)
        let old = try XCTUnwrap(FeedReadyVisualWindow.initial(snapshot: prior))
        let next = try XCTUnwrap(FeedReadyVisualWindow.initial(snapshot: candidate))
        XCTAssertEqual(old.cards.map(\.id), [a.id, reader.id])
        XCTAssertEqual(next.cards.map(\.id), [prepended.id, a.id, reader.id])

        let (native, scroll) = offset()
        native.updateWindow(old.cards.map(\.id))
        _ = native.observe(physical(reader.id, top: 180, offset: 500))
        let store = FeedScreenStore(onViewport: { _, _ in })
        var handshake = FeedNativeReadyWindowHandshake(owner: ObjectIdentifier(store),
            native: native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(next))
        let before = witness(reader.id, top: 180, offset: 500)
        let token = try XCTUnwrap(handshake.begin(before: before)?.token)
        // Merely staging a different LazyVStack is not a visual commit.
        XCTAssertFalse(handshake.commit(transaction: token, after: before))

        native.updateWindow(next.cards.map(\.id))
        XCTAssertTrue(native.observe(physical(reader.id, top: 420, offset: 500)))
        XCTAssertEqual(scroll.contentOffset.y, 740, accuracy: 0.01)
        XCTAssertEqual(native.appliedCount, 1, "Only the existing native writer may adjust the scroll")
        let after = witness(reader.id, top: 180, offset: 740)
        XCTAssertFalse(handshake.commit(transaction: token, after: after),
            "A write without a post-correction card callback is not a measured handoff")
        _ = native.observe(physical(reader.id, top: 180, offset: 740))
        XCTAssertTrue(handshake.commit(transaction: token, after: after))
        XCTAssertEqual(handshake.displayed?.cards.map(\.id),
            [prepended.id, a.id, reader.id])
        XCTAssertNil(handshake.rollbackRequired)
        XCTAssertEqual(native.appliedCount, 1, "Commit cannot perform a second native scroll write")
        XCTAssertEqual(after.viewportTop, before.viewportTop,
            "The same physical card must remain in the same screen position")
    }

    /// Cancelling after a prepend correction is not a rollback. The host owes
    /// both the old cell order and old physical offset, independently verified.
    func testOverlappingReadyPrependCancellationRetainsPhysicalRollbackDebt() throws {
        let prepended = card(), a = card(), reader = card()
        let edition = FeedEditionID(), sequence = UUID()
        let prior = try projection([a, reader], anchor: reader.id,
            edition: edition, sequence: sequence, ordinal: 1)
        let candidate = try projection([prepended, a, reader], anchor: reader.id,
            edition: edition, sequence: sequence, ordinal: 2)
        let old = try XCTUnwrap(FeedReadyVisualWindow.initial(snapshot: prior))
        let next = try XCTUnwrap(FeedReadyVisualWindow.initial(snapshot: candidate))
        let (native, scroll) = offset()
        native.updateWindow(old.cards.map(\.id))
        _ = native.observe(physical(reader.id, top: 180, offset: 500))
        let store = FeedScreenStore(onViewport: { _, _ in })
        var handshake = FeedNativeReadyWindowHandshake(owner: ObjectIdentifier(store),
            native: native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(next))
        let token = try XCTUnwrap(handshake.begin(
            before: witness(reader.id, top: 180, offset: 500))?.token)
        native.updateWindow(next.cards.map(\.id))
        XCTAssertTrue(native.observe(physical(reader.id, top: 420, offset: 500)))
        XCTAssertEqual(scroll.contentOffset.y, 740, accuracy: 0.01)
        XCTAssertTrue(handshake.cancel(transaction: token))
        XCTAssertEqual(handshake.displayed?.cards.map(\.id), [a.id, reader.id])
        let debt = try XCTUnwrap(handshake.rollbackRequired)
        XCTAssertEqual(debt.originalIDs, [a.id, reader.id])
        XCTAssertEqual(debt.originalOffset, 500, accuracy: 0.01)
        XCTAssertNil(handshake.begin(before: witness(reader.id, top: 180, offset: 740)),
            "A canceled transaction cannot retry with the candidate's offset")

        // The host has restored only the old CELL IDs, not the offset.
        native.updateWindow(old.cards.map(\.id))
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs: [a.id, reader.id],
            measured: witness(reader.id, top: 180, offset: 740)),
            "Returning the old cells with a new native offset is not rollback")
        // The mock host now restores its original physical offset. The
        // handshake performs no restoration; it only checks the receipt.
        scroll.contentOffset = CGPoint(x: 0, y: 500)
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs: [reader.id, a.id],
            measured: witness(reader.id, top: 180, offset: 500)),
            "Rollback must preserve the exact physical order")
        XCTAssertTrue(handshake.acknowledgePhysicalRollback(
            restoredIDs: [a.id, reader.id],
            measured: witness(reader.id, top: 180, offset: 500)))
        XCTAssertNil(handshake.rollbackRequired)
        XCTAssertNotNil(handshake.begin(before:
            witness(reader.id, top: 180, offset: 500)),
            "Only a measured return to the original reader authorizes retry")
    }

    func testNoJointCommitUntilNativeWriterAndGeometryAgree() throws {
        let a = card(), b = card(), added = card()
        let edition = FeedEditionID(), sequence = UUID()
        let s1 = try projection([a,b], anchor: b.id, edition: edition,
            sequence: sequence, ordinal: 1)
        let s2 = try projection([a,b,added], anchor: b.id, edition: edition,
            sequence: sequence, ordinal: 2)
        let old = try XCTUnwrap(FeedReadyVisualWindow(snapshot: s1,
            center: 1, backward: 1, forward: 0))
        let next = try XCTUnwrap(FeedReadyVisualWindow(snapshot: s2,
            center: 1, backward: 1, forward: 1))
        let (native, scroll) = offset()
        native.updateWindow([a.id, b.id])
        _ = native.observe(physical(b.id, top: 180, offset: 500))
        let store = FeedScreenStore(onViewport: { _, _ in })
        var handshake = FeedNativeReadyWindowHandshake(owner: ObjectIdentifier(store),
            native: native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(next))
        let before = witness(b.id, top: 180, offset: 500)
        let after = witness(b.id, top: 180, offset: 740)
        let token = try XCTUnwrap(handshake.begin(before: before)?.token)
        XCTAssertFalse(handshake.commit(transaction: token, after: after))
        XCTAssertEqual(handshake.displayed?.snapshot, s2)
        native.updateWindow([a.id, b.id, added.id])
        XCTAssertTrue(native.observe(physical(b.id, top: 420, offset: 500)))
        XCTAssertEqual(native.appliedCount, 1)
        XCTAssertEqual(scroll.contentOffset.y, 740, accuracy: 0.01)
        XCTAssertFalse(handshake.commit(transaction: token, after: after),
            "The real writer ran but no corrected layout callback arrived yet")
        _ = native.observe(physical(b.id, top: 180, offset: 740))
        XCTAssertFalse(handshake.commit(transaction: UUID(), after: after))
        XCTAssertTrue(handshake.commit(transaction: token, after: after))
        XCTAssertEqual(handshake.displayed?.snapshot, s2)
        XCTAssertNil(handshake.provisionalID)
        XCTAssertFalse(handshake.commit(transaction: token, after: after))
        XCTAssertEqual(native.appliedCount, 1,
            "No second native writer is hidden in the joint confirmation")
    }

    func testInvalidAfterGeometryKeepsOldReaderAndPendingRetryable() throws {
        let a=card(), b=card(), c=card(), edition=FeedEditionID(), sequence=UUID()
        let s1=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let s2=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let old=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s1,center:1,backward:1,forward:0))
        let newer=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s2,center:1,backward:1,forward:1))
        let (native,scroll)=offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(newer))
        let token=try XCTUnwrap(handshake.begin(before:witness(b.id,top:180,offset:500))?.token)
        native.updateWindow([a.id,b.id,c.id])
        _=native.observe(physical(b.id,top:420,offset:500))
        _=native.observe(physical(b.id,top:180,offset:740))
        XCTAssertFalse(handshake.commit(transaction:token,
            after:witness(b.id,top:180,offset:800)),
            "Host must not confirm a post-layout witness different from physical native offset")
        XCTAssertEqual(handshake.displayed?.snapshot,s2,
            "A rejected post-layout sample cannot silently commit or replace the pending rail")
        XCTAssertTrue(handshake.cancel(transaction:token))
        XCTAssertEqual(handshake.displayed?.snapshot,s1)
        XCTAssertEqual(handshake.pending?.snapshot,s2)
        XCTAssertEqual(scroll.contentOffset.y,740,accuracy:0.01,
            "The host still owes a physical offset rollback; model cancellation is not one")
    }

    func testNativeBeginFailureRevertsProvisionalButKeepsCandidate() throws {
        let a=card(),b=card(),c=card(),edition=FeedEditionID(),sequence=UUID()
        let old=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let next=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let first=try XCTUnwrap(FeedReadyVisualWindow(snapshot:old,center:1,backward:1,forward:0))
        let candidate=try XCTUnwrap(FeedReadyVisualWindow(snapshot:next,center:1,backward:1,forward:1))
        let native=FeedNativeScrollOffset() // No UIScrollView is attached.
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(first))
        XCTAssertTrue(handshake.stage(candidate))
        XCTAssertNil(handshake.begin(before:witness(b.id,top:180,offset:500)),
            "Native denial cannot leave UI ownership in a provisional state")
        XCTAssertNil(handshake.provisionalID)
        XCTAssertEqual(handshake.displayed?.snapshot,old)
        XCTAssertEqual(handshake.pending?.snapshot,next)
    }

    func testScopeResetInvalidatesBothTokensAndTheOldPhysicalReader() throws {
        let a=card(),b=card(),c=card(),edition=FeedEditionID(),sequence=UUID()
        let old=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let next=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let first=try XCTUnwrap(FeedReadyVisualWindow(snapshot:old,center:1,backward:1,forward:0))
        let candidate=try XCTUnwrap(FeedReadyVisualWindow(snapshot:next,center:1,backward:1,forward:1))
        let (native,_) = offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(first))
        XCTAssertTrue(handshake.stage(candidate))
        let token=try XCTUnwrap(handshake.begin(before:witness(b.id,top:180,offset:500))?.token)
        handshake.reset()
        XCTAssertNil(handshake.provisionalID)
        XCTAssertNil(handshake.displayed)
        XCTAssertNil(handshake.pending)
        XCTAssertFalse(native.takeProvisionalConfirmation(transaction:token))
        XCTAssertFalse(handshake.commit(transaction:token,
            after:witness(b.id,top:180,offset:500)))
        XCTAssertTrue(handshake.installInitial(first),
            "A later edition may start with new ownership after revocation")
    }

    func testCancelAfterPhysicalCorrectionRequiresMeasuredOldWindowRollback() throws {
        let a = card(), b = card(), c = card()
        let edition = FeedEditionID(), sequence = UUID()
        let s1 = try projection([a,b], anchor:b.id, edition:edition,
            sequence:sequence, ordinal:1)
        let s2 = try projection([a,b,c], anchor:b.id, edition:edition,
            sequence:sequence, ordinal:2)
        let old = try XCTUnwrap(FeedReadyVisualWindow(snapshot:s1,
            center:1, backward:1, forward:0))
        let newer = try XCTUnwrap(FeedReadyVisualWindow(snapshot:s2,
            center:1, backward:1, forward:1))
        let (native, scroll) = offset()
        native.updateWindow([a.id,b.id])
        _ = native.observe(physical(b.id,top:180,offset:500))
        let store = FeedScreenStore(onViewport:{ _,_ in })
        var handshake = FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),
            native:native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(newer))
        let token = try XCTUnwrap(handshake.begin(
            before:witness(b.id,top:180,offset:500))?.token)
        native.updateWindow([a.id,b.id,c.id])
        XCTAssertTrue(native.observe(physical(b.id,top:420,offset:500)))
        XCTAssertEqual(scroll.contentOffset.y,740,accuracy:0.01)
        XCTAssertTrue(handshake.cancel(transaction:token))
        XCTAssertEqual(handshake.displayed?.snapshot,s1)
        XCTAssertEqual(handshake.pending?.snapshot,s2)
        let debt = try XCTUnwrap(handshake.rollbackRequired)
        XCTAssertEqual(debt.originalOffset,500,accuracy:0.01)
        XCTAssertEqual(debt.originalIDs,[a.id,b.id])
        XCTAssertEqual(debt.transaction,token)
        XCTAssertNil(handshake.begin(before:witness(b.id,top:180,offset:740)),
            "The native offset is still wrong for the installed old layout")
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id], measured:witness(b.id,top:180,offset:740)))
        // Emulate the future UIKit host restoring the OLD physical list/offset.
        // The handshake never issues this write itself.
        native.updateWindow([a.id,b.id])
        scroll.contentOffset = CGPoint(x:0,y:500)
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs:[b.id,a.id], measured:witness(b.id,top:180,offset:500)),
            "The same members in different order are not the same physical rail")
        XCTAssertTrue(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id], measured:witness(b.id,top:180,offset:500)))
        XCTAssertNil(handshake.rollbackRequired)
        XCTAssertNotNil(handshake.begin(before:witness(b.id,top:180,offset:500)),
            "Only a verified old physical layout may restart a new transaction")
    }

    func testGestureAfterWriteRetainsPhysicalRollbackDebtUntilIdle() throws {
        let a=card(), b=card(), c=card(), edition=FeedEditionID(), sequence=UUID()
        let s1=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let s2=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let old=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s1,center:1,backward:1,forward:0))
        let next=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s2,center:1,backward:1,forward:1))
        let (native,scroll)=offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(next))
        let token=try XCTUnwrap(handshake.begin(
            before:witness(b.id,top:180,offset:500))?.token)
        native.updateWindow([a.id,b.id,c.id])
        XCTAssertTrue(native.observe(physical(b.id,top:420,offset:500)))
        XCTAssertTrue(handshake.nativeGestureBegan())
        XCTAssertEqual(handshake.displayed?.snapshot,s1)
        XCTAssertEqual(handshake.rollbackRequired?.transaction,token)
        scroll.contentOffset = CGPoint(x:0,y:500)
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id],measured:witness(b.id,top:180,offset:500)),
            "No rollback acknowledgment while the native gesture still owns the scroll")
        handshake.nativeGestureEnded()
        native.updateWindow([a.id,b.id])
        XCTAssertTrue(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id],measured:witness(b.id,top:180,offset:500)))
        XCTAssertNil(handshake.rollbackRequired)
        XCTAssertEqual(handshake.pending?.snapshot,s2)
    }

    func testJointMeasuredZeroDeltaCommitsWithoutAnyNativeOffsetWrite() throws {
        let a=card(), b=card(), c=card(), edition=FeedEditionID(), sequence=UUID()
        let s1=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let s2=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let old=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s1,center:1,backward:1,forward:0))
        let newer=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s2,center:1,backward:1,forward:1))
        let (native,scroll)=offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(newer))
        let measured=witness(b.id,top:180,offset:500)
        let token=try XCTUnwrap(handshake.begin(before:measured)?.token)
        native.updateWindow([a.id,b.id,c.id])
        XCTAssertFalse(native.observe(physical(b.id,top:180,offset:500)))
        XCTAssertTrue(handshake.commit(transaction:token,after:measured))
        XCTAssertEqual(handshake.displayed?.snapshot,s2)
        XCTAssertNil(handshake.rollbackRequired)
        XCTAssertEqual(scroll.contentOffset.y,500,accuracy:0.01)
        XCTAssertEqual(native.appliedCount,0,
            "The zero-shift path must never write the native scroll offset")
    }

    func testCancelAfterZeroDeltaStillRequiresOldPhysicalListConfirmation() throws {
        let a=card(),b=card(),c=card(),edition=FeedEditionID(),sequence=UUID()
        let s1=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let s2=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let old=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s1,center:1,backward:1,forward:0))
        let next=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s2,center:1,backward:1,forward:1))
        let (native,scroll)=offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(next))
        let before=witness(b.id,top:180,offset:500)
        let token=try XCTUnwrap(handshake.begin(before:before)?.token)
        native.updateWindow([a.id,b.id,c.id])
        XCTAssertFalse(native.observe(physical(b.id,top:180,offset:500)))
        XCTAssertEqual(native.appliedCount,0)
        XCTAssertTrue(handshake.cancel(transaction:token))
        XCTAssertNotNil(handshake.rollbackRequired,
            "The provisional physical list changed although the offset did not")
        XCTAssertNil(handshake.begin(before:before))
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id,c.id],measured:before))
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id],measured:before),
            "Caller-supplied IDs cannot claim restoration while the native probe still owns the provisional list")
        native.updateWindow([a.id,b.id])
        XCTAssertEqual(scroll.contentOffset.y,500,accuracy:0.01)
        XCTAssertTrue(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id],measured:before))
        XCTAssertNil(handshake.rollbackRequired)
        XCTAssertEqual(handshake.displayed?.snapshot,s1)
        XCTAssertEqual(handshake.pending?.snapshot,s2)
    }

    func testReplacementScrollViewCannotAcknowledgeOldPhysicalRollback() throws {
        let a=card(),b=card(),c=card(),edition=FeedEditionID(),sequence=UUID()
        let old=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let newer=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let first=try XCTUnwrap(FeedReadyVisualWindow(snapshot:old,center:1,backward:1,forward:0))
        let candidate=try XCTUnwrap(FeedReadyVisualWindow(snapshot:newer,center:1,backward:1,forward:1))
        let (native,scroll)=offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(first))
        XCTAssertTrue(handshake.stage(candidate))
        let before=witness(b.id,top:180,offset:500)
        let token=try XCTUnwrap(handshake.begin(before:before)?.token)
        native.updateWindow([a.id,b.id,c.id])
        XCTAssertTrue(native.observe(physical(b.id,top:420,offset:500)))
        XCTAssertTrue(handshake.cancel(transaction:token))
        let replacement=UIScrollView(frame:scroll.frame)
        replacement.contentSize=scroll.contentSize
        replacement.contentOffset=CGPoint(x:0,y:500)
        native.scrollView=replacement
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id],measured:before),
            "Equal geometry from a new UIScrollView does not restore the old physical owner")
        XCTAssertNotNil(handshake.rollbackRequired)
        XCTAssertNil(handshake.begin(before:before))
    }

    func testChangedInsetCannotAcknowledgeOldPhysicalRollback() throws {
        let a=card(),b=card(),c=card(),edition=FeedEditionID(),sequence=UUID()
        let old=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let newer=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let first=try XCTUnwrap(FeedReadyVisualWindow(snapshot:old,center:1,backward:1,forward:0))
        let candidate=try XCTUnwrap(FeedReadyVisualWindow(snapshot:newer,center:1,backward:1,forward:1))
        let (native,scroll)=offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(first))
        XCTAssertTrue(handshake.stage(candidate))
        let before=witness(b.id,top:180,offset:500)
        let token=try XCTUnwrap(handshake.begin(before:before)?.token)
        native.updateWindow([a.id,b.id,c.id])
        XCTAssertTrue(native.observe(physical(b.id,top:420,offset:500)))
        XCTAssertTrue(handshake.cancel(transaction:token))
        scroll.contentOffset=CGPoint(x:0,y:500)
        scroll.contentInset.top=30
        XCTAssertFalse(handshake.acknowledgePhysicalRollback(
            restoredIDs:[a.id,b.id],measured:before),
            "The old viewport offset cannot authorize rollback under new safe-area geometry")
        XCTAssertNotNil(handshake.rollbackRequired)
    }

    func testGesturePreemptsBothOwnersAndFencesOldToken() throws {
        let a=card(),b=card(),c=card(),edition=FeedEditionID(),sequence=UUID()
        let s1=try projection([a,b],anchor:b.id,edition:edition,sequence:sequence,ordinal:1)
        let s2=try projection([a,b,c],anchor:b.id,edition:edition,sequence:sequence,ordinal:2)
        let old=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s1,center:1,backward:1,forward:0))
        let newer=try XCTUnwrap(FeedReadyVisualWindow(snapshot:s2,center:1,backward:1,forward:1))
        let (native,scroll)=offset()
        native.updateWindow([a.id,b.id])
        _=native.observe(physical(b.id,top:180,offset:500))
        let store=FeedScreenStore(onViewport:{ _,_ in })
        var handshake=FeedNativeReadyWindowHandshake(owner:ObjectIdentifier(store),native:native)
        XCTAssertTrue(handshake.installInitial(old))
        XCTAssertTrue(handshake.stage(newer))
        let token=try XCTUnwrap(handshake.begin(before:witness(b.id,top:180,offset:500))?.token)
        XCTAssertTrue(handshake.nativeGestureBegan())
        native.updateWindow([a.id,b.id,c.id])
        _=native.observe(physical(b.id,top:420,offset:500))
        XCTAssertFalse(handshake.commit(transaction:token,
            after:witness(b.id,top:420,offset:500)))
        XCTAssertEqual(handshake.displayed?.snapshot,s1)
        XCTAssertEqual(handshake.pending?.snapshot,s2)
        XCTAssertEqual(scroll.contentOffset.y,500,accuracy:0.01)
        handshake.nativeGestureEnded()
        XCTAssertNil(handshake.provisionalID)
        XCTAssertEqual(handshake.displayed?.snapshot,s1)
    }
}
#endif
