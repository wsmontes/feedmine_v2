// Owns: exact durable content-addressed local bytes and strict SHA-256 key resolution.
// No image inspection, presentation semantics or storage policy.

import Foundation
import CryptoKit
import Darwin

public enum LocalMediaAssetError: Error, Equatable, Sendable {
    case unsupportedKey(PublishedMediaKey)
    case couldNotCreateDirectory
    case temporaryWriteFailed
    /// The volume had no room for the bytes. Distinct from a generic write failure on purpose: a full disk is
    /// a state the reader must be told about and can recover from, never a silent "this card has no image".
    case insufficientSpace
    case installFailed
    case durabilityFailed
    case readFailed
    case corruptStoredAsset(PublishedMediaKey)
    case invalidImage
}

struct AssetStore: Sendable {
    private let rootDirectory: URL
    private let syncFile: @Sendable (URL) -> Bool
    private let syncDirectory: @Sendable (URL) -> Bool
    private let writeBytes: @Sendable (Data, URL) throws -> Void

    init(rootDirectory: URL) {
        self.init(rootDirectory: rootDirectory, syncFile: Self.sync, syncDirectory: Self.sync)
    }

    // Mechanical internal seam for deterministic sync- and write-failure tests. The write seam is what lets a
    // full disk be exercised as the real error it is (`NSFileWriteOutOfSpaceError`) instead of as a guess.
    init(rootDirectory: URL, syncFile: @escaping @Sendable (URL) -> Bool,
        syncDirectory: @escaping @Sendable (URL) -> Bool,
        writeBytes: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .withoutOverwriting)
        }) {
        self.rootDirectory = rootDirectory
        self.syncFile = syncFile
        self.syncDirectory = syncDirectory
        self.writeBytes = writeBytes
    }

    func publish(_ bytes: Data) throws -> PublishedMediaKey {
        let digest = Self.digest(bytes)
        let key = PublishedMediaKey(rawValue: "sha256:" + digest)!
        let directory = rootDirectory.appendingPathComponent("sha256", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw Self.isOutOfSpace(error) ? LocalMediaAssetError.insufficientSpace : LocalMediaAssetError.couldNotCreateDirectory
        }
        let destination = directory.appendingPathComponent(digest)
        if try self.bytes(for: key) != nil {
            try ensureDurability(file: destination, directory: directory)
            return key
        }

        let temporary = directory.appendingPathComponent(".pending-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try writeBytes(bytes, temporary)
        } catch {
            // A full volume is a state, not a defect of the image: it must reach the caller as its own outcome.
            throw Self.isOutOfSpace(error) ? LocalMediaAssetError.insufficientSpace : LocalMediaAssetError.temporaryWriteFailed
        }
        guard syncFile(temporary) else { throw LocalMediaAssetError.durabilityFailed }

        // Exclusive atomic installation never overwrites an existing destination.
        let installed = temporary.path.withCString { source in
            destination.path.withCString { target in
                Darwin.renamex_np(source, target, UInt32(RENAME_EXCL))
            }
        }
        if installed != 0 {
            guard errno == EEXIST else { throw LocalMediaAssetError.installFailed }
            guard try self.bytes(for: key) != nil else { throw LocalMediaAssetError.installFailed }
            // Another writer won. Authenticate and sync that immutable destination.
            try ensureDurability(file: destination, directory: directory)
        } else {
            guard syncDirectory(directory) else { throw LocalMediaAssetError.durabilityFailed }
        }
        return key
    }

    func bytes(for key: PublishedMediaKey) throws -> Data? {
        let digest = try Self.parse(key)
        let file = rootDirectory.appendingPathComponent("sha256", isDirectory: true).appendingPathComponent(digest)
        let bytes: Data
        do {
            bytes = try Data(contentsOf: file)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError {
                return nil
            }
            if failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOENT) { return nil }
            throw LocalMediaAssetError.readFailed
        }
        guard Self.digest(bytes) == digest else { throw LocalMediaAssetError.corruptStoredAsset(key) }
        return bytes
    }

    private func ensureDurability(file: URL, directory: URL) throws {
        guard syncFile(file), syncDirectory(directory) else { throw LocalMediaAssetError.durabilityFailed }
    }

    private static func parse(_ key: PublishedMediaKey) throws -> String {
        let text = Array(key.rawValue.utf8)
        guard text.count == 71, text.prefix(7).elementsEqual("sha256:".utf8),
            text.dropFirst(7).allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw LocalMediaAssetError.unsupportedKey(key)
        }
        return String(key.rawValue.dropFirst(7))
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// The two shapes a full volume arrives in: Foundation's file-write code and the POSIX error underneath it.
    static func isOutOfSpace(_ error: any Error) -> Bool {
        let failure = error as NSError
        if failure.domain == NSCocoaErrorDomain && failure.code == NSFileWriteOutOfSpaceError { return true }
        if failure.domain == NSPOSIXErrorDomain && failure.code == Int(ENOSPC) { return true }
        return false
    }

    private static func sync(_ url: URL) -> Bool {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { _ = Darwin.close(descriptor) }
        return Darwin.fsync(descriptor) == 0
    }
}
