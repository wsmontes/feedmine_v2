import Foundation
import XCTest
import FeedMineDomain
import FeedMineMedia
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

    /// The terms an attempt runs on: `affordable` is what fits the wait, `safetyCeiling` is what may be transferred
    /// at all. Stated apart so a test never has to conflate the two.
    private func budget(affordable: Int = 50_000, safetyCeiling: Int = 12_000_000,
        waitSeconds: Double? = 0.5) -> MediaByteBudget {
        MediaByteBudget(affordableBytes: affordable, source: .dynamic, measuredBytesPerSecond: 100_000,
            waitSeconds: waitSeconds, safetyCeilingBytes: safetyCeiling)
    }

    /// The bytes the real fetcher returned, or the typed failure it stated.
    private func result(_ budget: MediaByteBudget) async -> Result<Data, MediaFetchFailure> {
        do {
            return .success(try await MediaHTTPFetcher(session: session)
                .fetch(URL(string: "https://images.example.com/card.png")!, budget: budget))
        } catch {
            return .failure(error as? MediaFetchFailure ?? MediaFetchFailure(.transient, reason: .unknown))
        }
    }

    private func failure(_ budget: MediaByteBudget) async -> MediaFetchFailure? {
        if case .failure(let failure) = await result(budget) { return failure }
        return nil
    }

    func testAMissingImageStatesItsStatusAndStaysDefinitive() async throws {
        Stub.status = 404
        let observed = await failure(budget())
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .status(404))
        XCTAssertEqual(failure.reason.traced, "status-404")
    }

    func testAServerErrorStatesItsStatusAndStaysTransient() async throws {
        Stub.status = 503
        let observed = await failure(budget())
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .transient)
        XCTAssertEqual(failure.reason, .status(503))
    }

    func testANonImageContentTypeIsNotAnImage() async throws {
        Stub.headers = ["Content-Type": "text/html; charset=utf-8"]
        let observed = await failure(budget(safetyCeiling: 1_000_000))
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .notAnImage)
    }

    func testADeclaredLengthOverTheSafetyCeilingIsOverCeiling() async throws {
        Stub.contentLength = 2_000
        Stub.body = Data(repeating: 0, count: 2_000)
        let observed = await failure(budget(safetyCeiling: 1_000))
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .overCeiling)
    }

    func testABodyThatOutgrowsTheSafetyCeilingWithoutALengthIsOverCeiling() async throws {
        Stub.body = Data(repeating: 0, count: 2_000)
        let observed = await failure(budget(safetyCeiling: 1_000))
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .overCeiling)
    }

    /// Product decision: the dynamic budget must not reject the typical image. 3 MB is inside the 12 MB safety
    /// ceiling, so it is fetched even though only 50 KB fitted the wait that used to refuse it. The owner's time
    /// allowance — not the byte count — is what bounds such an attempt.
    func testAnImageAboveTheAffordableBytesButInsideTheSafetyCeilingIsFetched() async throws {
        Stub.contentLength = 3_000_000
        Stub.body = Data(repeating: 0xAB, count: 3_000_000)
        guard case .success(let data) = await result(budget(affordable: 50_000, safetyCeiling: 12_000_000))
        else { return XCTFail("an image above the affordable bytes must be fetched, never refused") }
        XCTAssertEqual(data.count, 3_000_000)
    }

    /// The safety ceiling still protects: 13 MB is refused outright, whatever the wait would have allowed.
    func testAnImageOverTheSafetyCeilingIsRefusedEvenWhenTheWaitWouldAllowIt() async throws {
        Stub.contentLength = 13_000_000
        Stub.body = Data(repeating: 0, count: 16)
        let observed = await failure(budget(affordable: 20_000_000, safetyCeiling: 12_000_000))
        let failure = try XCTUnwrap(observed)
        XCTAssertEqual(failure.classification, .definitive)
        XCTAssertEqual(failure.reason, .overCeiling)
    }

    func testANonPublicHostIsPrivateHost() async throws {
        do {
            _ = try await MediaHTTPFetcher(session: session)
                .fetch(URL(string: "http://127.0.0.1:8080/card.png")!, budget: budget(safetyCeiling: 1_000))
            XCTFail("a loopback locator must be refused")
        } catch {
            let failure = try XCTUnwrap(error as? MediaFetchFailure)
            XCTAssertEqual(failure.classification, .definitive)
            XCTAssertEqual(failure.reason, .privateHost)
        }
    }
}
