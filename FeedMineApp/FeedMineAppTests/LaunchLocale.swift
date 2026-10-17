import XCTest

/// The suite's language is a declaration, not the device's accident: `FeedMine.xctestplan` pins pt-BR / pt_BR and
/// `America/Sao_Paulo` for every test, so the app under test resolves Portuguese copy, region names and decimal
/// separators the same way on any host.
///
/// A test whose **subject** is the language has to say so on its own launch — a test plan cannot vary per test —
/// and this is the only place that says it. `-AppleLanguages` is what the app under test reads when it resolves
/// `Bundle.main.preferredLocalizations` (the single path `CatalogLanguageNaming.interfaceLocale` uses).
enum LaunchLocale: String {
    case portugueseBrazil = "pt-BR"
    case english = "en"

    /// What `-AppleLocale` takes, which fixes region formats (dates, decimals) independently of the language.
    var appleLocale: String {
        switch self {
        case .portugueseBrazil: "pt_BR"
        case .english: "en_US"
        }
    }

    @MainActor
    func apply(to app: XCUIApplication) {
        app.launchArguments += ["-AppleLanguages", "(\(rawValue))", "-AppleLocale", appleLocale]
    }
}
