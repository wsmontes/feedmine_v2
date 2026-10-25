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
        XCTAssertEqual(snapshot.persistedBytes, 120, "the retained asset is not re-counted by the ignored settle")
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
        // Publishing a prepared card does not hand the budget back in this version: its bytes are still retained.
        await reserve.markPublished(prepared)
        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.persistedBytes, 500)
        let afterPublish = await reserve.plan(offer: [waiting])
        XCTAssertEqual(afterPublish, [], "the retained bytes still occupy the budget")
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
}
