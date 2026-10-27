import CoreGraphics
import XCTest
@testable import FeedMineRuntime

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

    /// The page's media facts: prepared is monotonic within one preparation, pending is the **current** count of
    /// undecided revisions (so it may fall to zero), and previews merge by published key without duplicates.
    func testMediaFactsAreMonotonicForPreparedAndCurrentForPending() {
        var p = PreparationProgress(startedAt: 0)
        XCTAssertEqual(p.imagesPrepared, 0); XCTAssertEqual(p.imagesPending, 0); XCTAssertTrue(p.previewImages.isEmpty)
        p = p.applying(.media(prepared: 2, pending: 5, previews: []), at: 1)
        XCTAssertEqual(p.imagesPrepared, 2); XCTAssertEqual(p.imagesPending, 5)
        // A decision is never un-made, but pending falls as revisions settle.
        p = p.applying(.media(prepared: 1, pending: 3, previews: []), at: 2)
        XCTAssertEqual(p.imagesPrepared, 2); XCTAssertEqual(p.imagesPending, 3)
        p = p.applying(.media(prepared: 3, pending: 0, previews: []), at: 3)
        XCTAssertEqual(p.imagesPrepared, 3); XCTAssertEqual(p.imagesPending, 0)
    }

    /// Previews are bounded and deduplicated by published key: the page draws exactly the pixels it was handed, once.
    func testPreviewImagesAreBoundedAndDeduplicated() throws {
        func image(_ key: String) throws -> PresentationImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let cg = try XCTUnwrap(context.makeImage())
            return PresentationImage(key: key, cgImage: cg)
        }
        var p = PreparationProgress(startedAt: 0, previewImageCapacity: 3)
        p = p.applying(.media(prepared: 2, pending: 4, previews: [try image("a"), try image("b")]), at: 1)
        XCTAssertEqual(p.previewImages.map(\.key), ["a", "b"])
        // Re-stating the same pixels adds nothing; a new one is prepended-kept after the fresh list.
        p = p.applying(.media(prepared: 3, pending: 2, previews: [try image("a"), try image("c")]), at: 2)
        XCTAssertEqual(p.previewImages.map(\.key), ["a", "c", "b"])
        p = p.applying(.media(prepared: 5, pending: 0, previews: [try image("d"), try image("e")]), at: 3)
        XCTAssertEqual(p.previewImages.count, 3, "the page never holds more than its capacity")
        XCTAssertEqual(p.previewImages.map(\.key), ["d", "e", "a"])
    }
}
