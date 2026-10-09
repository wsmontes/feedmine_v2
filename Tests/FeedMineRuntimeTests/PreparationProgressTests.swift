import XCTest
import FeedMineRuntime

/// PD-3: preparation evidence is real, bounded, and its estimate is derived from measurements.
final class PreparationProgressTests: XCTestCase {
    func testQuietHTTPSuccessIsNotPreparationReadiness() {
        let progress = PreparationProgress(startedAt: 0).applying(.contacting(id: "a", name: "A"), at: 0)
            .applying(.settled(id: "a", contributed: false, reachable: true), at: 1)
        XCTAssertNil(progress.estimatedRemainingSeconds)
        XCTAssertFalse(progress.isNearlyReady)
    }
    func testSourcesHeadlinesAndMeasuredEstimate() {
        var p = PreparationProgress(startedAt: 100, headlineCapacity: 3)
        XCTAssertNil(p.estimatedRemainingSeconds); XCTAssertFalse(p.isNearlyReady)
        p = p.applying(.contacting(id: "a", name: "A"), at: 100)
            .applying(.contacting(id: "b", name: "B"), at: 100)
            .applying(.contacting(id: "c", name: "C"), at: 100)
        XCTAssertEqual(p.sources.map(\.state), [.contacting, .contacting, .contacting])
        p = p.applying(.settled(id: "a", contributed: true, reachable: true), at: 104)
        // One settled in 4 s, two pending → 8 s remaining, more than the 4 s spent.
        XCTAssertNil(p.estimatedRemainingSeconds)
        p = p.applying(.prepared(cards: 1), at: 104)
        XCTAssertEqual(p.estimatedRemainingSeconds, 8); XCTAssertFalse(p.isNearlyReady)
        p = p.applying(.settled(id: "b", contributed: false, reachable: false), at: 106)
        XCTAssertEqual(p.estimatedRemainingSeconds, 3); XCTAssertTrue(p.isNearlyReady)
        XCTAssertEqual(p.sources.map(\.state), [.contributed, .unreachable, .contacting])
        XCTAssertEqual(p.contributingSources, 1)
        p = p.applying(.admitted(headlines: ["One", "Two"]), at: 106).applying(.admitted(headlines: ["Three", "Two", "Four", ""]), at: 107)
        XCTAssertEqual(p.headlines, ["Three", "Four", "One"])
    }
}
