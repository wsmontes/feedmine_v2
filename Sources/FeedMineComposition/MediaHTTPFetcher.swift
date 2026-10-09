// Owns the concrete HTTP transport for remote card media: one bounded GET per call.
// Runtime's MediaPrefetcher owns when and what to fetch; this value only moves bytes safely.
// v1 lessons: enforce the byte ceiling *while streaming* (a missing or lying Content-Length
// cannot exhaust memory), refuse non-image responses, never follow https→http downgrades.
// Failures are classified (review F04): definitive ones settle a card as text-only; transient
// ones let the media owner try again later.
// Review R15: feed-supplied locators are untrusted. Only publicly routable hosts are contacted,
// checked before the request, on every redirect and on the final response URL.

import Foundation
import FeedMineDomain
import FeedMineRuntime

public struct MediaHTTPFetcher: Sendable {
    private let session: URLSession

    public init(session: URLSession) { self.session = session }

    public func fetch(_ url: URL, byteCeiling: Int) async throws -> Data {
        guard let host = url.host, NetworkHostPolicy.isPubliclyRoutable(host) else { throw MediaFetchFailure.definitive }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: MediaRedirectGuard(original: url))
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw MediaFetchFailure.transient }
        if url.scheme?.lowercased() == "https", http.url?.scheme?.lowercased() == "http" {
            throw MediaFetchFailure.definitive
        }
        if let final = http.url?.host, !NetworkHostPolicy.isPubliclyRoutable(final) { throw MediaFetchFailure.definitive }
        switch http.statusCode {
        case 200..<300: break
        case 408, 425, 429, 500..<600: throw MediaFetchFailure.transient
        default: throw MediaFetchFailure.definitive
        }
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased()
        if let type, !type.hasPrefix("image/") && !type.hasPrefix("application/octet-stream") {
            throw MediaFetchFailure.definitive
        }
        if http.expectedContentLength > Int64(byteCeiling) { throw MediaFetchFailure.definitive }
        var data = Data()
        if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
        for try await byte in bytes {
            guard data.count < byteCeiling else { throw MediaFetchFailure.definitive }
            data.append(byte)
        }
        return data
    }
}

/// Refuses a redirect to a non-public host or an https→http downgrade before it is followed;
/// the 3xx response then surfaces and settles as a definitive failure.
final class MediaRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let originalIsHTTPS: Bool

    init(original: URL) { originalIsHTTPS = original.scheme?.lowercased() == "https" }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest) async -> URLRequest? {
        guard let next = request.url, let scheme = next.scheme?.lowercased(),
            scheme == "https" || (scheme == "http" && !originalIsHTTPS),
            let host = next.host, NetworkHostPolicy.isPubliclyRoutable(host) else { return nil }
        return request
    }
}
