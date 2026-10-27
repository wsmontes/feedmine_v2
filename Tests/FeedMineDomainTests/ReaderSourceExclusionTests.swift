import Foundation
import XCTest
import FeedMineDomain

final class ReaderSourceExclusionTests: XCTestCase {
    private let a = SourceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    private let b = SourceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

    func testOlderSettingsWithoutSourceRulesDecodeAsUnrestricted() throws {
        let old = Data(#"{"contentFiltersEnabled":true,"contentFilterRules":["casino"]}"#.utf8)
        let settings = try JSONDecoder().decode(ReaderSettings.self, from: old)
        XCTAssertEqual(settings.contentSourceExclusions, [])
        XCTAssertEqual(settings.contentFilterRules, ["casino"])
        XCTAssertEqual(ReaderSourceExclusionSnapshot(settings: settings), .unrestricted)
    }

    func testRoundTripKeepsIdentityNameAndDisabledRules() throws {
        let rule = ReaderSourceExclusion(sourceID: a, displayName: "BBC News")
        let settings = ReaderSettings(contentFiltersEnabled: false, contentSourceExclusions: [rule])
        let restored = try JSONDecoder().decode(ReaderSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
        XCTAssertEqual(restored.contentSourceExclusions, [rule])
        XCTAssertEqual(ReaderSourceExclusionSnapshot(settings: restored).sourceIDs, [])
        var enabled = restored
        enabled.contentFiltersEnabled = true
        XCTAssertEqual(ReaderSourceExclusionSnapshot(settings: enabled).sourceIDs, [a])
        XCTAssertEqual(enabled.contentSourceExclusions, restored.contentSourceExclusions)
    }

    func testIdentityDeduplicatesAndOrdersRulesWithoutMergingEqualNames() {
        let first = ReaderSourceExclusion(sourceID: a, displayName: "old name")
        let renamed = ReaderSourceExclusion(sourceID: a, displayName: "BBC News")
        let other = ReaderSourceExclusion(sourceID: b, displayName: "BBC News")
        var settings = ReaderSettings(contentSourceExclusions: [other, first, renamed])
        XCTAssertEqual(settings.contentSourceExclusions, [renamed, other])
        settings.contentSourceExclusions = [other, first, renamed]
        XCTAssertEqual(settings.contentSourceExclusions, [renamed, other], "mutation normalizes too")
        XCTAssertEqual(ReaderSourceExclusionSnapshot(settings: settings).sourceIDs, [a, b])
    }

    func testEffectiveSnapshotIgnoresNamesAndMaskedRules() {
        let before = ReaderSettings(contentSourceExclusions: [.init(sourceID: a, displayName: "old")])
        let after = ReaderSettings(contentSourceExclusions: [.init(sourceID: a, displayName: "new")])
        XCTAssertEqual(ReaderSourceExclusionSnapshot(settings: before), ReaderSourceExclusionSnapshot(settings: after))
        let disabled = ReaderSettings(contentFiltersEnabled: false, contentSourceExclusions: before.contentSourceExclusions)
        XCTAssertEqual(ReaderSourceExclusionSnapshot(settings: disabled), .unrestricted)
        XCTAssertNotEqual(ReaderSourceExclusionSnapshot(settings: before), .unrestricted)
    }

    func testMalformedRulesFailInsteadOfSilentlyDisablingExclusions() throws {
        let malformed = Data(#"{"contentSourceExclusions":"invalid"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ReaderSettings.self, from: malformed))
    }
}
