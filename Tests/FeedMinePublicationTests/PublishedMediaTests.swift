import XCTest
import FeedMineMedia

final class PublishedMediaTests: XCTestCase {
    func testKeyRejectsOnlyEmptyStringAndPreservesOpaqueValue() throws {
        XCTAssertNil(PublishedMediaKey(rawValue: ""))
        for raw in ["asset:opaque-É", " ", "\n", "arbitrary/value?x=1"] {
            let key = try XCTUnwrap(PublishedMediaKey(rawValue: raw))
            XCTAssertEqual(key.rawValue, raw)
            XCTAssertEqual(key.description, raw)
        }
    }

    func testAbsentDimensionsAndNoneMediaAreValid() throws {
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: "local-asset"))
        let ref = try XCTUnwrap(PublishedMediaRef(key: key, pixelWidth: nil, pixelHeight: nil, mimeType: nil))
        XCTAssertEqual(ref.key, key)
        XCTAssertNil(ref.aspectRatio)
        XCTAssertNil(ref.mimeType)
        XCTAssertNil(PublishedMediaSet.none.primary)
        XCTAssertEqual(PublishedMediaSet(primary: nil), .none)
        XCTAssertEqual(PublishedMediaSet(primary: ref).primary, ref)
    }

    func testPositiveDimensionsPreserveMetadataAndDeriveRatio() throws {
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: "opaque"))
        let ref = try XCTUnwrap(PublishedMediaRef(key: key, pixelWidth: 300, pixelHeight: 200, mimeType: "image/custom"))
        XCTAssertEqual(ref.pixelWidth, 300)
        XCTAssertEqual(ref.pixelHeight, 200)
        XCTAssertEqual(ref.mimeType, "image/custom")
        XCTAssertEqual(try XCTUnwrap(ref.aspectRatio), 1.5, accuracy: 0.000001)
    }

    func testPartialZeroAndNegativeDimensionsAreRejected() throws {
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: "opaque"))
        let invalid: [(Int?, Int?)] = [(1, nil), (nil, 1), (0, 1), (1, 0), (-1, 1), (1, -1), (0, 0), (-1, -1)]
        for (width, height) in invalid {
            XCTAssertNil(PublishedMediaRef(key: key, pixelWidth: width, pixelHeight: height, mimeType: nil))
        }
    }
}
