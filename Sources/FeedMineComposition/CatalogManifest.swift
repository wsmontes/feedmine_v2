//
// File: CatalogManifest.swift
// Module: FeedMineComposition
//
// Responsibility:
// The manifest PD-10 names as the authority's declaration: the shape `manifest.json` in
// `https://github.com/wawasoft/feed-repository` publishes (revision, schemaVersion, generatedAt, sourceCount,
// fileCount and one `{path, bytes, sha256}` entry per OPML), decoded and validated **before** any catalogue is
// built or activated. The same decoder reads two files, because they are the same declaration at two layers:
//
//   * the **public** manifest, fetched from the repository (OPML inventory only), and
//   * the **bundled** descriptor this build ships beside its compiled catalogue
//     (`FeedMineApp/Resources/catalog.manifest.json`), which adds one entry — `files` names the compiled
//     `catalog.sqlite` as well — so the immutable snapshot the app actually opens is covered by the same
//     checksums as the OPMLs it was built from. That is what makes the shipped copy "verifiable and
//     traceable" (PD-10, release criterion 1).
//
// Does not own: downloading the payload (`CatalogUpdateChannel`), deciding whether a revision is worth
// fetching (`CatalogSyncPolicy`), installing or quarantining anything (`CatalogInstallation`) or the catalogue's
// compiled identity (`LegacyCatalogReader`, which reports the snapshot's own declared version).
//
// No signature is verified here, and none is claimed: the public channel publishes none yet, and PD-10
// forbids inventing a cryptographic guarantee the channel does not offer.
import CryptoKit
import Foundation
import FeedMinePersistence

/// One declared artefact: a path relative to the payload root, its byte count and its SHA-256.
/// `bytes`/`sha256` describe the bytes actually shipped — the file itself is not in the JSON.
public struct CatalogManifestEntry: Hashable, Sendable, Codable {
    public let path: String
    public let bytes: Int
    public let sha256: String

    public init(path: String, bytes: Int, sha256: String) {
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// The declaration the public repository publishes and the bundled snapshot repeats.
public struct CatalogManifest: Hashable, Sendable, Codable {
    /// The manifest format this build understands. The upstream channel publishes `1`; a manifest that claims
    /// any other format is refused rather than guessed at.
    public static let supportedSchemaVersion = 1

    /// Monotonic revision of the published catalogue. Equal revisions mean "nothing to do"; a smaller one is a
    /// stale offer and never replaces a newer snapshot.
    public let revision: Int
    /// The manifest's own format version — not the SQLite catalogue's schema.
    public let schemaVersion: Int
    public let generatedAt: String?
    public let sourceCount: Int
    public let fileCount: Int
    public let files: [CatalogManifestEntry]

    public init(revision: Int, schemaVersion: Int = supportedSchemaVersion, generatedAt: String? = nil,
        sourceCount: Int, fileCount: Int, files: [CatalogManifestEntry]) {
        self.revision = revision
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.sourceCount = sourceCount
        self.fileCount = fileCount
        self.files = files
    }

    public enum DecodeError: Error, Equatable, Sendable {
        case malformed
    }

    /// Decodes a manifest. The only value the JSON may not carry is `schemaVersion`; a missing one is a
    /// malformed manifest rather than a default, because guessing the format is how a wrong revision gets in.
    public static func decode(_ data: Data) throws -> CatalogManifest {
        guard let manifest = try? JSONDecoder().decode(CatalogManifest.self, from: data) else {
            throw DecodeError.malformed
        }
        return manifest
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// The declaration this app installs for a revision it compiled **on the device**: this manifest's own
    /// inventory plus one entry for the compiled `catalogue`, whose byte count and digest are measured from the
    /// artefact just built. Nothing is invented — the published manifest is OPML-only, so the derived artefact needs
    /// its own entry, and measuring it is how it gets one. This is the device-side twin of the descriptor
    /// `scripts/bootstrap_catalog.py` writes beside the bundled snapshot, which is why a snapshot compiled on the
    /// device is verified by exactly the same rules as the one this build ships.
    ///
    /// A catalogue that cannot be read or hashed throws (a `CatalogRejection.catalogueUnreadable`) rather than
    /// yielding a declaration with a guessed entry.
    public func declaringCompiledCatalogue(at catalogue: URL) throws -> CatalogManifest {
        guard let values = try? catalogue.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true, let bytes = values.fileSize else {
            throw CatalogRejection.catalogueUnreadable("no readable file at \(catalogue.path)")
        }
        let digest: String
        do { digest = try Self.sha256(ofFile: catalogue) }
        catch { throw CatalogRejection.catalogueUnreadable(String(describing: error)) }
        // The name the installation stores a snapshot's copy under, so the entry describes the artefact where the
        // snapshot actually keeps it.
        let compiledEntry = CatalogManifestEntry(path: "catalog.sqlite", bytes: bytes, sha256: digest)
        let inventory = opmlEntries
        return CatalogManifest(revision: revision, schemaVersion: schemaVersion, generatedAt: generatedAt,
            sourceCount: sourceCount, fileCount: inventory.count + 1, files: inventory + [compiledEntry])
    }

    /// Every declared path, in manifest order.
    public var inventory: [CatalogManifestEntry] { files }

    /// The entries that describe OPML input rather than the compiled catalogue: every declaration except one
    /// whose path is the compiled database itself.
    public var opmlEntries: [CatalogManifestEntry] {
        files.filter { $0.path.lowercased().hasSuffix(".sqlite") == false }
    }

    /// The entry naming the compiled catalogue, when this descriptor covers it (the bundled snapshot does).
    public var catalogueEntry: CatalogManifestEntry? {
        files.first { $0.path.lowercased().hasSuffix(".sqlite") }
    }

    // MARK: - Validation

    /// Structural validation, before any byte is read. Names no filesystem.
    public static func validate(_ manifest: CatalogManifest) -> CatalogRejection? {
        guard manifest.schemaVersion == supportedSchemaVersion else {
            return .unsupportedManifestSchema(manifest.schemaVersion)
        }
        guard manifest.revision > 0 else { return .invalidDeclaration("revision must be positive") }
        guard manifest.sourceCount > 0 else { return .invalidDeclaration("sourceCount must be positive") }
        guard manifest.fileCount == manifest.files.count else {
            return .fileCountMismatch(declared: manifest.fileCount, actual: manifest.files.count)
        }
        var seen = Set<String>()
        for entry in manifest.files {
            guard Self.isSafeRelativePath(entry.path) else {
                return .unsafePath(entry.path)
            }
            guard seen.insert(entry.path).inserted else { return .unsafePath(entry.path) }
            guard entry.bytes > 0 else { return .invalidDeclaration("zero-byte entry: \(entry.path)") }
            guard Self.isHexDigest(entry.sha256) else {
                return .invalidDeclaration("malformed sha256 for \(entry.path)")
            }
        }
        return nil
    }

    /// Verifies every declared OPML against the payload directory the caller has already fetched. Nothing is
    /// built or activated before this passes (PD-10: "verify schema, inventory, size and SHA-256 of all
    /// downloaded OPMLs before building/validating the new local snapshot").
    public static func validate(_ manifest: CatalogManifest, payload: URL) -> CatalogRejection? {
        if let rejection = validate(manifest) { return rejection }
        let entries = manifest.opmlEntries
        guard !entries.isEmpty else { return .inventoryEmpty }
        for entry in entries {
            let url = payload.appendingPathComponent(entry.path)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true, let size = values.fileSize else {
                return .missingEntry(entry.path)
            }
            guard size == entry.bytes else {
                return .sizeMismatch(path: entry.path, declared: entry.bytes, present: size)
            }
            guard let digest = try? Self.sha256(ofFile: url) else { return .missingEntry(entry.path) }
            guard digest == entry.sha256.lowercased() else {
                return .checksumMismatch(path: entry.path, declared: entry.sha256, present: digest)
            }
        }
        return nil
    }

    /// Verifies a compiled catalogue against the manifest's own entry for it, then against the SQLite schema this
    /// build reads and the catalogue's declared `catalog_metadata`. This is the step that makes the shipped copy
    /// verifiable: a file whose bytes differ from the declaration, or whose schema this build cannot read, is
    /// refused instead of activated.
    public static func validate(_ manifest: CatalogManifest, catalogue: URL) -> CatalogRejection? {
        if let rejection = validate(manifest) { return rejection }
        guard let entry = manifest.catalogueEntry else {
            return .catalogueEntryMissing(manifest.revision)
        }
        guard let values = try? catalogue.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true, let size = values.fileSize else {
            return .missingEntry(entry.path)
        }
        guard size == entry.bytes else {
            return .sizeMismatch(path: entry.path, declared: entry.bytes, present: size)
        }
        guard let digest = try? Self.sha256(ofFile: catalogue) else { return .missingEntry(entry.path) }
        guard digest == entry.sha256.lowercased() else {
            return .checksumMismatch(path: entry.path, declared: entry.sha256, present: digest)
        }
        let reader: LegacyCatalogReader
        do { reader = try LegacyCatalogReader(catalogURL: catalogue) }
        catch { return .catalogueUnreadable(String(describing: error)) }
        guard let metadata = try? reader.metadata(), let schemaVersion = metadata.schemaVersion else {
            return .catalogueSchemaUnknown
        }
        guard schemaVersion == LegacyCatalogReader.supportedSchemaVersion else {
            return .catalogueSchemaUnsupported(schemaVersion)
        }
        guard metadata.sourceCount == nil || metadata.sourceCount == manifest.sourceCount else {
            return .sourceCountMismatch(declared: manifest.sourceCount,
                built: metadata.sourceCount ?? manifest.sourceCount)
        }
        return nil
    }

    // MARK: - Helpers

    /// A relative POSIX path inside the payload: never absolute, never escaping the root, never empty.
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.hasPrefix("\\") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        return !path.contains("\\")
    }

    public static func isHexDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    /// Streaming SHA-256 (the bundled catalogue is >100 MB; never loaded whole).
    public static func sha256(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Why a catalogue revision was refused. A reason, never a silent fallback.
public enum CatalogRejection: Error, Hashable, Sendable, Codable {
    case malformedManifest
    case unsupportedManifestSchema(Int)
    case invalidDeclaration(String)
    case fileCountMismatch(declared: Int, actual: Int)
    case unsafePath(String)
    case missingEntry(String)
    case sizeMismatch(path: String, declared: Int, present: Int)
    case checksumMismatch(path: String, declared: String, present: String)
    case inventoryEmpty
    case catalogueEntryMissing(Int)
    case catalogueUnreadable(String)
    case catalogueSchemaUnknown
    case catalogueSchemaUnsupported(Int)
    case sourceCountMismatch(declared: Int, built: Int)
    case revisionCollision(Int, active: Int)
    case revisionNotNewer(Int, active: Int)

    /// The line an external preparation report prints. Stated in the catalogue's own terms.
    public var reason: String {
        switch self {
        case .malformedManifest:
            return "manifest is not readable JSON in the published shape"
        case .unsupportedManifestSchema(let version):
            return "manifest schema \(version) is not supported by this build"
        case .invalidDeclaration(let detail):
            return "manifest declaration is invalid: \(detail)"
        case .fileCountMismatch(let declared, let actual):
            return "manifest declares \(declared) files but carries \(actual)"
        case .unsafePath(let path):
            return "manifest names an unsafe path: \(path)"
        case .missingEntry(let path):
            return "declared file is missing: \(path)"
        case .sizeMismatch(let path, let declared, let present):
            return "size mismatch for \(path): declared \(declared), present \(present)"
        case .checksumMismatch(let path, let declared, let present):
            return "sha256 mismatch for \(path): declared \(declared), present \(present)"
        case .inventoryEmpty:
            return "manifest declares no OPML inventory"
        case .catalogueEntryMissing(let revision):
            return "manifest of revision \(revision) declares no compiled catalogue"
        case .catalogueUnreadable(let detail):
            return "compiled catalogue is unreadable: \(detail)"
        case .catalogueSchemaUnknown:
            return "compiled catalogue declares no schema version"
        case .catalogueSchemaUnsupported(let version):
            return "compiled catalogue schema \(version) is not supported by this build"
        case .sourceCountMismatch(let declared, let built):
            return "source count mismatch: declared \(declared), compiled \(built)"
        case .revisionCollision(let revision, let active):
            return "revision \(revision) matches active \(active) but the declarations differ"
        case .revisionNotNewer(let revision, let active):
            return "revision \(revision) is not newer than active \(active)"
        }
    }

    /// Coarse class for the report's own grouping.
    public var kind: String {
        switch self {
        case .malformedManifest, .unsupportedManifestSchema, .invalidDeclaration, .fileCountMismatch,
            .unsafePath, .inventoryEmpty, .catalogueEntryMissing:
            return "manifest"
        case .missingEntry, .sizeMismatch, .checksumMismatch:
            return "payload"
        case .catalogueUnreadable, .catalogueSchemaUnknown, .catalogueSchemaUnsupported, .sourceCountMismatch:
            return "compiled-catalogue"
        case .revisionCollision, .revisionNotNewer:
            return "revision"
        }
    }
}
