import XCTest
import FeedMinePublication
@testable import FeedMineRuntime

final class MeasuredRunwayReserveTests: XCTestCase {
    private func evaluate(rate: Double?, latency: Double?, ready: ReadyAheadAmount,
        pressured: Bool = false, tail: Bool = false) -> RunwayPolicyEvaluation {
        RunwayPolicy.evaluate(facts: RunwayFacts(
            consumption: ConsumptionFacts(cardsPerSecond: rate, forwardIntent: true, explicitTailApproach: tail)!,
            replenishment: ReplenishmentFacts(p95Seconds: latency)!, readyAmount: ready,
            previouslyPressured: pressured, localSliceInFlight: false, unknownBootstrapAvailable: false),
            inputs: RunwayPolicyInputs(safetyFactor: 1.2, releaseMarginSeconds: 2)!,
            resources: RunwayResourceFacts(localWorkAllowed: true, examinedCandidateCapacity: 32,
                readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256,
                reserveCards: 16)!)
    }

    func testMeasuredReserveAnticipatesFasterConsumptionAndSlowerReplenishment() {
        // At the same N=16 a fixed reserve is satisfied in every row. Measured coverage
        // instead starts replenishment before exhaustion when consumption or latency rises.
        let rows: [(Double, Double, RunwayPolicyEvaluation)] = [
            (2, 5, .init(coverage: .healthy, action: .hold)),
            (8, 5, .init(coverage: .pressured(requiredCards: 48), action: .requestLocalSlice)),
            (2, 10, .init(coverage: .pressured(requiredCards: 24), action: .requestLocalSlice))
        ]
        for (rate, latency, expected) in rows {
            XCTAssertEqual(evaluate(rate: rate, latency: latency, ready: .exact(16)), expected)
        }
        // Unlike a permanent floor of 16, the measured target can also shrink to 12.
        XCTAssertEqual(evaluate(rate: 2, latency: 5, ready: .exact(12)),
            .init(coverage: .healthy, action: .hold))
        XCTAssertEqual(evaluate(rate: 2, latency: 5, ready: .exact(11)),
            .init(coverage: .pressured(requiredCards: 12), action: .requestLocalSlice))
        XCTAssertEqual(evaluate(rate: 8, latency: 5, ready: .exact(48), pressured: true),
            .init(coverage: .pressured(requiredCards: 64), action: .requestLocalSlice))
    }

    func testBootstrapReserveAppliesOnlyWhileMeasurementsAreMissing() {
        for (rate, latency) in [(nil, 5.0 as Double?), (2.0 as Double?, nil)] {
            XCTAssertEqual(evaluate(rate: rate, latency: latency, ready: .exact(12)),
                .init(coverage: .pressured(requiredCards: 16), action: .requestLocalSlice))
        }
        XCTAssertEqual(evaluate(rate: 0, latency: nil, ready: .exact(12)),
            .init(coverage: .healthy, action: .hold))
        XCTAssertEqual(evaluate(rate: 0, latency: 5, ready: .exact(12), tail: true),
            .init(coverage: .logicalPressure, action: .requestLocalSlice))
    }

    func testPhysicalProbeCeilingDoesNotClampMeasuredReserveOrRestoreBootstrapFloor() {
        XCTAssertEqual(evaluate(rate: 8, latency: 50, ready: .exact(256)),
            .init(coverage: .pressured(requiredCards: 480), action: .requestLocalSlice))
        XCTAssertEqual(evaluate(rate: 8, latency: 50, ready: .atLeast(256)),
            .init(coverage: .unknown, action: .hold))
        XCTAssertEqual(evaluate(rate: Double.greatestFiniteMagnitude, latency: 5, ready: .exact(12)),
            .init(coverage: .unknown, action: .hold))
    }
}
