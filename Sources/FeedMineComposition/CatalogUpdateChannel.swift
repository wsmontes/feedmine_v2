//
// File: CatalogUpdateChannel.swift
// Module: FeedMineComposition
//
// Responsibility:
// The one place the app reaches `https://github.com/wawasoft/feed-repository`: it fetches `manifest.json` with
// one conditional GET, and it downloads the OPML payload that manifest declares. It is a *fetch*, not a policy:
// it returns the bytes when the server says the manifest changed, reports "not modified" or a reason, and — for
// the payload — writes the declared files under the declared paths and hands back the directory the manifest
// paths are relative to plus the feeds tree the compiler takes, or a named reason it did not. PD-10's "discreet"
// attributes live outside this type: the caller decides when to call it (`CatalogSyncPolicy`), and the call runs
// where the caller puts it, never in the first-presentation barrier.
//
// Bytes that arrived are verified by the declaration that asked for them (`CatalogManifest.validate(_:payload:)`:
// every declared OPML by size and SHA-256, in manifest order), because a fetch that hands on unverified bytes is a
// fetch nothing can build on. Nothing is compiled, installed or activated here.
//
// Does not own: deciding whether an offer is worth acting on, compiling or installing anything, or scheduling.
import Foundation

/// The manifest the app asked for, or the reason it did not get one.
public enum CatalogUpdateFetch: Hashable, Sendable {
    /// The manifest changed (or was fetched without a validator). The bytes are the authority's.
    case manifest(Data)
    /// The server answered 304 or the ETag was unchanged: nothing to parse, nothing to rebuild.
    case notModified
    /// No manifest this time, and why. Never treated as a verified state.
    case unavailable(String)
}

/// The OPML payload a revision declares, downloaded and verified: where its declared files are, and the tree the
/// compiler takes from there.
public struct CatalogPayload: Hashable, Sendable {
    /// The directory the manifest's paths are relative to — the download root, and what
    /// `CatalogManifest.validate(_:payload:)` verified.
    public let root: URL
    /// The deepest directory that holds every declared OPML: the `feedsRoot` `CatalogCompiler.compile` takes.
    public let feedsRoot: URL

    public init(root: URL, feedsRoot: URL) {
        self.root = root
        self.feedsRoot = feedsRoot
    }
}

/// The payload the channel obtained, or why it did not.
public enum CatalogPayloadFetch: Hashable, Sendable {
    /// Every declared OPML is on disk under its declared path and matches its declaration.
    case payload(CatalogPayload)
    /// Nothing was obtained this time — no response at all, a timeout, a write that failed. Never a verdict about
    /// the revision, and never a reason to touch the active snapshot.
    case unavailable(String)
    /// The authority served a payload that does not match what it declared, or does not serve a file it declares.
    /// A refusal, named by `CatalogRejection`.
    case rejected(CatalogRejection)
}

public struct CatalogUpdateChannel: Sendable {
    /// The authority PD-10 names. Overridable so a test can point at its own server or file; never silently
    /// pointed at a mirror in production.
    public static let publicManifestURL = URL(string: "https://raw.githubusercontent.com/wawasoft/feed-repository/main/manifest.json")!

    private let manifestURL: URL
    private let session: URLSession
    /// The ETag of the last manifest this app parsed, so a repeat check costs one conditional request.
    private let storedETag: @Sendable () -> String?
    private let storeETag: @Sendable (String?) -> Void

    public init(manifestURL: URL = CatalogUpdateChannel.publicManifestURL, session: URLSession,
        storedETag: @escaping @Sendable () -> String? = { nil },
        storeETag: @escaping @Sendable (String?) -> Void = { _ in }) {
        self.manifestURL = manifestURL
        self.session = session
        self.storedETag = storedETag
        self.storeETag = storeETag
    }

    /// One conditional GET. A failure — offline, timeout, non-200 — is `.unavailable`, which the caller treats
    /// as "nothing verified this time", never as a reason to change the snapshot.
    public func fetch() async -> CatalogUpdateFetch {
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = storedETag() { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable("no HTTP response") }
            switch http.statusCode {
            case 304:
                return .notModified
            case 200:
                storeETag(http.value(forHTTPHeaderField: "ETag"))
                // The authority's own bytes are handed on: the caller parses and hashes exactly what was served,
                // never a re-encode of it.
                guard (try? CatalogManifest.decode(data)) != nil else {
                    return .unavailable("manifest is not readable in the published shape")
                }
                return .manifest(data)
            default:
                return .unavailable("manifest request answered \(http.statusCode)")
            }
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    /// Downloads the OPML inventory `manifest` declares into `directory`, under the paths it declares, and verifies
    /// every declared byte before returning. This is the "download and full validation" half of PD-10's update:
    /// nothing is compiled or installed here, and the caller compiles what this returned (`CatalogUpdater`).
    ///
    /// The distinction the two failure cases draw is the one the ledger needs. A transport failure — no response at
    /// all — is `.unavailable`: nothing was verified this time, and the caller degrades exactly as it does when the
    /// manifest itself cannot be fetched. Anything the authority did serve that does not match its own declaration
    /// — a file it does not serve, the wrong number of bytes, the wrong digest — is `.rejected`, named, because the
    /// payload contradicts the declaration that asked for it.
    ///
    /// The manifest's own directory is the payload's base: the published manifest declares paths relative to
    /// itself (`Feeds/…`), and each declared path is joined component by component, so a declared path addresses
    /// one file under the root. A path that is not a safe relative path is refused before anything is written.
    public func download(_ manifest: CatalogManifest, into directory: URL) async -> CatalogPayloadFetch {
        if let rejection = CatalogManifest.validate(manifest) { return .rejected(rejection) }
        // A compiled catalogue is not this channel's to fetch. This build compiles the OPML tree it verified
        // itself, so taking the authority's `.sqlite` would be installing a snapshot nothing on the device built.
        // The public channel is OPML-only; a manifest that declares otherwise is refused rather than guessed at.
        if let entry = manifest.catalogueEntry {
            return .rejected(.invalidDeclaration(
                "the inventory declares a compiled catalogue (\(entry.path)); this channel downloads the OPML "
                    + "tree and compiles it on the device"))
        }
        let entries = manifest.opmlEntries
        for entry in entries {
            guard CatalogManifest.isSafeRelativePath(entry.path) else { return .rejected(.unsafePath(entry.path)) }
            switch await fetch(from: joining(entry.path, onto: baseURL)) {
            case .unavailable(let why):
                return .unavailable(why)
            case .notServed:
                return .rejected(.missingEntry(entry.path))
            case .bytes(let data):
                let destination = joining(entry.path, onto: directory)
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    return .unavailable("could not write \(entry.path): \(String(describing: error))")
                }
            }
        }
        if let rejection = CatalogManifest.validate(manifest, payload: directory) { return .rejected(rejection) }
        return .payload(CatalogPayload(root: directory, feedsRoot: feedsRoot(of: entries, under: directory)))
    }

    // MARK: - Private

    /// The directory the manifest's own paths are relative to: the manifest URL names one file, so the payload
    /// lives beside it.
    private var baseURL: URL { manifestURL.deletingLastPathComponent() }

    private enum FileFetch {
        case bytes(Data)
        /// The authority answered, and the answer was not the file.
        case notServed
        /// No answer worth building on: offline, timeout, or a response that is not HTTP.
        case unavailable(String)
    }

    private func fetch(from url: URL) async -> FileFetch {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable("no HTTP response for \(url.absoluteString)")
            }
            return http.statusCode == 200 ? .bytes(data) : .notServed
        } catch {
            return .unavailable(String(describing: error))
        }
    }

    /// A declared path joined onto a root, component by component: each component is escaped, so a declared path
    /// addresses exactly one file under the root and cannot reach outside it.
    private func joining(_ path: String, onto root: URL) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    /// The tree the compiler takes: the deepest directory that holds every declared OPML. The published manifest
    /// happens to declare its inventory under `Feeds/`, and this derives that root from the declaration rather than
    /// naming it, so a manifest whose files sit in the payload root yields the payload root.
    private func feedsRoot(of entries: [CatalogManifestEntry], under root: URL) -> URL {
        guard var shared = entries.first?.path.split(separator: "/").dropLast().map(String.init) else {
            return root
        }
        for entry in entries.dropFirst() {
            let components = entry.path.split(separator: "/").dropLast().map(String.init)
            shared = zip(shared, components).prefix { $0 == $1 }.map { $0.0 }
            if shared.isEmpty { return root }
        }
        return joining(shared.joined(separator: "/"), onto: root)
    }
}
