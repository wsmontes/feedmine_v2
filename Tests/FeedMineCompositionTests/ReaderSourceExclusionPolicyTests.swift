import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition

final class ReaderSourceExclusionPolicyTests: XCTestCase {
    func testVerifiedAliasProjectionExpandsBothIDsWithoutCrossingAuthority() {
        let old = "https://example.test/old", new = "https://example.test/new"
        // Projection of an already verified identity row; the verifier itself is covered by SourceIdentityIndexTests.
        let link = ReaderLibraryStore.SourceLink(sourceKey: old, anchorKey: old, currentKey: new,
            authority: "catalog", proof: "verified-row-fixture", requestURL: new)
        let anchor = LegacyCatalogImport.sourceID(forKey: old), current = LegacyCatalogImport.sourceID(forKey: new)
        for id in [anchor, current] {
            let snapshot = ReaderSourceExclusionSnapshot(settings: .init(contentSourceExclusions: [
                .init(sourceID: id, displayName: "Feed")]))
            XCTAssertEqual(ReaderSourceExclusionPolicy.sourceIDs(snapshot: snapshot, links: [old: link]), [anchor, current])
        }
        let readerID = ReaderSourceIdentity.sourceID(forKey: old)
        let imported = ReaderSourceExclusionSnapshot(settings: .init(contentSourceExclusions: [
            .init(sourceID: readerID, displayName: "Feed")]))
        XCTAssertEqual(ReaderSourceExclusionPolicy.sourceIDs(snapshot: imported, links: [old: link]), [readerID])
    }

    func testUnknownOrRemovedSourceRetainsItsOwnIdentityAndDisabledRulesExpandNothing() {
        let id = SourceID()
        let rules = [ReaderSourceExclusion(sourceID: id, displayName: "Removed source")]
        let active = ReaderSourceExclusionSnapshot(settings: .init(contentSourceExclusions: rules))
        XCTAssertEqual(ReaderSourceExclusionPolicy.sourceIDs(snapshot: active, links: [:]), [id])
        let inactive = ReaderSourceExclusionSnapshot(settings: .init(contentFiltersEnabled: false, contentSourceExclusions: rules))
        XCTAssertEqual(ReaderSourceExclusionPolicy.sourceIDs(snapshot: inactive, links: [:]), [])
    }
}

extension ReaderSourceExclusionPolicyTests {
    func testUnrestrictedCaptureDoesNotScanTheSourceIdentityIndex() throws {
        final class Statements: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [String] = []
            func append(_ value: String) { lock.lock(); storage.append(value); lock.unlock() }
            func reset() { lock.lock(); storage.removeAll(); lock.unlock() }
            var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let statements = Statements()
        let db = try RuntimeDatabase(location: .init(directory: root), sqlTrace: { statements.append($0) })
        _ = try ReaderPreferencesStore(database: db).initialize(sourceKeys: ["a"])
        statements.reset()
        let captured = try ReaderSourceExclusionPolicy.capture(in: db)
        XCTAssertEqual(captured.snapshot, .unrestricted)
        XCTAssertEqual(captured.sourceIDs, [])
        XCTAssertFalse(statements.values.contains { $0.lowercased().contains("from reader_source_identity") },
            "an opportunity with no active source rule must not scan the whole identity catalogue")
    }
}
