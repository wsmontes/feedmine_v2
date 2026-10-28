// File: PublicationStore.swift
// Module: FeedMinePersistence
// Owns: the atomic history store's declaration, its immutable records and the material identity of an occurrence.
// Does not own: publication semantics, rendering, coordination, canonical data or retention.
// Dependencies: FeedMineDomain, Foundation and private GRDB access only.

// File: PublicationStore.swift
// Module: FeedMinePersistence
// Owns: concrete atomic immutable history storage and mechanical boundary records.
// Does not own: publication semantics, rendering, coordination, canonical data or retention.
// Dependencies: FeedMineDomain, Foundation and private GRDB access only.

import Foundation
import GRDB
import FeedMineDomain

public enum PublicationStoreError: Error, Equatable, Sendable {
    case invalidRepresentation(String)
    case missingEdition
    case editorialRevisionConflict
    case invalidInitialCheckpoint
    case invalidFirstSegment
    case invalidAppendOrdinal
    case publicationSchemaMismatch
    case cardIdentityMismatch
    case corruption(String)
    case invalidCapacity
    case staleHistoryExpectation
    case staleWordExclusions
    case staleSourceExclusions
    case duplicateOriginInEdition
}

public struct PublicationStore: Sendable {
    let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    public struct EditionRecord: Hashable, Sendable {
        public let id: FeedEditionID
        public let editorialRevision: EditorialRevision
        public let publicationSchemaVersion: UInt64
        public let selectionSeed: UInt64
        public let createdAt: Date

        public init(
            id: FeedEditionID,
            editorialRevision: EditorialRevision,
            publicationSchemaVersion: UInt64,
            selectionSeed: UInt64,
            createdAt: Date
        ) {
            self.id = id
            self.editorialRevision = editorialRevision
            self.publicationSchemaVersion = publicationSchemaVersion
            self.selectionSeed = selectionSeed
            self.createdAt = createdAt
        }
    }

    public struct SegmentRecord: Hashable, Sendable {
        public let id: FeedSegmentID
        public let editionID: FeedEditionID
        public let ordinal: UInt64
        public let segmentSeed: UInt64
        public let publicationSchemaVersion: UInt64
        public let createdAt: Date
        public let cardIDs: [PublicationCardID]

        public init(
            id: FeedSegmentID,
            editionID: FeedEditionID,
            ordinal: UInt64,
            segmentSeed: UInt64,
            publicationSchemaVersion: UInt64,
            createdAt: Date,
            cardIDs: [PublicationCardID]
        ) {
            self.id = id
            self.editionID = editionID
            self.ordinal = ordinal
            self.segmentSeed = segmentSeed
            self.publicationSchemaVersion = publicationSchemaVersion
            self.createdAt = createdAt
            self.cardIDs = cardIDs
        }
    }

    public struct CardRecord: Hashable, Sendable {
        public let id: PublicationCardID
        public let originRecordID: OriginRecordID
        public let originRevisionID: OriginRevisionID
        public let sourceID: SourceID?
        public let providerID: ProviderID?
        public let sourceDisplayName: String?
        public let providerDisplayName: String?
        public let contentEntityID: ContentEntityID?
        public let contentClusterID: ContentClusterID?
        public let title: String?
        public let primaryText: String?
        public let timestampValue: Date?
        public let timestampKind: String?
        public let mediaKey: String?
        public let mediaPixelWidth: Int?
        public let mediaPixelHeight: Int?
        public let mediaMimeType: String?
        public let renderLayout: String
        public let renderMediaAspectRatio: Double?
        public let primaryActionKind: String?
        public let primaryActionReference: String?
        /// D2: `audio`, `video` or `none`, frozen with the occurrence; nil for rows written before the fact existed.
        public let mediaIdentity: String?
        /// P10: editorial facts frozen with the occurrence; nil for rows written before the facts existed.
        public let diversity: EditorialDiversityFact?

        public init(
            id: PublicationCardID,
            originRecordID: OriginRecordID,
            originRevisionID: OriginRevisionID,
            sourceID: SourceID?,
            providerID: ProviderID?,
            sourceDisplayName: String?,
            providerDisplayName: String?,
            contentEntityID: ContentEntityID?,
            contentClusterID: ContentClusterID?,
            title: String?,
            primaryText: String?,
            timestampValue: Date?,
            timestampKind: String?,
            mediaKey: String?,
            mediaPixelWidth: Int?,
            mediaPixelHeight: Int?,
            mediaMimeType: String?,
            renderLayout: String,
            renderMediaAspectRatio: Double?,
            primaryActionKind: String?,
            primaryActionReference: String?,
            mediaIdentity: String? = nil,
            diversity: EditorialDiversityFact? = nil
        ) {
            self.id = id
            self.originRecordID = originRecordID
            self.originRevisionID = originRevisionID
            self.sourceID = sourceID
            self.providerID = providerID
            self.sourceDisplayName = sourceDisplayName
            self.providerDisplayName = providerDisplayName
            self.contentEntityID = contentEntityID
            self.contentClusterID = contentClusterID
            self.title = title
            self.primaryText = primaryText
            self.timestampValue = timestampValue
            self.timestampKind = timestampKind
            self.mediaKey = mediaKey
            self.mediaPixelWidth = mediaPixelWidth
            self.mediaPixelHeight = mediaPixelHeight
            self.mediaMimeType = mediaMimeType
            self.renderLayout = renderLayout
            self.renderMediaAspectRatio = renderMediaAspectRatio
            self.primaryActionKind = primaryActionKind
            self.primaryActionReference = primaryActionReference
            self.mediaIdentity = mediaIdentity
            self.diversity = diversity
        }
    }

    /// Material identity of an occurrence: whitespace-collapsed title and primary text, plus the
    /// revision's primary media locator (review F07 / PD-1: a new primary image is material).
    /// Editorial computes the identical key from candidate facts (`SelectionExposureSnapshot`).
    public static func materialKey(title: String?, primaryText: String?, primaryMedia: String? = nil,
        declaredBody: String? = nil, bodyObserved: Bool = false) -> String {
        MaterialContentIdentity.key(title: title, text: primaryText, primaryMedia: primaryMedia,
            declaredBody: declaredBody, bodyObserved: bodyObserved)
    }
}
