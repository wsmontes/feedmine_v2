//
// File: CatalogInstallation.swift
// Module: FeedMineComposition
//
// Responsibility:
// The one owner of the app's **managed catalogue snapshot** (PD-10): verifying a manifest, holding the verified
// local copy, activating a revision atomically, and keeping a durable record of every revision accepted or
// refused. The catalogue is *replaceable*; it is verified and installed here and opened read-only from here.
//
// A bundled snapshot is verified **in place**: the catalogue this build ships is already where it should be, so
// installation records its identity, its compiled revision and the manifest beside it — no copy, and nothing
// moved. A **fetched** revision is copied under its content fingerprint, and the pointer moves only after the
// bytes are complete.
//
// Nothing here opens, writes or deletes the runtime store. The reader's personal data — imported sources,
// bookmarks, collections, history, session state — lives in `runtime.sqlite` under the app's own directory and
// is never named here, so a refused or removed catalogue revision cannot reach it (PD-10: "preserve separation
// between the replaceable catalogue and the durable personal/runtime data"). A source the public catalogue drops
// therefore stays the reader's; only the managed universe stops offering it.
//
// No network, no timer, no task, no acquisition path: this is a value the app calls, not a scheduler. Whether and
// when to consult the authority is a caller's decision (`CatalogSyncPolicy`); performing a request is
// `CatalogUpdateChannel`'s single job.
//
// Does not own: fetching (`CatalogUpdateChannel`), the decision to check (`CatalogSyncPolicy`), or the
// catalogue's own compiled identity (`LegacyCatalogReader`, which reports the snapshot's declared version).
import Foundation
import FeedMinePersistence

/// One accepted or refused catalogue revision, as the external preparation report reads it.
public struct CatalogRevisionRecord: Hashable, Sendable, Codable {
    public enum Outcome: String, Hashable, Sendable, Codable {
        /// A revision was verified and is the active snapshot (a fetched one).
        case activated
        /// A revision was verified at launch from the copy this build ships.
        case bootstrapped
        /// A revision was offered, refused, and the previous snapshot kept.
        case rejected
        /// Nothing was verified, for the stated reason. Never a pass.
        case deferred
    }

    public let revision: Int?
    public let fingerprint: String?
    public let outcome: Outcome
    public let reason: String
    public let kind: String?
    public let at: String

    public init(revision: Int?, fingerprint: String?, outcome: Outcome, reason: String, kind: String?, at: String) {
        self.revision = revision
        self.fingerprint = fingerprint
        self.outcome = outcome
        self.reason = reason
        self.kind = kind
        self.at = at
    }
}

/// A catalogue revision that has been verified and is readable, immutable.
public struct CatalogSnapshot: Hashable, Sendable {
    public let manifest: CatalogManifest
    public let catalogueURL: URL
    /// The snapshot's own declared revision (`catalog_metadata.catalog_version`), when it declares one — the
    /// value provenance stamps (the seed for `CatalogGeneration`), reported so it can be traced.
    public let declaredRevision: Int64?
    /// Content-addressed identity: the SHA-256 of the compiled catalogue, or empty when nothing verified it.
    public let fingerprint: String

    public var revision: Int { manifest.revision }
    public var sourceCount: Int { manifest.sourceCount }
}

/// The outcome of one offer to install a revision. `installed` is the only state in which anything changed;
/// `rejected` names the reason and leaves the previous snapshot exactly as it was.
public enum CatalogInstallOutcome: Hashable, Sendable {
    case installed(CatalogSnapshot)
    case rejected(CatalogRejection)
}

/// What the active/previous pointer names: where to read the snapshot, and where its manifest sits. Stored as
/// JSON, so the bundled case (a catalogue verified where it already lives) and the fetched case (a copy under
/// `snapshots/`) resolve identically.
private struct CatalogPointer: Codable {
    let fingerprint: String
    let cataloguePath: String
    let manifestPath: String
}

/// Installs, activates and audits managed catalogue snapshots. Local files only.
public struct CatalogInstallation: Sendable {
    /// Where the snapshots, the active pointer and the ledger live. A directory of its own, beside — never
    /// inside — the runtime database.
    public let directory: URL
    /// What this build ships. `nil` stands for "this build carries no catalogue", stated rather than faked.
    public let bundledCatalogue: URL?
    public let bundledManifest: URL?
    private let now: @Sendable () -> Date

    public static let ledgerName = "quarantine.jsonl"

    public init(directory: URL, bundledCatalogue: URL?, bundledManifest: URL?,
        now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.bundledCatalogue = bundledCatalogue
        self.bundledManifest = bundledManifest
        self.now = now
    }

    /// The layout this app uses: `<appDirectory>/catalogue`. Both the catalogue and the descriptor that
    /// describes it are resources of the **app** bundle — the pair is one declaration and one set of bytes, and
    /// the descriptor is authoritative because it is the one shipped beside the catalogue. The two used to come
    /// from different bundles; that made verification read a descriptor for bytes it did not describe, which
    /// `bootstrap()` answers with the degraded path (the catalogue is then served unverified, PD-10's "never a
    /// pass" stated in the ledger), so the default now names one bundle for both.
    public init(appDirectory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(appDirectory: appDirectory, catalogueBundle: .main, descriptorBundle: .main, now: now)
    }

    /// The same, with the bundles stated — the app's own test surface needs both to name a fixture.
    public init(appDirectory: URL, catalogueBundle: Bundle, descriptorBundle: Bundle,
        now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(directory: appDirectory.appendingPathComponent("catalogue", isDirectory: true),
            bundledCatalogue: catalogueBundle.url(forResource: "catalog", withExtension: "sqlite"),
            bundledManifest: descriptorBundle.url(forResource: "catalog.manifest", withExtension: "json"),
            now: now)
    }

    /// Where the ledger an external preparation report reads is written.
    public var ledgerURL: URL { directory.appendingPathComponent(Self.ledgerName) }

    private var snapshotsDirectory: URL { directory.appendingPathComponent("snapshots", isDirectory: true) }
    private var activePointerURL: URL { directory.appendingPathComponent("active.json") }
    private var previousPointerURL: URL { directory.appendingPathComponent("previous.json") }

    // MARK: - Launch

    /// The launch path (PD-10: "cold/warm launch presents local first, including offline"). Verifies the copy
    /// this build ships if the descriptor describes it; otherwise keeps the last verified snapshot. When neither
    /// verifies, the bundled copy is still returned — unverified — and that deviation is written to the ledger
    /// rather than hidden, because a first run with no verified snapshot and no network must still present a
    /// feed. Every path here is local; nothing waits on a request.
    public func bootstrap() -> CatalogSnapshot? {
        if let installed = installBundled() { return installed }
        if let active = activeSnapshot() { return active }
        guard let bundledCatalogue, fileExists(bundledCatalogue) else { return nil }
        return degraded(bundledCatalogue)
    }

    /// Verifies and installs the bundled snapshot, in place. Equal revision with an identical declaration is a
    /// no-op (PD-10 criterion 3: "equal revision does not cause substitution"), and it is a no-op **without
    /// re-reading the catalogue**: the file this build ships cannot have changed under a running app, and a warm
    /// launch must not re-hash a hundred-megabyte asset on its way to presenting the feed. The bytes are read
    /// once, when the revision is new (or first seen); a later revision pays the verification once more.
    public func installBundled() -> CatalogSnapshot? {
        guard let bundledCatalogue, let bundledManifest,
            let data = try? Data(contentsOf: bundledManifest) else { return nil }
        if let bundled = try? CatalogManifest.decode(data), let active = activeSnapshot(),
            bundled.revision <= active.revision {
            if bundled.revision < active.revision { return nil }
            if active.manifest == bundled { return active }
            reject(.revisionCollision(bundled.revision, active: active.revision), revision: bundled.revision,
                fingerprint: bundled.catalogueEntry?.sha256)
            return nil
        }
        switch install(manifestData: data, catalogue: bundledCatalogue, outcome: .bootstrapped) {
        case .installed(let snapshot): return snapshot
        case .rejected: return nil
        }
    }

    // MARK: - Installing

    /// Verifies a manifest file and a compiled catalogue and activates them. On any refusal the previous snapshot
    /// and the active pointer are left exactly as they were, and the reason reaches the ledger.
    @discardableResult
    public func install(manifestURL: URL, catalogue: URL,
        outcome: CatalogRevisionRecord.Outcome = .activated) -> CatalogInstallOutcome {
        guard let data = try? Data(contentsOf: manifestURL) else {
            return reject(.malformedManifest, revision: nil, fingerprint: nil)
        }
        return install(manifestData: data, catalogue: catalogue, outcome: outcome)
    }

    /// The same step from bytes already in hand (a fetched manifest, or the bundled descriptor).
    @discardableResult
    public func install(manifestData: Data, catalogue: URL,
        outcome: CatalogRevisionRecord.Outcome = .activated) -> CatalogInstallOutcome {
        let manifest: CatalogManifest
        do { manifest = try CatalogManifest.decode(manifestData) }
        catch { return reject(.malformedManifest, revision: nil, fingerprint: nil) }
        if let rejection = CatalogManifest.validate(manifest, catalogue: catalogue) {
            return reject(rejection, revision: manifest.revision, fingerprint: manifest.catalogueEntry?.sha256)
        }
        return install(manifest: manifest, catalogue: catalogue, outcome: outcome)
    }

    /// Activates an already-validated manifest/catalogue pair.
    @discardableResult
    public func install(manifest: CatalogManifest, catalogue: URL,
        outcome: CatalogRevisionRecord.Outcome = .activated) -> CatalogInstallOutcome {
        if let rejection = CatalogManifest.validate(manifest, catalogue: catalogue) {
            return reject(rejection, revision: manifest.revision, fingerprint: manifest.catalogueEntry?.sha256)
        }
        guard let fingerprint = manifest.catalogueEntry?.sha256, !fingerprint.isEmpty else {
            return reject(.catalogueEntryMissing(manifest.revision), revision: manifest.revision, fingerprint: nil)
        }
        if let active = activeSnapshot() {
            if manifest.revision == active.revision {
                return active.manifest == manifest
                    ? .installed(active)
                    : reject(.revisionCollision(manifest.revision, active: active.revision),
                        revision: manifest.revision, fingerprint: fingerprint)
            }
            if manifest.revision < active.revision {
                return reject(.revisionNotNewer(manifest.revision, active: active.revision),
                    revision: manifest.revision, fingerprint: fingerprint)
            }
        }
        // Bundled snapshots are verified where they already are; fetched ones are copied under their content
        // fingerprint. The pointer is written only after the manifest is in place.
        let bundled = bundledCatalogue.map { sameFile($0, catalogue) } ?? false
        let pointer: CatalogPointer
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if bundled {
                let manifestURL = snapshotDirectory(fingerprint)
                    .appendingPathComponent("manifest.json")
                try write(data: try manifest.encoded(), to: manifestURL)
                pointer = CatalogPointer(fingerprint: fingerprint, cataloguePath: catalogue.path,
                    manifestPath: manifestURL.path)
            } else {
                try FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
                let directory = snapshotDirectory(fingerprint)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let localCatalogue = directory.appendingPathComponent("catalog.sqlite")
                let localManifest = directory.appendingPathComponent("manifest.json")
                try replace(file: catalogue, with: localCatalogue)
                try write(data: try manifest.encoded(), to: localManifest)
                pointer = CatalogPointer(fingerprint: fingerprint, cataloguePath: localCatalogue.path,
                    manifestPath: localManifest.path)
            }
            if let current = activePointer(), current.fingerprint != fingerprint {
                try? write(data: try JSONEncoder().encode(current), to: previousPointerURL)
            }
            try write(data: try JSONEncoder().encode(pointer), to: activePointerURL)
        } catch {
            return reject(.catalogueUnreadable(String(describing: error)), revision: manifest.revision,
                fingerprint: fingerprint)
        }
        let snapshot = CatalogSnapshot(manifest: manifest,
            catalogueURL: URL(fileURLWithPath: pointer.cataloguePath), declaredRevision: declaredRevision(of: catalogue),
            fingerprint: fingerprint)
        // What the reader of a ledger row needs to know is not *that* it verified, but *from where*: the copy
        // this build ships at launch, or a payload fetched from the authority. The outcomes differ and the
        // sentence must too — the architect's correction, 2026-10-11: "revision 5 verified and activated" is
        // true of a bootstrap and does not prove an update happened, which is exactly what criterion 4 needs.
        let provenance = outcome == .bootstrapped
            ? "verified from the copy this build ships"
            : "verified from a fetched payload and activated"
        record(CatalogRevisionRecord(revision: manifest.revision, fingerprint: fingerprint, outcome: outcome,
            reason: "revision \(manifest.revision) \(provenance)",
            kind: outcome == .bootstrapped ? "bootstrap" : "update", at: timestamp()))
        return .installed(snapshot)
    }

    /// Installs a **fetched** revision: a payload directory already downloaded (the OPML tree), plus whatever
    /// builds the snapshot. Every declared OPML is verified by size and SHA-256 **before** anything is built
    /// (PD-10), and the built snapshot is verified against the manifest before it is activated; any failure
    /// preserves the previous snapshot and records the reason.
    ///
    /// `build` stands for the compilation step, and it is a caller parameter rather than a hidden member so the
    /// order this type enforces (verify the payload, then build, then verify the artefact, then move the pointer) is
    /// the only order either caller can run: `CatalogUpdater` supplies the device's compiler and the declaration
    /// that covers what it produced; a test supplies one that fails, to prove the previous snapshot survives.
    @discardableResult
    public func installOffer(manifestData: Data, payload: URL, build: (URL) throws -> URL,
        outcome: CatalogRevisionRecord.Outcome = .activated) -> CatalogInstallOutcome {
        let manifest: CatalogManifest
        do { manifest = try CatalogManifest.decode(manifestData) }
        catch { return reject(.malformedManifest, revision: nil, fingerprint: nil) }
        if let rejection = CatalogManifest.validate(manifest, payload: payload) {
            return reject(rejection, revision: manifest.revision, fingerprint: manifest.catalogueEntry?.sha256)
        }
        guard let catalogueEntry = manifest.catalogueEntry else {
            return reject(.catalogueEntryMissing(manifest.revision), revision: manifest.revision, fingerprint: nil)
        }
        let built: URL
        do { built = try build(payload) }
        catch {
            return reject(.catalogueUnreadable("build failed: \(String(describing: error))"),
                revision: manifest.revision, fingerprint: catalogueEntry.sha256)
        }
        if let rejection = CatalogManifest.validate(manifest, catalogue: built) {
            return reject(rejection, revision: manifest.revision, fingerprint: catalogueEntry.sha256)
        }
        guard let active = activeSnapshot() else {
            return install(manifest: manifest, catalogue: built, outcome: outcome)
        }
        if manifest.revision == active.revision {
            return active.manifest == manifest
                ? .installed(active)
                : reject(.revisionCollision(manifest.revision, active: active.revision),
                    revision: manifest.revision, fingerprint: catalogueEntry.sha256)
        }
        if manifest.revision < active.revision {
            return reject(.revisionNotNewer(manifest.revision, active: active.revision),
                revision: manifest.revision, fingerprint: catalogueEntry.sha256)
        }
        return install(manifest: manifest, catalogue: built, outcome: outcome)
    }

    /// Re-applies the snapshot that was active before the current one. Activation is atomic and recoverable: a
    /// failure between here and `activeSnapshot()` can be undone by this call, and installing a snapshot never
    /// deletes the one it replaces.
    @discardableResult
    public func rollback() -> CatalogSnapshot? {
        guard let previous = previousPointer(), let snapshot = snapshot(for: previous) else { return nil }
        if let current = activePointer() {
            try? write(data: try JSONEncoder().encode(current), to: previousPointerURL)
        }
        try? write(data: try JSONEncoder().encode(previous), to: activePointerURL)
        record(CatalogRevisionRecord(revision: snapshot.revision, fingerprint: snapshot.fingerprint,
            outcome: .activated, reason: "rolled back to revision \(snapshot.revision)", kind: "rollback",
            at: timestamp()))
        return snapshot
    }

    // MARK: - Reading

    public func activeSnapshot() -> CatalogSnapshot? { snapshot(for: activePointer()) }

    /// Everything the ledger holds, oldest first — accepted and refused alike, so one pass prints the
    /// normalisations and the quarantine.
    public func ledger() -> [CatalogRevisionRecord] {
        guard let data = try? Data(contentsOf: ledgerURL),
            let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(CatalogRevisionRecord.self, from: lineData)
        }
    }

    /// A complete record for a check that did not run. The caller owns the ledger; this states the value.
    public func deferredRecord(reason: String, kind: String = "policy") -> CatalogRevisionRecord {
        CatalogRevisionRecord(revision: nil, fingerprint: nil, outcome: .deferred, reason: reason, kind: kind,
            at: timestamp())
    }

    /// Append one record to the ledger (a report; it never rewrites history).
    public func record(_ record: CatalogRevisionRecord) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? appendToLedger(record)
    }

    /// Records a refusal that happened **before** an installation attempt could be made — a payload that did not
    /// arrive, or arrived diverging from its declaration — and hands the outcome back. Exposed because the ledger
    /// has one owner: a caller that refuses an offer upstream (`CatalogUpdater`, for the payload it downloads)
    /// writes its row in this shape rather than inventing a second one.
    @discardableResult
    public func reject(_ rejection: CatalogRejection, revision: Int?, fingerprint: String?)
        -> CatalogInstallOutcome {
        record(CatalogRevisionRecord(revision: revision, fingerprint: fingerprint, outcome: .rejected,
            reason: rejection.reason, kind: rejection.kind, at: timestamp()))
        return .rejected(rejection)
    }

    // MARK: - Private

    /// Resolves a pointer to a snapshot: read the manifest it names, and confirm the catalogue is where the
    /// pointer says. Nothing is inferred from a path.
    private func snapshot(for pointer: CatalogPointer?) -> CatalogSnapshot? {
        guard let pointer else { return nil }
        let catalogueURL = URL(fileURLWithPath: pointer.cataloguePath)
        let manifestURL = URL(fileURLWithPath: pointer.manifestPath)
        guard fileExists(catalogueURL), let data = try? Data(contentsOf: manifestURL),
            let manifest = try? CatalogManifest.decode(data) else { return nil }
        return CatalogSnapshot(manifest: manifest, catalogueURL: catalogueURL,
            declaredRevision: declaredRevision(of: catalogueURL), fingerprint: pointer.fingerprint)
    }

    /// Where an in-place snapshot's manifest lives, keyed by fingerprint so two revisions of the same bundled
    /// file cannot claim one record. Fetched snapshots use the same directory for the copy they install.
    private func snapshotDirectory(_ fingerprint: String) -> URL {
        snapshotsDirectory.appendingPathComponent(fingerprint, isDirectory: true)
    }

    /// Whether a catalogue is the copy this build ships, so it is recorded in place rather than duplicated.
    private func sameFile(_ left: URL, _ right: URL) -> Bool {
        left.standardizedFileURL.resolvingSymlinksInPath() == right.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func pointer(at url: URL) -> CatalogPointer? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CatalogPointer.self, from: data)
    }

    private func activePointer() -> CatalogPointer? { pointer(at: activePointerURL) }
    private func previousPointer() -> CatalogPointer? { pointer(at: previousPointerURL) }

    private func degraded(_ bundledCatalogue: URL) -> CatalogSnapshot {
        record(CatalogRevisionRecord(revision: nil, fingerprint: nil, outcome: .deferred,
            reason: "serving the bundled catalogue unverified: no verified snapshot is installed",
            kind: "degraded", at: timestamp()))
        return CatalogSnapshot(manifest: CatalogManifest(revision: 0, sourceCount: 0, fileCount: 0, files: []),
            catalogueURL: bundledCatalogue, declaredRevision: declaredRevision(of: bundledCatalogue),
            fingerprint: "")
    }

    private func declaredRevision(of catalogue: URL) -> Int64? {
        guard let reader = try? LegacyCatalogReader(catalogURL: catalogue) else { return nil }
        return try? reader.metadata()?.revision
    }

    private func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: now())
    }

    private func appendToLedger(_ record: CatalogRevisionRecord) throws {
        var data = (try? Data(contentsOf: ledgerURL)) ?? Data()
        if !data.isEmpty, data.last != UInt8(ascii: "\n") { data.append(UInt8(ascii: "\n")) }
        data.append(try JSONEncoder().encode(record))
        data.append(UInt8(ascii: "\n"))
        try data.write(to: ledgerURL, options: .atomic)
    }

    /// Copies `source` over `destination` by writing elsewhere and moving into place, so a reader never sees a
    /// half-written catalogue and a failure leaves the previous file intact.
    private func replace(file source: URL, with destination: URL) throws {
        let temporary = destination.appendingPathExtension("incoming")
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.copyItem(at: source, to: temporary)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private func write(data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let temporary = url.appendingPathExtension("incoming")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
