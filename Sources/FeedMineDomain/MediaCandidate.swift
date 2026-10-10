// Owns: immutable upstream visual media possibility tied to an exact OriginRevision.
// Does not own: asset identity/bytes, prepared state, protocol evidence or publication.

import Foundation

public enum MediaCandidateRole: String, Hashable, Codable, Sendable {
    /// The card's own visual (V1's image).
    case cardVisual
    /// What the card plays (V1's enclosure for an audio or video episode). One per revision at most: a card
    /// has one primary action, and offering two playable targets would be a choice nobody made.
    case playback
}

public enum MediaCandidateClass: String, Hashable, Codable, Sendable {
    case image
    case audio
    case video

    /// The role a class belongs to, stated once so the storage check and the translator cannot disagree.
    public var role: MediaCandidateRole {
        switch self {
        case .image: return .cardVisual
        case .audio, .video: return .playback
        }
    }

    /// Whether a player can take this class (T9).
    public var isPlayable: Bool { self != .image }

    /// The class a declared MIME type names, when it is one a card can play. The translator asks this, so a
    /// feed says what its enclosure *is* instead of a guess about the file name.
    public static func playback(forMIME type: String) -> MediaCandidateClass? {
        let lower = type.lowercased()
        if lower.hasPrefix("audio/") { return .audio }
        if lower.hasPrefix("video/") { return .video }
        return nil
    }
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
