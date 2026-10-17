import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineComposition

@MainActor
final class SyndicationAcquisitionLanguageTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try RuntimeDatabase(location: .init(directory: directory))
    }

    private func registered(language: String?, authority: AcquisitionTargetAuthority) throws
        -> (AcquisitionTarget, SyndicationTargetRegistration) {
        let sourceID = SourceID()
        let target = try authority.register(id: AcquisitionTargetID(), connectorKind: .syndication,
            authorizedSources: [sourceID])
        let binding = SourceBinding(id: SourceBindingID(), sourceID: sourceID,
            externalPrincipal: .init(connectorKind: .syndication, namespace: "language-test",
                value: UUID().uuidString, role: .principal),
            aliases: [], generation: 1, state: .enabled)!
        let registration = SyndicationTargetRegistration(targetID: target.id,
            targetGeneration: target.generation, endpoint: URL(string: "https://example.test/rss")!,
            bindings: [binding], language: language)!
        return (target, registration)
    }

    private func snapshot(database: RuntimeDatabase, registrations: [SyndicationTargetRegistration],
        discovery: ReaderDiscoveryTraversal? = nil) throws -> SyndicationAcquisitionSnapshot {
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        return try SyndicationAcquisitionSnapshot(database: database, registrations: registrations,
            session: transport, redirectCapacity: 0, discovery: discovery)
    }

    func testD2RegisteredTargetOutsideDiscoveryRejectsUnansweredLanguageAndAcceptsAnsweredLanguage() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db)
        let (portuguese, wrong) = try registered(language: "pt-BR", authority: authority)
        let (english, right) = try registered(language: "en-US", authority: authority)
        let acquisition = try snapshot(database: db, registrations: [wrong, right])
        let context = FeedContext(request: .main, filter: ReaderFilter(languages: ["en"]))
        XCTAssertEqual(try acquisition.eligibleTargets(for: context), [english])
        XCTAssertFalse(try acquisition.eligibleTargets(for: context).contains(portuguese))
    }

    func testD2SavedDiscoveryLanguageAlsoFiltersRegisteredTargets() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db)
        let (_, wrong) = try registered(language: "es", authority: authority)
        let (english, right) = try registered(language: "en-GB", authority: authority)
        let context = FeedContext(request: .main)
        // No discovery page is needed: these targets were registered by a different route.
        let traversal = ReaderDiscoveryTraversal(
            builder: ReaderDiscoveryBuilder(catalogURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("unused-language-catalog.sqlite")),
            profile: ReaderDiscoveryProfile(languages: ["en"]), contextKey: context.key)
        let acquisition = try snapshot(database: db, registrations: [wrong, right], discovery: traversal)
        XCTAssertEqual(try acquisition.eligibleTargets(for: context), [english])
    }

    func testD2UndeclaredLanguageRemainsEligibleWithExplicitChoice() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db)
        let (target, unknown) = try registered(language: nil, authority: authority)
        let (undTarget, und) = try registered(language: "und", authority: authority)
        let (blankTarget, blank) = try registered(language: " ", authority: authority)
        let acquisition = try snapshot(database: db, registrations: [unknown, und, blank])
        let expected = [target, undTarget, blankTarget]
        XCTAssertEqual(try acquisition.eligibleTargets(for: .init(request: .main)), expected)
        let filtered = FeedContext(request: .main, filter: ReaderFilter(languages: ["pt"]))
        XCTAssertEqual(try acquisition.eligibleTargets(for: filtered), expected)
    }

    func testD2ContextLanguageWinsWhenDiscoveryProfileDiffers() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db)
        let (_, portuguese) = try registered(language: "pt", authority: authority)
        let (englishTarget, english) = try registered(language: "en", authority: authority)
        let context = FeedContext(request: .main, filter: ReaderFilter(languages: ["en"]))
        let traversal = ReaderDiscoveryTraversal(
            builder: ReaderDiscoveryBuilder(catalogURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("unused-language-catalog.sqlite")),
            profile: ReaderDiscoveryProfile(languages: ["pt"]), contextKey: context.key)
        let acquisition = try snapshot(database: db, registrations: [portuguese, english], discovery: traversal)
        XCTAssertEqual(try acquisition.eligibleTargets(for: context), [englishTarget])
    }

    /// Item C, end to end at the value the first run writes: the reader's language answer is a recipe, the recipe
    /// is the discovery profile, and the profile is the acquisition scope. Naming a language keeps only sources in
    /// it; the skip names none, and nothing is restricted. `ReaderDiscoveryProfile(recipe:)` is the one mapping the
    /// onboarding and the host share — no `Locale` reads anywhere on this path.
    func testTheOnboardingAnswerScopesAcquisitionAndTheSkipLeavesItUnrestricted() throws {
        let db = try database(), authority = AcquisitionTargetAuthority(database: db)
        let (portugueseTarget, portuguese) = try registered(language: "pt-BR", authority: authority)
        let (englishTarget, english) = try registered(language: "en", authority: authority)
        let context = FeedContext(request: .main)
        func traversal(_ profile: ReaderDiscoveryProfile) -> ReaderDiscoveryTraversal {
            ReaderDiscoveryTraversal(
                builder: ReaderDiscoveryBuilder(catalogURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("unused-language-catalog.sqlite")),
                profile: profile, contextKey: context.key)
        }

        let answered = try snapshot(database: db, registrations: [portuguese, english],
            discovery: traversal(ReaderDiscoveryProfile(recipe: .neutral(languages: ["pt-BR"]))))
        XCTAssertEqual(try answered.eligibleTargets(for: context), [portugueseTarget],
            "a named language is strict eligibility, and the regional code answers its own language")

        let skipped = try snapshot(database: db, registrations: [portuguese, english],
            discovery: traversal(ReaderDiscoveryProfile(recipe: .neutral())))
        XCTAssertEqual(try skipped.eligibleTargets(for: context), [portugueseTarget, englishTarget],
            "the skip names no language, so every target stays eligible")
        XCTAssertTrue(ReaderDiscoveryProfile(recipe: .neutral()).isEmpty, "and the skip is an empty profile")
    }
}
