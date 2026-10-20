import Foundation
import XCTest
import FeedMineDomain
import FeedMineRuntime
@testable import FeedMineComposition

/// The fetcher's half of the settlement evidence: it is the only layer that sees the status line, the content
/// type and the byte count, so it is the only layer that can name those causes. The classification it reports is
/// unchanged; the reason is the added fact.
final class MediaHTTPFetcherReasonTests: XCTestCase {
    private final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var headers: [String: String] = ["Content-Type": "image/png"]
        nonisolated(unsafe) static var body = Data([0x89, 0x50, 0x4E, 0x47])
        nonisolated(unsafe) static var contentLength: Int?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var fields = Self.headers
            if let length = Self.contentLength { fields["Content-Length"] = String(length) }
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                httpVersion: "HTTP/1.1", headerFields: fields)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        session = URLSession(configuration: configuration)
        Stub.status = 200
        Stub.headers = ["Content-Type": "image/png"]
        Stub.body = Data([0x89, 0x50, 0x4E, 0x47])
        Stub.contentLength = nil
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    private func failure(byteCeiling: Int = 1_000_000) async -> MediaFetchFailure? {
        do {
            _ = try await MediaHTTPFetcher(session: session)
                .fetch(URL(string: "https://images.example.com/card.png")!, byteCeiling: byteCeiling)
            return nil
        } catch {
            return error as? MediaFetchFailure
        }
    }

    func testAMissingImageStatesItsStatusAndStaysDefinitive() async throws {
        Stub.status = 404
        let observed = await failure()
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .status(404))
        XCTAssertEqual(failure.reason.traced, "status-404")
    }

    func testAServerErrorStatesItsStatusAndStaysTransient() async throws {
        Stub.status = 503
        let observed = await failure()
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .transient)
        XCTAssertEqual(failure.reason, .status(503))
    }

    func testANonImageContentTypeIsNotAnImage() async throws {
        Stub.headers = ["Content-Type": "text/html; charset=utf-8"]
        let observed = await failure()
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .notAnImage)
    }

    func testADeclaredLengthOverTheCeilingIsOverCeiling() async throws {
        Stub.contentLength = 2_000
        Stub.body = Data(repeating: 0, count: 2_000)
        let observed = await failure(byteCeiling: 1_000)
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .overCeiling)
    }

    func testABodyThatOutgrowsTheCeilingWithoutALengthIsOverCeiling() async throws {
        Stub.body = Data(repeating: 0, count: 2_000)
        let observed = await failure(byteCeiling: 1_000)
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .overCeiling)
    }

    func testANonPublicHostIsPrivateHost() async throws {
        do {
            _ = try await MediaHTTPFetcher(session: session)
                .fetch(URL(string: "http://127.0.0.1:8080/card.png")!, byteCeiling: 1_000)
            XCTFail("a loopback locator must be refused")
        } catch {
            let failure = try XCTUnwrap(error as? MediaFetchFailure)
            XCTAssertEqual(failure.classification, .definitive)
            XCTAssertEqual(failure.reason, .privateHost)
        }
    }
}
