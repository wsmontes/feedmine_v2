import Foundation
import XCTest
@testable import FeedMineMedia

final class ImageMaterializerTests: XCTestCase {
    // Complete deterministic 2x3 RGB PNG; metadata must come from these bytes, not a hint.
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
    private let expectedKey = "sha256:949ff4d564a25629663895b0b6e070342836121696a0165d32e6e9e16f8f6e29"

    private func assertError(_ expected: LocalMediaAssetError, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body()) { XCTAssertEqual($0 as? LocalMediaAssetError, expected) }
    }

    func testActualPNGMetadataAndIdentityPreserveExactInputBytes() throws {
        let root = LocalAssetFixture.directory(self)
        let asset = try ImageMaterializer(assetDirectory: root).materialize(png)
        XCTAssertEqual(asset.key.rawValue, expectedKey)
        XCTAssertEqual(asset.pixelWidth, 2)
        XCTAssertEqual(asset.pixelHeight, 3)
        XCTAssertEqual(asset.mimeType, "image/png")
        XCTAssertEqual(try AssetStore(rootDirectory: root).bytes(for: asset.key), png)
        XCTAssertEqual(try LocalAssetFixture.files(root), [String(expectedKey.dropFirst(7))])
    }

    func testInvalidImageLeavesNoDestinationOrTemporaryFiles() throws {
        let root = LocalAssetFixture.directory(self), materializer = ImageMaterializer(assetDirectory: root)
        for bytes in [Data(), Data("not an image".utf8), Data([0, 1, 2, 3])] {
            assertError(.invalidImage) { _ = try materializer.materialize(bytes) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSameImageAcrossFreshInstancesAndReopenedLocalReadHasExactFacts() throws {
        let root = LocalAssetFixture.directory(self)
        let first: LocalImageAsset
        do { first = try ImageMaterializer(assetDirectory: root).materialize(png) }
        let reopened = ImageMaterializer(assetDirectory: root)
        XCTAssertEqual(try reopened.materialize(png), first)
        XCTAssertEqual(try reopened.localAsset(for: first.key), first)
        XCTAssertEqual(try LocalAssetFixture.files(root).count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["sha256"])
    }

    func testMissingSupportedImageReturnsNilWithoutCreatingStorage() throws {
        let root = LocalAssetFixture.directory(self)
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: expectedKey))
        XCTAssertNil(try ImageMaterializer(assetDirectory: root).localAsset(for: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testCorruptStoredDigestPropagatesWithoutRepairOrDeletion() throws {
        let root = LocalAssetFixture.directory(self), materializer = ImageMaterializer(assetDirectory: root)
        let asset = try materializer.materialize(png), damaged = Data("damaged".utf8)
        let file = LocalAssetFixture.path(asset.key, root: root)
        try damaged.write(to: file)
        assertError(.corruptStoredAsset(asset.key)) { _ = try materializer.localAsset(for: asset.key) }
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        XCTAssertEqual(try LocalAssetFixture.files(root).count, 1)
    }

    func testAuthenticButNonImageStoredBytesAreRejectedAsCorruption() throws {
        let root = LocalAssetFixture.directory(self)
        let key = try AssetStore(rootDirectory: root).publish(Data("abc".utf8))
        assertError(.corruptStoredAsset(key)) { _ = try ImageMaterializer(assetDirectory: root).localAsset(for: key) }
        XCTAssertEqual(try AssetStore(rootDirectory: root).bytes(for: key), Data("abc".utf8))
    }

    func testUnsupportedKeyPropagatesWithoutCreatingStorage() throws {
        let root = LocalAssetFixture.directory(self), key = PublishedMediaKey(rawValue: "legacy-key")!
        assertError(.unsupportedKey(key)) { _ = try ImageMaterializer(assetDirectory: root).localAsset(for: key) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
