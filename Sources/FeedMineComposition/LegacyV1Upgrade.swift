//
// File: LegacyV1Upgrade.swift
// Module: FeedMineComposition
//
// Responsibility:
// The V1 upgrade's launch gate. It finds V1's `user.sqlite` in the **same app container** (Application
// Support/Feedmine, or the pre-1.0 Documents location V1 itself migrated from), runs the import exactly once,
// and returns the durable outcome. A second launch reads the completed marker and does no work.
//
// It never writes beside V1: the reader opens the file read-only and the import's destination is the existing
// runtime.sqlite. Nothing here invents a second database, a scheduler or a retry loop.
import Foundation
import FeedMineDomain
import FeedMinePersistence

public enum LegacyV1Upgrade: Sendable {
    public enum Outcome: Sendable {
        /// No V1 `user.sqlite` in this container.
        case noLegacyContainer
        /// A previous launch already completed (or found an unsupported generation). Nothing ran.
        case alreadyHandled(ReaderLegacyUpgradeReceipt)
        /// This launch carried what this build supports.
        case upgraded(LegacyUserStateImport.Report)
        /// The file exists and could not be read; the failure is recorded and no completed marker exists.
        case failed(String)
    }

    /// V1's own locations, in the order V1 used them: the 1.0 Application Support directory, then the older
    /// Documents file its `UserStateStore` moved from. `applicationSupport` is V2's **own** directory
    /// (`…/Application Support/FeedMine`), so its sibling is V1's (`…/Application Support/Feedmine`).
    public static func candidateUserStateURLs(applicationSupport: URL,
        documentsDirectory: URL? = nil) -> [URL] {
        let support = applicationSupport.deletingLastPathComponent()
        // The sibling directory is V1's `Feedmine`. It is looked up **by enumeration, case-insensitively**: a
        // case-insensitive volume (the simulator's, and any Mac volume with the default format) resolves
        // `FeedMine` and `Feedmine` to the same entry, and depends on which spelling created it — a hardcoded
        // second spelling silently resolves to nothing there (measured 2026-10-20: the rehearsal reported "no
        // legacy container" while the file existed). An exact match wins; otherwise the first case-variant.
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: support, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let feedmineSiblings = entries.filter { $0.lastPathComponent.lowercased() == "feedmine" }
        var candidates: [URL] = []
        if let exact = feedmineSiblings.first(where: { $0.lastPathComponent == "Feedmine" }) {
            candidates.append(exact)
        }
        candidates.append(contentsOf: feedmineSiblings.filter { $0.lastPathComponent != "Feedmine" })
        if candidates.isEmpty {
            // Nothing to enumerate yet: keep the documented spelling so the candidate list still states the
            // location this build expects, even when the directory does not exist.
            candidates = [support.appendingPathComponent("Feedmine", isDirectory: true)]
        }
        var urls = candidates.map { $0.appendingPathComponent("user.sqlite") }
        if let documentsDirectory, !documentsDirectory.appendingPathComponent("user.sqlite").path.isEmpty {
            urls.append(documentsDirectory.appendingPathComponent("user.sqlite"))
        }
        return urls
    }

    /// Runs at launch, before any session reads the library. The marker, the imported rows and every reported
    /// skip commit together; a failure records its own status and leaves no completed marker.
    @discardableResult
    public static func runAtLaunch(applicationSupport: URL, documentsDirectory: URL? = nil,
        into database: RuntimeDatabase, at date: Date = Date()) -> Outcome {
        let store = ReaderLibraryStore(database: database)
        if let existing = try? store.legacyUpgradeReceipt() {
            if existing.status == .completed || existing.status == .unsupported {
                return .alreadyHandled(existing)
            }
        }

        for candidate in candidateUserStateURLs(applicationSupport: applicationSupport,
            documentsDirectory: documentsDirectory) {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            do {
                let reader = try LegacyUserStateReader(url: candidate)
                guard try reader.isLegacyUserState() else { continue }
                let report = try LegacyUserStateImport.run(reader: reader, into: database, at: date)
                if report.schema == .unsupported {
                    if let receipt = try store.legacyUpgradeReceipt() { return .alreadyHandled(receipt) }
                    return .failed("V1 schema variant is not supported")
                }
                return .upgraded(report)
            } catch {
                let reason = String(describing: error)
                try? store.recordLegacyUpgradeFailure(sourcePath: candidate.path, reason: reason, at: date)
                return .failed(reason)
            }
        }
        return .noLegacyContainer
    }

    /// What the first open still owes the reader: a completed or unsupported upgrade whose notice was not
    /// presented. Reading it never changes it; `markLegacyUpgradeNoticePresented` does.
    public static func pendingNotice(in database: RuntimeDatabase) -> ReaderLegacyUpgradeReceipt? {
        guard let receipt = try? ReaderLibraryStore(database: database).legacyUpgradeReceipt(),
            !receipt.noticePresented, receipt.status != .failed else { return nil }
        return receipt
    }
}
