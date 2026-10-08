import Foundation
import XCTest
@testable import FeedMineMedia

enum LocalAssetFixture {
    static let abcKey = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    static func directory(_ test: XCTestCase) -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    static func path(_ key: PublishedMediaKey, root: URL) -> URL {
        root.appendingPathComponent("sha256").appendingPathComponent(String(key.rawValue.dropFirst(7)))
    }
    static func files(_ root: URL) throws -> [String] {
        let directory = root.appendingPathComponent("sha256")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }
}

final class AssetStoreTests: XCTestCase {
    private func assertError(_ expected: LocalMediaAssetError, _ body: () throws -> Void,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? LocalMediaAssetError, expected, file: file, line: line)
        }
    }

    func testKnownSHA256KeyExactBytesAndIdempotentSingleFile() throws {
        let root = LocalAssetFixture.directory(self), store = AssetStore(rootDirectory: root)
        let bytes = Data("abc".utf8)
        let first = try store.publish(bytes), second = try store.publish(bytes)
        XCTAssertEqual(first.rawValue, LocalAssetFixture.abcKey)
        XCTAssertEqual(second, first)
        XCTAssertEqual(try store.bytes(for: first), bytes)
        XCTAssertEqual(try LocalAssetFixture.files(root), [String(LocalAssetFixture.abcKey.dropFirst(7))])
        XCTAssertEqual(try Data(contentsOf: LocalAssetFixture.path(first, root: root)), bytes)
    }

    func testDifferentBytesHaveIndependentDestinationsAndReopenWithoutMemoryState() throws {
        let root = LocalAssetFixture.directory(self)
        let a: PublishedMediaKey, b: PublishedMediaKey
        do {
            let store = AssetStore(rootDirectory: root)
            a = try store.publish(Data("abc".utf8))
            b = try store.publish(Data("abcd".utf8))
        }
        XCTAssertNotEqual(a, b)
        let reopened = AssetStore(rootDirectory: root)
        XCTAssertEqual(try reopened.bytes(for: a), Data("abc".utf8))
        XCTAssertEqual(try reopened.bytes(for: b), Data("abcd".utf8))
        XCTAssertEqual(try LocalAssetFixture.files(root).count, 2)
    }

    func testMissingSupportedKeyDoesNotCreateFiles() throws {
        let root = LocalAssetFixture.directory(self), store = AssetStore(rootDirectory: root)
        XCTAssertNil(try store.bytes(for: PublishedMediaKey(rawValue: LocalAssetFixture.abcKey)!))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testCorruptStoredContentIsRefusedByReadAndPublishWithoutRepair() throws {
        let root = LocalAssetFixture.directory(self), store = AssetStore(rootDirectory: root)
        let key = try store.publish(Data("abc".utf8))
        let damaged = Data("damaged".utf8), path = LocalAssetFixture.path(key, root: root)
        try damaged.write(to: path)
        assertError(.corruptStoredAsset(key)) { _ = try store.bytes(for: key) }
        assertError(.corruptStoredAsset(key)) { _ = try store.publish(Data("abc".utf8)) }
        XCTAssertEqual(try Data(contentsOf: path), damaged)
        XCTAssertEqual(try LocalAssetFixture.files(root).count, 1)
    }

    func testUnsupportedKeysAreRejectedWithoutUsingThemAsPaths() throws {
        let root = LocalAssetFixture.directory(self), store = AssetStore(rootDirectory: root)
        for text in ["legacy-or-arbitrary-key", "../outside", LocalAssetFixture.abcKey.uppercased(),
            "sha256:" + String(repeating: "a", count: 63), "sha256:" + String(repeating: "g", count: 64),
            LocalAssetFixture.abcKey + "/child", " " + LocalAssetFixture.abcKey] {
            let key = try XCTUnwrap(PublishedMediaKey(rawValue: text))
            assertError(.unsupportedKey(key)) { _ = try store.bytes(for: key) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testFileSyncFailureReturnsNoKeyAndCleansTemporaryFile() throws {
        let root = LocalAssetFixture.directory(self)
        let store = AssetStore(rootDirectory: root, syncFile: { url in
            XCTAssertEqual(url.deletingLastPathComponent(), root.appendingPathComponent("sha256"))
            XCTAssertEqual(try? Data(contentsOf: url), Data("abc".utf8))
            return false
        }, syncDirectory: { _ in XCTFail("Install/directory sync must not run after file-sync failure"); return true })
        assertError(.durabilityFailed) { _ = try store.publish(Data("abc".utf8)) }
        XCTAssertEqual(try LocalAssetFixture.files(root), [])
    }

    func testDirectorySyncFailureReturnsNoKeyThenNormalPublishCompletesDurability() throws {
        let root = LocalAssetFixture.directory(self), bytes = Data("abc".utf8)
        let store = AssetStore(rootDirectory: root, syncFile: { url in
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            return true
        }, syncDirectory: { url in
            XCTAssertEqual(url, root.appendingPathComponent("sha256"))
            XCTAssertEqual(try? LocalAssetFixture.files(root), [String(LocalAssetFixture.abcKey.dropFirst(7))])
            return false
        })
        assertError(.durabilityFailed) { _ = try store.publish(bytes) }
        XCTAssertEqual(try LocalAssetFixture.files(root), [String(LocalAssetFixture.abcKey.dropFirst(7))])
        let normal = AssetStore(rootDirectory: root)
        XCTAssertEqual(try normal.publish(bytes).rawValue, LocalAssetFixture.abcKey)
        XCTAssertEqual(try normal.bytes(for: PublishedMediaKey(rawValue: LocalAssetFixture.abcKey)!), bytes)
    }

    func testExistingDestinationMustAlsoPassFileAndDirectorySync() throws {
        let root = LocalAssetFixture.directory(self), bytes = Data("abc".utf8)
        _ = try AssetStore(rootDirectory: root).publish(bytes)
        let fileFailure = AssetStore(rootDirectory: root, syncFile: { _ in false }, syncDirectory: { _ in true })
        assertError(.durabilityFailed) { _ = try fileFailure.publish(bytes) }
        let directoryFailure = AssetStore(rootDirectory: root, syncFile: { _ in true }, syncDirectory: { _ in false })
        assertError(.durabilityFailed) { _ = try directoryFailure.publish(bytes) }
        XCTAssertEqual(try LocalAssetFixture.files(root).count, 1)
    }

    func testDirectoryCreationAndReadFailuresRemainTyped() throws {
        let root = LocalAssetFixture.directory(self)
        try Data("not a directory".utf8).write(to: root)
        assertError(.couldNotCreateDirectory) { _ = try AssetStore(rootDirectory: root).publish(Data("abc".utf8)) }
        let other = LocalAssetFixture.directory(self), key = PublishedMediaKey(rawValue: LocalAssetFixture.abcKey)!
        try FileManager.default.createDirectory(at: LocalAssetFixture.path(key, root: other), withIntermediateDirectories: true)
        assertError(.readFailed) { _ = try AssetStore(rootDirectory: other).bytes(for: key) }
    }

    func testConcurrentSameBytesInstallOneImmutableDestination() throws {
        let root = LocalAssetFixture.directory(self), barrier = InstallBarrier()
        let store = AssetStore(rootDirectory: root, syncFile: { _ in barrier.arrive(); return true }, syncDirectory: { _ in true })
        let results = PublishResults()
        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            do { results.append(.success(try store.publish(Data("abc".utf8)))) }
            catch { results.append(.failure(error)) }
        }
        XCTAssertEqual(results.values.count, 2)
        for result in results.values {
            XCTAssertEqual(try result.get().rawValue, LocalAssetFixture.abcKey)
        }
        XCTAssertEqual(try LocalAssetFixture.files(root), [String(LocalAssetFixture.abcKey.dropFirst(7))])
        XCTAssertEqual(try AssetStore(rootDirectory: root).bytes(for: PublishedMediaKey(rawValue: LocalAssetFixture.abcKey)!), Data("abc".utf8))
    }
}

// Test-only synchronization forces both temporary writes to precede either install.
private final class InstallBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private var arrived = 0
    func arrive() {
        condition.lock()
        defer { condition.unlock() }
        arrived += 1
        if arrived >= 2 { condition.broadcast() }
        while arrived < 2 { condition.wait() }
    }
}

private final class PublishResults: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Result<PublishedMediaKey, Error>] = []
    func append(_ value: Result<PublishedMediaKey, Error>) {
        lock.lock(); defer { lock.unlock() }; stored.append(value)
    }
    var values: [Result<PublishedMediaKey, Error>] {
        lock.lock(); defer { lock.unlock() }; return stored
    }
}
