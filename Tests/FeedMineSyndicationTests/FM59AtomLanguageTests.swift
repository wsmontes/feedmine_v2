import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition
import FeedMineSyndication

final class FM59AtomLanguageTests: XCTestCase {
    private func video(feedLanguage: String? = nil, entryLanguage: String? = nil,
        title: String = "Uma descoberta sobre ciência") throws -> AcquisitionObservation {
        let feedAttribute = feedLanguage.map { " xml:lang=\"\($0)\"" } ?? ""
        let entryAttribute = entryLanguage.map { " xml:lang=\"\($0)\"" } ?? ""
        let data = Data("""
            <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/"\(feedAttribute)>
              <title>Channel</title>
              <entry\(entryAttribute)><id>urn:fm59:video</id><title>\(title)</title>
                <link rel="alternate" href="https://www.youtube.com/watch?v=fm59"/>
                <media:group>
                  <media:content url="https://www.youtube.com/v/fm59" type="application/x-shockwave-flash"/>
                  <media:thumbnail url="https://images.example.test/video.jpg" width="640" height="360"/>
                </media:group>
              </entry>
            </feed>
            """.utf8)
        let configuration = try XCTUnwrap(SyndicationTargetConfiguration(targetID: AcquisitionTargetID(),
            endpoint: URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=fm59")!,
            memberships: [.init(sourceID: SourceID(), kind: .direct)]))
        let translated = try SyndicationTranslator().translate(data: data, configuration: configuration,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000), startIndex: 0, itemCapacity: 8)
        XCTAssertTrue(translated.rejections.isEmpty)
        return try XCTUnwrap(translated.observations.first)
    }

    func testEntryPortugueseDeclarationSurvivesTranslationBesideVideoIdentity() throws {
        let item = try video(entryLanguage: "pt-BR")
        XCTAssertEqual(item.language, "pt-BR", "Strict Portuguese eligibility needs the declaration the item actually provided")
        XCTAssertEqual(item.mediaCandidates.first { $0.role == .playback }?.mediaClass, .video)
        XCTAssertEqual(item.primaryLink?.absoluteString, "https://www.youtube.com/watch?v=fm59")
    }

    func testFeedLanguageIsInheritedOnlyWhenEntryDoesNotOverrideIt() throws {
        XCTAssertEqual(try video(feedLanguage: "pt-PT").language, "pt-PT")
        XCTAssertEqual(try video(feedLanguage: "pt", entryLanguage: "en", title: "A new discovery about science").language, "en",
            "A Portuguese feed must not silently relabel its English item")
    }

    func testEntryDeclarationOverridesAnIncompatibleFeedDeclaration() throws {
        XCTAssertEqual(try video(feedLanguage: "en", entryLanguage: "pt-BR").language, "pt-BR")
        XCTAssertEqual(try video(feedLanguage: "pt", entryLanguage: "ja", title: "日本の科学と文化について").language, "ja")
    }

    func testExplicitlyEmptyEntryDeclarationClearsInheritedLanguage() throws {
        let language = try video(feedLanguage: "pt", entryLanguage: "").language
        XCTAssertTrue(language == nil || language?.isEmpty == true,
            "xml:lang=empty explicitly withdraws inheritance; it is not Portuguese evidence")
    }

    func testUndeclaredVideoLanguageRemainsUnknownRatherThanGuessedFromItsTitle() throws {
        XCTAssertNil(try video().language,
            "Canonical declarations stay unknown; any later item-text recognition needs separate scoped provenance")
    }
}
