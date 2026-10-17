//
// File: AppearanceLegibilityUITests.swift
// Module: FeedMineUITests
//
// UI-READABILITY-01. The reader's palette (`ReaderAppearance`) pins every page tint to a light value per period and
// every surface that paints it pairs it with `.foregroundStyle(.primary)`. Under a **dark** device appearance that
// pairing measured 1.19:1 before the fix (white text over `#F0EBE4`), because nothing declared the presentation's
// appearance. The fix declares the light presentation at the app's presentation owner, so this test exists to read
// the **rendered pixels** of the real surfaces in a dark environment and to refuse a surface that is not the
// declared light presentation or whose text does not clear its contrast bar.
//
// It samples, in this order: the first feed card's title band, the local reading surface's headline and body, and
// one sheet reachable from the header (the settings), because those are three different presentations (the window's
// own content, a presented page, and a sheet) and the appearance has to reach all of them.
//
// Run it with the simulator in dark appearance — that is the environment the defect was measured in:
//
//   xcrun simctl ui <device> appearance dark
//   xcodebuild … -only-testing:FeedMineUITests/AppearanceLegibilityUITests test
//
// In light appearance the same assertions pass trivially; the dark run is the one that proves the declaration.
// Both are run for this branch, and the attachment names carry no appearance: the environment is the run's, and
// the statement lines the test prints are the measurement.
import XCTest
import UIKit

@MainActor
final class AppearanceLegibilityUITests: XCTestCase {
    /// A publication identity, exactly as the feed's cards state it (the same shape `ReadingSurfaceUITests` uses).
    private static let cardIdentifier = NSPredicate(format: "identifier MATCHES %@",
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /// WCAG AA for normal text. Every sample below is normal-size text (a 17 pt semibold headline or smaller, a
    /// 15 pt body, a 15 pt list row); no sample is the 18 pt regular / 14 pt bold "large" exception.
    private static let normalTextRatio: Double = 4.5

    func testTheFeedTheReadingSurfaceAndASheetAreLegibleWithTheDeviceInDarkAppearance() throws {
        let app = launched(shape: "body")
        defer { app.terminate() }

        guard let card = visibleCard(app) else {
            return XCTFail("the local fixture feed publishes cards")
        }
        let screen = app.windows.firstMatch.frame
        let feedShot = app.screenshot()
        let feedPixels = try PixelCapture(feedShot, screen: screen)
        let feed = try feedPixels.sample(titleBand(of: card), screen: screen, label: "feed card title")
        attach(feedShot, name: "ui-readability-feed")
        assertLegible(feed)

        // The local reading surface: the same `.primary` over the same page tint, one presentation up.
        let open = card.buttons["card.open"]
        if open.exists && open.isHittable { open.tap() } else { card.tap() }
        let headline = element(app, "reading.headline")
        XCTAssertTrue(headline.waitForExistence(timeout: 25), "a stored body opens the local reading surface")
        let body = element(app, "reading.body")
        XCTAssertTrue(body.waitForExistence(timeout: 25), "the stored text is on the reading surface")
        let readingShot = app.screenshot()
        let readingPixels = try PixelCapture(readingShot, screen: screen)
        let reading = try readingPixels.sample(inset(headline.frame, by: 2), screen: screen,
            label: "reading headline")
        let paragraph = try readingPixels.sample(visibleTop(of: body.frame, height: 200, on: screen),
            screen: screen, label: "reading body")
        attach(readingShot, name: "ui-readability-reading")
        assertLegible(reading)
        assertLegible(paragraph)

        element(app, "reading.close").tap()
        XCTAssertTrue(element(app, "reading.headline").waitForNonExistence(timeout: 20),
            "closing the reader returns to the feed")

        // One sheet, from the header's own menu. The settings surface is a presentation of its own: it is what
        // proves the declaration reaches a surface the window is not drawing. Its title is `.primary` over the
        // sheet's own page tint — the same pairing the feed and the reading surface were measured on.
        openAdjustments(app)
        let title = app.navigationBars.firstMatch.staticTexts.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the settings sheet states its own title")
        let sheetShot = app.screenshot()
        let sheetPixels = try PixelCapture(sheetShot, screen: screen)
        let sheet = try sheetPixels.sample(inset(title.frame, by: 2), screen: screen,
            label: "settings sheet title")
        attach(sheetShot, name: "ui-readability-sheet")
        assertLegible(sheet)
    }

    // MARK: - The surfaces' regions

    /// The card's title band. `card.open` wraps the title, summary and date, and the title is its first line: the
    /// band stops before the summary, which is `.secondary` and deliberately not what this test measures. The
    /// leading inset clears the card's 3 pt accent bar, which is decoration rather than text.
    private func titleBand(of card: XCUIElement) -> CGRect {
        let surface = card.buttons["card.open"].exists ? card.buttons["card.open"].frame : card.frame
        return CGRect(x: surface.minX + 14, y: surface.minY + 2,
            width: max(1, surface.width - 28), height: min(28, max(10, surface.height / 2)))
    }

    private func inset(_ rect: CGRect, by value: CGFloat) -> CGRect {
        rect.insetBy(dx: value, dy: value)
    }

    /// The on-screen part of a region that can be taller than the screen (the stored text is one `Text`).
    private func visibleTop(of rect: CGRect, height: CGFloat, on screen: CGRect) -> CGRect {
        let top = max(rect.minY, screen.minY)
        return CGRect(x: rect.minX, y: top, width: rect.width,
            height: max(1, min(height, min(rect.maxY, screen.maxY) - top)))
    }

    // MARK: - The measurement

    private struct PixelSample {
        let label: String
        let background: (r: Double, g: Double, b: Double)
        let ink: (r: Double, g: Double, b: Double)
        let backgroundLuminance: Double
        let inkLuminance: Double
        let pixels: (x: Int, y: Int, width: Int, height: Int)

        var ratio: Double {
            (max(backgroundLuminance, inkLuminance) + 0.05) / (min(backgroundLuminance, inkLuminance) + 0.05)
        }

        var statement: String {
            String(format: "%@ [%d,%d %d×%d]: background #%02X%02X%02X (L=%.4f), text #%02X%02X%02X (L=%.4f), "
                + "contrast %.2f:1",
                label, pixels.x, pixels.y, pixels.width, pixels.height,
                Int(background.r.rounded()), Int(background.g.rounded()), Int(background.b.rounded()),
                backgroundLuminance,
                Int(ink.r.rounded()), Int(ink.g.rounded()), Int(ink.b.rounded()),
                inkLuminance, ratio)
        }
    }

    private enum LegibilityError: Error, CustomStringConvertible {
        case unreadableRegion(String)
        case unreadableCapture(String)

        var description: String {
            switch self {
            case .unreadableRegion(let detail): return "the sampled region holds no measurable pixels: \(detail)"
            case .unreadableCapture(let detail): return "the capture could not be read: \(detail)"
            }
        }
    }

    /// One capture, decoded once into sRGB bytes with **row 0 at the top**, so a region's row range is the band a
    /// reader sees there. Element frames are in screen points; the capture is the screen in device pixels, and the
    /// ratio between the two is the only mapping this test needs.
    private struct PixelCapture {
        let width: Int
        let height: Int
        let scale: CGFloat
        let bytes: [UInt8]

        init(_ shot: XCUIScreenshot, screen: CGRect) throws {
            guard let image = shot.image.cgImage else { throw LegibilityError.unreadableCapture("no CGImage") }
            width = image.width
            height = image.height
            scale = CGFloat(image.width) / screen.width
            var storage = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let drawn: Bool = storage.withUnsafeMutableBytes { raw in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                    let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                // A bitmap context's memory rows are laid out with row 0 at the top, which is also the capture's
                // own orientation: drawing the image upright puts its first row at memory row 0, so no CTM
                // transform belongs here. (Flipping the CTM, the usual reflex, stored the capture upside down —
                // measured against the same pixels with PIL: the band then held the area 700 pt below it.)
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { throw LegibilityError.unreadableCapture("no sRGB bitmap context") }
            bytes = storage
        }

        /// Two colours of a region: the **background** (its modal colour, so a stray icon or a control's tint
        /// cannot stand in for the page) and the **ink** (the mean of its darkest 1% — the app's page tints are
        /// light by construction, so the text a reader follows is always the dark side).
        func sample(_ region: CGRect, screen: CGRect, label: String) throws -> PixelSample {
            let originX = Int(((region.minX - screen.minX) * scale).rounded(.down))
            let originY = Int(((region.minY - screen.minY) * scale).rounded(.down))
            let endX = min(width, Int(((region.maxX - screen.minX) * scale).rounded(.up)))
            let endY = min(height, Int(((region.maxY - screen.minY) * scale).rounded(.up)))
            let x0 = max(0, min(width, originX)), y0 = max(0, min(height, originY))
            let columns = endX - x0, rows = endY - y0
            guard columns >= 16, rows >= 8 else {
                throw LegibilityError.unreadableRegion(
                    "\(label) at \(region) maps to \(columns)×\(rows) px")
            }

            var histogram: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
            var luminances: [Double] = []
            luminances.reserveCapacity(columns * rows)
            for row in y0..<endY {
                for column in x0..<endX {
                    let index = (row * width + column) * 4
                    let r = Double(bytes[index]), g = Double(bytes[index + 1]), b = Double(bytes[index + 2])
                    let key = (Int(r) >> 3) << 10 | (Int(g) >> 3) << 5 | (Int(b) >> 3)
                    let entry = histogram[key] ?? (0, 0, 0, 0)
                    histogram[key] = (entry.count + 1, entry.r + r, entry.g + g, entry.b + b)
                    luminances.append(wcagLuminance(r, g, b))
                }
            }
            guard let modal = histogram.max(by: { $0.value.count < $1.value.count })?.value else {
                throw LegibilityError.unreadableRegion("empty histogram for \(label)")
            }
            let background = (r: modal.r / Double(modal.count), g: modal.g / Double(modal.count),
                b: modal.b / Double(modal.count))
            luminances.sort()
            let inkCount = max(32, luminances.count / 100)
            let darkest = meanColour(in: y0..<endY, columns: x0..<endX) { $0 <= luminances[inkCount - 1] }
            let lightest = meanColour(in: y0..<endY, columns: x0..<endX) { $0 >= luminances[luminances.count - inkCount] }
            let backgroundLuminance = wcagLuminance(background.r, background.g, background.b)
            // The text is the colour **farthest** from the page, whichever side of it that is: the fix makes it
            // darker, the defect made it lighter (white over the fixed light tint), and both have to be measured,
            // not just the dark one — a sampler that only looked for dark ink reported 1.00:1 on the red tree.
            let ink = abs(wcagLuminance(darkest.r, darkest.g, darkest.b) - backgroundLuminance)
                >= abs(wcagLuminance(lightest.r, lightest.g, lightest.b) - backgroundLuminance)
                ? darkest : lightest
            return PixelSample(label: label, background: background, ink: ink,
                backgroundLuminance: backgroundLuminance,
                inkLuminance: wcagLuminance(ink.r, ink.g, ink.b),
                pixels: (x0, y0, columns, rows))
        }

        /// The mean colour of the pixels of a region whose luminance passes `included`.
        private func meanColour(in rows: Range<Int>, columns: Range<Int>,
            where included: (Double) -> Bool) -> (r: Double, g: Double, b: Double) {
            var sumR = 0.0, sumG = 0.0, sumB = 0.0, taken = 0
            for row in rows {
                for column in columns {
                    let index = (row * width + column) * 4
                    let r = Double(bytes[index]), g = Double(bytes[index + 1]), b = Double(bytes[index + 2])
                    if included(wcagLuminance(r, g, b)) {
                        sumR += r; sumG += g; sumB += b; taken += 1
                    }
                }
            }
            return (sumR / Double(max(1, taken)), sumG / Double(max(1, taken)), sumB / Double(max(1, taken)))
        }
    }

    /// Both halves of UI-READABILITY-01's acceptance: the surface is the **declared light presentation** (a dark
    /// environment may not leave a page tinted light and its text flipped), and the text on it is legible.
    private func assertLegible(_ sample: PixelSample, file: StaticString = #filePath, line: UInt = #line) {
        print("LEGIBILITY \(sample.statement)")
        XCTAssertGreaterThanOrEqual(sample.backgroundLuminance, 0.5,
            "\(sample.statement) — the 1.0 presentation is light, in light and in dark appearance alike",
            file: file, line: line)
        XCTAssertGreaterThanOrEqual(sample.ratio, Self.normalTextRatio,
            "\(sample.statement) — WCAG AA asks 4.5:1 for normal text", file: file, line: line)
    }

    // MARK: - The app

    private func launched(shape: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = shape
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    private func visibleCard(_ app: XCUIApplication) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            let window = app.windows.firstMatch.frame
            if let card = app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
                .filter({ $0.exists && $0.frame.height > 40 })
                .first(where: { $0.frame.minY > window.minY + 120 && $0.frame.maxY < window.maxY - 80 }) {
                return card
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return nil
    }

    /// The header's menu → the settings surface, with the retry the surface needs (the first tap can reach the
    /// layout before the header is ready). The menu row carries the system symbol's name, which no language moves.
    private func openAdjustments(_ app: XCUIApplication) {
        for attempt in 0..<3 {
            let menu = app.buttons["more-menu"]
            if menu.waitForExistence(timeout: 20), menu.isHittable { menu.tap() }
            let settings = app.buttons["gearshape"]
            if settings.waitForExistence(timeout: 8), settings.isHittable {
                settings.tap()
                XCTAssertTrue(app.switches["settings-prefetch"].waitForExistence(timeout: 20),
                    "the adjustments opened")
                return
            }
            Thread.sleep(forTimeInterval: 1.5)
            if attempt == 2 { print("MENU_TREE_BEGIN\n\(app.debugDescription)\nMENU_TREE_END") }
        }
        XCTFail("the reader's own menu offers the adjustments")
    }

    private func attach(_ shot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// WCAG 2.x relative luminance of one sRGB channel.
private func wcagLinear(_ channel: Double) -> Double {
    let value = channel / 255
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
}

private func wcagLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
    0.2126 * wcagLinear(r) + 0.7152 * wcagLinear(g) + 0.0722 * wcagLinear(b)
}
