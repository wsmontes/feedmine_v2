import Foundation
import XCTest
@testable import FeedMineComposition

/// PD-10's sync rules as values: a check is due only when no verification succeeded in the last ~24 h, an equal
/// revision is a no-op, and an older revision never moves the snapshot back. No scheduler is exercised because
/// there is none — these are the decisions a caller makes.
final class CatalogSyncPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - When to check

    func testACheckIsDueWhenNoVerificationSucceededInTheLastDay() {
        let stale = CatalogSyncRecord(verifiedRevision: 5, verifiedAt: now.addingTimeInterval(-25 * 60 * 60))
        XCTAssertEqual(CatalogSyncPolicy.decision(record: stale, now: now, remoteRevision: 6),
            .check(remoteRevision: 6))

        let never = CatalogSyncRecord()
        XCTAssertEqual(CatalogSyncPolicy.decision(record: never, now: now, remoteRevision: nil),
            .check(remoteRevision: nil))
    }

    func testNoCheckIsDueWhenAVerificationSucceededWithinTheDay() {
        let recent = now.addingTimeInterval(-23 * 60 * 60)
        let record = CatalogSyncRecord(verifiedRevision: 5, verifiedAt: recent)
        XCTAssertEqual(CatalogSyncPolicy.decision(record: record, now: now, remoteRevision: 6),
            .skip(verifiedAt: recent))
    }

    func testACheckIsDeferredAndStatedWhenNoNetworkOpportunityExists() {
        let record = CatalogSyncRecord()
        XCTAssertEqual(CatalogSyncPolicy.decision(record: record, now: now, allowed: false),
            .deferReason("no network opportunity was expressed"))
    }

    func testTheWindowIsOneDay() {
        let boundary = now.addingTimeInterval(-CatalogSyncPolicy.verificationWindow)
        XCTAssertEqual(CatalogSyncPolicy.verificationWindow, 86_400)
        // Exactly at the boundary a check is due: the window has elapsed.
        XCTAssertEqual(CatalogSyncPolicy.decision(record: CatalogSyncRecord(verifiedAt: boundary), now: now),
            .check(remoteRevision: nil))
    }

    // MARK: - Whether an offer is worth acting on

    func testANewerRevisionIsAccepted() {
        let remote = CatalogManifest(revision: 6, sourceCount: 10, fileCount: 1, files: [entry()])
        let active = CatalogManifest(revision: 5, sourceCount: 10, fileCount: 1, files: [entry()])
        XCTAssertEqual(CatalogOffer.decide(remote: remote, active: active), .accept(6))
    }

    func testAnEqualRevisionWithAnIdenticalDeclarationIsUpToDate() {
        let manifest = CatalogManifest(revision: 5, sourceCount: 10, fileCount: 1, files: [entry()])
        XCTAssertEqual(CatalogOffer.decide(remote: manifest, active: manifest), .upToDate(5))
    }

    func testAnEqualRevisionWithADifferentDeclarationIsACollision() {
        let remote = CatalogManifest(revision: 5, sourceCount: 11, fileCount: 1, files: [entry()])
        let active = CatalogManifest(revision: 5, sourceCount: 10, fileCount: 1, files: [entry()])
        XCTAssertEqual(CatalogOffer.decide(remote: remote, active: active), .collision(5))
    }

    /// Criterion 3: the published revision has 118 OPML entries; the device descriptor has those same
    /// entries plus a locally derived SQLite with an unrelated digest. That is not a collision.
    func testThe118PublicOpmlEntriesEqualThe119EntryLocalDescriptor() {
        let opml = (0..<118).map { index in
            CatalogManifestEntry(path: String(format: "Feeds/%03d.opml", index), bytes: 10,
                sha256: String(repeating: "a", count: 64))
        }
        let derived = CatalogManifestEntry(path: "catalog.sqlite", bytes: 8_000,
            sha256: String(repeating: "b", count: 64))
        let publicManifest = CatalogManifest(revision: 5, generatedAt: "public", sourceCount: 77_443,
            fileCount: 118, files: opml)
        let localDescriptor = CatalogManifest(revision: 5, generatedAt: "derived", sourceCount: 77_443,
            fileCount: 119, files: opml + [derived])
        XCTAssertEqual(CatalogOffer.decide(remote: publicManifest, active: localDescriptor), .upToDate(5))
    }

    /// Criterion 4: ignoring the derived SQLite may not ignore any material OPML change.
    func testSameRevisionWithChangedPublicOpmlDigestIsStillCollision() {
        let original = CatalogManifestEntry(path: "Feeds/01.opml", bytes: 10,
            sha256: String(repeating: "a", count: 64))
        let modified = CatalogManifestEntry(path: "Feeds/01.opml", bytes: 10,
            sha256: String(repeating: "c", count: 64))
        let derived = entry()
        let active = CatalogManifest(revision: 5, sourceCount: 10, fileCount: 2,
            files: [original, derived])
        let remote = CatalogManifest(revision: 5, sourceCount: 10, fileCount: 1, files: [modified])
        XCTAssertEqual(CatalogOffer.decide(remote: remote, active: active), .collision(5))
    }

    func testAnOlderRevisionIsStale() {
        let remote = CatalogManifest(revision: 4, sourceCount: 10, fileCount: 1, files: [entry()])
        let active = CatalogManifest(revision: 5, sourceCount: 10, fileCount: 1, files: [entry()])
        XCTAssertEqual(CatalogOffer.decide(remote: remote, active: active), .stale(4))
    }

    func testWithNothingInstalledAnyRevisionIsAccepted() {
        let remote = CatalogManifest(revision: 1, sourceCount: 10, fileCount: 1, files: [entry()])
        XCTAssertEqual(CatalogOffer.decide(remote: remote, active: nil), .accept(1))
    }

    private func entry() -> CatalogManifestEntry {
        CatalogManifestEntry(path: "catalog.sqlite", bytes: 10, sha256: String(repeating: "a", count: 64))
    }
}
