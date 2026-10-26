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
    /// A visit cannot pull for a target whose durable authority was withdrawn (revoked).
    case visitAuthorityWithdrawn(AcquisitionTargetID)
    case searchContextUnavailable
    /// Kiro K-05: an authorized non-public origin must be an exact http(s) origin on a non-public host.
    case invalidAuthorizedOrigin(URL)
}

public struct SyndicationAcquisitionSnapshot: Sendable {
    let discovery: ReaderDiscoveryTraversal?
    private let database: RuntimeDatabase
    private let registrations: [SyndicationTargetRegistration]
    /// S1: the registration of the one source the reader explicitly opened, and the process-scoped authority that
    /// licenses it. They are not selection and not discovery: they answer only for the source context they were
    /// armed for, and only while the arming lives.
    private let visitRegistrations: [SyndicationTargetRegistration]
    private let visitAuthority: VisitTargetAuthority?
    /// Explicitly selected sources remain reader-owned even if their managed catalogue row disappears.
    private let selectedSourceIDs: Set<SourceID>
    /// What the composition knows about each source's catalogue quality/activity and (when measured) latency.
    /// Empty is "no evidence": eligibility then keeps its supplied order.
    private let targetSignals: [SourceID: AcquisitionTargetSignal]
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
        installation: CatalogInstallation? = nil,
        targetSignals: [SourceID: AcquisitionTargetSignal] = [:],
        visitRegistrations: [SyndicationTargetRegistration] = [],
        visitAuthority: VisitTargetAuthority? = nil) throws {
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
        // A visit registration is validated against the ledger and never materialized: opening a source must create
        // no durable target, so the only durable row that may answer for it is one that already exists — and if that
        // row is revoked, the visit is refused rather than resurrecting the authority.
        let ledger = AcquisitionTargetLedger(durable: authority, visit: visitAuthority)
        for registration in visitRegistrations {
            guard seen.insert(registration.targetID).inserted else {
                throw SyndicationAcquisitionSnapshotError.duplicateTargetID(registration.targetID)
            }
            guard let resolved = try ledger.target(id: registration.targetID) else {
                throw SyndicationAcquisitionSnapshotError.missingDurableTarget(registration.targetID)
            }
            guard registration.targetGeneration == resolved.target.generation else {
                throw SyndicationAcquisitionSnapshotError.staleConfigurationGeneration(targetID: registration.targetID,
                    configured: registration.targetGeneration, durable: resolved.target.generation)
            }
            guard resolved.target.state == .enabled else {
                throw SyndicationAcquisitionSnapshotError.visitAuthorityWithdrawn(registration.targetID)
            }
            guard resolved.target.connectorKind == .syndication else {
                throw SyndicationAcquisitionSnapshotError.connectorKindMismatch(targetID: registration.targetID)
            }
        }
        self.discovery = discovery
        self.database = database
        self.registrations = registrations
        self.visitRegistrations = visitRegistrations
        self.visitAuthority = visitAuthority
        self.selectedSourceIDs = selectedSourceIDs
        self.targetSignals = targetSignals
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
        // S1: the explicitly visited source, and only inside its own context. The registration was armed for one
        // source; a `.main` opportunity (or another source's) is not the gesture that licensed it. The target is
        // read from the same ledger the coordinator uses, so a durable row (enabled or revoked) is the only answer
        // where it exists, and generation/connector fences are the durable path's.
        if case .source(let visited) = context.request {
            let ledger = AcquisitionTargetLedger(durable: AcquisitionTargetAuthority(database: database),
                visit: visitAuthority)
            for registration in visitRegistrations {
                guard registration.bindings.contains(where: { $0.sourceID == visited }) else { continue }
                if !languages.isEmpty, let language = registration.language,
                    !ReaderLanguageCode.isUndeclared(language),
                    !ReaderLanguageCode.answered(language, by: languages) { continue }
                guard let resolved = try ledger.target(id: registration.targetID),
                    resolved.target.state == .enabled,
                    resolved.target.generation == registration.targetGeneration,
                    resolved.target.connectorKind == .syndication else { continue }
                targets.append(resolved.target)
            }
        }
        var seen = Set<AcquisitionTargetID>()
        let unique = targets.filter { seen.insert($0.id).inserted }
        guard !targetSignals.isEmpty else { return unique }
        // D (spec "Estabilidade de coleta e UI"): the composition orders what it supplies, before any planner
        // sees it. `AcquisitionPlanner` is untouched — its contract is explicit that "Targets are never
        // reordered by pressure" and that the supplied order remains priority. With no signals this returns
        // `unique` unchanged, so the default is exactly the registration order.
        let sourcesByTarget = Dictionary(uniqueKeysWithValues: registrations.map {
            ($0.targetID, $0.bindings.map(\.sourceID))
        })
        return AcquisitionTargetOrdering.ordered(unique, sourcesByTarget: sourcesByTarget, signals: targetSignals)
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
        // S1: the visited source's endpoint, re-validated against a catalogue promoted after the visit was armed.
        // The registration is the same value the durable path uses; only its lifetime differs.
        if let visited = visitRegistrations.first(where: {
            $0.targetID == target.id && $0.targetGeneration == target.generation
        }), let registration = visitRegistration(visited, from: promotedReader()) {
            return SyndicationConnector(configuration: registration.configuration, session: transport,
                redirectCapacity: redirectCapacity, now: now, authorizedNonPublicOrigins: authorizedNonPublicOrigins)
        }
        return discovery?.connector(for: target, using: transport)
    }

    /// A visit registration survives a catalogue promotion, exactly as a reader-selected one does: the armed
    /// endpoint is swapped only when the **same identity** still resolves, and a missing record keeps the armed
    /// registration instead of silently withdrawing a licence a public update knows nothing about. (A renamed source
    /// is the case that made this matter: its binding principal is the anchor key, which the promoted catalogue no
    /// longer contains.) Retirement is durable `revoked` — refused by the ledger, not by this function.
    private func visitRegistration(_ registration: SyndicationTargetRegistration,
        from catalogue: LegacyCatalogReader?) -> SyndicationTargetRegistration? {
        guard let catalogue,
            let identity = registration.bindings.first?.externalPrincipal,
            identity.namespace == LegacyCatalogImport.principalNamespace else { return registration }
        guard let record = try? catalogue.source(key: identity.value) else { return registration }
        guard let updated = LegacyCatalogImport.entry(record),
            updated.targetID == registration.targetID else { return nil }
        return SyndicationTargetRegistration(targetID: registration.targetID,
            targetGeneration: registration.targetGeneration, endpoint: updated.endpoint,
            bindings: registration.bindings, language: updated.language)
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
        // Retained discovery pages carry no visit: a page is a catalogue fact, not the reader's gesture.
        visitRegistrations = []
        visitAuthority = nil
        selectedSourceIDs = original.selectedSourceIDs
        targetSignals = original.targetSignals
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

    // Page snapshots carry no traversal, so connector lookup cannot recurse into its owner. They do carry every
    // fact that decides *how* a target is fetched: the session, the redirect budget, the clock and the non-public
    // origins the composition authorized. Dropping the last one made a benchmark/discovery run fetch only the
    // association's first page: every target discovered later was refused as a non-public host before any request.
    func discoverySnapshot(registrations: [SyndicationTargetRegistration]) -> SyndicationAcquisitionSnapshot {
        SyndicationAcquisitionSnapshot(pageOf: self, registrations: registrations)
    }

    private init(pageOf original: SyndicationAcquisitionSnapshot,
        registrations: [SyndicationTargetRegistration]) {
        discovery = nil
        database = original.database
        self.registrations = registrations
        visitRegistrations = []
        visitAuthority = nil
        selectedSourceIDs = original.selectedSourceIDs
        targetSignals = original.targetSignals
        installation = original.installation
        installedFingerprint = original.installedFingerprint
        session = original.session
        redirectCapacity = original.redirectCapacity
        authorizedNonPublicOrigins = original.authorizedNonPublicOrigins
        now = original.now
    }

    internal var runtimeDatabase: RuntimeDatabase { database }

    public func makeCoordinator(backoff: AcquisitionBackoffPolicy? = nil, concurrentTargetLimit: Int = 1) -> AcquisitionCoordinator {
        AcquisitionCoordinator(database: database, connectorForTarget: { target in self.connector(for: target) },
            backoff: backoff, concurrentTargetLimit: concurrentTargetLimit, visitAuthority: visitAuthority)
    }
}
