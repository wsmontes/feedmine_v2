// Owns opaque connector checkpoints and one bounded HTTP opportunity; no durable writes.
import CryptoKit
import Foundation
import FeedMineAcquisition
import FeedMineDomain

public struct SyndicationCheckpointState: Hashable, Codable, Sendable {
    public let etag: String?
    public let lastModified: String?
    public let documentFingerprint: String?
    public let nextItemIndex: Int

    public init?(etag: String?, lastModified: String?, documentFingerprint: String?, nextItemIndex: Int) {
        guard nextItemIndex >= 0,
            [etag, lastModified, documentFingerprint].allSatisfy({ $0.map { !$0.utf8.isEmpty } ?? true }),
            (documentFingerprint != nil || nextItemIndex == 0)
        else { return nil }
        self.etag = etag
        self.lastModified = lastModified
        self.documentFingerprint = documentFingerprint
        self.nextItemIndex = nextItemIndex
    }

    private enum CodingKeys: String, CodingKey { case etag, lastModified, documentFingerprint, nextItemIndex }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let state = Self(etag: try values.decodeIfPresent(String.self, forKey: .etag),
            lastModified: try values.decodeIfPresent(String.self, forKey: .lastModified),
            documentFingerprint: try values.decodeIfPresent(String.self, forKey: .documentFingerprint),
            nextItemIndex: try values.decode(Int.self, forKey: .nextItemIndex)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid checkpoint state"))
        }
        self = state
    }
}

public enum SyndicationCheckpointError: Error, Equatable, Sendable {
    case unsupportedSchema(UInt64)
    case unsupportedConnectorVersion(String)
    case malformed
}

public enum SyndicationCheckpointCodec {
    public static let serializationSchema: UInt64 = 1
    public static let connectorVersion = "feedmine-syndication/1-feedkit/10.9.4"
    public static var empty: SyndicationCheckpointState {
        SyndicationCheckpointState(etag: nil, lastModified: nil, documentFingerprint: nil, nextItemIndex: 0)!
    }
    public static func encode(_ state: SyndicationCheckpointState) throws -> AcquisitionCheckpoint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AcquisitionCheckpoint(blob: try encoder.encode(state), serializationSchema: serializationSchema,
            connectorVersion: connectorVersion)!
    }
    public static func decode(_ checkpoint: AcquisitionCheckpoint) throws -> SyndicationCheckpointState {
        guard checkpoint.serializationSchema == serializationSchema else {
            throw SyndicationCheckpointError.unsupportedSchema(checkpoint.serializationSchema)
        }
        guard checkpoint.connectorVersion.utf8.elementsEqual(connectorVersion.utf8) else {
            throw SyndicationCheckpointError.unsupportedConnectorVersion(checkpoint.connectorVersion)
        }
        do { return try JSONDecoder().decode(SyndicationCheckpointState.self, from: checkpoint.blob) }
        catch { throw SyndicationCheckpointError.malformed }
    }
}

public enum SyndicationHTTPError: Error, Equatable, Sendable {
    case nonHTTPResponse
    case unexpectedStatus(Int)
    case missingRedirectLocation(Int)
    case invalidRedirectTarget
    case redirectCapacityExceeded(Int)
    case notModifiedWithoutConditionalRequest
    case bodyTooLarge(limit: Int, actualAtLeast: Int)
    /// Kiro K-01: the endpoint or a redirect hop is not publicly routable (loopback, LAN, metadata).
    case nonPublicHost
}

/// Which hosts one feed-document opportunity may contact (Kiro K-01: review R15 applied to feed documents).
/// Feed servers are untrusted and choose redirect targets; OPML and catalog rows are untrusted input too.
internal enum SyndicationHostAccess: Sendable, Equatable {
    /// Product behaviour: the endpoint and every redirect hop must be publicly routable.
    case publicOnly
    /// Public hosts plus the exact non-public origins a development or benchmark composition authorized.
    case publicAndAuthorized(Set<SyndicationAuthorizedOrigin>)
    /// Explicit opt-in for a controlled test transport (scripted transport, URLProtocol fixture, local
    /// server). Internal on purpose: only `@testable` tests can choose it; product composition cannot.
    case controlledFixture

    init(authorizedOrigins: Set<SyndicationAuthorizedOrigin>) {
        self = authorizedOrigins.isEmpty ? .publicOnly : .publicAndAuthorized(authorizedOrigins)
    }

    func permits(_ url: URL) -> Bool {
        let isPublic = url.host.map { NetworkHostPolicy.isPubliclyRoutable($0) } ?? false
        switch self {
        case .controlledFixture: return true
        case .publicOnly: return isPublic
        case .publicAndAuthorized(let origins): return isPublic || origins.contains { $0.matches(url) }
        }
    }
}

/// One non-public HTTP origin (scheme, host, port) that a development or benchmark build authorizes
/// explicitly, e.g. an instrumented fixture server on the LAN (Kiro K-01). Matching is exact: authorizing
/// `http://192.168.1.76:8757` opens neither another port nor another LAN host, and a redirect away from it
/// into private space is still refused. Construction refuses public hosts (they need no authorization),
/// userinfo and non-HTTP schemes. Which builds may supply origins is decided by the composition root.
public struct SyndicationAuthorizedOrigin: Hashable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int

    public init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil,
            !NetworkHostPolicy.isPubliclyRoutable(host) else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = url.port ?? (scheme == "https" ? 443 : 80)
    }

    func matches(_ url: URL) -> Bool { SyndicationAuthorizedOrigin(url) == self }
}

internal protocol SyndicationHTTPTransport: Sendable {
    func execute(_ request: URLRequest, bodyByteCapacity: Int) async throws -> SyndicationHTTPHop
}
internal struct SyndicationHTTPHop: Sendable {
    let statusCode: Int
    let location: String?
    let etag: String?
    let lastModified: String?
    let body: Data
}
internal struct SyndicationHTTPDocument: Sendable {
    let body: Data
    var byteCount: Int { body.count }
    let etag: String?
    let lastModified: String?
    let redirectCount: Int
}
internal enum SyndicationHTTPOutcome: Sendable {
    case notModified
    case document(SyndicationHTTPDocument)
}
internal struct SyndicationHTTPClient: Sendable {
    let transport: any SyndicationHTTPTransport
    let redirectCapacity: Int
    var hostAccess: SyndicationHostAccess = .publicOnly

    func fetch(endpoint: URL, checkpoint: SyndicationCheckpointState, bodyByteCapacity: Int) async throws -> SyndicationHTTPOutcome {
        guard hostAccess.permits(endpoint) else { throw SyndicationHTTPError.nonPublicHost }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        if checkpoint.nextItemIndex == 0 {
            request.setValue(checkpoint.etag, forHTTPHeaderField: "If-None-Match")
            request.setValue(checkpoint.lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        var redirects = 0
        // Each traversal consumes an explicit redirect slot; no status starts a second opportunity.
        for _ in 0...redirectCapacity {
            try Task.checkCancellation()
            let hop: SyndicationHTTPHop
            do { hop = try await transport.execute(request, bodyByteCapacity: bodyByteCapacity) }
            catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            switch hop.statusCode {
            case 200:
                guard hop.body.count <= bodyByteCapacity else {
                    throw SyndicationHTTPError.bodyTooLarge(limit: bodyByteCapacity, actualAtLeast: hop.body.count)
                }
                return .document(.init(body: hop.body, etag: hop.etag, lastModified: hop.lastModified, redirectCount: redirects))
            case 304:
                guard request.value(forHTTPHeaderField: "If-None-Match") != nil ||
                    request.value(forHTTPHeaderField: "If-Modified-Since") != nil else {
                    throw SyndicationHTTPError.notModifiedWithoutConditionalRequest
                }
                return .notModified
            case 301, 302, 303, 307, 308:
                guard redirects < redirectCapacity else { throw SyndicationHTTPError.redirectCapacityExceeded(redirectCapacity) }
                guard let location = hop.location, !location.utf8.isEmpty,
                    let destination = URL(string: location, relativeTo: request.url)?.absoluteURL else {
                    throw SyndicationHTTPError.missingRedirectLocation(hop.statusCode)
                }
                guard let scheme = destination.scheme?.lowercased(), scheme == "http" || scheme == "https",
                    let host = destination.host, !host.isEmpty, destination.user == nil, destination.password == nil else {
                    throw SyndicationHTTPError.invalidRedirectTarget
                }
                // v1 lesson IN-2 / review M13: never follow a redirect from https down to http.
                if request.url?.scheme?.lowercased() == "https", scheme == "http" {
                    throw SyndicationHTTPError.invalidRedirectTarget
                }
                // Kiro K-01 (review R15 applied to feed documents): the redirect target is chosen by the
                // remote server, so every hop obeys the same host access as the endpoint itself.
                guard hostAccess.permits(destination) else { throw SyndicationHTTPError.nonPublicHost }
                request = URLRequest(url: destination, cachePolicy: .reloadIgnoringLocalCacheData)
                request.httpMethod = "GET"
                redirects += 1
            default: throw SyndicationHTTPError.unexpectedStatus(hop.statusCode)
            }
        }
        throw SyndicationHTTPError.redirectCapacityExceeded(redirectCapacity)
    }
}

internal struct URLSessionSyndicationHTTPTransport: SyndicationHTTPTransport {
    let session: URLSession
    func execute(_ request: URLRequest, bodyByteCapacity: Int) async throws -> SyndicationHTTPHop {
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: SyndicationRedirectRefusal())
            // Cancelling also stops bodies that are irrelevant to this status.
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw SyndicationHTTPError.nonHTTPResponse }
            var body = Data()
            if response.statusCode == 200 {
                let declared = response.expectedContentLength
                if declared >= 0 && declared > Int64(bodyByteCapacity) {
                    throw SyndicationHTTPError.bodyTooLarge(limit: bodyByteCapacity, actualAtLeast: Int(clamping: declared))
                }
                // The accumulator never grows past the supplied capacity; the first excess byte cancels the task.
                try await withTaskCancellationHandler {
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard body.count < bodyByteCapacity else {
                            let actual = bodyByteCapacity.addingReportingOverflow(1)
                            throw SyndicationHTTPError.bodyTooLarge(limit: bodyByteCapacity,
                                actualAtLeast: actual.overflow ? Int.max : actual.partialValue)
                        }
                        body.append(byte)
                    }
                } onCancel: { bytes.task.cancel() }
            }
            return .init(statusCode: response.statusCode, location: response.value(forHTTPHeaderField: "Location"),
                etag: response.value(forHTTPHeaderField: "ETag"), lastModified: response.value(forHTTPHeaderField: "Last-Modified"), body: body)
        } catch let error as URLError where error.code == .cancelled { throw CancellationError() }
    }
}

private final class SyndicationRedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

internal func syndicationBodyFingerprint(_ body: Data) -> String {
    "sha256:" + SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
}
