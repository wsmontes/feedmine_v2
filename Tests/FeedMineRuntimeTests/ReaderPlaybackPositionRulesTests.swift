import Foundation
import XCTest
import FeedMineRuntime

/// V1's own numbers, stated once: the threshold a position has to pass to be worth resuming, the cadence it is
/// written at, and the tolerance that decides a seek landed before the end.
final class ReaderPlaybackPositionRulesTests: XCTestCase {
    func testTheResumeNumbersAreV1sOwn() {
        XCTAssertEqual(ReaderPlaybackPositionRules.resumeThreshold, 5,
            "V1 restored a saved position only when it was past five seconds")
        XCTAssertEqual(ReaderPlaybackPositionRules.saveInterval, 5, "and wrote it every five seconds of playback")
        XCTAssertFalse(ReaderPlaybackPositionRules.isResumable(nil))
        XCTAssertFalse(ReaderPlaybackPositionRules.isResumable(5), "more than five, not five")
        XCTAssertTrue(ReaderPlaybackPositionRules.isResumable(5.5))
        XCTAssertEqual(ReaderPlaybackPositionRules.completionTolerance, 0.5,
            "a seek half a second before the end makes an item unfinished again")
    }
}
