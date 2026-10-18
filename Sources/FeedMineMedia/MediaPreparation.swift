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
    private let materializeBytes: @Sendable (Data) throws -> LocalImageAsset
    private let inspectLocal: @Sendable (PublishedMediaKey) throws -> LocalImageAsset?

    public init(assetDirectory: URL) {
        let materializer = ImageMaterializer(assetDirectory: assetDirectory)
        self.materializeBytes = { try materializer.materialize($0) }
        self.inspectLocal = { try materializer.localAsset(for: $0) }
    }

    /// Mechanical seam for deterministic storage failures (a full disk, an unwritable asset root) at the media
    /// boundary. Production constructs the store from the asset directory; tests state the failure instead of
    /// having to fill a volume.
    public init(materializeBytes: @escaping @Sendable (Data) throws -> LocalImageAsset,
        inspectLocal: @escaping @Sendable (PublishedMediaKey) throws -> LocalImageAsset?) {
        self.materializeBytes = materializeBytes
        self.inspectLocal = inspectLocal
    }

    /// Storage failures — `insufficientSpace` included — are thrown, never folded into `unavailable`: "the disk
    /// could not hold it" is not "this occurrence has no image".
    public func prepare(candidate: MediaCandidate, input: MediaPreparationInput) throws -> MediaPreparationResult {
        let state: MediaPreparationState
        switch input {
        case .bytes(let bytes):
            do {
                state = .usable(try materializeBytes(bytes))
            } catch LocalMediaAssetError.invalidImage {
                state = .unsuitable
            }
        case .localAsset(let key):
            if let asset = try inspectLocal(key) {
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
