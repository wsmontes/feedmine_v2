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
        nothingInFlight: Bool = true, noOutstandingAcquisition: Bool = true) -> FeedPresentationState.Work {
        FeedPresentationHandoff.work(settledEligibleOffer: FeedEligibleOfferSettlement(acquisition: acquisition,
            localSupplyExhausted: localSupplyExhausted, nothingInFlight: nothingInFlight,
            noOutstandingAcquisition: noOutstandingAcquisition))
    }

    /// The only evidence that can state the end: an attempt that found no eligible target, nothing being
    /// prepared, and no acquisition still outstanding.
    func testEndIsStatedOnlyWithTheFullEvidence() {
        let full = FeedEligibleOfferSettlement(acquisition: .acceptedUnavailable(.noEligibleTargets),
            localSupplyExhausted: true, nothingInFlight: true, noOutstandingAcquisition: true)
        XCTAssertTrue(full.isEligibleOfferExhausted)
        XCTAssertEqual(FeedPresentationHandoff.work(settledEligibleOffer: full), .endOfContent)
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
