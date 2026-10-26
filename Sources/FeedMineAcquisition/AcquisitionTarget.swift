// Semantic target/checkpoint facts mapped from durable mechanical authority.
import Foundation
import FeedMineDomain
import FeedMinePersistence

public enum AcquisitionTargetState: String, Hashable, Sendable {
    case enabled
    case revoked
}

public struct AcquisitionCheckpoint: Hashable, Sendable {
    public let blob: Data
    public let serializationSchema: UInt64
    public let connectorVersion: String
    public init?(blob: Data, serializationSchema: UInt64, connectorVersion: String) {
        guard serializationSchema > 0, !connectorVersion.utf8.isEmpty else { return nil }
        self.blob = blob
        self.serializationSchema = serializationSchema
        self.connectorVersion = connectorVersion
    }
}

public struct AcquisitionTarget: Hashable, Sendable {
    public let id: AcquisitionTargetID
    public let connectorKind: ConnectorKind
    public let generation: UInt64
    public let state: AcquisitionTargetState
    public let checkpointRevision: UInt64
    public let checkpoint: AcquisitionCheckpoint?
    public init?(id: AcquisitionTargetID, connectorKind: ConnectorKind, generation: UInt64,
        state: AcquisitionTargetState, checkpointRevision: UInt64, checkpoint: AcquisitionCheckpoint?) {
        guard !connectorKind.rawValue.utf8.isEmpty, generation > 0 else { return nil }
        self.id = id
        self.connectorKind = connectorKind
        self.generation = generation
        self.state = state
        self.checkpointRevision = checkpointRevision
        self.checkpoint = checkpoint
    }
}

/// Process-scoped authority for an **explicit visit** to one source (S1). It has the same responsibility the durable
/// authority has — say whether a target may be pulled, for which sources, and at which cursor — with a different
/// lifetime: the visit, not the reader's selection. Nothing here is written to storage, so visiting a source can
/// neither enable its endpoint nor survive a relaunch; only the payload the admission already owns is durable.
///
/// It never answers for a target the durable authority knows: a durable row is the only authority for that target
/// (a revoked row included), which is what keeps a visit from resurrecting withdrawn authority.
public final class VisitTargetAuthority: @unchecked Sendable {
    private final class Armed {
        var target: AcquisitionTarget
        let authorizedSources: Set<SourceID>
        init(target: AcquisitionTarget, authorizedSources: Set<SourceID>) {
            self.target = target
            self.authorizedSources = authorizedSources
        }
    }

    private let lock = NSLock()
    private var armed: [AcquisitionTargetID: Armed] = [:]

    public init() {}

    /// Arms exactly one target for this visit. Generation starts at 1 and only ever grows through this object;
    /// a replaced arming is a new authority, never an edited one.
    @discardableResult
    public func arm(targetID: AcquisitionTargetID, connectorKind: ConnectorKind = .syndication,
        authorizedSources: Set<SourceID>, sourceID: SourceID, generation: UInt64 = 1) -> AcquisitionTarget? {
        guard !authorizedSources.isEmpty, authorizedSources.contains(sourceID),
            let target = AcquisitionTarget(id: targetID, connectorKind: connectorKind, generation: generation,
                state: .enabled, checkpointRevision: 0, checkpoint: nil) else { return nil }
        lock.lock(); defer { lock.unlock() }
        armed[targetID] = Armed(target: target, authorizedSources: authorizedSources)
        return target
    }

    public func target(id: AcquisitionTargetID) -> AcquisitionTarget? {
        lock.lock(); defer { lock.unlock() }
        return armed[id]?.target
    }

    public func authorizedSources(id: AcquisitionTargetID) -> Set<SourceID>? {
        lock.lock(); defer { lock.unlock() }
        return armed[id]?.authorizedSources
    }

    public var isArmed: Bool {
        lock.lock(); defer { lock.unlock() }
        return !armed.isEmpty
    }

    /// Advances the in-memory cursor only if this is still the armed generation at the revision the pull read.
    /// `nil` is a retired visit, and the caller must not treat the batch as settled.
    @discardableResult
    public func compareAndSwapCheckpoint(id: AcquisitionTargetID, expectedGeneration: UInt64,
        expectedCheckpointRevision: UInt64, next: AcquisitionCheckpoint) -> AcquisitionTarget? {
        lock.lock(); defer { lock.unlock() }
        guard let state = armed[id], state.target.state == .enabled,
            state.target.generation == expectedGeneration,
            state.target.checkpointRevision == expectedCheckpointRevision,
            let updated = AcquisitionTarget(id: state.target.id, connectorKind: state.target.connectorKind,
                generation: state.target.generation, state: .enabled,
                checkpointRevision: expectedCheckpointRevision + 1, checkpoint: next) else { return nil }
        state.target = updated
        return updated
    }

    /// The visit is over: no target this object armed answers any more. In-flight pulls settle as `.cancelled`.
    public func revokeAll() {
        lock.lock(); defer { lock.unlock() }
        armed.removeAll()
    }
}

/// Where a target's authority came from. The durable row always wins; a visit only answers where no durable row
/// exists, so the two lifetimes never compete for the same target.
public enum AcquisitionTargetOrigin: Hashable, Sendable {
    case durable
    case visit
}

public struct AcquisitionTargetLedger: Sendable {
    public let durable: AcquisitionTargetAuthority
    public let visit: VisitTargetAuthority?

    public init(durable: AcquisitionTargetAuthority, visit: VisitTargetAuthority? = nil) {
        self.durable = durable
        self.visit = visit
    }

    public init(database: RuntimeDatabase, visit: VisitTargetAuthority? = nil) {
        self.init(durable: AcquisitionTargetAuthority(database: database), visit: visit)
    }

    /// Durable first, and only its absence lets the visit answer. A durable `revoked` row is withdrawn authority:
    /// it is returned as such and the caller refuses the pull — it is never skipped in favour of the visit.
    public func target(id: AcquisitionTargetID) throws -> (target: AcquisitionTarget, origin: AcquisitionTargetOrigin)? {
        if let durableTarget = try durable.target(id: id) { return (durableTarget, .durable) }
        if let visitTarget = visit?.target(id: id) { return (visitTarget, .visit) }
        return nil
    }

    public func authorizedSources(id: AcquisitionTargetID) throws -> Set<SourceID>? {
        // The store's own read requires a row; only ask it when the row is there, so a visit-only target is the
        // visit's answer instead of a persistence error.
        if try durable.target(id: id) != nil { return try durable.authorizedSources(id: id) }
        return visit?.authorizedSources(id: id)
    }
}

public struct AcquisitionTargetAuthority: Sendable {
    private let store: AcquisitionTargetStore
    public init(database: RuntimeDatabase) { store = AcquisitionTargetStore(database: database) }

    public func register(id: AcquisitionTargetID, connectorKind: ConnectorKind, authorizedSources: Set<SourceID>) throws -> AcquisitionTarget {
        try Self.map(store.register(id: id,connectorKind: connectorKind,authorizedSources: authorizedSources))
    }
    public func target(id: AcquisitionTargetID) throws -> AcquisitionTarget? {
        try store.target(id: id).map(Self.map)
    }
    public func reconfigure(id: AcquisitionTargetID, expectedGeneration: UInt64, connectorKind: ConnectorKind,
        checkpoint: AcquisitionTargetStore.ReconfigurationCheckpoint, authorizedSources: Set<SourceID>) throws -> AcquisitionTarget {
        try Self.map(store.reconfigure(id: id,expectedGeneration: expectedGeneration,connectorKind: connectorKind,checkpoint: checkpoint,authorizedSources: authorizedSources))
    }
    public func authorizedSources(id: AcquisitionTargetID) throws -> Set<SourceID>? {
        try store.authorizedSources(id: id)
    }
    public func materializeSources(id: AcquisitionTargetID, expectedGeneration: UInt64,
        connectorKind: ConnectorKind, authorizedSources: Set<SourceID>) throws -> AcquisitionTarget {
        try Self.map(store.materializeSources(id: id, expectedGeneration: expectedGeneration,
            connectorKind: connectorKind, authorizedSources: authorizedSources))
    }
    public func revoke(id: AcquisitionTargetID, expectedGeneration: UInt64) throws -> AcquisitionTarget {
        try Self.map(store.revoke(id: id,expectedGeneration: expectedGeneration))
    }
    public func enable(id: AcquisitionTargetID, expectedGeneration: UInt64) throws -> AcquisitionTarget {
        try Self.map(store.enable(id: id,expectedGeneration: expectedGeneration))
    }
    public func compareAndSwapCheckpoint(id: AcquisitionTargetID, expectedGeneration: UInt64,
        expectedCheckpointRevision: UInt64, next: AcquisitionCheckpoint) throws -> AcquisitionTarget {
        guard let record = AcquisitionTargetStore.CheckpointRecord(blob: next.blob,
            serializationSchema: next.serializationSchema,connectorVersion: next.connectorVersion) else {
            throw AcquisitionTargetStoreError.invalidRepresentation("checkpoint")
        }
        return try Self.map(store.compareAndSwapCheckpoint(id: id,expectedGeneration: expectedGeneration,
            expectedCheckpointRevision: expectedCheckpointRevision,next: record))
    }

    private static func map(_ record: AcquisitionTargetStore.TargetRecord) throws -> AcquisitionTarget {
        guard let state = AcquisitionTargetState(rawValue: record.state) else { throw AcquisitionTargetStoreError.corruption("state") }
        let checkpoint = try record.checkpoint.map { value in
            guard let result = AcquisitionCheckpoint(blob: value.blob,serializationSchema: value.serializationSchema,
                connectorVersion: value.connectorVersion) else { throw AcquisitionTargetStoreError.corruption("checkpoint") }
            return result
        }
        guard let target = AcquisitionTarget(id: record.id,connectorKind: record.connectorKind,generation: record.generation,
            state: state,checkpointRevision: record.checkpointRevision,checkpoint: checkpoint) else {
            throw AcquisitionTargetStoreError.corruption("target")
        }
        return target
    }
}
