//
// File: CatalogUpdater.swift
// Module: FeedMineComposition
//
// Responsibility:
// One accepted offer, end to end: download the payload the authority declared into a working directory, verify
// every declared byte, compile it into a `catalog.sqlite` in staging, declare the artefact that was just built, and
// hand the pair to `CatalogInstallation` for verification and atomic activation. This is PD-10's device update
// (release criterion 4); before it, every piece existed and no caller joined them.
//
// The order is the architect's, and it is the order here: **download and full validation precede the staging
// compilation**, and **validating the SQLite precedes the atomic activation**. Any failure at any step preserves
// the previous snapshot exactly as it was, and says why in the ledger.
//
// What a substitution reaches, and what it does not: the managed catalogue and the work that resolves from it after
// this returns. It never touches the runtime store — imported sources, bookmarks, collections, history and session
// state are not named anywhere on this path (`CatalogInstallation` owns that separation) — and it does not swap the
// catalogue an open session already reads: that session keeps the snapshot it opened with.
//
// Nothing here is scheduled: the caller decides when, `CatalogUpdateChannel` performs the requests,
// `CatalogCompiler` compiles, `CatalogInstallation` installs.
//
// Does not own: the decision to check or to accept (`CatalogSyncPolicy`), the transport (`CatalogUpdateChannel`),
// the compilation rules (`CatalogCompiler`), or activation and the ledger (`CatalogInstallation`).
import Foundation
import FeedMinePersistence

/// Runs one accepted offer through the update path: download, verify, compile in staging, activate atomically.
public struct CatalogUpdater: Sendable {
    /// What one attempt produced. `activated` is the only case in which anything changed.
    public enum Outcome: Hashable, Sendable {
        /// The revision was verified, compiled and is now the active snapshot.
        case activated(CatalogSnapshot)
        /// The offer was refused, by name, and the previous snapshot is untouched.
        case rejected(CatalogRejection)
        /// Nothing was verified this time. Never a verdict about the revision.
        case unavailable(String)
    }

    private let installation: CatalogInstallation
    private let channel: CatalogUpdateChannel
    private let compiler: CatalogCompiler
    private let workingDirectory: URL

    /// `workingDirectory` holds the download, the staging output and the declared artefact for the duration of one
    /// attempt, and is removed when the attempt ends — success or failure. Nothing outside it is written.
    public init(installation: CatalogInstallation, channel: CatalogUpdateChannel,
        compiler: CatalogCompiler = CatalogCompiler(),
        workingDirectory: URL = FileManager.default.temporaryDirectory) {
        self.installation = installation
        self.channel = channel
        self.compiler = compiler
        self.workingDirectory = workingDirectory
    }

    /// Downloads, verifies, compiles and activates `manifest`, or refuses and leaves the active snapshot exactly as
    /// it is. Every outcome reaches the ledger: `CatalogInstallation` writes the rows for the revision it judged
    /// (activated, or refused by name) and this writes the rows for the steps the installation never saw (nothing
    /// arrived, the compilation failed).
    ///
    /// The manifest handed to the installation is not the one fetched: it is that manifest's own inventory plus the
    /// one entry the device can declare — the compiled catalogue, measured from the artefact this attempt produced
    /// (`CatalogManifest.declaringCompiledCatalogue(at:)`). The installation verifies the OPML inventory again
    /// against the downloaded tree, then the artefact against that declaration, then the compiled catalogue against
    /// the schema this build reads and against the authority's own `sourceCount` — that last comparison is the build
    /// report's side of the reference procedure (`scripts/bootstrap_catalog.py`), read from the artefact rather
    /// than from a report this caller would have to be trusted to hand over.
    public func install(_ manifest: CatalogManifest) async -> Outcome {
        let work = workingDirectory.appendingPathComponent("catalog-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }

        switch await channel.download(manifest, into: work.appendingPathComponent("payload", isDirectory: true)) {
        case .unavailable(let why):
            // Nothing was verified this time. The previous snapshot stands, the check window is not refreshed, and
            // the reason is recorded rather than passed over.
            installation.record(installation.deferredRecord(reason: "no payload this time: \(why)", kind: "network"))
            return .unavailable(why)
        case .rejected(let rejection):
            return refuse(rejection, revision: manifest.revision)
        case .payload(let payload):
            let staging = work.appendingPathComponent("staging/catalog.sqlite")
            do { _ = try compiler.compile(feedsRoot: payload.feedsRoot, staging: staging) }
            catch {
                return refuse(.catalogueUnreadable("compilation failed: \(String(describing: error))"),
                    revision: manifest.revision)
            }
            let declaration: Data
            do { declaration = try manifest.declaringCompiledCatalogue(at: staging).encoded() }
            catch let rejection as CatalogRejection { return refuse(rejection, revision: manifest.revision) }
            catch { return refuse(.catalogueUnreadable(String(describing: error)), revision: manifest.revision) }
            switch installation.installOffer(manifestData: declaration, payload: payload.root,
                build: { _ in staging }) {
            case .installed(let snapshot):
                return .activated(snapshot)
            case .rejected(let rejection):
                // The installation recorded it: one owner writes the ledger.
                return .rejected(rejection)
            }
        }
    }

    /// Records a refusal this path owns and hands it back.
    private func refuse(_ rejection: CatalogRejection, revision: Int?) -> Outcome {
        installation.reject(rejection, revision: revision, fingerprint: nil)
        return .rejected(rejection)
    }
}
