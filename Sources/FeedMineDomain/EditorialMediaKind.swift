// Owns: the payload kind editorial sequencing may use for a candidate.
// Does not own: media retrieval, readiness, publication or rendering.
//
// A cover image is never a payload type. `.none` is a known admitted absence (a canonical revision whose
// complete media collection was admitted with no playable payload); `nil` means unspecified (manual candidates
// and old published facts), not "none".

import Foundation

public enum EditorialMediaKind: String, Hashable, Codable, Sendable {
    case audio
    case video
    case none
}
