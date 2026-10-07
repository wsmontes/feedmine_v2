import XCTest
import FeedMinePublication

final class RenderContractTests: XCTestCase {
    func testTextOnlyRequiresNoMediaGeometry() throws {
        let contract = try XCTUnwrap(RenderContract(layout: .textOnly, mediaAspectRatio: nil))
        XCTAssertEqual(contract.layout, .textOnly)
        XCTAssertNil(contract.mediaAspectRatio)
        XCTAssertNil(RenderContract(layout: .textOnly, mediaAspectRatio: 1.5))
    }

    func testMediaLayoutsAcceptDefaultOrPositiveSlotGeometry() throws {
        for layout in [PublishedCardLayout.hero, .thumbnail] {
            let defaultContract = try XCTUnwrap(RenderContract(layout: layout, mediaAspectRatio: nil))
            XCTAssertEqual(defaultContract.layout, layout)
            XCTAssertNil(defaultContract.mediaAspectRatio)
            let contract = try XCTUnwrap(RenderContract(layout: layout, mediaAspectRatio: 1.5))
            XCTAssertEqual(contract.mediaAspectRatio, 1.5)
        }
    }

    func testNonpositiveAndNonfiniteRatiosAreRejected() {
        for layout in [PublishedCardLayout.hero, .thumbnail, .textOnly] {
            for ratio in [0.0, -1.0, Double.infinity, -Double.infinity, Double.nan] {
                XCTAssertNil(RenderContract(layout: layout, mediaAspectRatio: ratio))
            }
        }
    }
}
