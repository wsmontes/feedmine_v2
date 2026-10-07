import XCTest
import FeedMineDomain
import FeedMinePublication

final class PublishedOriginTests: XCTestCase {
    func testHistoricalIDsAndExactAttributionRemainFrozen() {
        let record = OriginRecordID()
        let revision = OriginRevisionID()
        let source = SourceID()
        let provider = ProviderID()
        var sourceName = "  Example News\n"
        var providerName = "Author É"
        let origin = PublishedOrigin(originRecordID: record, originRevisionID: revision,
            sourceID: source, providerID: provider,
            sourceDisplayName: sourceName, providerDisplayName: providerName)
        sourceName = "Example Media"
        providerName = "Renamed Author"
        XCTAssertEqual(origin.originRecordID, record)
        XCTAssertEqual(origin.originRevisionID, revision)
        XCTAssertEqual(origin.sourceID, source)
        XCTAssertEqual(origin.providerID, provider)
        XCTAssertEqual(origin.sourceDisplayName, "  Example News\n")
        XCTAssertEqual(origin.providerDisplayName, "Author É")
        XCTAssertNotEqual(origin.sourceDisplayName, sourceName)
        XCTAssertNotEqual(origin.providerDisplayName, providerName)
    }

    func testSourceAndProviderCanBeAbsentIndependently() {
        let record = OriginRecordID()
        let revision = OriginRevisionID()
        let provider = ProviderID()
        let source = SourceID()
        let noSource = PublishedOrigin(originRecordID: record, originRevisionID: revision,
            sourceID: nil, providerID: provider, sourceDisplayName: nil, providerDisplayName: "Author")
        XCTAssertNil(noSource.sourceID)
        XCTAssertNil(noSource.sourceDisplayName)
        XCTAssertEqual(noSource.providerID, provider)
        let noProvider = PublishedOrigin(originRecordID: record, originRevisionID: revision,
            sourceID: source, providerID: nil, sourceDisplayName: "News", providerDisplayName: nil)
        XCTAssertEqual(noProvider.sourceID, source)
        XCTAssertNil(noProvider.providerID)
        XCTAssertNil(noProvider.providerDisplayName)
        let neither = PublishedOrigin(originRecordID: record, originRevisionID: revision,
            sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil)
        XCTAssertNil(neither.sourceID)
        XCTAssertNil(neither.providerID)
    }
}
