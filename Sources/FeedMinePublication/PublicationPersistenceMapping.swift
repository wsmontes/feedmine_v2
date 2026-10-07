// File: PublicationPersistenceMapping.swift
// Module: FeedMinePublication
// Owns: internal semantic ↔ explicit mechanical record mapping for exact restore.
// Does not own: SQL, persistence lifecycle, Runtime/UI API or Codable blobs.

import Foundation
import FeedMineDomain
import FeedMineMedia
import FeedMinePersistence

enum PublicationPersistenceMappingError: Error, Equatable, Sendable {
    case invalidSegmentCardOrder
    case invalidPersistedCard
    case invalidPersistedEdition
    case invalidPersistedSegment
    case invalidPersistedCheckpoint
}

enum PublicationPersistenceMapping {
    static func record(_ edition: FeedEdition) -> PublicationStore.EditionRecord {
        .init(id: edition.id, editorialRevision: edition.editorialRevision,
            publicationSchemaVersion: edition.publicationSchemaVersion.rawValue,
            selectionSeed: edition.selectionSeed, createdAt: edition.createdAt)
    }

    static func edition(_ record: PublicationStore.EditionRecord) throws -> FeedEdition {
        guard record.createdAt.timeIntervalSince1970.isFinite else { throw PublicationPersistenceMappingError.invalidPersistedEdition }
        return FeedEdition(id: record.id, editorialRevision: record.editorialRevision,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: record.publicationSchemaVersion),
            selectionSeed: record.selectionSeed, createdAt: record.createdAt)
    }

    static func record(_ segment: FeedSegment) -> PublicationStore.SegmentRecord {
        .init(id: segment.id, editionID: segment.editionID, ordinal: segment.ordinal,
            segmentSeed: segment.segmentSeed, publicationSchemaVersion: segment.publicationSchemaVersion.rawValue,
            createdAt: segment.createdAt, cardIDs: segment.cardIDs)
    }

    static func segment(_ record: PublicationStore.SegmentRecord) throws -> FeedSegment {
        guard record.createdAt.timeIntervalSince1970.isFinite,
            let segment = FeedSegment(id: record.id, editionID: record.editionID, ordinal: record.ordinal,
                segmentSeed: record.segmentSeed, publicationSchemaVersion: PublicationSchemaVersion(rawValue: record.publicationSchemaVersion),
                createdAt: record.createdAt, cardIDs: record.cardIDs) else { throw PublicationPersistenceMappingError.invalidPersistedSegment }
        return segment
    }

    static func records(segment: FeedSegment, cards: [PublishedCard]) throws -> (PublicationStore.SegmentRecord, [PublicationStore.CardRecord]) {
        guard segment.cardIDs == cards.map(\.id) else { throw PublicationPersistenceMappingError.invalidSegmentCardOrder }
        return (record(segment), cards.map(record))
    }

    static func record(_ card: PublishedCard) -> PublicationStore.CardRecord {
        let actionKind: String?, actionReference: String?
        switch card.primaryAction {
        case nil: actionKind = nil; actionReference = nil
        case .localContentDetail: actionKind = "localContentDetail"; actionReference = nil
        case .externalURL(let url): actionKind = "externalURL"; actionReference = url.absoluteString
        case .mediaPlayback(let url): actionKind = "mediaPlayback"; actionReference = url.absoluteString
        }
        let media = card.media.primary
        return .init(id: card.id, originRecordID: card.origin.originRecordID, originRevisionID: card.origin.originRevisionID,
            sourceID: card.origin.sourceID, providerID: card.origin.providerID,
            sourceDisplayName: card.origin.sourceDisplayName, providerDisplayName: card.origin.providerDisplayName,
            contentEntityID: card.contentEntityID, contentClusterID: card.contentClusterID,
            title: card.text.title, primaryText: card.text.primaryText,
            timestampValue: card.timestamp?.value, timestampKind: card.timestamp?.kind.rawValue,
            mediaKey: media?.key.rawValue, mediaPixelWidth: media?.pixelWidth, mediaPixelHeight: media?.pixelHeight, mediaMimeType: media?.mimeType,
            renderLayout: card.renderContract.layout.rawValue, renderMediaAspectRatio: card.renderContract.mediaAspectRatio,
            primaryActionKind: actionKind, primaryActionReference: actionReference)
    }

    static func card(_ record: PublicationStore.CardRecord) throws -> PublishedCard {
        let timestamp: PublishedTimestamp?
        switch (record.timestampValue, record.timestampKind) {
        case (nil, nil): timestamp = nil
        case (.some(let date), .some(let raw)):
            guard date.timeIntervalSince1970.isFinite, let kind = PublishedTimestampKind(rawValue: raw) else {
                throw PublicationPersistenceMappingError.invalidPersistedCard
            }
            timestamp = PublishedTimestamp(value: date, kind: kind)
        default: throw PublicationPersistenceMappingError.invalidPersistedCard
        }
        let media: PublishedMediaSet
        if let rawKey = record.mediaKey {
            guard let key = PublishedMediaKey(rawValue: rawKey),
                let reference = PublishedMediaRef(key: key, pixelWidth: record.mediaPixelWidth,
                    pixelHeight: record.mediaPixelHeight, mimeType: record.mediaMimeType) else {
                throw PublicationPersistenceMappingError.invalidPersistedCard
            }
            media = PublishedMediaSet(primary: reference)
        } else {
            guard record.mediaPixelWidth == nil, record.mediaPixelHeight == nil, record.mediaMimeType == nil else {
                throw PublicationPersistenceMappingError.invalidPersistedCard
            }
            media = .none
        }
        guard let layout = PublishedCardLayout(rawValue: record.renderLayout),
            let contract = RenderContract(layout: layout, mediaAspectRatio: record.renderMediaAspectRatio) else {
            throw PublicationPersistenceMappingError.invalidPersistedCard
        }
        let action: PublishedPrimaryAction?
        switch (record.primaryActionKind, record.primaryActionReference) {
        case (nil, nil): action = nil
        case (.some("localContentDetail"), nil): action = .localContentDetail
        case (.some(let kind), .some(let target)) where kind == "externalURL" || kind == "mediaPlayback":
            guard let url = URL(string: target), url.absoluteString == target else { throw PublicationPersistenceMappingError.invalidPersistedCard }
            action = kind == "externalURL" ? .externalURL(url) : .mediaPlayback(url)
        default: throw PublicationPersistenceMappingError.invalidPersistedCard
        }
        guard let card = PublishedCard(id: record.id,
            origin: PublishedOrigin(originRecordID: record.originRecordID, originRevisionID: record.originRevisionID,
                sourceID: record.sourceID, providerID: record.providerID,
                sourceDisplayName: record.sourceDisplayName, providerDisplayName: record.providerDisplayName),
            contentEntityID: record.contentEntityID, contentClusterID: record.contentClusterID,
            text: PublishedText(title: record.title, primaryText: record.primaryText), timestamp: timestamp,
            media: media, renderContract: contract, primaryAction: action) else {
            throw PublicationPersistenceMappingError.invalidPersistedCard
        }
        return card
    }

    static func checkpoint(_ cursor: SessionCursor, updatedAt: Date) -> SessionStore.CheckpointRecord {
        .init(editionID: cursor.editionID, cardID: cursor.anchor.cardID,
            anchorPlacement: cursor.anchor.placement.rawValue, updatedAt: updatedAt)
    }

    static func cursor(_ record: SessionStore.CheckpointRecord) throws -> SessionCursor {
        guard record.updatedAt.timeIntervalSince1970.isFinite, let placement = AnchorPlacement(rawValue: record.anchorPlacement) else {
            throw PublicationPersistenceMappingError.invalidPersistedCheckpoint
        }
        return SessionCursor(editionID: record.editionID, anchor: FeedWindowAnchor(cardID: record.cardID, placement: placement))
    }
}
