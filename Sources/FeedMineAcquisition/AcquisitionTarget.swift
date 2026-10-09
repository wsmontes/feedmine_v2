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
