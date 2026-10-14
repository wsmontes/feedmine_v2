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

    /// Places an offer the way the feed does: the decision first, the offer only when it was allowed.
    @discardableResult
    private func expectOffer(_ cadence: EditorialInvitationCadence, _ subject: String, at cards: Int,
        on card: PublicationCardID = PublicationCardID(),
        file: StaticString = #filePath, line: UInt = #line) -> PublicationCardID {
        XCTAssertNil(cadence.decision(subject: subject, isAnswered: false, cardsTraversed: cards),
            "expected the budget to allow an offer for \(subject) at \(cards) cards exposed", file: file, line: line)
        cadence.offered(subject: subject, on: card, cardsTraversed: cards)
        return card
    }

    private func expectRefusal(_ cadence: EditorialInvitationCadence, _ subject: String, at cards: Int,
        _ expected: EditorialInvitationCadence.Refusal,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cadence.decision(subject: subject, isAnswered: false, cardsTraversed: cards), expected,
            "at \(cards) cards exposed", file: file, line: line)
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

    /// R3: engagement is not punished.
    func testAnAnswerBringsTheNextOpportunityBackToAComfortableInterval() {
        let cadence = started()
        expectOffer(cadence, "topic:a", at: 4)
        expectOffer(cadence, "topic:b", at: 16)
        XCTAssertEqual(cadence.ignoredOffers, 1)

        cadence.answered(subject: "topic:b")
        XCTAssertEqual(cadence.ignoredOffers, 0)
        XCTAssertEqual(cadence.interval, 12, "after an answer the wait is the base interval again")

        expectRefusal(cadence, "topic:c", at: 27, .tooSoon(cardsRemaining: 1))
        expectOffer(cadence, "topic:c", at: 28)
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
