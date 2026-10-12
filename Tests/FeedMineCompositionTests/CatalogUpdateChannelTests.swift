import Foundation
import XCTest
@testable import FeedMineComposition

/// The authority channel's contract: one GET, "not modified" when the server says so, and an honest
/// "unavailable" — never a silent pass — when the request cannot produce a manifest. The transport is stubbed, so
/// no request leaves the machine; what is proven is the contract, not the network.
final class CatalogUpdateChannelTests: XCTestCase {
    private final class Stub: URLProtocol {
        enum Reply {
            case answer(Int, [String: String], Data)
            case failure
        }

        nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
        nonisolated(unsafe) static var requests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requests.append(request)
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            switch handler(request) {
            case .failure:
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            case .answer(let status, let headers, let body):
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                    httpVersion: "HTTP/1.1", headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}
    }

    /// A box a `@Sendable` stub can write to; the test reads it after the fetch completes.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?
        var last: String? { lock.withLock { value } }
        func set(_ new: String?) { lock.withLock { value = new } }
    }

    private let manifestJSON = """
    {"schemaVersion":1,"revision":5,"generatedAt":"2026-08-03T23:35:34Z","sourceCount":77443,"fileCount":1,
     "files":[{"path":"catalog.sqlite","bytes":10,"sha256":"\(String(repeating: "a", count: 64))"}]}
    """

    private func channel(etag: String? = nil, store: @escaping @Sendable (String?) -> Void = { _ in })
        -> CatalogUpdateChannel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return CatalogUpdateChannel(manifestURL: URL(string: "https://exemplo.test/manifest.json")!,
            session: URLSession(configuration: configuration), storedETag: { etag }, storeETag: store)
    }

    override func setUp() {
        Stub.handler = nil
        Stub.requests = []
    }

    func testAModifiedManifestIsHandedBackByteForByte() async throws {
        let body = Data(manifestJSON.utf8)
        Stub.handler = { _ in .answer(200, ["ETag": "\"v5\""], body) }
        let stored = Box()
        let result = await channel(store: { stored.set($0) }).fetch()
        guard case .manifest(let data) = result else { return XCTFail("a 200 with a manifest body is a manifest") }
        XCTAssertEqual(data, body, "the authority's own bytes are handed on")
        XCTAssertEqual(stored.last, "\"v5\"", "the validator is stored for the next conditional request")
        XCTAssertEqual(try CatalogManifest.decode(data).revision, 5)
    }

    func testAConditionalRequestSendsTheStoredValidator() async throws {
        Stub.handler = { _ in .answer(304, [:], Data()) }
        _ = await channel(etag: "\"v5\"").fetch()
        // The session may retry a 304-less path; at least one request must carry the validator.
        XCTAssertTrue(Stub.requests.contains { $0.value(forHTTPHeaderField: "If-None-Match") == "\"v5\"" })
    }

    func testANotModifiedAnswerIsNotAManifest() async {
        Stub.handler = { _ in .answer(304, [:], Data()) }
        let result = await channel().fetch()
        XCTAssertEqual(result, .notModified)
    }

    func testANon200AnswerIsUnavailableWithTheStatusCode() async {
        Stub.handler = { _ in .answer(503, [:], Data()) }
        guard case .unavailable(let reason) = await channel().fetch() else {
            return XCTFail("a 503 is unavailable, never a manifest")
        }
        XCTAssertTrue(reason.contains("503"), reason)
    }

    func testAManifestThatDoesNotDecodeIsUnavailable() async {
        Stub.handler = { _ in .answer(200, [:], Data("not a manifest".utf8)) }
        guard case .unavailable = await channel().fetch() else {
            return XCTFail("an unreadable body is unavailable, never a pass")
        }
    }

    func testATransportFailureIsUnavailable() async {
        Stub.handler = { _ in .failure }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let channel = CatalogUpdateChannel(manifestURL: URL(string: "https://exemplo.test/manifest.json")!,
            session: URLSession(configuration: configuration))
        guard case .unavailable = await channel.fetch() else {
            return XCTFail("offline is unavailable, stated, never a verified state")
        }
    }
}
