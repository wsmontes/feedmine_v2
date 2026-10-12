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
    private let builder: ReaderDiscoveryBuilder
    private let lock = NSLock()
    private var cursor: ReaderDiscoveryCursor?
    private var finished = false
    private var discovered: [LegacyCatalogEntry] = []
    private var pages: [SyndicationAcquisitionSnapshot] = []

    public init(builder: ReaderDiscoveryBuilder, profile: ReaderDiscoveryProfile, contextKey: ContextKey) {
        self.builder = builder; self.profile = profile; self.contextKey = contextKey
    }

    public var entries: [LegacyCatalogEntry] { lock.withLock { discovered } }
    public var exhausted: Bool { lock.withLock { finished } }

    /// Registration must succeed before committing examination, so failures leave this page retryable.
    /// No suspension under the lock: connector lookup and discovery cannot race page installation.
    func advance(examinedCapacity: Int,
        materialize: ([LegacyCatalogEntry]) throws -> SyndicationAcquisitionSnapshot) throws -> ReaderDiscoveryPage? {
        try lock.withLock {
            try Task.checkCancellation()
            guard !finished else { return nil }
            let page = try builder.page(for: profile, after: cursor, examinedCapacity: examinedCapacity)
            if !page.entries.isEmpty {
                let snapshot = try materialize(page.entries)
                pages.append(snapshot)
                discovered.append(contentsOf: page.entries)
            }
            cursor = page.nextCursor
            finished = page.exhausted
            return page
        }
    }

    func targets(for context: FeedContext) throws -> [AcquisitionTarget] {
        let snapshots = lock.withLock { pages }
        return try snapshots.flatMap { try $0.eligibleTargets(for: context, skippingRevokedDiscovery: true) }
    }

    func liveSourceIDs() throws -> Set<SourceID> {
        let snapshots = lock.withLock { pages }
        return try snapshots.reduce(into: Set<SourceID>()) { sources, snapshot in
            sources.formUnion(try snapshot.discoverySourceIDs(for: FeedContext(key: contextKey)))
        }
    }

    func connector(for target: AcquisitionTarget, using transport: URLSession) -> (any FeedConnector)? {
        let snapshots = lock.withLock { pages }
        return snapshots.lazy.compactMap { $0.connector(for: target, using: transport) }.first
    }
}

extension SyndicationAcquisitionSnapshot {
    /// The resource bound applies to this examination only; future explicit opportunities resume it.
    /// Source/search contexts remain local to their declared scope and never expand the universe.
    public func advanceDiscovery(for context: FeedContext, examinedCapacity: Int) throws -> ReaderDiscoveryPage? {
        guard case .main = context.request, let discovery else { return nil }
        guard discovery.contextKey == context.key else { throw ReaderDiscoveryTraversalError.contextMismatch }
        return try discovery.advance(examinedCapacity: examinedCapacity) { entries in
            let authority = AcquisitionTargetAuthority(database: runtimeDatabase)
            let registrations = try entries.compactMap { entry -> SyndicationTargetRegistration? in
                let target = try authority.target(id: entry.targetID) ?? authority.register(id: entry.targetID,
                    connectorKind: .syndication, authorizedSources: [entry.source.id])
                // Discovery cannot revive a revoked source or override its durable generation fence.
                guard target.state == .enabled else { return nil }
                let binding = SourceBinding(id: entry.bindingID, sourceID: entry.source.id,
                    externalPrincipal: .init(connectorKind: .syndication, namespace: LegacyCatalogImport.principalNamespace,
                        value: entry.principal, role: .principal), aliases: [], generation: 1, state: .enabled)!
                return SyndicationTargetRegistration(targetID: target.id, targetGeneration: target.generation,
                    endpoint: entry.endpoint, bindings: [binding])!
            }
            return try discoverySnapshot(registrations: registrations)
        }
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
