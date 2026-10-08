import Foundation
import XCTest
import FeedMineDomain
import FeedMineMedia

final class MediaPreparationTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
    private func candidate() throws -> MediaCandidate {
        try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: OriginRevisionID(),
            role: .cardVisual, mediaClass: .image, remoteURL: URL(string: "https://definitely.invalid/not-fetched")!,
            declaredMimeType: "not-the-actual-mime", declaredPixelWidth: 99, declaredPixelHeight: 77))
    }

    func testExplicitBytesProduceUsableExactCandidateAndActualAssetFacts() throws {
        let root = LocalAssetFixture.directory(self), candidate = try candidate()
        let result = try MediaPreparation(assetDirectory: root).prepare(candidate: candidate, input: .bytes(png))
        XCTAssertEqual(result.candidateID, candidate.id)
        XCTAssertEqual(result.originRevisionID, candidate.originRevisionID)
        guard case .usable(let asset) = result.state else { return XCTFail("Expected usable local image") }
        XCTAssertEqual(asset.key.rawValue, "sha256:949ff4d564a25629663895b0b6e070342836121696a0165d32e6e9e16f8f6e29")
        XCTAssertEqual(asset.pixelWidth, 2)
        XCTAssertEqual(asset.pixelHeight, 3)
        XCTAssertEqual(asset.mimeType, "image/png")
        XCTAssertEqual(candidate.declaredPixelWidth, 99)
        XCTAssertEqual(candidate.declaredPixelHeight, 77)
        XCTAssertEqual(candidate.declaredMimeType, "not-the-actual-mime")
        XCTAssertEqual(candidate.remoteURL.absoluteString, "https://definitely.invalid/not-fetched")
    }

    func testInvalidBytesAreUnsuitableWithoutAssetFiles() throws {
        let root = LocalAssetFixture.directory(self), candidate = try candidate()
        let result = try MediaPreparation(assetDirectory: root).prepare(candidate: candidate, input: .bytes(Data("invalid".utf8)))
        XCTAssertEqual(result.candidateID, candidate.id)
        XCTAssertEqual(result.originRevisionID, candidate.originRevisionID)
        XCTAssertEqual(result.state, .unsuitable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testFreshPreparationUsesExistingLocalKeyWithoutMemoryState() throws {
        let root = LocalAssetFixture.directory(self), candidate = try candidate()
        let asset = try ImageMaterializer(assetDirectory: root).materialize(png)
        let result = try MediaPreparation(assetDirectory: root).prepare(candidate: candidate, input: .localAsset(asset.key))
        XCTAssertEqual(result.state, .usable(asset))
        XCTAssertEqual(result.candidateID, candidate.id)
        XCTAssertEqual(result.originRevisionID, candidate.originRevisionID)
    }

    func testMissingLocalKeyAndExplicitUnavailableRetainIDsWithoutCreatingStorage() throws {
        let root = LocalAssetFixture.directory(self), candidate = try candidate()
        let preparation = MediaPreparation(assetDirectory: root)
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: LocalAssetFixture.abcKey))
        for input in [MediaPreparationInput.localAsset(key), .unavailable] {
            let result = try preparation.prepare(candidate: candidate, input: input)
            XCTAssertEqual(result.candidateID, candidate.id)
            XCTAssertEqual(result.originRevisionID, candidate.originRevisionID)
            XCTAssertEqual(result.state, .unavailable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testExplicitUnavailableDoesNotRequireUsableFilesystem() throws {
        let root = LocalAssetFixture.directory(self), candidate = try candidate()
        try Data("not a directory".utf8).write(to: root)
        let result = try MediaPreparation(assetDirectory: root).prepare(candidate: candidate, input: .unavailable)
        XCTAssertEqual(result.state, .unavailable)
        XCTAssertEqual(try Data(contentsOf: root), Data("not a directory".utf8))
    }

    func testCorruptionIsPropagatedForLocalKeyAndExplicitBytesWithoutRepair() throws {
        let root = LocalAssetFixture.directory(self), candidate = try candidate()
        let asset = try ImageMaterializer(assetDirectory: root).materialize(png)
        let file = LocalAssetFixture.path(asset.key, root: root), damaged = Data("damaged".utf8)
        try damaged.write(to: file)
        let preparation = MediaPreparation(assetDirectory: root)
        for input in [MediaPreparationInput.localAsset(asset.key), .bytes(png)] {
            XCTAssertThrowsError(try preparation.prepare(candidate: candidate, input: input)) {
                XCTAssertEqual($0 as? LocalMediaAssetError, .corruptStoredAsset(asset.key))
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    func testStorageAndUnsupportedKeyFailuresAreNotEditorialStates() throws {
        let root = LocalAssetFixture.directory(self), candidate = try candidate()
        try Data("not a directory".utf8).write(to: root)
        let preparation = MediaPreparation(assetDirectory: root)
        XCTAssertThrowsError(try preparation.prepare(candidate: candidate, input: .bytes(png))) {
            XCTAssertEqual($0 as? LocalMediaAssetError, .couldNotCreateDirectory)
        }
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: "unsupported-local-key"))
        XCTAssertThrowsError(try preparation.prepare(candidate: candidate, input: .localAsset(key))) {
            XCTAssertEqual($0 as? LocalMediaAssetError, .unsupportedKey(key))
        }
    }
}
