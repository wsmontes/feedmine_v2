// Owns explicit materialization of trusted caller-supplied target/source registrations before
// constructing an immutable acquisition snapshot. Durable authority belongs to Acquisition/Persistence.
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

    public init?(targetID: AcquisitionTargetID, targetGeneration: UInt64, endpoint: URL, bindings: [SourceBinding]) {
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
}

public struct SyndicationAcquisitionSnapshot: Sendable {
    private let database: RuntimeDatabase
    private let registrations: [SyndicationTargetRegistration]
    private let session: URLSession
    private let redirectCapacity: Int
    private let now: @Sendable () -> Date

    public init(database: RuntimeDatabase, registrations: [SyndicationTargetRegistration], session: URLSession,
        redirectCapacity: Int, now: @escaping @Sendable () -> Date = { Date() }) throws {
        guard redirectCapacity >= 0 else { throw SyndicationAcquisitionSnapshotError.invalidRedirectCapacity }
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
        self.database = database
        self.registrations = registrations
        self.session = session
        self.redirectCapacity = redirectCapacity
        self.now = now
    }

    public func eligibleTargets(for context: FeedContext) throws -> [AcquisitionTarget] {
        let sourceID: SourceID?
        switch context.request {
        case .main: sourceID = nil
        case .source(let source): sourceID = source
        case .search: throw SyndicationAcquisitionSnapshotError.searchContextUnavailable
        }
        let authority = AcquisitionTargetAuthority(database: database)
        var targets: [AcquisitionTarget] = []
        for registration in registrations {
            if let sourceID, !registration.bindings.contains(where: { $0.sourceID == sourceID }) { continue }
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
            if target.state == .enabled { targets.append(target) }
        }
        return targets
    }

    public func connector(for target: AcquisitionTarget) -> (any FeedConnector)? {
        guard target.state == .enabled, target.connectorKind == .syndication,
            let registration = registrations.first(where: { $0.targetID == target.id && $0.targetGeneration == target.generation })
        else { return nil }
        return SyndicationConnector(configuration: registration.configuration, session: session,
            redirectCapacity: redirectCapacity, now: now)
    }

    internal var runtimeDatabase: RuntimeDatabase { database }

    public func makeCoordinator() -> AcquisitionCoordinator {
        AcquisitionCoordinator(database: database, connectorForTarget: { target in self.connector(for: target) })
    }
}
