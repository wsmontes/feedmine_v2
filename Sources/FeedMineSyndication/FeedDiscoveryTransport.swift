//
// File: FeedDiscoveryTransport.swift
// Module: FeedMineSyndication
//
// Responsibility:
// The one network edge feed discovery uses, behind a protocol so a test drives it with documents instead of a
// network. The live implementation keeps V1's bounds: a byte ceiling per response that is enforced *while*
// streaming (never after the body is already in memory), a per-request timeout, and the host policy V2 already
// applies to media — a reader-supplied address must not be able to reach loopback, the LAN or a metadata
// service, and a redirect must not take it there either.
//
// Does not own: what an address means (FeedLinkInput), which feed it resolves to (FeedLinkResolver) or where a
// resolved feed is stored (Composition).
import Foundation
import FeedMineDomain

public struct FeedDiscoveryRequest: Hashable, Sendable {
    public enum Method: String, Hashable, Sendable {
        case get = "GET"
        case head = "HEAD"
    }

    public let url: URL
    public let method: Method
    /// The `Range` header for a probe that only needs the first bytes of a body.
    public let range: String?
    public let timeout: TimeInterval
    /// The most bytes this request may read; a larger response is refused, not truncated.
    public let byteCeiling: Int

    public init(url: URL, method: Method = .get, range: String? = nil, timeout: TimeInterval,
        byteCeiling: Int) {
        self.url = url
        self.method = method
        self.range = range
        self.timeout = timeout
        self.byteCeiling = byteCeiling
    }
}

public struct FeedDiscoveryResponse: Hashable, Sendable {
    public let statusCode: Int
    public let contentType: String?
    public let body: Data

    public init(statusCode: Int, contentType: String?, body: Data) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
    }

    /// A response whose body is usable: any 2xx, and a 206 for a ranged probe.
    public var isUsable: Bool { (200...299).contains(statusCode) }
}

public enum FeedDiscoveryTransportError: Error, Equatable, Sendable {
    /// The address is not one this app will fetch (non-public host, or a redirect to one).
    case refused
    /// The response announced or delivered more than the ceiling allowed.
    case tooLarge
    /// The request itself failed: no response at all.
    case unreachable
}

public protocol FeedDiscoveryTransport: Sendable {
    func send(_ request: FeedDiscoveryRequest) async throws -> FeedDiscoveryResponse
}

/// The live transport: one bounded, host-policy-guarded HTTP read.
public struct URLSessionFeedDiscoveryTransport: FeedDiscoveryTransport {
    private let session: URLSession

    public init(session: URLSession) { self.session = session }

    public func send(_ request: FeedDiscoveryRequest) async throws -> FeedDiscoveryResponse {
        guard let host = request.url.host, NetworkHostPolicy.isPubliclyRoutable(host) else {
            throw FeedDiscoveryTransportError.refused
        }
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        if let range = request.range { urlRequest.setValue(range, forHTTPHeaderField: "Range") }
        urlRequest.setValue("Feedmine/1", forHTTPHeaderField: "User-Agent")

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw FeedDiscoveryTransportError.unreachable }
            // A redirect that lands on a private host is refused after the fact: the body is never read.
            if let finalHost = http.url?.host, !NetworkHostPolicy.isPubliclyRoutable(finalHost) {
                throw FeedDiscoveryTransportError.refused
            }
            if let length = http.value(forHTTPHeaderField: "Content-Length"), let value = Int(length),
                value > request.byteCeiling {
                throw FeedDiscoveryTransportError.tooLarge
            }
            var body = Data()
            body.reserveCapacity(min(request.byteCeiling, 64_000))
            for try await chunk in bytes {
                body.append(chunk)
                if body.count > request.byteCeiling { throw FeedDiscoveryTransportError.tooLarge }
            }
            return FeedDiscoveryResponse(statusCode: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type"), body: body)
        } catch let error as FeedDiscoveryTransportError {
            throw error
        } catch {
            throw FeedDiscoveryTransportError.unreachable
        }
    }
}
