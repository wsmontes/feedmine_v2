// Owns explicit materialization of trusted caller-supplied target/source registrations before
// constructing acquisition configuration snapshots. Durable authority belongs to Acquisition/Persistence.
// Does not own admission, canonical membership mutations or implicit writes during target lookup.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineSyndication

public struct SyndicationTargetRegistration: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let targetGeneration: UInt64
    public let endpoint: URL
    public let bindings: [SourceBinding]
    /// An optional language declaration; nil, blank and `und` are unknown, not mismatches.
    public let language: String?

    public init?(targetID: AcquisitionTargetID, targetGeneration: UInt64, endpoint: URL, bindings: [SourceBinding],
        language: String? = nil) {
        guard targetGeneration > 0, !bindings.isEmpty,
            bindings.allSatisfy({ $0.state == .enabled && $0.connectorKind == .syndication }),
            Set(bindings.map(\.id)).count == bindings.count,
            Set(bindings.map(\.sourceID)).count == bindings.count,
            SyndicationTargetConfiguration(targetID: targetID, endpoint: endpoint,
                memberships: bindings.map { .init(sourceID: $0.sourceID, kind: .direct) }) != nil else { return nil }
        self.targetID = targetID
        self.targetGeneration = targetGeneration
        self.endpoint = endpoint
        self.bindings = bindings
        self.language = language
    }

    fileprivate var configuration: SyndicationTargetConfiguration {
        // Immutable fields already passed this exact value initializer during registration.
        SyndicationTargetConfiguration(targetID: targetID, endpoint: endpoint,
            memberships: bindings.map { .init(sourceID: $0.sourceID, kind: .direct) })!
    }
}

public enum SyndicationAcquisitionSnapshotError: Error, Equatable, Sendable {
    case duplicateTargetID(AcquisitionTargetID)
    case invalidRedirectCapacity
    case missingDurableTarget(AcquisitionTargetID)
    case staleConfigurationGeneration(targetID: AcquisitionTargetID, configured: UInt64, durable: UInt64)
    case connectorKindMismatch(targetID: AcquisitionTargetID)
    case searchContextUnavailable
    /// Kiro K-05: an authorized non-public origin must be an exact http(s) origin on a non-public host.
    case invalidAuthorizedOrigin(URL)
}

public struct SyndicationAcquisitionSnapshot: Sendable {
    let discovery: ReaderDiscoveryTraversal?
    private let database: RuntimeDatabase
    private let registrations: [SyndicationTargetRegistration]
    /// Explicitly selected sources remain reader-owned even if their managed catalogue row disappears.
    private let selectedSourceIDs: Set<SourceID>
    // Transient reference to the installed authority, independent of whether discovery is enabled.
    private let installation: CatalogInstallation?
    private let installedFingerprint: String?
    private let session: URLSession
    private let redirectCapacity: Int
    private let authorizedNonPublicOrigins: Set<SyndicationAuthorizedOrigin>
    private let now: @Sendable () -> Date

    /// `authorizedNonPublicOrigins` (Kiro K-05) defaults to none, so product acquisition reaches only publicly
    /// routable hosts. A development composition may pass the exact fixture origins it controls (for example
    /// an instrumented benchmark server on the LAN); each must be an http(s) origin on a non-public host or
    /// the snapshot is refused. Authorization never derives from catalog or OPML endpoints.
    public init(database: RuntimeDatabase, registrations: [SyndicationTargetRegistration], session: URLSession,
        redirectCapacity: Int, now: @escaping @Sendable () -> Date = { Date() },
        discovery: ReaderDiscoveryTraversal? = nil,
        authorizedNonPublicOrigins: [URL] = [],
        selectedSourceIDs: Set<SourceID> = [],
        installation: CatalogInstallation? = nil) throws {
        guard redirectCapacity >= 0 else { throw SyndicationAcquisitionSnapshotError.invalidRedirectCapacity }
        var origins = Set<SyndicationAuthorizedOrigin>()
        for url in authorizedNonPublicOrigins {
            guard let origin = SyndicationAuthorizedOrigin(url) else {
                throw SyndicationAcquisitionSnapshotError.invalidAuthorizedOrigin(url)
            }
            origins.insert(origin)
        }
        var seen = Set<AcquisitionTargetID>()
        for registration in registrations {
            guard seen.insert(registration.targetID).inserted else {
                throw SyndicationAcquisitionSnapshotError.duplicateTargetID(registration.targetID)
            }
        }
        let authority = AcquisitionTargetAuthority(database: database)
        // Preflight every registration before materializing; each write rechecks its durable fence.
        for registration in registrations {
            guard let target = try authority.target(id: registration.targetID) else {
                throw SyndicationAcquisitionSnapshotError.missingDurableTarget(registration.targetID)
            }
            guard target.generation == registration.targetGeneration else {
                throw SyndicationAcquisitionSnapshotError.staleConfigurationGeneration(targetID: target.id,
                    configured: registration.targetGeneration, durable: target.generation)
            }
            guard target.connectorKind == .syndication else {
                throw SyndicationAcquisitionSnapshotError.connectorKindMismatch(targetID: target.id)
            }
            if let sources = try authority.authorizedSources(id: target.id), sources != Set(registration.bindings.map(\.sourceID)) {
                throw AcquisitionTargetStoreError.sourceConfigurationConflict(target.id)
            }
        }
        for registration in registrations {
            _ = try authority.materializeSources(id: registration.targetID, expectedGeneration: registration.targetGeneration,
                connectorKind: .syndication, authorizedSources: Set(registration.bindings.map(\.sourceID)))
        }
        self.discovery = discovery
        self.database = database
        self.registrations = registrations
        self.selectedSourceIDs = selectedSourceIDs
        self.installation = installation
        self.installedFingerprint = installation?.activeFingerprint()
        self.session = session
        self.redirectCapacity = redirectCapacity
        self.authorizedNonPublicOrigins = origins
        self.now = now
    }

    public func eligibleTargets(for context: FeedContext) throws -> [AcquisitionTarget] {
        try eligibleTargets(for: context, skippingRevokedDiscovery: false)
    }

    func eligibleTargets(for context: FeedContext, skippingRevokedDiscovery: Bool) throws -> [AcquisitionTarget] {
        let sourceID: SourceID?
        switch context.request {
        case .main: sourceID = nil
        case .source(let source): sourceID = source
        case .search: return [] // Local search never starts remote acquisition.
        }
        // The explicit context lens takes precedence; otherwise the saved discovery answer applies.
        // No declared languages means unrestricted acquisition.
        let languages: Set<String>
        if !context.filter.languages.isEmpty {
            languages = context.filter.languages
        } else if discovery?.contextKey == context.key {
            languages = discovery?.profile.languages ?? []
        } else {
            languages = []
        }
        let authority = AcquisitionTargetAuthority(database: database)
        // Only after a catalogue promotion: static registrations from the original discovery pool
        // must be re-resolved against the newly committed authority, without revoking running targets.
        let promoted = promotedReader()
        var targets: [AcquisitionTarget] = []
        for original in registrations {
            guard let registration = try managedRegistration(original, from: promoted) else { continue }
            if let sourceID, !registration.bindings.contains(where: { $0.sourceID == sourceID }) { continue }
            // An undeclared language does not contradict an explicit choice. Reject only a known mismatch.
            if !languages.isEmpty, let language = registration.language,
                !ReaderLanguageCode.isUndeclared(language),
                !ReaderLanguageCode.answered(language, by: languages) { continue }
            guard let target = try authority.target(id: registration.targetID) else {
                throw SyndicationAcquisitionSnapshotError.missingDurableTarget(registration.targetID)
            }
            // Retained discovery pages follow revocation without suppressing healthy pages.
            // An enabled target with a changed configuration still requires a fresh snapshot.
            if skippingRevokedDiscovery, target.state != .enabled { continue }
            guard target.generation == registration.targetGeneration else {
                throw SyndicationAcquisitionSnapshotError.staleConfigurationGeneration(targetID: target.id,
                    configured: registration.targetGeneration, durable: target.generation)
            }
            guard target.connectorKind == .syndication else {
                throw SyndicationAcquisitionSnapshotError.connectorKindMismatch(targetID: target.id)
            }
            if target.state == .enabled { targets.append(target) }
        }
        if let discovery, discovery.contextKey == context.key {
            let discovered = try discovery.targets(for: context)
            if languages.isEmpty {
                targets.append(contentsOf: discovered)
            } else {
                let answering = Set(discovery.entries.filter { entry in
                    guard let language = entry.language,
                        !ReaderLanguageCode.isUndeclared(language) else { return true }
                    return ReaderLanguageCode.answered(language, by: languages)
                }.map(\.targetID))
                targets.append(contentsOf: discovered.filter { answering.contains($0.id) })
            }
        }
        var seen = Set<AcquisitionTargetID>()
        return targets.filter { seen.insert($0.id).inserted }
    }

    func discoverySourceIDs(for context: FeedContext) throws -> Set<SourceID> {
        let enabled = Set(try eligibleTargets(for: context, skippingRevokedDiscovery: true).map(\.id))
        return Set(registrations.filter { enabled.contains($0.targetID) }.flatMap { $0.bindings.map(\.sourceID) })
    }

    public func connector(for target: AcquisitionTarget) -> (any FeedConnector)? {
        connector(for: target, using: session)
    }

    // Retained catalogue pages own registrations, not the retired association's transport.
    func connector(for target: AcquisitionTarget, using transport: URLSession) -> (any FeedConnector)? {
        guard target.state == .enabled, target.connectorKind == .syndication else { return nil }
        if let original = registrations.first(where: {
            $0.targetID == target.id && $0.targetGeneration == target.generation
        }) {
            let promoted = promotedReader()
            guard let registration = try? managedRegistration(original, from: promoted) else { return nil }
            return SyndicationConnector(configuration: registration.configuration, session: transport,
                redirectCapacity: redirectCapacity, now: now, authorizedNonPublicOrigins: authorizedNonPublicOrigins)
        }
        return discovery?.connector(for: target, using: transport)
    }

    /// Consult only the committed pointer at a new acquisition opportunity. A reader without
    /// discovery still has an installed authority; the association remembers the fingerprint it opened.
    private func promotedReader() -> LegacyCatalogReader? {
        if let installation {
            guard let current = installation.activeFingerprint(), current != installedFingerprint,
                let snapshot = installation.activeSnapshot(), snapshot.fingerprint == current else { return nil }
            return try? LegacyCatalogReader(catalogURL: snapshot.catalogueURL)
        }
        // Preserve callers that own a traversal but did not supply the installer to this snapshot.
        return discovery?.promotedCatalogue().flatMap { try? LegacyCatalogReader(catalogURL: $0) }
    }

    /// Refresh an already materialized page's registration language and endpoint using the matching
    /// promoted entries. Its durable targets and connector state remain intact: this is a value copy,
    /// not a new materialization or a new cache, and in-flight pulls keep their captured connectors.
    func retaining(_ entries: [LegacyCatalogEntry]) -> SyndicationAcquisitionSnapshot {
        let currentByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.targetID, $0) })
        let retained = registrations.compactMap { registration -> SyndicationTargetRegistration? in
            guard let entry = currentByID[registration.targetID] else { return nil }
            return SyndicationTargetRegistration(targetID: registration.targetID,
                targetGeneration: registration.targetGeneration, endpoint: entry.endpoint,
                bindings: registration.bindings, language: entry.language)
        }
        return SyndicationAcquisitionSnapshot(retaining: self, registrations: retained)
    }

    private init(retaining original: SyndicationAcquisitionSnapshot,
        registrations: [SyndicationTargetRegistration]) {
        discovery = original.discovery
        database = original.database
        self.registrations = registrations
        selectedSourceIDs = original.selectedSourceIDs
        installation = original.installation
        installedFingerprint = original.installedFingerprint
        session = original.session
        redirectCapacity = original.redirectCapacity
        authorizedNonPublicOrigins = original.authorizedNonPublicOrigins
        now = original.now
    }

    /// A prior registration is still useful if it remains in the active catalogue. If its stable key
    /// now resolves to an edited URL, the next connector uses that URL without changing SourceID or
    /// the durable target generation. An absent managed discovery row is no longer eligible.
    /// Reader-selected and imported sources are never silently revoked by a public update.
    private func managedRegistration(_ registration: SyndicationTargetRegistration,
        from catalogue: LegacyCatalogReader?) throws -> SyndicationTargetRegistration? {
        guard let catalogue,
            let identity = registration.bindings.first?.externalPrincipal,
            identity.namespace == LegacyCatalogImport.principalNamespace else { return registration }
        let selected = registration.bindings.contains { selectedSourceIDs.contains($0.sourceID) }
        guard let record = try catalogue.source(key: identity.value),
            let updated = LegacyCatalogImport.entry(record),
            updated.targetID == registration.targetID,
            registration.bindings.contains(where: { $0.sourceID == updated.source.id }) else {
            return selected ? registration : nil
        }
        guard selected || record.defaultEnabled else { return nil }
        return SyndicationTargetRegistration(targetID: registration.targetID,
            targetGeneration: registration.targetGeneration, endpoint: updated.endpoint,
            bindings: registration.bindings, language: updated.language)
    }

    // Page snapshots carry no traversal, so connector lookup cannot recurse into its owner.
    func discoverySnapshot(registrations: [SyndicationTargetRegistration]) throws -> SyndicationAcquisitionSnapshot {
        try SyndicationAcquisitionSnapshot(database: database, registrations: registrations,
            session: session, redirectCapacity: redirectCapacity, now: now)
    }

    internal var runtimeDatabase: RuntimeDatabase { database }

    public func makeCoordinator(backoff: AcquisitionBackoffPolicy? = nil, concurrentTargetLimit: Int = 1) -> AcquisitionCoordinator {
        AcquisitionCoordinator(database: database, connectorForTarget: { target in self.connector(for: target) },
            backoff: backoff, concurrentTargetLimit: concurrentTargetLimit)
    }
}
