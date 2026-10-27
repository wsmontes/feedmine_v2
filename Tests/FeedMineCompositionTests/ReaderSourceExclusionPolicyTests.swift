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
