// Owns: one explicit candidate/local input to Media-owned prepared facts.
// Storage and integrity failures remain errors; declared facts are never changed.

import Foundation
import FeedMineDomain

public enum MediaPreparationInput: Sendable {
    case bytes(Data)
    case localAsset(PublishedMediaKey)
    case unavailable
}

public enum MediaPreparationState: Hashable, Sendable {
    case usable(LocalImageAsset)
    case unavailable
    case unsuitable
}

public struct MediaPreparationResult: Hashable, Sendable {
    public let candidateID: MediaCandidateID
    public let originRevisionID: OriginRevisionID
    public let state: MediaPreparationState

    internal init(candidateID: MediaCandidateID, originRevisionID: OriginRevisionID,
        state: MediaPreparationState) {
        self.candidateID = candidateID
        self.originRevisionID = originRevisionID
        self.state = state
    }
}

public struct MediaPreparation: Sendable {
    private let materializer: ImageMaterializer

    public init(assetDirectory: URL) {
        self.materializer = ImageMaterializer(assetDirectory: assetDirectory)
    }

    public func prepare(candidate: MediaCandidate, input: MediaPreparationInput) throws -> MediaPreparationResult {
        let state: MediaPreparationState
        switch input {
        case .bytes(let bytes):
            do {
                state = .usable(try materializer.materialize(bytes))
            } catch LocalMediaAssetError.invalidImage {
                state = .unsuitable
            }
        case .localAsset(let key):
            if let asset = try materializer.localAsset(for: key) {
                state = .usable(asset)
            } else {
                state = .unavailable
            }
        case .unavailable:
            state = .unavailable
        }
        return MediaPreparationResult(candidateID: candidate.id,
            originRevisionID: candidate.originRevisionID, state: state)
    }
}
