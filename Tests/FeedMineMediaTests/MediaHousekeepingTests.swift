import Foundation
import XCTest
import FeedMineMedia

/// PD-5/PD-6: housekeeping lists only content-addressed assets and deletes exactly what it is told.
final class MediaHousekeepingTests: XCTestCase {
    func testFailedRemovalDoesNotReportReclaimedBytesOrSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let materializer = ImageMaterializer(assetDirectory: root)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        let asset = try materializer.materialize(png)
        let directory = root.appendingPathComponent("sha256")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        let report = MediaHousekeeping(assetDirectory: root).evictReporting([asset.key])
        XCTAssertTrue(report.removedKeys.isEmpty)
        XCTAssertEqual(report.reclaimedBytes, 0)
        XCTAssertNotNil(try materializer.localAsset(for: asset.key))
    }

    func testInventoryAndEvictionTouchOnlyValidAssets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let materializer = ImageMaterializer(assetDirectory: root)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        let asset = try materializer.materialize(png)
        let stray = root.appendingPathComponent("sha256/.pending-keep")
        try Data([1]).write(to: stray)
        let housekeeping = MediaHousekeeping(assetDirectory: root)
        let inventory = housekeeping.inventory()
        XCTAssertEqual(inventory.map(\.key), [asset.key])
        XCTAssertEqual(inventory.first?.byteCount, Int64(png.count))
        XCTAssertEqual(housekeeping.evict([asset.key]), Int64(png.count))
        XCTAssertNil(try materializer.localAsset(for: asset.key))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stray.path))
        XCTAssertEqual(housekeeping.evict([try XCTUnwrap(PublishedMediaKey(rawValue: "../escape"))]), 0)
    }
}
