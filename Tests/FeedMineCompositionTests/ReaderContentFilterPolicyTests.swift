import Foundation
import XCTest
import FeedMineDomain
import FeedMineComposition

/// The reader's content filters: what their settings add up to, and the one rule that decides what is hidden —
/// the gate masks the rules, it never deletes them.
final class ReaderContentFilterPolicyTests: XCTestCase {
    private let template = ReaderContentFilterTemplate(key: "crypto",
        names: ["en": "Crypto", "pt": "Cripto", "pt-BR": "Cripto (BR)"],
        keywords: ["en": ["crypto", "blockchain"], "pt": ["cripto", "bitcoin"], "pt-BR": ["criptomoeda"]])

    func testTheReadersLanguageComesFromTheirLocale() {
        XCTAssertEqual(ReaderContentFilterTemplate.preferredLanguages(for: Locale(identifier: "pt-BR")),
            ["pt-BR", "pt"], "the reader's language and its base language")
        XCTAssertEqual(ReaderContentFilterTemplate.preferredLanguages(for: Locale(identifier: "pt")), ["pt"])
        XCTAssertEqual(ReaderContentFilterTemplate.preferredLanguages(for: Locale(identifier: "ja")), ["ja"])
    }

    /// V1's own resolution: the locale's words and English, never a language the reader does not read.
    func testATemplateResolvesItsWordsForTheReadersLanguage() {
        XCTAssertEqual(template.rules(languages: ["pt-BR", "pt"]),
            ["bitcoin", "cripto", "criptomoeda", "crypto", "blockchain"].sorted(),
            "a regional language takes its own list, its base language's and English")
        XCTAssertEqual(template.rules(languages: ["en"]), ["blockchain", "crypto"])
        XCTAssertEqual(template.rules(languages: ["ja"]), ["blockchain", "crypto"],
            "a language the catalogue does not carry falls back to English, not to another reader's words")
        XCTAssertEqual(template.name(languages: ["pt-BR", "pt"]), "Cripto (BR)")
    }

    /// The reader's own words and their templates' add up; both are normalized into one canonical rule set.
    func testRulesAddTheReadersWordsToTheirTemplates() {
        let settings = ReaderSettings(contentFilterRules: ["  Squash ", "squash", "Crypto"],
            contentFilterTemplates: ["crypto"])
        XCTAssertEqual(ReaderContentFilterPolicy.rules(settings: settings, templates: [template],
            languages: ["en"]), ["blockchain", "crypto", "squash"])
    }

    /// The gate masks what the filters hide without erasing a rule: with it off nothing is excluded, and the
    /// rules the reader wrote are still there to state and to turn back on.
    func testTheGateMasksTheRulesWithoutErasingThem() {
        let rules = ReaderSettings(contentFilterRules: ["casino"], contentFilterTemplates: [])
        let off = ReaderSettings(contentFiltersEnabled: false, contentFilterRules: ["casino"])
        XCTAssertEqual(ReaderContentFilterPolicy.exclusions(settings: rules, templates: [],
            languages: ["en"]),
            ReaderContentExclusions(isEnabled: true, rules: ["casino"]))
        XCTAssertEqual(ReaderContentFilterPolicy.exclusions(settings: off, templates: [],
            languages: ["en"]), .disabled, "off hides nothing")
        XCTAssertEqual(ReaderContentFilterPolicy.rules(settings: off, templates: [],
            languages: ["en"]), ["casino"], "and forgets nothing")
        XCTAssertTrue(ReaderContentFilterPolicy.exclusions(settings: rules, templates: [],
            languages: ["en"]).excludes("The CASINO story"), "a rule hides whatever contains it")
        XCTAssertFalse(ReaderContentFilterPolicy.exclusions(settings: off, templates: [],
            languages: ["en"]).excludes("The casino story"), "and hides nothing while the gate is off")
    }

    /// A rule set with no rules is not a criterion: the filter stays unrestricted, exactly as T6 decided.
    func testAnEmptyRuleSetIsNotAFilter() {
        let settings = ReaderSettings(contentFiltersEnabled: true, contentFilterRules: [""])
        XCTAssertEqual(ReaderContentFilterPolicy.exclusions(settings: settings, templates: [],
            languages: ["en"]), .disabled)
        XCTAssertTrue(ReaderContentFilterPolicy.applying(settings: settings, templates: [],
            to: .unrestricted, languages: ["en"]).isUnrestricted)
    }

    /// Applying the filters leaves the lens criteria exactly as the reader set them: the content filters are
    /// not a lens criterion and never expire.
    func testApplyingKeepsTheLensAndReplacesOnlyTheExclusions() {
        let filter = ReaderFilter(languages: ["pt"], mood: .serious)
        let settings = ReaderSettings(contentFilterRules: ["casino"])
        let applied = ReaderContentFilterPolicy.applying(settings: settings, templates: [], to: filter,
            languages: ["en"])
        XCTAssertEqual(applied.languages, ["pt"])
        XCTAssertEqual(applied.mood, .serious)
        XCTAssertEqual(applied.effectiveExclusionRules, ["casino"])
    }

    /// A context's own exclusions (a smart bookmark's words, which V1's import preserved) and the reader's global
    /// rules add up rather than replacing each other — and the gate masks only the global half.
    func testAContextsOwnExclusionsSurviveTheGlobalGate() {
        let context = ReaderContentExclusions(isEnabled: true, rules: ["squash"])
        let global = ReaderContentExclusions(isEnabled: true, rules: ["crypto"])
        let both = ReaderContentFilterPolicy.combining(context: context, global: global)
        XCTAssertEqual(both, ReaderContentExclusions(isEnabled: true, rules: ["crypto", "squash"]))
        XCTAssertTrue(both.excludes("Squash finals"))
        XCTAssertTrue(both.excludes("Crypto market"))

        let masked = ReaderContentFilterPolicy.combining(context: context, global: .disabled)
        XCTAssertEqual(masked, context, "the gate masks the global rules and leaves the context's own")
        XCTAssertTrue(masked.excludes("Squash finals"))
        XCTAssertFalse(masked.excludes("Crypto market"))
        XCTAssertEqual(ReaderContentFilterPolicy.combining(context: .disabled, global: .disabled), .disabled)
        XCTAssertEqual(ReaderContentFilterPolicy.combining(
            context: ReaderContentExclusions(isEnabled: false, rules: ["squash"]), global: .disabled), .disabled,
            "a disabled set contributes nothing, rules or not")
    }

    func testStrictResolutionRejectsMissingTemplates() {
        let settings = ReaderSettings(contentFilterTemplates: ["z", "missing", "z"])
        XCTAssertThrowsError(try ReaderContentFilterPolicy.resolvedExclusions(
            settings: settings, templates: [template], languages: ["en"])) {
            XCTAssertEqual($0 as? ReaderContentFilterPolicy.ResolutionError,
                .missingTemplates(["missing", "z"]))
        }
    }

    func testStrictResolutionRejectsDuplicateCatalogueDefinitions() {
        let settings = ReaderSettings(contentFilterTemplates: ["crypto"])
        XCTAssertThrowsError(try ReaderContentFilterPolicy.resolvedExclusions(
            settings: settings, templates: [template, template], languages: ["en"])) {
            XCTAssertEqual($0 as? ReaderContentFilterPolicy.ResolutionError, .duplicateTemplate("crypto"))
        }
    }

    func testStrictDuplicateValidationIncludesUnselectedKeysAndIsOrderIndependent() {
        let a = ReaderContentFilterTemplate(key: "a", names: [:], keywords: ["en": ["alpha"]])
        let z = ReaderContentFilterTemplate(key: "z", names: [:], keywords: ["en": ["zeta"]])
        let catalogue = [z, a, template, z, a]
        for entries in [catalogue, Array(catalogue.reversed())] {
            XCTAssertThrowsError(try ReaderContentFilterPolicy.resolvedExclusions(
                settings: ReaderSettings(contentFilterTemplates: ["crypto"]),
                templates: entries, languages: ["en"])) {
                XCTAssertEqual($0 as? ReaderContentFilterPolicy.ResolutionError, .duplicateTemplate("a"))
            }
        }
    }

    func testStrictGateOffIgnoresUnresolvedTemplatesAndKeepsContextWords() throws {
        let context = ReaderContentExclusions(isEnabled: true, rules: ["crypto", "squash"])
        let settings = ReaderSettings(contentFiltersEnabled: false, contentFilterRules: ["crypto"],
            contentFilterTemplates: ["missing"])
        XCTAssertEqual(try ReaderContentFilterPolicy.resolvedExclusions(settings: settings,
            templates: [template, template], context: context, languages: ["en"]), context)
    }

    func testStrictResolutionCombinesContextGlobalAndLocalizedTemplateWords() throws {
        let settings = ReaderSettings(contentFilterRules: [" SQUASH ", "crypto"],
            contentFilterTemplates: ["crypto"])
        let context = ReaderContentExclusions(isEnabled: true, rules: ["context", "squash"])
        XCTAssertEqual(try ReaderContentFilterPolicy.resolvedExclusions(settings: settings,
            templates: [template], context: context, languages: ["pt"]),
            ReaderContentExclusions(isEnabled: true,
                rules: ["bitcoin", "blockchain", "context", "cripto", "crypto", "squash"]))
    }

    func testStrictEffectivePolicyIgnoresTemplateLabelsAndRuleOrder() throws {
        let renamed = ReaderContentFilterTemplate(key: "crypto", names: ["en": "Renamed"],
            keywords: ["en": ["blockchain", "crypto", "crypto"]])
        let settings = ReaderSettings(contentFilterTemplates: ["crypto"])
        XCTAssertEqual(try ReaderContentFilterPolicy.resolvedExclusions(settings: settings,
            templates: [template], languages: ["en"]),
            try ReaderContentFilterPolicy.resolvedExclusions(settings: settings,
                templates: [renamed], languages: ["en"]))
        XCTAssertEqual(try ReaderContentFilterPolicy.resolvedExclusions(
            settings: ReaderSettings(contentFilterRules: [" Explicit "]), templates: [], languages: ["en"]),
            ReaderContentExclusions(isEnabled: true, rules: ["explicit"]))
    }

    /// The catalogue is V1's own file, read from the package: six templates, each with English words.
    func testTheCatalogueIsV1sOwnFile() {
        let templates = ReaderContentFilterCatalog.bundled()
        XCTAssertEqual(templates.map(\.key).sorted(),
            ["ai_hype", "celebrity", "crypto", "politics", "sports", "violence"])
        for template in templates {
            XCTAssertFalse(template.rules(languages: ["en"]).isEmpty,
                "\(template.key) must carry English words")
            XCTAssertFalse(template.name(languages: ["en"]).isEmpty)
        }
    }
}
