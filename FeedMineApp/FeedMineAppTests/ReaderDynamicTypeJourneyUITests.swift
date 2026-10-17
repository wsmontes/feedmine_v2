//
// File: ReaderDynamicTypeJourneyUITests.swift
// Module: FeedMineUITests
//
// F-UI-4 on the device. The package-level `ReaderAccessibilityTests` pins the frozen V1 ruler, the text style each
// card role scales against and the source-level pins; it states outright that a resolved point size at an
// accessibility category needs a running app. This journey is that missing half: it launches the app twice — the
// reader's current size and `UICTContentSizeCategoryAccessibilityXXXL` — measures the same card's title, summary
// and card box on screen, and taps the card.
//
// What it does **not** prove, and the second test measures instead of pretending: XCUITest reports a `Text`'s
// accessibility label, which SwiftUI derives from the string regardless of `.lineLimit`. Visual ellipsis is a
// property of drawn glyphs, not of the label, so "the label is the full string" cannot by itself rule out a title
// truncated on screen. For the short fixture strings the measured frame growth shows the scaled text is laid out;
// the long-summary control shows, measured, that the label keeps the whole 4,800-character string while its frame
// can only draw a few lines — i.e. the instrument is blind to that truncation.
import XCTest

@MainActor
final class ReaderDynamicTypeJourneyUITests: XCTestCase {
    /// The launch argument the suite already uses for its large-text runs (see `ReadingSurfaceUITests`).
    private static let accessibilityXXXL = "UICTContentSizeCategoryAccessibilityXXXL"

    /// A publication identity, exactly as the feed's cards state it.
    private static let cardIdentifier = NSPredicate(format: "identifier MATCHES %@",
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /// The local fixture transport's headlines (`TrustedFeeds.swift`: `"\(feedTitle) story \(index + 1)"`).
    private static let storyTitle = NSPredicate(format: "label MATCHES %@",
        "BBC (World|Science) story [0-9]+")

    /// Its short summaries (`"Fixture summary \(index + 1) for \(feedTitle)."`), the shape this run serves.
    private static let storySummary = NSPredicate(format: "label BEGINSWITH %@", "Fixture summary ")

    /// The long-text shape (`FEEDMINE_FIXTURE_TEXT=longSummary`): sixty paragraphs as one description.
    private static let longSummary = NSPredicate(format: "label BEGINSWITH %@", "Parágrafo 1:")

    /// The same card measured in one launch.
    private struct CardText {
        let title: String
        let titleFrame: CGRect
        let summary: String
        let summaryFrame: CGRect
        let cardFrame: CGRect
        let openHittable: Bool
    }

    func testCardTextScalesAtAccessibilityXXXLAndTheCardStaysReachable() throws {
        let baselineApp = launched()
        let baselineCard = try XCTUnwrap(waitForStoryCard(baselineApp, within: 180),
            "the local fixture feed publishes cards at the reader's current size")
        let baseline = measured(baselineCard)
        attach(baselineApp, "dynamic-type-default")
        baselineApp.terminate()

        let largeApp = launched(contentSize: Self.accessibilityXXXL)
        let largeCard = try XCTUnwrap(waitForStoryCard(largeApp, within: 180),
            "the same feed publishes cards at AccessibilityXXXL")
        let large = measured(largeCard)
        attach(largeApp, "dynamic-type-accessibility-xxxl")

        print("DYNAMIC_TYPE default titleHeight=\(baseline.titleFrame.height) summaryHeight=\(baseline.summaryFrame.height) cardHeight=\(baseline.cardFrame.height)")
        print("DYNAMIC_TYPE xxxl titleHeight=\(large.titleFrame.height) summaryHeight=\(large.summaryFrame.height) cardHeight=\(large.cardFrame.height)")
        print("DYNAMIC_TYPE title=\(baseline.title) summary=\(baseline.summary)")

        // The card is the same one: a deterministic fixture, read twice.
        XCTAssertEqual(large.title, baseline.title, "the same card is measured at both sizes")
        XCTAssertEqual(large.summary, baseline.summary, "the same card's summary is measured at both sizes")

        // The announced text is the fixture's whole headline and summary — not an abbreviation, not a placeholder.
        XCTAssertTrue(large.title.range(of: "story", options: .regularExpression) != nil)
        XCTAssertFalse(large.title.contains("…"), "the title announces the whole headline: \(large.title)")
        XCTAssertFalse(large.summary.contains("…"), "the summary announces the whole text: \(large.summary)")

        // F-UI-4 itself: the same strings are laid out at the reader's accessibility size, not at the frozen one.
        // A card title that ignored Dynamic Type would keep its 20 pt height at every category.
        XCTAssertGreaterThanOrEqual(large.titleFrame.height, baseline.titleFrame.height * 1.5,
            "the title must be drawn at the accessibility size: \(large.titleFrame.height) vs \(baseline.titleFrame.height)")
        XCTAssertGreaterThan(large.summaryFrame.height, baseline.summaryFrame.height,
            "the summary must be drawn at the accessibility size: \(large.summaryFrame.height) vs \(baseline.summaryFrame.height)")
        XCTAssertGreaterThan(large.cardFrame.height, baseline.cardFrame.height,
            "the card grows with its text instead of clipping it: \(large.cardFrame.height) vs \(baseline.cardFrame.height)")

        // F-UI-5's rule applied to the card: the reader's target is still at least a finger, and a real tap on it
        // opens the article.
        XCTAssertGreaterThanOrEqual(large.cardFrame.height, 44, "the card stays a 44 pt target")
        XCTAssertTrue(large.openHittable, "the card's opening surface is reachable at AccessibilityXXXL (frame \(large.cardFrame))")

        let open = largeCard.buttons["card.open"]
        if open.exists && open.isHittable {
            open.tap()
        } else {
            largeCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(largeApp.webViews.firstMatch.waitForExistence(timeout: 40),
            "tapping the card at AccessibilityXXXL opens its article")
        attach(largeApp, "dynamic-type-xxxl-after-open")
    }

    /// The measured blind spot, kept as a test so it is not forgotten: the label is the whole string even when the
    /// drawing cannot be. It asserts nothing about the product's layout; it fixes what this instrument can see.
    func testAccessibilityLabelDoesNotReportVisualTruncation() throws {
        let app = launched(contentSize: Self.accessibilityXXXL, textShape: "longSummary")
        let card = try XCTUnwrap(waitForCard(app, titleMatching: Self.storyTitle, within: 180),
            "the long-summary run publishes cards")
        let summary = card.staticTexts.matching(Self.longSummary).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "the long description is the card's summary")
        print("DYNAMIC_TYPE_LONG_SUMMARY characters=\(summary.label.count) frameHeight=\(summary.frame.height) frameWidth=\(summary.frame.width)")
        XCTAssertGreaterThan(summary.label.count, 3_000,
            "the announced string is the whole stored text")
        XCTAssertTrue(summary.label.contains("Parágrafo 60:"), "the announcement runs to its end")
        XCTAssertLessThan(summary.frame.height, 250,
            "the drawn element holds at most three lines of accessibility-sized text, so the label reports text "
                + "the frame cannot draw: ellipsis is invisible to this instrument")
        attach(app, "dynamic-type-long-summary-control")
    }

    // MARK: - Launching and measuring

    private func launched(contentSize: String? = nil, textShape: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        if let textShape { app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = textShape }
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    @discardableResult
    private func waitForStoryCard(_ app: XCUIApplication, within seconds: TimeInterval) -> XCUIElement? {
        waitForCard(app, titleMatching: Self.storyTitle, within: seconds)
    }

    /// The first card the feed draws that carries a headline of this shape. XCUITest has no "which cards are
    /// materialised" query, so the walk is over the card elements the tree exposes; a card taller than the
    /// viewport is still accepted (only its top has to be on screen), because that is exactly what a card at
    /// AccessibilityXXXL may be.
    private func waitForCard(_ app: XCUIApplication, titleMatching title: NSPredicate,
        within seconds: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let card = storyCards(app, titleMatching: title).first { return card }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return nil
    }

    private func storyCards(_ app: XCUIApplication, titleMatching title: NSPredicate) -> [XCUIElement] {
        let viewport = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 }
            .filter { $0.frame.maxY > viewport.minY + 100 && $0.frame.minY < viewport.maxY - 60 }
            .filter { $0.staticTexts.matching(title).firstMatch.exists }
    }

    private func measured(_ card: XCUIElement) -> CardText {
        let title = card.staticTexts.matching(Self.storyTitle).firstMatch
        let summary = card.staticTexts.matching(Self.storySummary).firstMatch
        let open = card.buttons["card.open"]
        return CardText(
            title: title.label, titleFrame: title.frame,
            summary: summary.label, summaryFrame: summary.frame,
            cardFrame: card.frame,
            openHittable: open.exists && open.isHittable)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
