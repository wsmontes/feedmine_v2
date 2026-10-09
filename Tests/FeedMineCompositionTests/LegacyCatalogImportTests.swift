import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineComposition

/// PD-2: v1 catalog identity maps to stable, collision-resistant v2 UUIDs; fetch URL stays separate.
final class LegacyCatalogImportTests: XCTestCase {
    private func record(_ key: String, url: String, title: String = "Feed", enabled: Bool = true) -> LegacyCatalogSourceRecord {
        LegacyCatalogSourceRecord(key: key, title: title, requestURL: url, siteURL: nil, language: "pt", mediaKind: "text",
            qualityScore: nil, defaultEnabled: enabled, nodeKeys: ["news"])
    }

    func testIdentityIsDeterministicDistinctPerRoleAndIndependentOfFetchURL() throws {
        let a = try XCTUnwrap(LegacyCatalogImport.entry(record("https://a.example/rss", url: "https://a.example/rss?sig=1")))
        let again = try XCTUnwrap(LegacyCatalogImport.entry(record("https://a.example/rss", url: "https://a.example/rss?sig=2")))
        XCTAssertEqual(a.source.id, again.source.id); XCTAssertEqual(a.targetID, again.targetID); XCTAssertEqual(a.bindingID, again.bindingID)
        XCTAssertNotEqual(a.endpoint, again.endpoint)
        XCTAssertNotEqual(a.source.id.rawValue, a.targetID.rawValue)
        XCTAssertNotEqual(a.targetID.rawValue, a.bindingID.rawValue)
        let b = try XCTUnwrap(LegacyCatalogImport.entry(record("https://b.example/rss", url: "https://b.example/rss")))
        XCTAssertNotEqual(a.source.id, b.source.id)
        XCTAssertEqual(a.principal, "https://a.example/rss")
        let uuid = LegacyCatalogImport.stableUUID(namespace: "n", key: "k").uuid
        XCTAssertEqual(uuid.6 >> 4, 8); XCTAssertEqual(uuid.8 >> 6, 2)
    }

    func testUnfetchableAndUntitledRecords() {
        XCTAssertNil(LegacyCatalogImport.entry(record("k", url: "ftp://x.example/feed")))
        XCTAssertNil(LegacyCatalogImport.entry(record("k", url: "https://user:pw@x.example/feed")))
        XCTAssertEqual(LegacyCatalogImport.entry(record("k", url: "https://x.example/f", title: "  "))?.source.displayName, "x.example")
        XCTAssertEqual(LegacyCatalogImport.entry(record("k", url: "https://x.example/f", enabled: false))?.source.isEnabled, false)
    }
}
