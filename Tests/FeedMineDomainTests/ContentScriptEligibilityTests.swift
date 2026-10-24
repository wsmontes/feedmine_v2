import XCTest
import FeedMineDomain

/// The measured defect this covers: a catalogue channel declaring `en` published a story written in Cyrillic, and
/// a reader who had chosen only English received it. The rule is about the writing system of the text actually
/// shown, never about meaning, and it never invents evidence: unknown language, absent declaration or mixed text
/// admits.
final class ContentScriptEligibilityTests: XCTestCase {
    func testDominantScriptNeedsAStrictMajorityOfLetters() {
        XCTAssertEqual(ReaderLanguageScript.dominantScript(of: "Архитектура капитала"), .cyrillic)
        XCTAssertEqual(ReaderLanguageScript.dominantScript(of: "Quarterly earnings report"), .latin)
        XCTAssertEqual(ReaderLanguageScript.dominantScript(of: "Cómo EE.UU. se ha convertido"), .latin,
            "a Latin-script language is still Latin: the minimal rule does not claim to tell Spanish from English")
        // Half Cyrillic and half Latin is ambiguous, not a majority.
        XCTAssertNil(ReaderLanguageScript.dominantScript(of: "Арх abc"), "three letters of each script is a tie, not a majority")
        XCTAssertNil(ReaderLanguageScript.dominantScript(of: "123 — 🎄 ✨"), "no letters, no evidence")
        XCTAssertNil(ReaderLanguageScript.dominantScript(of: ""))
    }

    func testADeclaredLanguageRejectsTextWrittenInAnotherScript() {
        XCTAssertFalse(ReaderLanguageScript.admits("Архитектура капитала", declaredLanguage: "en"),
            "the measured Russian advertisement declared itself en")
        XCTAssertFalse(ReaderLanguageScript.admits("МФО без переплат", declaredLanguage: "en-US"))
        XCTAssertTrue(ReaderLanguageScript.admits("Quarterly earnings report", declaredLanguage: "en"))
        XCTAssertTrue(ReaderLanguageScript.admits("Crise no tribunal", declaredLanguage: "pt-BR"))
    }

    func testNoEvidenceNeverRejects() {
        XCTAssertTrue(ReaderLanguageScript.admits("Архитектура капитала", declaredLanguage: nil))
        XCTAssertTrue(ReaderLanguageScript.admits("Quarterly earnings report", declaredLanguage: ""))
        XCTAssertTrue(ReaderLanguageScript.admits("Архитектура капитала", declaredLanguage: "xx"),
            "a language this build does not know is no evidence against the text")
        XCTAssertTrue(ReaderLanguageScript.admits("Арх abc", declaredLanguage: "en"),
            "mixed text is ambiguous, and ambiguity admits")
    }

    func testRussianTextIsAdmittedWhenRussianIsTheDeclaredLanguage() {
        XCTAssertTrue(ReaderLanguageScript.admits("Архитектура капитала", declaredLanguage: "ru"))
        XCTAssertTrue(ReaderLanguageScript.admits("Российская экономика", declaredLanguage: "ru-RU"))
    }

    func testASetOfLanguagesAdmitsEveryScriptItUses() {
        XCTAssertFalse(ReaderLanguageScript.admits("Архитектура капитала", languages: ["en"]))
        XCTAssertTrue(ReaderLanguageScript.admits("Архитектура капитала", languages: ["en", "ru"]))
        XCTAssertTrue(ReaderLanguageScript.admits("Quarterly earnings report", languages: ["en", "ru"]))
        XCTAssertTrue(ReaderLanguageScript.admits("Архитектура капитала", languages: []),
            "an empty choice is not a restriction")
        XCTAssertTrue(ReaderLanguageScript.admits("Архитектура капитала", languages: ["en", "xx"]),
            "one language this build cannot classify makes the whole set unevidenced")
    }

    func testCjkLanguagesAreNotTreatedAsOneLanguage() {
        XCTAssertEqual(ContentScript.scripts(forLanguage: "ja"), [.han, .kana])
        XCTAssertEqual(ContentScript.scripts(forLanguage: "ko"), [.hangul, .han])
        XCTAssertFalse(ReaderLanguageScript.admits("東京の天気", languages: ["en"]))
        XCTAssertTrue(ReaderLanguageScript.admits("東京の天気", languages: ["ja"]))
        XCTAssertTrue(ReaderLanguageScript.admits("東京の天気", languages: ["zh"]), "Han covers Chinese too")
    }
}
