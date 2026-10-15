//
// File: ReaderSourceIdentity.swift
// Module: FeedMineComposition
//
// Responsibility:
// The identities of the sources the **reader** brought — a pasted link, an imported OPML file. They are not in
// the shipped catalogue, so a key the reader added still has to map to the same Source, Target and Binding on
// every launch, exactly as PD-2's catalogue mapping does: deterministic UUIDs from SHA-256 over a fixed
// namespace and the feed's own identity key.
//
// The namespaces are the reader's own, never the catalogue's, so a key the reader added can never collide with
// a catalogue record, and the binding states which authority the feed came from. Without this mapping an
// imported key is written, selected and then dropped when the session is built — the source the reader added
// produces no card at all.
//
// Does not own: reading or writing the reader's sources (Persistence), resolving a link into a feed
// (Syndication/ui) or building a session (the app host).
import Foundation
import FeedMineDomain

public enum ReaderSourceIdentity {
    static let sourceNamespace = "feedmine.reader-source.source"
    static let targetNamespace = "feedmine.reader-source.target"
    static let bindingNamespace = "feedmine.reader-source.binding"
    /// External principal namespace for bindings whose key came from the reader, not from the catalogue.
    public static let principalNamespace = "feedmine-reader-source"

    /// One imported entry, in the shape the catalogue mapping produces for one record: the same identities, the
    /// same two-URL split (`id` is the identity, `requestURL` is what gets fetched).
    ///
    /// nil when the entry cannot be fetched by the syndication connector — a non-http address, no host, or
    /// credentials in the URL — so an unusable entry is refused here instead of failing acquisition later.
    public static func entry(_ imported: ReaderImportEntry, identityKey: String? = nil) -> LegacyCatalogEntry? {
        let identity = (identityKey ?? imported.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { return nil }
        guard let endpoint = URL(string: imported.requestURL), let scheme = endpoint.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = endpoint.host, !host.isEmpty,
            endpoint.user == nil, endpoint.password == nil else { return nil }
        let title = imported.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = Source(id: SourceID(rawValue: LegacyCatalogImport.stableUUID(namespace: sourceNamespace,
                key: identity)),
            displayName: title.isEmpty ? host : title, isEnabled: true)
        return LegacyCatalogEntry(source: source,
            targetID: AcquisitionTargetID(rawValue: LegacyCatalogImport.stableUUID(namespace: targetNamespace,
                key: identity)),
            bindingID: SourceBindingID(rawValue: LegacyCatalogImport.stableUUID(namespace: bindingNamespace,
                key: identity)),
            endpoint: endpoint, principal: identity, language: nil, nodeKeys: [], qualityScore: nil)
    }
}
