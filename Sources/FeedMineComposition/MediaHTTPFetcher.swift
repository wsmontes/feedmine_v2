// Owns the concrete HTTP transport for remote card media: one bounded GET per call.
// Runtime's MediaPrefetcher owns when and what to fetch; this value only moves bytes safely.
// v1 lessons: enforce the byte ceiling *while streaming* (a missing or lying Content-Length
// cannot exhaust memory), refuse non-image responses, never follow https→http downgrades.

import Foundation

public enum MediaHTTPError: Error, Equatable, Sendable {
    case nonHTTPResponse
    case unexpectedStatus(Int)
    case notAnImage(String?)
    case tooLarge(limit: Int)
    case insecureRedirect
}

public struct MediaHTTPFetcher: Sendable {
    private let session: URLSession

    public init(session: URLSession) { self.session = session }

    public func fetch(_ url: URL, byteCeiling: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw MediaHTTPError.nonHTTPResponse }
        if url.scheme?.lowercased() == "https", http.url?.scheme?.lowercased() == "http" {
            throw MediaHTTPError.insecureRedirect
        }
        guard (200..<300).contains(http.statusCode) else { throw MediaHTTPError.unexpectedStatus(http.statusCode) }
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased()
        if let type, !type.hasPrefix("image/") && !type.hasPrefix("application/octet-stream") {
            throw MediaHTTPError.notAnImage(type)
        }
        if http.expectedContentLength > Int64(byteCeiling) { throw MediaHTTPError.tooLarge(limit: byteCeiling) }
        var data = Data()
        if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
        for try await byte in bytes {
            guard data.count < byteCeiling else { throw MediaHTTPError.tooLarge(limit: byteCeiling) }
            data.append(byte)
        }
        return data
    }
}
