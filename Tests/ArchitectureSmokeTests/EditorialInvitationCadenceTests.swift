//
// File: EditorialInvitationCadenceTests.swift
// Module: ArchitectureSmokeTests
//
// Responsibility:
// Round 10's offer budget as rules: the cards the reader **really** read decide when an offer may be placed, an
// offer left unanswered lengthens the wait, an answer shortens it again, hiding stops the offers and re-enabling
// restores them, and a session begins only where the reader's context changes.
//
// These are the rules the PO accepted. The rendered height of the compact form and the VoiceOver behaviour of
// the hidden block are not testable here; they belong to the simulator validation the acceptance requires.
import XCTest
import Observation
import FeedMineDomain
import FeedMineRuntime
import FeedMineUI

final class EditorialInvitationCadenceTests: XCTestCase {
    private let main = ContextKey(request: .main)
    private let other = ContextKey(request: .source(SourceID()))

    private func started() -> EditorialInvitationCadence {
        let cadence = EditorialInvitationCadence()
        cadence.beginSession(key: main, cardsTraversed: 0)
        return cadence
    }

    /// Places an offer the way the feed does: the decision first, the block only when it was allowed — and then
    /// the reader's own position reaching that card, which is what makes it an offer that was **shown**. Placing
    /// is not showing: the window draws behind and ahead of the reader (`presented(on:cardsTraversed:)`).
    @discardableResult
    private func expectOffer(_ cadence: EditorialInvitationCadence, _ subject: String, at cards: Int,
        on card: PublicationCardID = PublicationCardID(),
        file: StaticString = #filePath, line: UInt = #line) -> PublicationCardID {
        XCTAssertNil(cadence.decision(subject: subject, isAnswered: false, cardsTraversed: cards),
            "expected the budget to allow an offer for \(subject) at \(cards) cards exposed", file: file, line: line)
        cadence.offered(subject: subject, on: card, cardsTraversed: cards)
        XCTAssertTrue(cadence.presented(on: card, cardsTraversed: cards),
            "the reader's position reached the block that was placed", file: file, line: line)
        return card
    }

    private func expectRefusal(_ cadence: EditorialInvitationCadence, _ subject: String, at cards: Int,
        _ expected: EditorialInvitationCadence.Refusal,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cadence.decision(subject: subject, isAnswered: false, cardsTraversed: cards), expected,
            "at \(cards) cards exposed", file: file, line: line)
    }

    /// R1, second half (2026-10-13): a block the window placed and the reader never reached is **not** an offer
    /// shown. The window draws behind and ahead of the reader, so placement and presentation are different events;
    /// one placement stands at a time, and an unreached one is released after an interval — nothing is spent.
    func testAnOfferTheReaderNeverReachedIsNotAnOfferShown() {
        let cadence = started()
        let card = PublicationCardID()
        XCTAssertNil(cadence.decision(subject: "topic:a", isAnswered: false, cardsTraversed: 4))
        cadence.offered(subject: "topic:a", on: card, cardsTraversed: 4)

        XCTAssertEqual(cadence.offersShown, 0, "placing a block is not showing it")
        XCTAssertEqual(cadence.interval, 4, "no offer was shown, so the first offer's own distance still governs")
        XCTAssertEqual(cadence.decision(subject: "topic:b", isAnswered: false, cardsTraversed: 5),
            .offerNotYetReached(cardsRemaining: 3), "one placement stands at a time")
        XCTAssertEqual(cadence.ignoredOffers, 0, "an offer nobody met was not left unanswered")

        // The reader walked past it without meeting it: the block is released and its subject is placeable again.
        XCTAssertNil(cadence.decision(subject: "topic:b", isAnswered: false, cardsTraversed: 8),
            "the placement expired, so a new one is allowed")
        XCTAssertTrue(cadence.offeredSubjects.isEmpty, "a released placement spends nothing")
        XCTAssertNil(cadence.hosts[card])
        XCTAssertNil(cadence.decision(subject: "topic:a", isAnswered: false, cardsTraversed: 8),
            "the released subject is offered again when the reader's position is right")
    }

    /// The reader reaching the host card counts the offer — once. Turning back to the same block is one offer.
    func testReachingTheHostCardCountsTheOfferExactlyOnce() {
        let cadence = started()
        let card = PublicationCardID()
        cadence.offered(subject: "topic:a", on: card, cardsTraversed: 4)
        XCTAssertTrue(cadence.presented(on: card, cardsTraversed: 5))
        XCTAssertEqual(cadence.offersShown, 1)
        XCTAssertFalse(cadence.presented(on: card, cardsTraversed: 6), "a card met twice is one offer shown")
        XCTAssertEqual(cadence.offersShown, 1)
        XCTAssertEqual(cadence.ignoredOffers, 0)
        XCTAssertEqual(cadence.interval, 12)
        XCTAssertFalse(cadence.presented(on: PublicationCardID(), cardsTraversed: 7), "nothing was placed there")
    }

    /// R1: the budget counts cards the reader actually passed — the exposure ledger is its unit — and a card seen
    /// twice is one card read.
    func testOnlyCardsTheReaderReallyPassedCount() {
        let ledger = EditorialExposureLedger()
        let card = PublicationCardID()
        XCTAssertEqual(ledger.count, 0)
        XCTAssertFalse(ledger.wasExposed(card), "nothing has been presented yet")
        ledger.expose(card)
        ledger.expose(card)
        XCTAssertEqual(ledger.count, 1, "turning back to a card already read is still one card read")
        XCTAssertTrue(ledger.wasExposed(card), "a card the reader has passed is one an offer may not be placed on")
        ledger.expose(PublicationCardID())
        XCTAssertEqual(ledger.count, 2)
    }

    func testNewExposureInvalidatesTheInvitationEligibilityReader() {
        let ledger = EditorialExposureLedger()
        let changed = expectation(description: "a new exposure updates the invitation's eligibility")
        withObservationTracking {
            _ = ledger.count
        } onChange: {
            changed.fulfill()
        }
        ledger.expose(PublicationCardID())
        wait(for: [changed], timeout: 0.2)
    }

    func testRepeatedExposureDoesNotInvalidateTheInvitationEligibilityReader() {
        let ledger = EditorialExposureLedger()
        let card = PublicationCardID()
        ledger.expose(card)
        let changed = expectation(description: "the same card adds no exposure")
        changed.isInverted = true
        withObservationTracking {
            _ = ledger.count
        } onChange: {
            changed.fulfill()
        }
        ledger.expose(card)
        wait(for: [changed], timeout: 0.05)
    }

    func testNoOfferBeforeTheReaderHasReadEnoughCards() {
        let cadence = started()
        expectRefusal(cadence, "topic:a", at: 0, .tooSoon(cardsRemaining: 4))
        expectRefusal(cadence, "topic:a", at: 3, .tooSoon(cardsRemaining: 1))
        expectOffer(cadence, "topic:a", at: 4)
    }

    /// R2: an offer shown and left unanswered doubles the wait, and the growth has a ceiling — an interval may
    /// never become "never".
    func testAnOfferLeftUnansweredLengthensTheWaitProgressively() {
        let cadence = started()
        expectOffer(cadence, "topic:a", at: 4)
        XCTAssertEqual(cadence.interval, 12)

        expectRefusal(cadence, "topic:b", at: 15, .tooSoon(cardsRemaining: 1))
        expectOffer(cadence, "topic:b", at: 16)
        XCTAssertEqual(cadence.ignoredOffers, 1, "reaching the next offer without answering counts the first")
        XCTAssertEqual(cadence.interval, 24)

        expectRefusal(cadence, "topic:c", at: 39, .tooSoon(cardsRemaining: 1))
        expectOffer(cadence, "topic:c", at: 40)
        XCTAssertEqual(cadence.ignoredOffers, 2)
        XCTAssertEqual(cadence.interval, 48)

        expectOffer(cadence, "topic:d", at: 88)
        XCTAssertEqual(cadence.ignoredOffers, 3)
        XCTAssertEqual(cadence.interval, 96, "48 doubled is 96, which is the ceiling")
    }

    /// R3: engagement is not punished, and the first answer of a session is acted on while the reader is still
    /// reading — the next opportunity comes at the first-contact distance, not at the base interval.
    func testAnAnswerBringsTheNextOpportunityBackToAComfortableInterval() {
        let cadence = started()
        expectOffer(cadence, "topic:a", at: 4)
        expectOffer(cadence, "topic:b", at: 16)
        XCTAssertEqual(cadence.ignoredOffers, 1)

        cadence.answered(subject: "topic:b")
        XCTAssertEqual(cadence.ignoredOffers, 0)
        XCTAssertEqual(cadence.interval, 4, "the first answer buys back the first-contact distance")

        expectRefusal(cadence, "topic:c", at: 19, .tooSoon(cardsRemaining: 1))
        expectOffer(cadence, "topic:c", at: 20)
    }

    /// PO, 2026-10-14: "não quero convite imediato: precisamos preservar espaço de leitura". Only the first
    /// answer shortens the wait; a reader who answers every invitation is not filling a questionnaire.
    func testOnlyTheFirstAnswerShortensTheWait() {
        let cadence = started()
        expectOffer(cadence, "topic:a", at: 4)
        cadence.answered(subject: "topic:a")
        XCTAssertEqual(cadence.interval, 4)
        expectOffer(cadence, "topic:b", at: 8)
        XCTAssertEqual(cadence.interval, 12, "the decided distance was spent on that opportunity")

        cadence.answered(subject: "topic:b")
        XCTAssertEqual(cadence.interval, 12, "a second answer does not shorten the wait again")
        XCTAssertEqual(cadence.decision(subject: "topic:c", isAnswered: false, cardsTraversed: 19),
            .tooSoon(cardsRemaining: 1))
        expectOffer(cadence, "topic:c", at: 20)
    }

    /// R4 and R5: a subject is offered once, an answered subject is never asked, and the session's cap holds.
    func testASubjectIsAskedOnceAndTheSessionHasACap() {
        let cadence = started()
        expectOffer(cadence, "topic:a", at: 4)
        XCTAssertEqual(cadence.decision(subject: "topic:a", isAnswered: false, cardsTraversed: 100),
            .subjectAlreadyOffered)
        XCTAssertEqual(cadence.decision(subject: "topic:b", isAnswered: true, cardsTraversed: 100),
            .subjectAnswered)

        expectOffer(cadence, "topic:c", at: 16)
        expectOffer(cadence, "topic:d", at: 64)
        expectOffer(cadence, "topic:e", at: 208)
        XCTAssertEqual(cadence.offersShown, 4)
        XCTAssertEqual(cadence.decision(subject: "topic:f", isAnswered: false, cardsTraversed: 100_000),
            .sessionCapReached)
    }

    /// R6 and R7: hiding stops the offers — the block that was already offered is not withdrawn, it stops being
    /// offered — and only an explicit re-enable brings them back. Re-enabling clears the penalty; it does **not**
    /// hand out a fresh session's worth of offers.
    func testHidingStopsTheOffersAndReenablingRestoresThem() {
        let cadence = started()
        let card = expectOffer(cadence, "topic:a", at: 4)
        cadence.setHidden(true)
        expectRefusal(cadence, "topic:b", at: 500, .hidden)
        XCTAssertEqual(cadence.offersShown, 1, "hiding stops new offers; it does not retract the one that was made")
        XCTAssertEqual(cadence.hosts[card]?.subject, "topic:a",
            "the block that was offered keeps its card while hidden")

        cadence.reenabled(cardsTraversed: 500)
        XCTAssertEqual(cadence.offersShown, 1, "re-enabling does not renew the session's offer budget")
        XCTAssertEqual(cadence.ignoredOffers, 0, "and it does clear the penalty an ignored offer left behind")
        XCTAssertEqual(cadence.interval, 12, "the wait after re-enabling is the base interval, not a first offer")
        expectRefusal(cadence, "topic:b", at: 500, .tooSoon(cardsRemaining: 12))
        expectOffer(cadence, "topic:b", at: 512)
    }

    /// R5, second half (the architect's rule, 2026-10-11): re-enabling may release offers again, but it may never
    /// take the session past its cap — and the cap is the session's, not the re-enable's.
    func testReenablingNeverTakesTheSessionPastItsCap() {
        let cadence = started()
        expectOffer(cadence, "topic:a", at: 4)
        expectOffer(cadence, "topic:b", at: 16)
        expectOffer(cadence, "topic:c", at: 64)
        expectOffer(cadence, "topic:d", at: 208)
        XCTAssertEqual(cadence.offersShown, 4)

        cadence.setHidden(true)
        cadence.reenabled(cardsTraversed: 1_000)
        XCTAssertEqual(cadence.offersShown, 4, "the cap the session spent stays spent")
        expectRefusal(cadence, "topic:e", at: 100_000, .sessionCapReached)
    }

    /// R8: a foreground and an internal rebuild of the **same** context do not start a session; a context the
    /// reader has not visited does — and coming back to a visited one **resumes it** instead of renewing it.
    func testASessionBeginsOnlyWhereTheContextChangesAndIsResumedWhenItComesBack() {
        let cadence = started()
        expectOffer(cadence, "topic:a", at: 4)

        cadence.beginSession(key: main, cardsTraversed: 500)
        cadence.beginSession(key: main, cardsTraversed: 900)
        XCTAssertEqual(cadence.offersShown, 1, "a rebuild of the same context is not a new session")
        XCTAssertEqual(cadence.offeredSubjects, ["topic:a"])
        XCTAssertEqual(cadence.hosts.count, 1)

        cadence.beginSession(key: other, cardsTraversed: 900)
        XCTAssertEqual(cadence.offersShown, 0, "a context the reader has not visited starts with a full budget")
        XCTAssertTrue(cadence.offeredSubjects.isEmpty)
        XCTAssertTrue(cadence.hosts.isEmpty)
        expectRefusal(cadence, "topic:a", at: 903, .tooSoon(cardsRemaining: 1))

        // Back to the first context: its session is the one the reader left, cap included.
        cadence.beginSession(key: main, cardsTraversed: 1_000)
        XCTAssertEqual(cadence.offersShown, 1, "returning resumes the session; it does not renew the cap")
        XCTAssertEqual(cadence.offeredSubjects, ["topic:a"])
        XCTAssertEqual(cadence.hosts.count, 1)
        expectRefusal(cadence, "topic:a", at: 1_000, .subjectAlreadyOffered)
    }
}
