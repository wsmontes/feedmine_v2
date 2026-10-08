// Owns: semantic preflight and exact protocol-free mapping to one mechanical admission call.
// Does not own: transport, identity allocation, canonical writes or acquisition execution.
import FeedMineDomain
import FeedMinePersistence

public enum AdmissionPolicyError: Error, Equatable, Sendable {
    case unsupportedUnversionedHistorical(index: Int)
    case invalidPersistenceMapping(index: Int)
}

public struct AdmissionPolicy: Sendable {
    private let store: AcquisitionAdmissionStore
    public init(database: RuntimeDatabase) { store = AcquisitionAdmissionStore(database: database) }

    public func admit(_ batch: AcquisitionBatch) throws -> AdmissionReceipt {
        for (index, observation) in batch.observations.enumerated() {
            if observation.versionIdentity == nil, observation.precedence == .historicalOnly {
                throw AdmissionPolicyError.unsupportedUnversionedHistorical(index: index)
            }
        }
        let observations = try batch.observations.enumerated().map { index, value in
            let media = try value.mediaCandidates.map { claim in
                guard let mapped = AcquisitionAdmissionStore.MediaCandidateCommand(role: claim.role,
                    mediaClass: claim.mediaClass, remoteURL: claim.remoteURL, declaredMimeType: claim.declaredMimeType,
                    declaredPixelWidth: claim.declaredPixelWidth, declaredPixelHeight: claim.declaredPixelHeight) else {
                    throw AdmissionPolicyError.invalidPersistenceMapping(index: index)
                }
                return mapped
            }
            return AcquisitionAdmissionStore.ObservationCommand(objectIdentity: value.objectIdentity,
                versionIdentity: value.versionIdentity, precedence: value.precedence == .makeCurrent ? .makeCurrent : .historicalOnly,
                availability: value.availability, headline: value.headline, summary: value.summary, bodyText: value.bodyText,
                authoredAt: value.authoredAt, modifiedAt: value.modifiedAt, observedAt: value.observedAt,
                language: value.language, primaryLink: value.primaryLink, searchProjection: value.searchProjection,
                providerID: value.providerID, memberships: value.memberships.map {
                    .init(sourceID: $0.sourceID, kind: $0.kind)
                }, mediaCandidates: media)
        }
        let checkpoint = try batch.nextCheckpoint.map { value in
            guard let mapped = AcquisitionTargetStore.CheckpointRecord(blob: value.blob,
                serializationSchema: value.serializationSchema, connectorVersion: value.connectorVersion) else {
                throw AdmissionPolicyError.invalidPersistenceMapping(index: 0)
            }
            return mapped
        }
        let record = try store.admit(.init(targetID: batch.targetID, targetGeneration: batch.targetGeneration,
            expectedCheckpointRevision: batch.expectedCheckpointRevision, observations: observations, nextCheckpoint: checkpoint))
        return AdmissionReceipt(targetID: record.targetID, checkpointAdvanced: record.checkpointAdvanced,
            selectableSupplyChanged: record.selectableSupplyChanged)
    }
}
