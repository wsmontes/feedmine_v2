import XCTest
import Foundation
@testable import FeedMineDomain

/// T6, first step: the filter value's canonical identity and V1's criterion vocabulary.
/// Design: `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md` §2.
final class ReaderFilterTests: XCTestCase {
    /// Reordered equivalent sets produce identical identity text (and therefore one context key).
    func testEquivalentSelectionsShareOneIdentity() throws {
        let a = ReaderFilter(regionIDs: ["us", "br"], taxonomyNodeIDs: ["tech", "science"],
            languages: ["pt", "en"], contentType: .text, mood: .technical,
            exclusions: ReaderContentExclusions(isEnabled: true, rules: [" Taylor ", "crypto", "CRYPTO"]))
        let b = ReaderFilter(regionIDs: ["br", "us"], taxonomyNodeIDs: ["science", "tech"],
            languages: ["en", "pt"], contentType: .text, mood: .technical,
            exclusions: ReaderContentExclusions(isEnabled: true, rules: ["crypto", "taylor"]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.identityText, b.identityText)
        // And the encoded form is deterministic too — persistence identity must not depend on set order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(a), try encoder.encode(b))
    }

    /// The default filter is unrestricted and stable: the unfiltered surface keeps today's identity.
    func testDefaultFilterIsUnrestrictedAndStable() {
        XCTAssertTrue(ReaderFilter().isUnrestricted)
        XCTAssertEqual(ReaderFilter().identityText, ReaderFilter.unrestricted.identityText)
        XCTAssertEqual(ReaderFilter().identityText,
            "regions=;taxonomy=;languages=;type=All;mood=All;exclusions=-")
        // Whitespace-only inputs normalize away; they are not criteria.
        XCTAssertTrue(ReaderFilter(regionIDs: ["", "  "], languages: [" "] ).isUnrestricted)
    }

    /// Any real criterion changes the identity, and the change is visible in the canonical text.
    func testEachCriterionChangesIdentity() {
        let base = ReaderFilter().identityText
        XCTAssertNotEqual(ReaderFilter(regionIDs: ["us"]).identityText, base)
        XCTAssertNotEqual(ReaderFilter(taxonomyNodeIDs: ["tech"]).identityText, base)
        XCTAssertNotEqual(ReaderFilter(languages: ["pt"]).identityText, base)
        XCTAssertNotEqual(ReaderFilter(contentType: .audio).identityText, base)
        XCTAssertNotEqual(ReaderFilter(mood: .fun).identityText, base)
        XCTAssertFalse(ReaderFilter(exclusions: ReaderContentExclusions(isEnabled: true, rules: ["x"])).isUnrestricted)
        // Enabling exclusions with no rules filters nothing, and says so.
        XCTAssertTrue(ReaderFilter(exclusions: ReaderContentExclusions(isEnabled: true, rules: []))
            .isUnrestricted)
    }

    /// V1's mood rule, ported: a case-insensitive keyword test over the headline (`FeedLoader.MoodFilter`).
    func testMoodRulesReproduceV1() {
        XCTAssertTrue(ReaderMood.all.matches(nil), "All matches everything, including an absent title")
        XCTAssertFalse(ReaderMood.fun.matches(nil), "A missing title cannot match a real mood")
        XCTAssertTrue(ReaderMood.serious.matches("Court ruling bans the app"))
        XCTAssertFalse(ReaderMood.serious.matches("An adorable puppy"))
        XCTAssertTrue(ReaderMood.fun.matches("An adorable puppy"))
        XCTAssertTrue(ReaderMood.technical.matches("Quantum chip startup raises"))
        XCTAssertTrue(ReaderMood.inspiring.matches("Scientists discovered a cure"))
        XCTAssertFalse(ReaderMood.inspiring.matches("Quarterly earnings report"))
        XCTAssertEqual(ReaderMood.all.keywords, [])
    }

    /// V1's content-type vocabulary, verbatim (raw values and icons are the UI's contract).
    func testContentTypeVocabularyMatchesV1() {
        XCTAssertEqual(ReaderContentType.allCases.map(\.rawValue),
            ["All", "Articles", "Videos", "Podcasts", "Forums"])
        XCTAssertEqual(ReaderContentType.audio.icon, "headphones")
        XCTAssertEqual(ReaderContentType.forum.icon, "bubble.left.and.bubble.right.fill")
        XCTAssertEqual(ReaderMood.allCases.map(\.rawValue),
            ["All", "Serious", "Fun", "Technical", "Inspiring"])
        XCTAssertEqual(ReaderMood.inspiring.icon, "sun.max.fill")
    }

    /// Exclusions hide content, are normalized, and never expire: there is no timestamp on the value.
    func testExclusionsNormalizeAndNeverExpire() {
        let exclusions = ReaderContentExclusions(isEnabled: true, rules: [" Crypto ", "crypto", "", "AI"])
        XCTAssertEqual(exclusions.rules, ["ai", "crypto"])
        XCTAssertTrue(exclusions.excludes("The CRYPTO market"))
        XCTAssertTrue(exclusions.excludes("ai everywhere"))
        XCTAssertFalse(exclusions.excludes("markets"))
        XCTAssertFalse(exclusions.excludes(nil))
        XCTAssertFalse(ReaderContentExclusions.disabled.excludes("crypto"),
            "A disabled exclusion set hides nothing")
        // Structural: the value carries no expiry of its own (the design keeps expiry out of identity).
        XCTAssertFalse(Mirror(reflecting: exclusions).children.contains { $0.label?.lowercased().contains("expiry") == true })
    }

    /// The preset id is identity, not display: it survives as opaque external ids and never as names.
    func testPresetIdentityIsStableAndPayloadFree() {
        XCTAssertEqual(ReaderPresetID.everything.identityText, "everything")
        XCTAssertEqual(ReaderPresetID.collection("abc-123").identityText, "collection:abc-123")
        XCTAssertEqual(ReaderPresetID.editorial("tech-science").identityText, "editorial:tech-science")
        XCTAssertTrue(ReaderPresetID.curatedFeed("x").isCurated)
        XCTAssertTrue(ReaderPresetID.smartFeed("x").isSmart)
        XCTAssertFalse(ReaderPresetID.everything.isCollection)
        XCTAssertNotEqual(ReaderPresetID.collection("a").identityText, ReaderPresetID.collection("b").identityText)
    }

    /// The search scope is part of identity only for a search surface.
    func testSearchScopeSemantics() {
        XCTAssertEqual(ReaderSearchScope.both.rawValue, "both")
        XCTAssertTrue(ReaderSearchScope.sources.includesSources)
        XCTAssertFalse(ReaderSearchScope.sources.includesContents)
        XCTAssertTrue(ReaderSearchScope.both.includesSources)
        XCTAssertTrue(ReaderSearchScope.both.includesContents)
    }

    /// T6 lens: the criteria the bar must draw, in V1's order, and the removal of exactly one of them.
    func testActiveCriteriaAndRemovalTouchExactlyOneCriterion() throws {
        let filter = ReaderFilter(regionIDs: ["br", "us"], taxonomyNodeIDs: ["tech"], languages: ["pt"],
            contentType: .audio, mood: .serious,
            exclusions: ReaderContentExclusions(isEnabled: true, rules: ["ads"]))
        XCTAssertEqual(filter.activeCriteria, [
            .region("br"), .region("us"), .taxonomyNode("tech"), .contentType, .language("pt"), .mood, .exclusions
        ], "the lens follows V1's chip order and only shows what is set")
        XCTAssertTrue(ReaderFilter.unrestricted.activeCriteria.isEmpty, "a plain surface shows no lens at all")

        XCTAssertEqual(filter.removing(.region("br")).regionIDs, ["us"])
        XCTAssertEqual(filter.removing(.region("us")).regionIDs, ["br"])
        XCTAssertEqual(filter.removing(.taxonomyNode("tech")).taxonomyNodeIDs, [])
        XCTAssertEqual(filter.removing(.contentType).contentType, .all)
        XCTAssertEqual(filter.removing(.language("pt")).languages, [])
        XCTAssertEqual(filter.removing(.mood).mood, .all)
        XCTAssertEqual(filter.removing(.exclusions).exclusions, .disabled)
        // Everything else survives a removal, and removing something absent changes nothing.
        let withoutMood = filter.removing(.mood)
        XCTAssertEqual(withoutMood.regionIDs, filter.regionIDs)
        XCTAssertEqual(withoutMood.languages, ["pt"])
        XCTAssertEqual(withoutMood.exclusions.rules, ["ads"])
        XCTAssertEqual(withoutMood.removing(.mood), withoutMood)
        XCTAssertEqual(filter.removing(.preset), filter, "a preset is removed through the preset id, not a filter")
    }

    /// T6 expiry: the four-hour window is a *pending* fact that an explicit transition resolves; content
    /// exclusions never expire (V1's content-filter screen was outside the rule).
    func testExpiryIsPendingAndResolvesOnlyTheOverlaySelection() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let set = ReaderFilter(regionIDs: ["br"], taxonomyNodeIDs: ["tech"], languages: ["pt"],
            contentType: .audio, mood: .fun,
            exclusions: ReaderContentExclusions(isEnabled: true, rules: ["ads"]))

        // Disabled, or enabled with nothing set: nothing expires, and there is no deadline to state.
        XCTAssertFalse(ReaderFilterExpiry.disabled.isExpired(at: start.addingTimeInterval(86_400)))
        XCTAssertNil(ReaderFilterExpiry.disabled.expiresAt())
        XCTAssertNil(ReaderFilterExpiry(isEnabled: true, startsAt: nil).expiresAt())
        XCTAssertEqual(ReaderFilterExpiry(isEnabled: true, startsAt: nil).resolving(set, at: start), set)

        let record = ReaderFilterExpiry(isEnabled: true, startsAt: start)
        XCTAssertEqual(record.expiresAt(), start.addingTimeInterval(ReaderFilterExpiry.lifetime))
        XCTAssertEqual(ReaderFilterExpiry.lifetime, 4 * 60 * 60, "V1's window is four hours")
        // Inside the window nothing moves, including on a transition.
        XCTAssertFalse(record.isExpired(at: start.addingTimeInterval(3 * 3600)))
        XCTAssertEqual(record.resolving(set, at: start.addingTimeInterval(3 * 3600)), set)
        // At and after the boundary the overlay selection is dropped, and the exclusions survive.
        for moment in [start.addingTimeInterval(4 * 3600), start.addingTimeInterval(9 * 3600)] {
            XCTAssertTrue(record.isExpired(at: moment))
            let resolved = record.resolving(set, at: moment)
            XCTAssertTrue(resolved.regionIDs.isEmpty)
            XCTAssertTrue(resolved.taxonomyNodeIDs.isEmpty)
            XCTAssertTrue(resolved.languages.isEmpty)
            XCTAssertEqual(resolved.contentType, .all)
            XCTAssertEqual(resolved.mood, .all)
            XCTAssertEqual(resolved.exclusions.rules, ["ads"], "content exclusions are outside the rule")
            XCTAssertFalse(resolved.isUnrestricted, "the surviving exclusions keep the filter non-default")
        }
        // Renewing the selection restarts the window without changing whether expiry is on.
        let renewed = record.renewed(at: start.addingTimeInterval(5 * 3600))
        XCTAssertTrue(renewed.isEnabled)
        XCTAssertFalse(renewed.isExpired(at: start.addingTimeInterval(5 * 3600)))
        XCTAssertFalse(renewed.isExpired(at: start.addingTimeInterval(8 * 3600 + 3599)))
        XCTAssertTrue(renewed.isExpired(at: start.addingTimeInterval(9 * 3600)))
        // The record round-trips through persistence.
        let decoded = try? JSONDecoder().decode(ReaderFilterExpiry.self,
            from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    /// The default filter must round-trip through persistence byte-identically (canonical encoding).
    func testFilterRoundTripsThroughCodable() throws {
        let original = ReaderFilter(regionIDs: ["br"], taxonomyNodeIDs: ["tech"], languages: ["pt"],
            contentType: .audio, mood: .serious,
            exclusions: ReaderContentExclusions(isEnabled: true, rules: ["ads"]))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReaderFilter.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.identityText, original.identityText)
        let empty = try JSONDecoder().decode(ReaderFilter.self, from: JSONEncoder().encode(ReaderFilter()))
        XCTAssertTrue(empty.isUnrestricted)
    }
}
