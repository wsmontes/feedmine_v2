import XCTest
import FeedMinePublication
@testable import FeedMineRuntime

final class RunwayPolicyTests: XCTestCase {
    private func evaluate(rate: Double? = 2, latency: Double? = 3, ready: ReadyAheadAmount? = .exact(5),
        pressured: Bool = false, margin: Double = 0, forward: Bool = true, tail: Bool = false,
        bootstrap: Bool = true, flight: Bool = false, allowed: Bool = true, ceiling: Int = 100) throws -> RunwayPolicyEvaluation {
        RunwayPolicy.evaluate(facts: RunwayFacts(consumption: try XCTUnwrap(ConsumptionFacts(cardsPerSecond: rate,forwardIntent: forward,explicitTailApproach: tail)),
            replenishment: try XCTUnwrap(ReplenishmentFacts(p95Seconds: latency)),readyAmount: ready,previouslyPressured: pressured,
            localSliceInFlight: flight,unknownBootstrapAvailable: bootstrap),inputs: try XCTUnwrap(RunwayPolicyInputs(safetyFactor: 1,releaseMarginSeconds: margin)),
            resources: try XCTUnwrap(RunwayResourceFacts(localWorkAllowed: allowed,examinedCandidateCapacity: 4,readyProbeBound: 1,readyProbeCeiling: ceiling,forwardAdvanceProbeBound: 8)))
    }
    func testReserveSixteenDoesNotCapMeasuredFastScrollDemand() throws {
        let facts = RunwayFacts(consumption: try XCTUnwrap(ConsumptionFacts(cardsPerSecond: 8, forwardIntent: true, explicitTailApproach: false)),
            replenishment: try XCTUnwrap(ReplenishmentFacts(p95Seconds: 5)), readyAmount: .exact(16), previouslyPressured: false,
            localSliceInFlight: false, unknownBootstrapAvailable: true)
        let resources = try XCTUnwrap(RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 32,
            readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256, reserveCards: 16))
        let result = RunwayPolicy.evaluate(facts: facts, inputs: try XCTUnwrap(RunwayPolicyInputs(safetyFactor: 1.2, releaseMarginSeconds: 2)), resources: resources)
        XCTAssertEqual(result.coverage, .pressured(requiredCards: 48))
        XCTAssertEqual(result.action, .requestLocalSlice)
        print("T7 reserve floor=16, measured scroll=8 cards/s, replenishment p95=5s, target=48")
    }
    func testMeasuredRateAndLatencyChangeCoverageRatherThanUsingFixedCount() throws {
        XCTAssertEqual(try evaluate(ready: .exact(6)).coverage,.healthy)
        XCTAssertEqual(try evaluate().coverage,.pressured(requiredCards: 6))
        XCTAssertEqual(try evaluate(rate: 4,ready: .exact(6)).coverage,.pressured(requiredCards: 12))
        XCTAssertEqual(try evaluate(latency: 6,ready: .exact(6)).coverage,.pressured(requiredCards: 12))
        XCTAssertEqual(try evaluate().action,.requestLocalSlice)
    }
    func testHysteresisUsesExplicitPreviousPressureAndReleaseMargin() throws {
        XCTAssertEqual(try evaluate(ready: .exact(6),margin: 2).coverage,.healthy)
        XCTAssertEqual(try evaluate(ready: .exact(5),margin: 2).coverage,.pressured(requiredCards: 6))
        XCTAssertEqual(try evaluate(ready: .exact(9),pressured: true,margin: 2).coverage,.pressured(requiredCards: 10))
        XCTAssertEqual(try evaluate(ready: .exact(10),pressured: true,margin: 2).coverage,.healthy)
    }
    func testSaturatedLowerBoundProvesHealthOrRequestsLargerProbeBeforeWork() throws {
        XCTAssertEqual(try evaluate(ready: .atLeast(6)).coverage,.healthy)
        let larger = try evaluate(ready: .atLeast(5))
        XCTAssertEqual(larger.coverage,.unknown); XCTAssertEqual(larger.action,.requestReadyProbe(6))
        let limited = try evaluate(ready: .atLeast(5),bootstrap: false,ceiling: 5)
        XCTAssertEqual(limited.coverage,.unknown); XCTAssertEqual(limited.action,.hold)
        XCTAssertEqual(try evaluate(rate: 4,ready: .atLeast(5),ceiling: 8).action,.requestReadyProbe(8))
    }
    func testZeroRateAndUnknownFactsUseLogicalPressureWithoutInventingOneCardTarget() throws {
        XCTAssertEqual(try evaluate(rate: 0,latency: nil,ready: .exact(3),forward: false).coverage,.healthy)
        XCTAssertEqual(try evaluate(rate: 0,tail: true).coverage,.logicalPressure)
        XCTAssertEqual(try evaluate(rate: 0,ready: .exact(0)).coverage,.logicalPressure)
        XCTAssertEqual(try evaluate(rate: nil,ready: .exact(0)).coverage,.logicalPressure)
        XCTAssertEqual(try evaluate(latency: nil,ready: .exact(0),forward: false,tail: true).coverage,.logicalPressure)
        XCTAssertEqual(try evaluate(rate: nil,ready: .exact(3)).coverage,.unknown)
        XCTAssertEqual(try evaluate(rate: nil,ready: .exact(3)).action,.requestLocalSlice)
        XCTAssertEqual(try evaluate(rate: nil,bootstrap: false).action,.hold)
        XCTAssertEqual(try evaluate(rate: nil,forward: false).action,.hold)
    }
    func testInFlightAndResourceDenialHoldWithoutChangingPressure() throws {
        for result in [try evaluate(flight: true),try evaluate(allowed: false)] {
            XCTAssertEqual(result.coverage,.pressured(requiredCards: 6)); XCTAssertEqual(result.action,.hold)
        }
        XCTAssertEqual(try evaluate(ready: .exact(20)).action,.hold)
    }
    func testInvalidMeasuredFactsAndResourceBoundsAreRefused() {
        for n in [Double.nan,Double.infinity,-1] {
            XCTAssertNil(ConsumptionFacts(cardsPerSecond: n,forwardIntent: false,explicitTailApproach: false))
            XCTAssertNil(ReplenishmentFacts(p95Seconds: n))
            XCTAssertNil(RunwayPolicyInputs(safetyFactor: n,releaseMarginSeconds: 0))
            XCTAssertNil(RunwayPolicyInputs(safetyFactor: 1,releaseMarginSeconds: n))
        }
        XCTAssertNil(ReplenishmentFacts(p95Seconds: 0)); XCTAssertNil(RunwayPolicyInputs(safetyFactor: 0.9,releaseMarginSeconds: 0))
        for (candidate,ready,ceiling,advance) in [(0,1,1,1),(1,0,1,1),(1,2,1,1),(1,1,1,0)] {
            XCTAssertNil(RunwayResourceFacts(localWorkAllowed: true,examinedCandidateCapacity: candidate,readyProbeBound: ready,readyProbeCeiling: ceiling,forwardAdvanceProbeBound: advance))
        }
    }
    func testNearestRankP95IsOrderIndependentAndOverflowCannotProveHealth() throws {
        XCTAssertEqual(runwayP95([1,2,3,10]),10)
        XCTAssertEqual(runwayP95([10,3,1,2]),10)
        XCTAssertEqual(runwayP95(Array(1...20).map(Double.init)),19)
        XCTAssertNil(runwayP95([]))
        XCTAssertEqual(try evaluate(rate: Double.greatestFiniteMagnitude,latency: 3,ready: .atLeast(Int.max),bootstrap: false).coverage,.unknown)
    }
}

extension RunwayPolicyTests {
    /// Review F01: a stationary or unmeasured reader still gets the presented window backed.
    func testReserveFloorDrivesProactiveFillWithoutConsumptionSamples() {
        let inputs = RunwayPolicyInputs(safetyFactor: 1, releaseMarginSeconds: 0)!
        let resources = RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 8, readyProbeBound: 4,
            readyProbeCeiling: 64, forwardAdvanceProbeBound: 8, reserveCards: 6)!
        func evaluate(rate: Double?, ready: ReadyAheadAmount) -> RunwayPolicyEvaluation {
            RunwayPolicy.evaluate(facts: RunwayFacts(consumption: ConsumptionFacts(cardsPerSecond: rate, forwardIntent: false,
                explicitTailApproach: false)!, replenishment: ReplenishmentFacts(p95Seconds: nil)!, readyAmount: ready,
                previouslyPressured: false, localSliceInFlight: false, unknownBootstrapAvailable: false),
                inputs: inputs, resources: resources)
        }
        XCTAssertEqual(evaluate(rate: 0, ready: .exact(2)), .init(coverage: .pressured(requiredCards: 6), action: .requestLocalSlice))
        XCTAssertEqual(evaluate(rate: nil, ready: .exact(2)), .init(coverage: .pressured(requiredCards: 6), action: .requestLocalSlice))
        XCTAssertEqual(evaluate(rate: 0, ready: .exact(6)).action, .hold)
        XCTAssertEqual(evaluate(rate: nil, ready: .atLeast(4)), .init(coverage: .unknown, action: .requestReadyProbe(6)))
        XCTAssertNil(RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 8, readyProbeBound: 4,
            readyProbeCeiling: 5, forwardAdvanceProbeBound: 8, reserveCards: 6))
    }
}