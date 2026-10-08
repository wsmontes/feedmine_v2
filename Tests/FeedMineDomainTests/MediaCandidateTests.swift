import Foundation
import XCTest
import FeedMineDomain

final class MediaCandidateTests: XCTestCase {
    func testValidLocatorsRetainIdentityAndExactDeclaredEvidence() throws {
        let id = MediaCandidateID(), revision = OriginRevisionID()
        for locator in ["http://example.test/A%2fb?q=X#Y", "HTTPS://EXAMPLE.test/Image"] {
            let url = try XCTUnwrap(URL(string: locator))
            for mime in [nil, "", " Image/PNG é "] as [String?] {
                let candidate = try XCTUnwrap(MediaCandidate(id: id, originRevisionID: revision,
                    role: .cardVisual, mediaClass: .image, remoteURL: url, declaredMimeType: mime,
                    declaredPixelWidth: 200, declaredPixelHeight: 100))
                XCTAssertEqual(candidate.id, id)
                XCTAssertEqual(candidate.originRevisionID, revision)
                XCTAssertEqual(candidate.role, .cardVisual)
                XCTAssertEqual(candidate.mediaClass, .image)
                XCTAssertTrue(candidate.remoteURL.absoluteString.utf8.elementsEqual(locator.utf8))
                XCTAssertEqual(candidate.declaredMimeType?.utf8.map { $0 }, mime?.utf8.map { $0 })
                XCTAssertEqual(candidate.declaredPixelWidth, 200)
                XCTAssertEqual(candidate.declaredPixelHeight, 100)
            }
        }
        let url = URL(string: "https://example.test/a")!
        let a = try XCTUnwrap(MediaCandidate(id: id, originRevisionID: revision,
            role: .cardVisual, mediaClass: .image, remoteURL: url,
            declaredMimeType: nil, declaredPixelWidth: nil, declaredPixelHeight: nil))
        let b = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision,
            role: .cardVisual, mediaClass: .image, remoteURL: url,
            declaredMimeType: nil, declaredPixelWidth: nil, declaredPixelHeight: nil))
        XCTAssertNotEqual(a.id, b.id, "Caller identity is independent of the shared locator")
        XCTAssertNil(a.declaredPixelWidth)
        XCTAssertNil(a.declaredPixelHeight)
        XCTAssertEqual(try JSONDecoder().decode(MediaCandidateID.self,
            from: JSONEncoder().encode(id)), id)
        XCTAssertEqual(id.description, id.rawValue.uuidString)
    }

    func testInvalidLocatorOrDimensionPairIsRejected() {
        for locator in ["file:///tmp/image", "ftp://example.test/a", "/image", "https:/image", "http://"] {
            if let url = URL(string: locator) {
                XCTAssertNil(MediaCandidate(id: MediaCandidateID(), originRevisionID: OriginRevisionID(),
                    role: .cardVisual, mediaClass: .image, remoteURL: url,
                    declaredMimeType: nil, declaredPixelWidth: nil, declaredPixelHeight: nil), locator)
            }
        }
        for (width, height) in [(1, nil), (nil, 1), (0, 1), (1, 0), (-1, 1), (1, -1)] as [(Int?, Int?)] {
            XCTAssertNil(MediaCandidate(id: MediaCandidateID(), originRevisionID: OriginRevisionID(),
                role: .cardVisual, mediaClass: .image, remoteURL: URL(string: "https://example.test/a")!,
                declaredMimeType: nil, declaredPixelWidth: width, declaredPixelHeight: height))
        }
    }
}
