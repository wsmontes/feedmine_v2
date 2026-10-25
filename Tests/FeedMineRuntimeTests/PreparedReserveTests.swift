import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineRuntime

/// PM-028A §2: the reserve's phase machine is decided by facts a caller states, so every rule it implements is
/// provable without a fetcher, a clock or a device. The clock here is a value the test moves.
final class PreparedReserveTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0.0
        var now: Double { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: Double) { lock.lock(); value += seconds; lock.unlock() }
    }

    private func revision() -> OriginRevisionID { OriginRevisionID() }

    private func reserve(_ clock: Clock, targetDepth: Int = 4, lowWaterMark: Int = 2, maxAttempts: Int = 3,
        persistedByteBudget: Int = 1_000, retryDelays: [Double] = [1, 4, 16]) -> PreparedReserve {
        PreparedReserve(targetDepth: targetDepth, lowWaterMark: lowWaterMark, maxAttempts: maxAttempts,
            persistedByteBudget: persistedByteBudget, retryDelays: retryDelays, now: { clock.now })
    }

    /// The reserve only ever counts what a settlement states, and a settled presentation is settled once.
    func testSettleIsIdempotentAndCountsTheBytesOnce() async {
        let clock = Clock(), reserve = reserve(clock), revision = revision()
        let planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [revision])
        await reserve.markPreparing(revision, attempt: 0)
        let first = await reserve.settle(revision, outcome: .prepared(hasImage: true), persistedBytes: 300)
        XCTAssertTrue(first)
        let second = await reserve.settle(revision, outcome: .prepared(hasImage: true), persistedBytes: 300)
        XCTAssertFalse(second, "a presentation already prepared is not settled a second time")
        // A later attempt record must not pull a ready revision back into work.
        await reserve.markPreparing(revision, attempt: 1)
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.ready, 1)
        XCTAssertEqual(snapshot.preparing, 0)
        XCTAssertEqual(snapshot.persistedBytes, 300, "the retained asset is counted once")
        XCTAssertEqual(snapshot.lateCompletions, 0, "a completion inside its window is not late")
        let phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .ready(hasImage: true))
    }

    /// Rule 4/6: a published revision ignores every later settlement and never competes again.
    func testPublishedIgnoresLaterSettlementAndLeavesThePlan() async {
        let clock = Clock(), reserve = reserve(clock), revision = revision()
        _ = await reserve.plan(offer: [revision])
        await reserve.markPreparing(revision, attempt: 0)
        _ = await reserve.settle(revision, outcome: .prepared(hasImage: true), persistedBytes: 120)
        await reserve.markPublished(revision)
        let phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .published)
        let late = await reserve.settle(revision, outcome: .prepared(hasImage: true), persistedBytes: 999)
        XCTAssertFalse(late, "a published revision is never republished by a late completion")
        let planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [])
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.published, 1)
        XCTAssertEqual(snapshot.ready, 0)
        XCTAssertEqual(snapshot.persistedBytes, 0,
            "publishing hands the retained share back, and the ignored settle cannot re-add it")
    }

    /// Rule 6: published through another path, so it is superseded rather than left waiting to compete.
    func testMarkPublishedSupersedesARevisionThatNeverBecameReady() async {
        let clock = Clock(), reserve = reserve(clock), pending = revision(), deferred = revision()
        _ = await reserve.plan(offer: [pending, deferred])
        _ = await reserve.settle(deferred, outcome: .conditionsUnavailable)
        await reserve.markPublished(pending)
        await reserve.markPublished(deferred)
        let pendingPhase = await reserve.phase(of: pending)
        let deferredPhase = await reserve.phase(of: deferred)
        XCTAssertEqual(pendingPhase, .exhausted(.superseded))
        XCTAssertEqual(deferredPhase, .exhausted(.superseded))
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.exhausted, 2)
        let planned = await reserve.plan(offer: [pending, deferred])
        XCTAssertEqual(planned, [], "a superseded revision does not come back to the reserve")
    }

    /// Rule 1: every transient failure spends an attempt, the curve spaces the retries, and the last attempt exhausts
    /// instead of retrying forever. A deferred revision is not due before its own `retryAt`.
    func testTransientFailureSpendsAttemptsThenExhausts() async {
        let clock = Clock(), reserve = reserve(clock), revision = revision()
        _ = await reserve.plan(offer: [revision])
        await reserve.markPreparing(revision, attempt: 0)
        _ = await reserve.settle(revision, outcome: .transientFailure)
        var phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .deferred(retryAt: 1), "the first backoff is the curve's first delay")
        var planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [], "a deferred revision is not offered before its retryAt")

        clock.advance(1)
        planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [revision])
        await reserve.markPreparing(revision, attempt: 1)
        _ = await reserve.settle(revision, outcome: .transientFailure)
        phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .deferred(retryAt: 5), "the second backoff is the curve's second delay")

        clock.advance(4)
        planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [revision])
        await reserve.markPreparing(revision, attempt: 2)
        _ = await reserve.settle(revision, outcome: .transientFailure)
        phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .exhausted(.attemptsSpent), "the third failure is the attempt budget")
        clock.advance(1_000)
        planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [], "an exhausted revision keeps its identity and stops competing")
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.exhausted, 1)
        XCTAssertEqual(snapshot.deferred, 0)
    }

    /// A caller that always names attempt zero cannot retry forever: the spend count is the reserve's own.
    func testRepeatedAttemptZeroStillExhausts() async {
        let clock = Clock(), reserve = reserve(clock), revision = revision()
        for _ in 0..<3 {
            await reserve.markPreparing(revision, attempt: 0)
            _ = await reserve.settle(revision, outcome: .transientFailure)
            clock.advance(1_000)
        }
        let phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .exhausted(.attemptsSpent))
    }

    /// Rule 2: declared media that cannot be prepared is final at once, and it does not block the rest of the offer.
    func testDefinitiveFailureExhaustsImmediatelyWithoutBlockingTheOffer() async {
        let clock = Clock(), reserve = reserve(clock), invalid = revision(), healthy = revision()
        let planned = await reserve.plan(offer: [invalid, healthy])
        XCTAssertEqual(planned, [invalid, healthy])
        _ = await reserve.settle(invalid, outcome: .definitiveFailure)
        let phase = await reserve.phase(of: invalid)
        XCTAssertEqual(phase, .exhausted(.mediaInvalid), "the first definitive answer is final")
        let next = await reserve.plan(offer: [invalid, healthy])
        XCTAssertEqual(next, [healthy], "the rest of the same offer is still workable")
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.exhausted, 1)
        XCTAssertEqual(snapshot.pending, 1)
    }

    /// Rule 3: conditions are not a failure of the media, so they never spend an attempt.
    func testConditionsUnavailableDefersWithoutSpendingAttempts() async {
        let clock = Clock(), reserve = reserve(clock), revision = revision()
        for _ in 0..<6 {
            _ = await reserve.settle(revision, outcome: .conditionsUnavailable)
            let phase = await reserve.phase(of: revision)
            XCTAssertEqual(phase, .deferred(retryAt: clock.now + 1))
            clock.advance(1)
        }
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.exhausted, 0, "offline is not an attempt")
        let planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [revision], "the revision is still eligible once conditions are due again")
    }

    /// The persisted-byte budget stops new work and drops nothing: evicting a prepared presentation would demand
    /// re-materialising it, which is not this delivery (PM-028A §2).
    func testPersistedBudgetStopsPlanningWithoutDroppingWhatIsReady() async {
        let clock = Clock()
        let reserve = reserve(clock, targetDepth: 4, lowWaterMark: 4, persistedByteBudget: 500)
        let prepared = revision(), waiting = revision()
        _ = await reserve.plan(offer: [prepared, waiting])
        await reserve.markPreparing(prepared, attempt: 0)
        _ = await reserve.settle(prepared, outcome: .prepared(hasImage: true), persistedBytes: 500)
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.persistedBytes, 500)
        XCTAssertEqual(snapshot.ready, 1)
        let planned = await reserve.plan(offer: [waiting])
        XCTAssertEqual(planned, [], "the budget is spent, so no new revision is emitted")
        let waitingPhase = await reserve.phase(of: waiting)
        XCTAssertEqual(waitingPhase, .pending, "the refused revision stays pending, not exhausted")
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.ready, 1, "nothing already prepared is dropped")
    }

    /// PM-028A §4.2: the budget governs prepared-but-**unpublished** asset. Publishing hands that revision's share
    /// back and reopens the plan, so a long session cannot fill the budget with cards the reader already has; the
    /// published revision itself never returns to preparation.
    func testPublishingReleasesTheRetainedBytesAndReopensTheBudget() async {
        let clock = Clock()
        let reserve = reserve(clock, targetDepth: 4, lowWaterMark: 4, persistedByteBudget: 500)
        let old = revision(), fresh = revision()
        _ = await reserve.plan(offer: [old])
        await reserve.markPreparing(old, attempt: 0)
        _ = await reserve.settle(old, outcome: .prepared(hasImage: true), persistedBytes: 500)
        let blocked = await reserve.plan(offer: [fresh])
        XCTAssertEqual(blocked, [], "the reserve is full of retained asset")

        await reserve.markPublished(old)
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.persistedBytes, 0, "the published revision handed its share back")
        XCTAssertEqual(snapshot.published, 1)
        let reopened = await reserve.plan(offer: [fresh])
        XCTAssertEqual(reopened, [fresh], "the released budget authorizes new work again")

        // A published revision is never prepared again, even if an offer still names it.
        let publishedOld = await reserve.plan(offer: [old])
        XCTAssertEqual(publishedOld, [])
        let lateSettle = await reserve.settle(old, outcome: .prepared(hasImage: true), persistedBytes: 500)
        XCTAssertFalse(lateSettle, "a published revision ignores later settlements")
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.persistedBytes, 0, "and it cannot re-add bytes to a budget it left")
    }

    /// PM-029: the two comparison counters count only cards that were **recovered** (a durable deferral row marked by
    /// the owner) and then published, and among them the ones that carried an image.
    func testReconsiderationCountersCountOnlyRecoveredPublishedCards() async {
        let clock = Clock(), reserve = reserve(clock)
        let recoveredWithImage = revision(), recoveredText = revision(), structural = revision()
        await reserve.noteReconsidered([recoveredWithImage, recoveredText])
        for revision in [recoveredWithImage, recoveredText, structural] {
            _ = await reserve.plan(offer: [revision])
            await reserve.markPreparing(revision, attempt: 0)
        }
        _ = await reserve.settle(recoveredWithImage, outcome: .prepared(hasImage: true), persistedBytes: 10)
        _ = await reserve.settle(recoveredText, outcome: .prepared(hasImage: false), persistedBytes: 0)
        _ = await reserve.settle(structural, outcome: .prepared(hasImage: true), persistedBytes: 10)
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.reconsideredPublished, 0, "nothing is counted before it publishes")

        for revision in [recoveredWithImage, recoveredText, structural] {
            await reserve.markPublished(revision)
        }
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.reconsideredPublished, 2, "only the deferral-page stories are recovered")
        XCTAssertEqual(snapshot.reconsideredWithImage, 1, "one of them published with an image")
        XCTAssertEqual(snapshot.published, 3)
        // Publishing the same revision again cannot count it twice.
        await reserve.markPublished(recoveredWithImage)
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.reconsideredPublished, 2)
        // A story that was recovered but published from `.pending` (another path) is not "recovered and published".
        let superseded = revision()
        await reserve.noteReconsidered([superseded])
        await reserve.markPublished(superseded)
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.reconsideredPublished, 2)
        XCTAssertEqual(snapshot.exhausted, 1)
    }

    /// `targetDepth` bounds one plan, and the band between the low water mark and the target is where the reserve
    /// stops asking: a reader who walks one card must not start a download.
    func testPlanRespectsTargetDepthAndTheHysteresisBand() async {
        let clock = Clock(), reserve = reserve(clock, targetDepth: 4, lowWaterMark: 2)
        let offer = (0..<8).map { _ in revision() }
        let first = await reserve.plan(offer: offer)
        XCTAssertEqual(first, Array(offer.prefix(4)), "one plan stops at the target depth")
        for revision in offer.prefix(4) {
            await reserve.markPreparing(revision, attempt: 0)
            _ = await reserve.settle(revision, outcome: .prepared(hasImage: true), persistedBytes: 10)
        }
        let atDepth = await reserve.plan(offer: offer)
        XCTAssertEqual(atDepth, [], "a full reserve asks for nothing")
        await reserve.markPublished(offer[0])
        let deadBand = await reserve.plan(offer: offer)
        XCTAssertEqual(deadBand, [], "three ready is the dead band, not a reason to download")
        await reserve.markPublished(offer[1])
        let refill = await reserve.plan(offer: offer)
        XCTAssertEqual(refill, [offer[4], offer[5]], "at the low water mark the reserve refills toward the target")
        await reserve.markPreparing(offer[4], attempt: 0)
        _ = await reserve.settle(offer[4], outcome: .prepared(hasImage: true), persistedBytes: 10)
        let topping = await reserve.plan(offer: offer)
        XCTAssertEqual(topping, [offer[5]], "a refill under way continues to the target")
        await reserve.markPreparing(offer[5], attempt: 0)
        _ = await reserve.settle(offer[5], outcome: .prepared(hasImage: true), persistedBytes: 10)
        let full = await reserve.plan(offer: offer)
        XCTAssertEqual(full, [], "the target depth ends the refill and clears the latch")
        await reserve.markPublished(offer[2])
        let againDeadBand = await reserve.plan(offer: offer)
        XCTAssertEqual(againDeadBand, [], "the latch was cleared, so the dead band applies again")
        await reserve.markPublished(offer[3])
        let nextRefill = await reserve.plan(offer: [offer[6], offer[7]])
        XCTAssertEqual(nextRefill, [offer[6], offer[7]], "new supply is offered once the band is reached")
    }

    /// A revision with work in flight is not offered again by the same or a later opportunity.
    func testPlanSkipsAPreparingRevision() async {
        let clock = Clock(), reserve = reserve(clock), revision = revision()
        _ = await reserve.plan(offer: [revision])
        await reserve.markPreparing(revision, attempt: 0)
        await reserve.markPreparing(revision, attempt: 0)
        let planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [])
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.preparing, 1, "repeating the same attempt record is idempotent")
    }

    /// PM-028A §4.3: a completion that arrives after the window of the slice that started it is still taken, is
    /// counted as late, and the revision competes for publication. Rule 5: a completion for a revision no
    /// `markPreparing` announced is taken too.
    func testLateCompletionIsAcceptedAndCounted() async {
        let clock = Clock(), reserve = reserve(clock), subject = revision(), unannounced = revision()
        _ = await reserve.plan(offer: [subject])
        await reserve.markPreparing(subject, attempt: 0)
        await reserve.windowClosed([subject])
        var phase = await reserve.phase(of: subject)
        XCTAssertEqual(phase, .deferred(retryAt: 1), "an ended window leaves the revision waiting, spending nothing")
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.preparing, 0)
        XCTAssertEqual(snapshot.lateCompletions, 0)
        let planned = await reserve.plan(offer: [subject])
        XCTAssertEqual(planned, [], "the ended window is not due again immediately")
        clock.advance(1)
        let settled = await reserve.settle(subject, outcome: .prepared(hasImage: true), persistedBytes: 42)
        XCTAssertTrue(settled)
        phase = await reserve.phase(of: subject)
        XCTAssertEqual(phase, .ready(hasImage: true), "a late completion still becomes a presentation")
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.ready, 1)
        XCTAssertEqual(snapshot.lateCompletions, 1)
        XCTAssertEqual(snapshot.persistedBytes, 42)

        // Rule 5: the prefetch may conclude before the record of its attempt exists.
        let beforeRecord = await reserve.settle(unannounced, outcome: .prepared(hasImage: false))
        XCTAssertTrue(beforeRecord)
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.lateCompletions, 2, "a completion with no attempt on record is late by definition")
        let unannouncedPhase = await reserve.phase(of: unannounced)
        XCTAssertEqual(unannouncedPhase, .ready(hasImage: false), "text without an image is a legitimate presentation")
    }

    /// Closing a window only releases what was in flight: settled decisions are not rewritten.
    func testWindowClosedLeavesSettledRevisionsAlone() async {
        let clock = Clock(), reserve = reserve(clock), ready = revision(), published = revision()
        _ = await reserve.plan(offer: [ready, published])
        await reserve.markPreparing(ready, attempt: 0)
        _ = await reserve.settle(ready, outcome: .prepared(hasImage: true), persistedBytes: 8)
        await reserve.windowClosed([ready, published])
        let readyPhase = await reserve.phase(of: ready)
        XCTAssertEqual(readyPhase, .ready(hasImage: true))
        let publishedPhase = await reserve.phase(of: published)
        XCTAssertEqual(publishedPhase, .pending)
    }

    /// P1 (review): ready depth must not permanently veto the work that unblocks selection. When the edition tail
    /// shares a source with every ready revision, `MaximumDistanceSequencing` holds them all — nothing publishes,
    /// nothing is marked published, and a plan that refuses everything at the target would leave the reserve unable to
    /// drain. One bounded batch above the target is what the deadlock needs.
    func testFullReserveAuthorizesABoundedUnblockingBatchWhenNothingPublishes() async {
        let clock = Clock(), reserve = reserve(clock, targetDepth: 2, lowWaterMark: 1)
        let blocked = (0..<2).map { _ in revision() }, unblocking = revision()
        _ = await reserve.plan(offer: blocked)
        for revision in blocked {
            await reserve.markPreparing(revision, attempt: 0)
            _ = await reserve.settle(revision, outcome: .prepared(hasImage: true), persistedBytes: 10)
        }
        // Every ready revision is PD-4-blocked by the tail. The first refusal may still be a publication on its way.
        let firstRefusal = await reserve.plan(offer: blocked + [unblocking])
        XCTAssertEqual(firstRefusal, [], "one refusal at the target waits for the publication that may be coming")
        // Nothing published in between: the depth may no longer refuse the revision that unblocks selection.
        let unblocked = await reserve.plan(offer: blocked + [unblocking])
        XCTAssertEqual(unblocked, [unblocking], "a bounded batch above the target is authorized")
        await reserve.markPreparing(unblocking, attempt: 0)
        _ = await reserve.settle(unblocking, outcome: .prepared(hasImage: true), persistedBytes: 10)
        // The story publishes, and the blocked revisions leave with it.
        await reserve.markPublished(blocked + [unblocking])
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.ready, 0, "the reserve drained instead of holding the deadlock")
        XCTAssertEqual(snapshot.published, 3)
        XCTAssertEqual(snapshot.persistedBytes, 0, "publication released every retained share")
    }

    /// P4 (review): a closed window frees no slot while the prefetcher still owns the attempt. Counting `.ready`
    /// alone let a window close with every download still running, so the next opportunity authorized a second full
    /// batch on top of the first and the reserve overshot both depth and bytes.
    func testClosedWindowWithOutstandingWorkDoesNotAuthorizeASecondBatch() async {
        let clock = Clock(), reserve = reserve(clock, targetDepth: 2, lowWaterMark: 0)
        let first = (0..<2).map { _ in revision() }, second = (0..<2).map { _ in revision() }
        let opening = await reserve.plan(offer: first)
        XCTAssertEqual(opening, first)
        for revision in first { await reserve.markPreparing(revision, attempt: 0) }
        await reserve.windowClosed(first, outstanding: Set(first))
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.outstanding, 2)
        XCTAssertEqual(snapshot.ready, 0)
        let held = await reserve.plan(offer: second)
        XCTAssertEqual(held, [], "outstanding work holds the depth")
        // Time does not free the slot: only the outcome does.
        clock.advance(600)
        let stillHeld = await reserve.plan(offer: second)
        XCTAssertEqual(stillHeld, [], "an ended window's work is not due again by time")
        // The outcomes arrive: the capacity moves and the late completion is still counted.
        _ = await reserve.settle(first[0], outcome: .prepared(hasImage: true), persistedBytes: 5)
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.outstanding, 1)
        XCTAssertEqual(snapshot.lateCompletions, 1, "a completion past its window is still a late completion")
        _ = await reserve.settle(first[1], outcome: .prepared(hasImage: true), persistedBytes: 5)
        let filled = await reserve.plan(offer: second)
        XCTAssertEqual(filled, [], "two ready presentations fill the depth")
        await reserve.markPublished(first)
        let reopened = await reserve.plan(offer: second)
        XCTAssertEqual(reopened, second, "publication reopens the plan")
    }

    /// P2 (review): the return of `plan` **is** the reservation. `MediaPreparationOpportunity.request` can run two
    /// opportunities concurrently, and each of them calls `plan` before either loop reaches `markPreparing`. Counting
    /// only `.ready`/`.preparing`/`outstanding` let both plans see the same free room and each grant a batch into it.
    func testConcurrentPlansCannotSpendTheSameFreeRoom() async {
        let clock = Clock()
        let reserve = reserve(clock, targetDepth: 96, lowWaterMark: 64, persistedByteBudget: 1 << 20)
        // A first opportunity below the low water mark latches the top-up band, exactly as production does.
        _ = await reserve.plan(offer: [])
        let ready = (0..<80).map { _ in revision() }
        for revision in ready {
            _ = await reserve.settle(revision, outcome: .prepared(hasImage: false))
        }
        let first = (0..<32).map { _ in revision() }, second = (0..<32).map { _ in revision() }
        async let one = reserve.plan(offer: first)
        async let two = reserve.plan(offer: second)
        let (grantedOne, grantedTwo) = await (one, two)
        XCTAssertEqual(grantedOne.count + grantedTwo.count, 16,
            "80 ready leaves 16 free slots to the target, granted once and not once per opportunity")
        XCTAssertTrue(Set(grantedOne).isDisjoint(with: Set(grantedTwo)),
            "no revision is authorised by both opportunities")
    }

    /// P2 (review): on a full reserve the bounded unblocking batch is granted **once**. Two authorising plans
    /// separated by an opportunity that authorises nothing used to each receive 16 while their work was still
    /// unmarked: 96 ready + 16 + 16 authorised 128 against the ceiling of `targetDepth + 16` = 112.
    func testAFullReserveGrantsTheUnblockingBatchOnce() async {
        let clock = Clock()
        let reserve = reserve(clock, targetDepth: 96, lowWaterMark: 64, persistedByteBudget: 1 << 20)
        let ready = (0..<96).map { _ in revision() }
        let opening = await reserve.plan(offer: ready)
        XCTAssertEqual(opening.count, 96)
        for revision in ready {
            await reserve.markPreparing(revision, attempt: 0)
            _ = await reserve.settle(revision, outcome: .prepared(hasImage: false))
        }
        // The first refusal waits for the publication that may be on its way.
        let firstRefusal = await reserve.plan(offer: ready)
        XCTAssertEqual(firstRefusal, [])
        let firstBatch = (0..<16).map { _ in revision() }
        let granted = await reserve.plan(offer: firstBatch)
        XCTAssertEqual(granted, firstBatch, "the bounded batch above the target is authorised")
        // An opportunity that authorises nothing does not reopen the room the first grant already spent.
        let refusal = await reserve.plan(offer: ready)
        XCTAssertEqual(refusal, [])
        let secondBatch = (0..<16).map { _ in revision() }
        let secondGrant = await reserve.plan(offer: secondBatch)
        XCTAssertEqual(secondGrant, [],
            "the second batch would authorise 128 against the promised ceiling of 112")
    }

    /// P2 (review): a revision whose window closed while the prefetcher still owns the attempt is not planned again
    /// when the retry timestamp passes. The first attempt is still running; planning it again lets `markPreparing`
    /// name one revision in `.preparing` and in `outstanding` at once, counting it twice. Only its own settlement
    /// frees it.
    func testPlanDoesNotReauthorizeARevisionWhoseWorkIsOutstanding() async {
        let clock = Clock(), reserve = reserve(clock, targetDepth: 2, lowWaterMark: 0), revision = revision()
        let planned = await reserve.plan(offer: [revision])
        XCTAssertEqual(planned, [revision])
        await reserve.markPreparing(revision, attempt: 0)
        await reserve.windowClosed([revision], outstanding: [revision])
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.outstanding, 1)
        XCTAssertEqual(snapshot.preparing, 0)

        clock.advance(1)
        var reoffered = await reserve.plan(offer: [revision])
        XCTAssertEqual(reoffered, [],
            "the deferred retry timestamp is not a reason to plan work the prefetcher still owns")
        clock.advance(600)
        reoffered = await reserve.plan(offer: [revision])
        XCTAssertEqual(reoffered, [],
            "time never frees a revision whose attempt is running; only its outcome does")

        // The original attempt concludes: one presentation, never a second flight.
        let settled = await reserve.settle(revision, outcome: .prepared(hasImage: false))
        XCTAssertTrue(settled)
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.outstanding, 0)
        XCTAssertEqual(snapshot.ready, 1)
        XCTAssertEqual(snapshot.preparing, 0)
        reoffered = await reserve.plan(offer: [revision])
        XCTAssertEqual(reoffered, [], "the settled revision is not offered again")
    }
}
