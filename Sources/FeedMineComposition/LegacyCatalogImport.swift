// Owns: mapping the v1 catalog into v2 Domain sources and syndication registrations (PD-2).
// Does not own: reading the catalog file (Persistence), durable target authority (Acquisition)
//   or choosing which sources a user follows (future catalog/onboarding gate).
//
// Identity (PD-2, v1 lesson CE-1): v1 source IDs were a 32-bit truncation of SHA-256 and are never
// reused. Each v2 identity is a deterministic UUID derived from SHA-256 over a fixed namespace and
// the v1 canonical key, so a catalog rebuild maps the same feed to the same Source, Target and
// Binding forever. The fetch URL stays separate from identity (v1 two-URL model).

import CryptoKit
import Foundation
import FeedMineDomain
import FeedMinePersistence

public struct LegacyCatalogEntry: Hashable, Sendable {
    public let source: Source
    public let targetID: AcquisitionTargetID
    public let bindingID: SourceBindingID
    public let endpoint: URL
    public let principal: String
    public let language: String?
    public let nodeKeys: [String]
    public let qualityScore: Int?
}

public enum LegacyCatalogImport {
    static let sourceNamespace = "feedmine.v1-catalog.source"
    static let targetNamespace = "feedmine.v1-catalog.target"
    static let bindingNamespace = "feedmine.v1-catalog.binding"
    /// External principal namespace for bindings that came from the v1 catalog.
    public static let principalNamespace = "feedmine-v1-catalog"

    /// Deterministic UUID (RFC 4122 layout, version 8 "custom") from SHA-256(namespace NUL key).
    public static func stableUUID(namespace: String, key: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data((namespace + "\u{0}" + key).utf8)).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x80
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    /// Maps one catalog record; nil when it cannot be fetched by the syndication connector.
    public static func entry(_ record: LegacyCatalogSourceRecord) -> LegacyCatalogEntry? {
        guard let endpoint = URL(string: record.requestURL), let scheme = endpoint.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = endpoint.host, !host.isEmpty,
            endpoint.user == nil, endpoint.password == nil else { return nil }
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = Source(id: SourceID(rawValue: stableUUID(namespace: sourceNamespace, key: record.key)),
            displayName: title.isEmpty ? host : title, isEnabled: record.defaultEnabled)
        return LegacyCatalogEntry(source: source,
            targetID: AcquisitionTargetID(rawValue: stableUUID(namespace: targetNamespace, key: record.key)),
            bindingID: SourceBindingID(rawValue: stableUUID(namespace: bindingNamespace, key: record.key)),
            endpoint: endpoint, principal: record.key, language: record.language, nodeKeys: record.nodeKeys,
            qualityScore: record.qualityScore)
    }

    /// Reads entries page by page in stable key order. Pages are bounded; the caller decides how many
    /// sources become active acquisition targets (registering the entire catalog at launch would be wrong).
    public static func entries(from reader: LegacyCatalogReader, limit: Int, onlyDefaultEnabled: Bool = true,
        mediaKinds: Set<String> = ["text"], pageSize: Int = 500) throws -> [LegacyCatalogEntry] {
        var result: [LegacyCatalogEntry] = []
        var after: String?
        while result.count < limit {
            let page = try reader.sources(after: after, limit: min(pageSize, limit - result.count),
                onlyDefaultEnabled: onlyDefaultEnabled, mediaKinds: mediaKinds)
            guard let last = page.last else { break }
            result += page.compactMap(entry)
            after = last.key
        }
        return result
    }
}
