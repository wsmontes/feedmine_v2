//
// File: FeedEligibleOfferTests.swift
// Module: FeedMineCompositionTests
//
// Responsibility:
//   The rule that guards the reader-facing end of the eligible offer: the end may be stated only from the
//   full settled evidence, and never from a local window, a finished acquisition round or an unavailable
//   source.
import XCTest
import FeedMineAcquisition
import FeedMineUI
import FeedMineComposition

final class FeedEligibleOfferTests: XCTestCase {
    private func settled(_ acquisition: RunwayAcquisitionCycleOutcome, localSupplyExhausted: Bool = true,
        nothingInFlight: Bool = true, noOutstandingAcquisition: Bool = true,
        noStoryAhead: Bool = true) -> FeedPresentationState.Work {
        FeedPresentationHandoff.work(settledEligibleOffer: FeedEligibleOfferSettlement(acquisition: acquisition,
            localSupplyExhausted: localSupplyExhausted, nothingInFlight: nothingInFlight,
            noOutstandingAcquisition: noOutstandingAcquisition, noStoryAhead: noStoryAhead))
    }

    /// The only evidence that can state the end: an attempt that found no eligible target, nothing being
    /// prepared, no acquisition still outstanding, and nothing ready still waiting to be published ahead.
    func testEndIsStatedOnlyWithTheFullEvidence() {
        let full = FeedEligibleOfferSettlement(acquisition: .acceptedUnavailable(.noEligibleTargets),
            localSupplyExhausted: true, nothingInFlight: true, noOutstandingAcquisition: true, noStoryAhead: true)
        XCTAssertTrue(full.isEligibleOfferExhausted)
        XCTAssertEqual(FeedPresentationHandoff.work(settledEligibleOffer: full), .endOfContent)
    }

    /// Review 2026-10-14: stories still waiting ahead of the reader are not the end, whatever the acquisition
    /// found. Without this fact the block could be drawn after a card that is not the last one, and the reader
    /// would meet the rest of the stories above it.
    func testStoriesStillAheadAreNotTheEnd() {
        XCTAssertEqual(settled(.acceptedUnavailable(.noEligibleTargets), noStoryAhead: false), .unavailable)
    }

    /// An empty local window is the provisional state: the local supply is not exhausted yet.
    func testLocalWindowIsNotTheEnd() {
        XCTAssertEqual(settled(.acceptedUnavailable(.noEligibleTargets), localSupplyExhausted: false), .unavailable)
    }

    /// A finished acquisition round is the provisional state, whatever it did to the supply.
    func testFinishedAcquisitionRoundIsNotTheEnd() {
        XCTAssertEqual(settled(.executed([])), .idle)
        XCTAssertEqual(settled(.executed([]), localSupplyExhausted: false), .idle)
    }

    /// An unavailable source — and every other non-`noEligibleTargets` disposition — is the provisional state.
    func testUnavailableSourceIsNotTheEnd() {
        XCTAssertEqual(settled(.acceptedUnavailable(.resourceDenied)), .unavailable)
        XCTAssertEqual(settled(.acceptedUnavailable(.activeGenerationConflict)), .unavailable)
        XCTAssertEqual(settled(.deferred(.resourceDenied)), .deferred)
        XCTAssertEqual(settled(.deferred(.activeGenerationConflict)), .deferred)
    }

    /// Each of the two runway facts is required on its own.
    func testNothingInFlightAndNoOutstandingAcquisitionAreRequired() {
        XCTAssertEqual(settled(.acceptedUnavailable(.noEligibleTargets), nothingInFlight: false), .unavailable)
        XCTAssertEqual(settled(.acceptedUnavailable(.noEligibleTargets), noOutstandingAcquisition: false), .unavailable)
    }
}
