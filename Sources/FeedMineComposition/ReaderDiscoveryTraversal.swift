// Owns catalogue examination for one association/profile and its materialized snapshot pages.
// Does not own an acquisition queue, execution, scheduling, publication or reader position.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineEditorial

public enum ReaderDiscoveryTraversalError: Error, Equatable, Sendable {
    case contextMismatch
}

/// Shared by cold and active drivers through their acquisition snapshot. Recreate it when the
/// profile/catalogue changes; retaining a preview array cannot represent discovery progress.
public final class ReaderDiscoveryTraversal: @unchecked Sendable {
    public let profile: ReaderDiscoveryProfile
    public let contextKey: ContextKey
    private let installation: CatalogInstallation?
    private let lock = NSLock()
    private var builder: ReaderDiscoveryBuilder
    private var catalogueFingerprint: String?
    /// Non-nil only when the installed authority advanced beyond the builder supplied at construction.
    private var promotedCatalogueURL: URL?
    private var cursor: ReaderDiscoveryCursor?
    private var finished = false

    /// The existing materialized page runway, with each page's entries kept beside its acquisition
    /// snapshot. A promotion retains stable target/endpoint identities, refreshing their source metadata
    /// and acquisition eligibility. No second traversal/cache or durable target revocation is introduced.
    private var pages: [(entries: [LegacyCatalogEntry], snapshot: SyndicationAcquisitionSnapshot)] = []

    public init(builder: ReaderDiscoveryBuilder, profile: ReaderDiscoveryProfile, contextKey: ContextKey,
        installation: CatalogInstallation? = nil) {
        self.builder = builder
        self.profile = profile
        self.contextKey = contextKey
        self.installation = installation
        self.catalogueFingerprint = installation?.activeFingerprint()
    }

    /// A pointer change is checked only at actual discovery/acquisition opportunities. The installed
    /// snapshot remains the sole authority. Valid prepared pages are retained; a removed source or a
    /// changed endpoint/metadata no longer qualifies as work prepared for the new revision.
    private func refreshIfNeeded() {
        guard let installation, let fingerprint = installation.activeFingerprint(),
            fingerprint != catalogueFingerprint,
            let active = installation.activeSnapshot(), active.fingerprint == fingerprint else { return }
        let newReader = try? LegacyCatalogReader(catalogURL: active.catalogueURL)
        pages = pages.compactMap { old in
            let compatible = old.entries.compactMap { entry -> LegacyCatalogEntry? in
                guard let record = try? newReader?.source(key: entry.principal),
                    let updated = LegacyCatalogImport.entry(record),
                    record.defaultEnabled,
                    updated.source.id == entry.source.id, updated.targetID == entry.targetID,
                    updated.bindingID == entry.bindingID, updated.endpoint == entry.endpoint else { return nil }
                // The same endpoint and durable identity still have usable prepared acquisition work.
                // Adopt new names, language and placements for work after promotion, without rewriting
                // already published cards. A changed endpoint needs a fresh registration.
                return updated
            }
            // A retained page is reusable supply, but its original registration still contains
            // the old language. Rebind that immutable value to the promoted entry's metadata;
            // otherwise eligibility excludes e.g. en -> pt even though the entry now says pt.
            return compatible.isEmpty ? nil
                : (entries: compatible, snapshot: old.snapshot.retaining(compatible))
        }
        builder = ReaderDiscoveryBuilder(catalogURL: active.catalogueURL)
        catalogueFingerprint = fingerprint
        promotedCatalogueURL = active.catalogueURL
        cursor = nil
        finished = false
    }

    /// Nil until a promotion; the association's immutable initial registrations stay cheap on
    /// ordinary opportunities. A changed snapshot supplies the current source/endpoint authority.
    func promotedCatalogue() -> URL? {
        lock.withLock {
            refreshIfNeeded()
            return promotedCatalogueURL
        }
    }

    public var entries: [LegacyCatalogEntry] {
        lock.withLock {
            refreshIfNeeded()
            return pages.flatMap { $0.entries }
        }
    }
    public var exhausted: Bool {
        lock.withLock {
            refreshIfNeeded()
            return finished
        }
    }

    /// Registration must succeed before committing examination, so failures leave this page retryable.
    /// No suspension under the lock: connector lookup and discovery cannot race page installation.
    func advance(examinedCapacity: Int,
        materialize: ([LegacyCatalogEntry]) throws -> SyndicationAcquisitionSnapshot) throws -> ReaderDiscoveryPage? {
        try lock.withLock {
            try Task.checkCancellation()
            refreshIfNeeded()
            guard !finished else { return nil }
            let page = try builder.page(for: profile, after: cursor, examinedCapacity: examinedCapacity)
            // Pages retained across a promotion are useful supply. Re-examination advances the new
            // catalogue cursor without re-registering or re-fetching identical prepared targets.
            let known = Set(pages.flatMap { $0.entries }.map(\.targetID))
            let additions = page.entries.filter { !known.contains($0.targetID) }
            if !additions.isEmpty {
                let snapshot = try materialize(additions)
                pages.append((entries: additions, snapshot: snapshot))
            }
            cursor = page.nextCursor
            finished = page.exhausted
            return page
        }
    }

    /// A pool a profile named — read **beside** the walk, which is what a warm launch does with it — materialized
    /// as supply through the same owner an examined page goes through: durable target taken or registered, revoked
    /// source refused, endpoint and language of the entry carried into the registration. It does **not** move
    /// `cursor`: the walk still examines the catalogue where it was, because adopting a preview is not evidence
    /// that those sources were examined, and pretending otherwise would skip the pages in between. Entries whose
    /// target is already prepared (by a page or by an earlier adoption) are not registered twice, and the ones the
    /// authority refused are not recorded at all — a revoked source must not become a permanent "already
    /// examined" here. Returns the entries that really became supply.
    func adopt(_ entries: [LegacyCatalogEntry],
        materialize: ([LegacyCatalogEntry]) throws
            -> (installed: [LegacyCatalogEntry], snapshot: SyndicationAcquisitionSnapshot)) throws
        -> [LegacyCatalogEntry] {
        try lock.withLock {
            try Task.checkCancellation()
            refreshIfNeeded()
            let known = Set(pages.flatMap { $0.entries }.map(\.targetID))
            let candidates = entries.filter { !known.contains($0.targetID) }
            guard !candidates.isEmpty else { return [] }
            let (installed, snapshot) = try materialize(candidates)
            guard !installed.isEmpty else { return [] }
            pages.append((entries: installed, snapshot: snapshot))
            return installed
        }
    }

    func targets(for context: FeedContext) throws -> [AcquisitionTarget] {
        try lock.withLock {
            refreshIfNeeded()
            return try pages.flatMap { page in
                let allowed = Set(page.entries.map(\.targetID))
                return try page.snapshot.eligibleTargets(for: context, skippingRevokedDiscovery: true)
                    .filter { allowed.contains($0.id) }
            }
        }
    }

    func liveSourceIDs() throws -> Set<SourceID> {
        try lock.withLock {
            refreshIfNeeded()
            var ids = Set<SourceID>()
            for page in pages {
                let enabled = Set(try page.snapshot.eligibleTargets(
                    for: FeedContext(key: contextKey), skippingRevokedDiscovery: true).map(\.id))
                ids.formUnion(page.entries.filter { enabled.contains($0.targetID) }.map { $0.source.id })
            }
            return ids
        }
    }

    func connector(for target: AcquisitionTarget, using transport: URLSession) -> (any FeedConnector)? {
        lock.withLock {
            refreshIfNeeded()
            for page in pages where page.entries.contains(where: { $0.targetID == target.id }) {
                if let connector = page.snapshot.connector(for: target, using: transport) { return connector }
            }
            return nil
        }
    }
}

extension SyndicationAcquisitionSnapshot {
    /// The resource bound applies to this examination only; future explicit opportunities resume it.
    /// Source/search contexts remain local to their declared scope and never expand the universe.
    public func advanceDiscovery(for context: FeedContext, examinedCapacity: Int) throws -> ReaderDiscoveryPage? {
        guard case .main = context.request, let discovery else { return nil }
        guard discovery.contextKey == context.key else { throw ReaderDiscoveryTraversalError.contextMismatch }
        return try discovery.advance(examinedCapacity: examinedCapacity) { entries in
            try materialization(of: entries).snapshot
        }
    }

    /// The pool a launch read **beside** the walk — for a warm launch, the one read behind the reader's own
    /// window — made supply through the same materialization an examined page goes through, and without moving the
    /// walk's cursor. Returns the entries that really became supply: the authority's own refusals are not in it.
    public func adoptDiscovered(_ entries: [LegacyCatalogEntry]) throws -> [LegacyCatalogEntry] {
        guard let discovery else { return [] }
        return try discovery.adopt(entries) { try self.materialization(of: $0) }
    }

    /// The one materialization discovery goes through, examination and adoption alike: the durable target is taken
    /// or registered, a revoked target is refused (discovery cannot revive a source or override its durable
    /// generation fence), and the registration carries the entry's own endpoint and language. `installed` is
    /// exactly the entries that became supply — what a caller may publish as discovered.
    private func materialization(of entries: [LegacyCatalogEntry])
        throws -> (installed: [LegacyCatalogEntry], snapshot: SyndicationAcquisitionSnapshot) {
        let authority = AcquisitionTargetAuthority(database: runtimeDatabase)
        var installed: [LegacyCatalogEntry] = []
        let registrations = try entries.compactMap { entry -> SyndicationTargetRegistration? in
            let target = try authority.target(id: entry.targetID) ?? authority.register(id: entry.targetID,
                connectorKind: .syndication, authorizedSources: [entry.source.id])
            guard target.state == .enabled else { return nil }
            guard let binding = SourceBinding(id: entry.bindingID, sourceID: entry.source.id,
                externalPrincipal: .init(connectorKind: .syndication, namespace: LegacyCatalogImport.principalNamespace,
                    value: entry.principal, role: .principal), aliases: [], generation: 1, state: .enabled),
                let registration = SyndicationTargetRegistration(targetID: target.id,
                    targetGeneration: target.generation, endpoint: entry.endpoint, bindings: [binding],
                    language: entry.language) else { return nil }
            installed.append(entry)
            return registration
        }
        return (installed, try discoverySnapshot(registrations: registrations))
    }

    /// Eligibility grows with the examined profile, while all nominal policy identity stays fixed.
    /// Resource capacity is never a permanent selected-source restriction.
    func policyIncludingDiscovery(_ policy: ResolvedSelectionPolicy) throws -> ResolvedSelectionPolicy {
        guard let discovery, discovery.contextKey == policy.contextKey,
            case .selectedSources(let sources) = policy.eligibility else { return policy }
        return ResolvedSelectionPolicy(contextKey: policy.contextKey,
            userSelectionVersion: policy.userSelectionVersion, eligibilityPolicyVersion: policy.eligibilityPolicyVersion,
            scoringPolicyVersion: policy.scoringPolicyVersion, sequencingPolicyVersion: policy.sequencingPolicyVersion,
            exposurePolicyVersion: policy.exposurePolicyVersion, selectionSchemaVersion: policy.selectionSchemaVersion,
            eligibility: .selectedSources(sources.union(try discovery.liveSourceIDs())),
            scoring: policy.scoring, sequencing: policy.sequencing, exposure: policy.exposure)
    }
}
