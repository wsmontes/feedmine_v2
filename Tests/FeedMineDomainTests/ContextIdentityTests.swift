import XCTest
import Foundation
@testable import FeedMineDomain

/// T6, step 2: the context identity is the whole request — surface, preset, normalized filter and, for a
/// search, its scope. Backward compatibility is part of the contract: a key with only a request decodes to
/// the plain unfiltered surface, which is exactly the identity every pre-T6 checkpoint has.
final class ContextIdentityTests: XCTestCase {
    /// The unfiltered surface keeps the identity it had before the filter existed.
    func testDefaultSurfaceMatchesThePreFilterIdentity() {
        let key = ContextKey(request: .main)
        XCTAssertTrue(key.isDefaultSurface)
        XCTAssertEqual(key.surfaceIdentity, "main")
        XCTAssertEqual(key.identitySchemaVersion, ContextKey.currentIdentitySchemaVersion)
        XCTAssertNil(key.searchScope, "a scope outside a search is not part of any identity")
        XCTAssertEqual(key.canonicalIdentity, ContextKey(request: .main).canonicalIdentity)
        XCTAssertEqual(key.canonicalIdentity,
            "v1|main|preset=everything|filter=regions=;taxonomy=;languages=;type=All;mood=All;exclusions=-")
        // Equivalent default constructions agree, including one built from a source filter that is empty.
        XCTAssertEqual(ContextKey(request: .main, filter: ReaderFilter(regionIDs: [])), key)
    }

    /// Equivalent selections — including a different order of the same set — are one identity.
    func testEquivalentFiltersShareOneIdentity() {
        let a = ContextKey(request: .main, filter: ReaderFilter(languages: ["pt", "en"], mood: .technical))
        let b = ContextKey(request: .main, filter: ReaderFilter(languages: ["en", "pt"], mood: .technical))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.canonicalIdentity, b.canonicalIdentity)
    }

    /// Every part of the identity is load-bearing: preset, filter and scope each change it.
    func testEachIdentityPartChangesTheKey() {
        let base = ContextKey(request: .main)
        XCTAssertNotEqual(ContextKey(request: .main, preset: .lastClicked), base)
        XCTAssertNotEqual(ContextKey(request: .main, preset: .collection("c1")), base)
        XCTAssertNotEqual(ContextKey(request: .main, filter: ReaderFilter(mood: .fun)), base)
        XCTAssertNotEqual(ContextKey(request: .main,
            filter: ReaderFilter(exclusions: ReaderContentExclusions(isEnabled: true, rules: ["ads"]))), base)
        XCTAssertEqual(ContextKey(request: .main,
            filter: ReaderFilter(exclusions: ReaderContentExclusions(isEnabled: true, rules: []))), base,
            "Enabling exclusions with no rules filters nothing and must not fork the identity")
        // A different surface is a different identity even with the same filter.
        let source = SourceID()
        XCTAssertNotEqual(ContextKey(request: .source(source), filter: ReaderFilter(mood: .fun)),
            ContextKey(request: .main, filter: ReaderFilter(mood: .fun)))
        XCTAssertEqual(ContextKey(request: .source(source)).surfaceIdentity, "source:" + source.rawValue.uuidString)
    }

    /// A search keeps its exact query (no normalization) and gains a scope; the scope is identity.
    func testSearchSurfaceKeepsQueryAndCarriesItsScope() throws {
        let search = try XCTUnwrap(SearchContext(query: "  mercado livre  "))
        let both = ContextKey(request: .search(search))
        XCTAssertEqual(both.searchScope, .both, "a search without an explicit scope looks through both")
        XCTAssertEqual(both.surfaceIdentity, "search:  mercado livre  ", "the stored query is not normalized")
        let contents = ContextKey(request: .search(search), searchScope: .contents)
        XCTAssertNotEqual(contents, both)
        XCTAssertNotEqual(contents.canonicalIdentity, both.canonicalIdentity)
        XCTAssertTrue(contents.canonicalIdentity.hasSuffix("|scope=contents"))
    }

    /// A key persisted before T6 (only a request) decodes to the default surface identity.
    func testLegacyKeyDecodesToTheDefaultSurface() throws {
        let legacy = try JSONEncoder().encode(LegacyKey(request: .main))
        let decoded = try JSONDecoder().decode(ContextKey.self, from: legacy)
        XCTAssertTrue(decoded.isDefaultSurface)
        XCTAssertEqual(decoded.preset, .everything)
        XCTAssertTrue(decoded.filter.isUnrestricted)
        XCTAssertEqual(decoded.identitySchemaVersion, ContextKey.currentIdentitySchemaVersion)
        XCTAssertEqual(decoded.canonicalIdentity, ContextKey(request: .main).canonicalIdentity)
    }

    /// The full identity round-trips through persistence without losing a part of it.
    func testFullIdentityRoundTrips() throws {
        let key = ContextKey(request: .main, preset: .smartFeed("s1"),
            filter: ReaderFilter(languages: ["pt"], contentType: .audio, mood: .serious,
                exclusions: ReaderContentExclusions(isEnabled: true, rules: ["Ads"])),
            searchScope: .sources)
        let decoded = try JSONDecoder().decode(ContextKey.self, from: JSONEncoder().encode(key))
        XCTAssertEqual(decoded, key)
        XCTAssertEqual(decoded.canonicalIdentity, key.canonicalIdentity)
        XCTAssertEqual(decoded.filter.exclusions.rules, ["ads"], "the scope is dropped but the rules normalize")
        XCTAssertNil(decoded.searchScope, "a scope on a non-search surface is never part of the identity")
    }

    /// `FeedContext.key` is the default-surface convenience and stays equivalent to an explicit default key.
    func testFeedContextKeyIsTheDefaultSurface() {
        let context = FeedContext(request: .main)
        XCTAssertEqual(context.key, ContextKey(request: .main))
        XCTAssertTrue(context.key.isDefaultSurface)
    }

    private struct LegacyKey: Encodable {
        let request: FeedContextRequest
    }
}
