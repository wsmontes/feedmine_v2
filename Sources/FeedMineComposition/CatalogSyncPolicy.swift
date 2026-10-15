//
// File: CatalogSyncPolicy.swift
// Module: FeedMineComposition
//
// Responsibility:
// PD-10's sync rules as pure values: whether a background manifest check is due (no successful verification in
// the last ~24 h), and — given the public manifest and the active snapshot — whether the offer is worth acting
// on. Equal revisions mean "nothing to do" (criterion 3); a smaller revision is stale and is refused, never
// applied (criterion 4 only ever moves forward). Anything undecidable is a stated reason, never a silent pass.
//
// Does not own: performing the check (`CatalogUpdateChannel`), installing (`CatalogInstallation`) or which
// snapshot is active (the installation).
import Foundation

/// What the app remembers about the last check it completed, durable so the window survives relaunch.
public struct CatalogSyncRecord: Hashable, Sendable, Codable {
    /// The revision of the last **successful** verification, if any.
    public let verifiedRevision: Int?
    /// When that verification succeeded.
    public let verifiedAt: Date?
    /// The remote revision seen in the last successful check, even when nothing was applied.
    public let remoteRevision: Int?
    /// The validator the authority gave for the manifest last parsed, so a repeat check costs one conditional
    /// request. The channel takes this as a closure because deciding *when* to check is not its job; where the
    /// value is kept is the caller's, and here it is kept beside the ledger.
    public let etag: String?

    public init(verifiedRevision: Int? = nil, verifiedAt: Date? = nil, remoteRevision: Int? = nil,
                etag: String? = nil) {
        self.verifiedRevision = verifiedRevision
        self.verifiedAt = verifiedAt
        self.remoteRevision = remoteRevision
        self.etag = etag
    }
}

/// PD-10's decision: whether the public manifest should be consulted now.
public enum CatalogSyncDecision: Hashable, Sendable {
    /// Consult the public manifest.
    case check(remoteRevision: Int?)
    /// Do not consult; a successful verification is recent enough.
    case skip(verifiedAt: Date)
    /// Do not consult, and say why — for example no network opportunity was expressed.
    case deferReason(String)

    public var isCheck: Bool { if case .check = self { return true }; return false }
    public var isSkip: Bool { if case .skip = self { return true }; return false }
}

public enum CatalogSyncPolicy {
    /// One day, as the decision states. A wall-clock window, not a scheduler: nothing is guaranteed to run.
    public static let verificationWindow: TimeInterval = 24 * 60 * 60

    /// What to do when the app is running and can make a request. `remoteRevision` is what the resolved manifest
    /// declares when a manifest was consulted, or the record's own last-seen revision when the caller is
    /// expressing a grant rather than a manifest.
    public static func decision(record: CatalogSyncRecord, now: Date,
        remoteRevision: Int? = nil, allowed: Bool = true,
        window: TimeInterval = verificationWindow) -> CatalogSyncDecision {
        guard allowed else { return .deferReason("no network opportunity was expressed") }
        if let verifiedAt = record.verifiedAt, now.timeIntervalSince(verifiedAt) < window {
            return .skip(verifiedAt: verifiedAt)
        }
        return .check(remoteRevision: remoteRevision ?? record.remoteRevision)
    }
}

/// What one offer of a public manifest means for the installed snapshot.
public enum CatalogOfferDecision: Hashable, Sendable {
    /// The manifest declares a newer revision: it is worth fetching the payload.
    case accept(Int)
    /// The manifest equals the active revision with identical declaration: nothing to fetch, nothing to rebuild.
    case upToDate(Int)
    /// The manifest equals the active revision but declares something else: refused, and named.
    case collision(Int)
    /// The manifest is older than the active revision: stale, refused.
    case stale(Int)
}

public enum CatalogOffer {
    /// The monotonic-revision rule. `active` is the installed snapshot's manifest, when one is installed.
    public static func decide(remote: CatalogManifest, active: CatalogManifest?) -> CatalogOfferDecision {
        guard let active else { return .accept(remote.revision) }
        if remote.revision > active.revision { return .accept(remote.revision) }
        if remote.revision < active.revision { return .stale(remote.revision) }
        // The public authority declares OPML inputs; an installed snapshot additionally declares the
        // locally compiled SQLite. That derived artifact is not an editorial change to the public revision.
        // Compare the actual public declaration, not the two different layers' full manifests.
        let samePublicDeclaration = remote.schemaVersion == active.schemaVersion
            && remote.sourceCount == active.sourceCount
            && remote.opmlEntries == active.opmlEntries
        return samePublicDeclaration ? .upToDate(remote.revision) : .collision(remote.revision)
    }
}
