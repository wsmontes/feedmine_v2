//
// File: ReaderHeaderWordmarkUITests.swift
// Module: FeedMineUITests
//
// The header's status chip draws the app's wordmark (`Feedmine`) beside the context switcher. At
// `UICTContentSizeCategoryAccessibilityXXXL` the word was laid out as four fragments — `Fe-`, `ed-`, `min`, `e` —
// because the text scales with Dynamic Type while the header's 44 pt controls leave it a narrow slot.
//
// This journey launches the app twice — the reader's current size and AccessibilityXXXL — and measures the
// wordmark's accessibility frame. A word drawn on one line is wider than it is tall; the fragmented drawing was
// taller than it was wide. The attachment is the screen, because the frame alone cannot show a hyphen.
import XCTest

@MainActor
final class ReaderHeaderWordmarkUITests: XCTestCase {
    private static let accessibilityXXXL = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let mark = NSPredicate(format: "label == %@", "Feedmine")

    /// The wordmark's announcement and the frame it was drawn in. `XCUIElement` is a query, not a snapshot: after
    /// the app terminates its `frame` resolves against the next launch, so every number is taken here.
    private struct Mark {
        let label: String
        let frame: CGRect
        let chipHittable: Bool
    }

    func testHeaderWordmarkStaysOnOneLineAtAccessibilityXXXL() throws {
        let baselineApp = launched()
        let baseline = try XCTUnwrap(measured(baselineApp, within: 120),
            "the header draws its wordmark at the reader's current size")
        print("WORDMARK default label=\(baseline.label) frame=\(baseline.frame) chipHittable=\(baseline.chipHittable)")
        attach(baselineApp, "wordmark-default")
        baselineApp.terminate()

        let largeApp = launched(contentSize: Self.accessibilityXXXL)
        guard let large = measured(largeApp, within: 120) else {
            print("WORDMARK_TREE\n\(largeApp.debugDescription)")
            return XCTFail("the header draws its wordmark at AccessibilityXXXL")
        }
        print("WORDMARK xxxl label=\(large.label) frame=\(large.frame) chipHittable=\(large.chipHittable) screen=\(largeApp.windows.firstMatch.frame)")
        let record = """
            default label=\(baseline.label) frame=\(baseline.frame) chipHittable=\(baseline.chipHittable)
            xxxl label=\(large.label) frame=\(large.frame) chipHittable=\(large.chipHittable) screen=\(largeApp.windows.firstMatch.frame)
            """
        let evidence = XCTAttachment(string: record)
        evidence.name = "wordmark-measurements"
        evidence.lifetime = .keepAlways
        add(evidence)
        attach(largeApp, "wordmark-accessibility-xxxl")

        // The announcement is the whole word: this part was already true (the fragments were one `Text`), so it
        // is the control for the measurement below, not the defect.
        XCTAssertEqual(large.label, "Feedmine", "the wordmark announces the whole word")
        XCTAssertTrue(large.chipHittable, "the context chip is still reachable at AccessibilityXXXL")

        // The defect's shape: four stacked fragments made the frame taller than wide. One line is wider than tall.
        XCTAssertGreaterThan(large.frame.width, large.frame.height * 1.5,
            "the wordmark is drawn on one line, not stacked: frame \(large.frame)")
        // And it is still the accessibility size, not the small default: the one line is larger than the default
        // drawing, so the fix did not simply pin the type back to the frozen ruler.
        XCTAssertGreaterThan(large.frame.height, baseline.frame.height,
            "the mark still grows with Dynamic Type: \(large.frame.height) vs default \(baseline.frame.height)")
        XCTAssertGreaterThan(large.frame.width, baseline.frame.width,
            "the one line is drawn at the accessibility size: \(large.frame.width) vs default \(baseline.frame.width)")
    }

    private func launched(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    /// The wordmark's own leaf. The chip is a `Menu`; the text it draws may surface as a descendant of the menu
    /// button or, on this runtime, as a window-level static text. Both are tried, and the chip itself is never
    /// used as a stand-in: its frame includes the other chip texts.
    private func measured(_ app: XCUIApplication, within seconds: TimeInterval) -> Mark? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let leaf = wordmark(app) {
                let chip = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@", "reader-contexts")).firstMatch
                return Mark(label: leaf.label, frame: leaf.frame,
                    chipHittable: chip.exists && chip.isHittable)
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return nil
    }

    private func wordmark(_ app: XCUIApplication) -> XCUIElement? {
        let chip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "reader-contexts")).firstMatch
        if chip.exists {
            let inside = chip.staticTexts.matching(Self.mark).firstMatch
            if inside.exists && inside.frame.height > 4 { return inside }
        }
        let anywhere = app.staticTexts.matching(Self.mark).firstMatch
        if anywhere.exists && anywhere.frame.height > 4 { return anywhere }
        return nil
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
