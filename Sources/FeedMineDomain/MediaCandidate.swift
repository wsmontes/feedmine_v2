// Owns: immutable upstream visual media possibility tied to an exact OriginRevision.
// Does not own: asset identity/bytes, prepared state, protocol evidence or publication.

import Foundation

public enum MediaCandidateRole: String, Hashable, Codable, Sendable {
    case cardVisual
}

public enum MediaCandidateClass: String, Hashable, Codable, Sendable {
    case image
}

public struct MediaCandidate: Hashable, Sendable {
    public let id: MediaCandidateID
    public let originRevisionID: OriginRevisionID
    public let role: MediaCandidateRole
    public let mediaClass: MediaCandidateClass
    public let remoteURL: URL
    public let declaredMimeType: String?
    public let declaredPixelWidth: Int?
    public let declaredPixelHeight: Int?

    public init?(id: MediaCandidateID, originRevisionID: OriginRevisionID,
        role: MediaCandidateRole, mediaClass: MediaCandidateClass, remoteURL: URL,
        declaredMimeType: String?, declaredPixelWidth: Int?, declaredPixelHeight: Int?) {
        guard let scheme = remoteURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = remoteURL.host, !host.isEmpty else { return nil }
        switch (declaredPixelWidth, declaredPixelHeight) {
        case (nil, nil): break
        case (.some(let width), .some(let height)) where width > 0 && height > 0: break
        default: return nil
        }
        self.id = id
        self.originRevisionID = originRevisionID
        self.role = role
        self.mediaClass = mediaClass
        self.remoteURL = remoteURL
        self.declaredMimeType = declaredMimeType
        self.declaredPixelWidth = declaredPixelWidth
        self.declaredPixelHeight = declaredPixelHeight
    }
}
