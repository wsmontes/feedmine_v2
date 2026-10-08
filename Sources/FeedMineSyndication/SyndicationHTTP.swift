// Opaque connector checkpoint contract only. HTTP execution belongs to a future phase.
import Foundation
import FeedMineAcquisition

public struct SyndicationCheckpointState: Hashable, Codable, Sendable {
    public let etag: String?
    public let lastModified: String?
    public let documentFingerprint: String?
    public let nextItemIndex: Int

    public init?(etag: String?, lastModified: String?, documentFingerprint: String?, nextItemIndex: Int) {
        guard nextItemIndex >= 0,
            [etag, lastModified, documentFingerprint].allSatisfy({ $0.map { !$0.utf8.isEmpty } ?? true }),
            (documentFingerprint == nil && nextItemIndex == 0) || (documentFingerprint != nil && nextItemIndex > 0)
        else { return nil }
        self.etag = etag
        self.lastModified = lastModified
        self.documentFingerprint = documentFingerprint
        self.nextItemIndex = nextItemIndex
    }

    private enum CodingKeys: String, CodingKey { case etag, lastModified, documentFingerprint, nextItemIndex }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let state = Self(etag: try values.decodeIfPresent(String.self, forKey: .etag),
            lastModified: try values.decodeIfPresent(String.self, forKey: .lastModified),
            documentFingerprint: try values.decodeIfPresent(String.self, forKey: .documentFingerprint),
            nextItemIndex: try values.decode(Int.self, forKey: .nextItemIndex)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid checkpoint state"))
        }
        self = state
    }
}

public enum SyndicationCheckpointError: Error, Equatable, Sendable {
    case unsupportedSchema(UInt64)
    case unsupportedConnectorVersion(String)
    case malformed
}

public enum SyndicationCheckpointCodec {
    public static let serializationSchema: UInt64 = 1
    public static let connectorVersion = "feedmine-syndication/1-feedkit/10.9.4"
    public static var empty: SyndicationCheckpointState {
        SyndicationCheckpointState(etag: nil, lastModified: nil, documentFingerprint: nil, nextItemIndex: 0)!
    }
    public static func encode(_ state: SyndicationCheckpointState) throws -> AcquisitionCheckpoint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AcquisitionCheckpoint(blob: try encoder.encode(state), serializationSchema: serializationSchema,
            connectorVersion: connectorVersion)!
    }
    public static func decode(_ checkpoint: AcquisitionCheckpoint) throws -> SyndicationCheckpointState {
        guard checkpoint.serializationSchema == serializationSchema else {
            throw SyndicationCheckpointError.unsupportedSchema(checkpoint.serializationSchema)
        }
        guard checkpoint.connectorVersion.utf8.elementsEqual(connectorVersion.utf8) else {
            throw SyndicationCheckpointError.unsupportedConnectorVersion(checkpoint.connectorVersion)
        }
        do { return try JSONDecoder().decode(SyndicationCheckpointState.self, from: checkpoint.blob) }
        catch { throw SyndicationCheckpointError.malformed }
    }
}
