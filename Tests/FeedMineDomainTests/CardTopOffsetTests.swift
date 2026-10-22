//
// File: CardTopOffsetTests.swift
// Module: FeedMineDomainTests
//
// The relative point a durable viewport carries: same geometry restores the exact point, a changed
// card height keeps the same fraction and states that the recovery is approximate, a spacing gap
// stays a point distance, and invalid values never construct.
//

import XCTest
import FeedMineDomain

final class CardTopOffsetTests: XCTestCase {
    func testSameHeightRestoresTheExactPoint() throws {
        let value = try XCTUnwrap(CardTopOffset(topDelta: -159, height: 600))
        let restored = value.restoredTopDelta(forMeasuredHeight: 600)
        XCTAssertEqual(restored.topDelta, -159)
        XCTAssertTrue(restored.exact)
        XCTAssertEqual(try XCTUnwrap(value.fraction), 159.0 / 600.0)
    }

    func testAChangedHeightKeepsTheFractionAndStatesApproximation() throws {
        let value = try XCTUnwrap(CardTopOffset(topDelta: -159, height: 600))
        let restored = value.restoredTopDelta(forMeasuredHeight: 900)
        XCTAssertEqual(restored.topDelta, -238.5)
        XCTAssertFalse(restored.exact, "a different card height is an approximate recovery")
    }

    func testASpacingGapStaysAPointDistance() throws {
        let value = try XCTUnwrap(CardTopOffset(topDelta: 8, height: 600))
        XCTAssertNil(value.fraction)
        XCTAssertEqual(value.restoredTopDelta(forMeasuredHeight: 900).topDelta, 8)
        XCTAssertTrue(value.restoredTopDelta(forMeasuredHeight: 900).exact)
        XCTAssertEqual(value.restoredTopDelta(forMeasuredHeight: 600).topDelta, 8)
    }

    func testTheCardTopBoundaryIsExactAndOnePointFurtherIsRejected() throws {
        XCTAssertEqual(try XCTUnwrap(CardTopOffset(topDelta: 0, height: 600)).topDelta, 0)
        XCTAssertNotNil(CardTopOffset(topDelta: -600, height: 600),
            "a line on the card's bottom edge still belongs to this card")
        XCTAssertNil(CardTopOffset(topDelta: -601.5, height: 600),
            "a line more than one point below the card is not its top")
    }

    func testNonFiniteAndNonPositiveHeightsNeverConstruct() {
        XCTAssertNil(CardTopOffset(topDelta: .nan, height: 600))
        XCTAssertNil(CardTopOffset(topDelta: 0, height: .infinity))
        XCTAssertNil(CardTopOffset(topDelta: 0, height: 0))
        XCTAssertNil(CardTopOffset(topDelta: 0, height: -1))
    }

    func testAMeasuredHeightThatIsNotPositiveFallsBackToTheRecordedPoint() throws {
        let value = try XCTUnwrap(CardTopOffset(topDelta: -159, height: 600))
        let restored = value.restoredTopDelta(forMeasuredHeight: 0)
        XCTAssertEqual(restored.topDelta, -159)
        XCTAssertFalse(restored.exact)
    }
}
