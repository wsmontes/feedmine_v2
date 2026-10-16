//
// File: FeedFrameMeter.swift
// Module: FeedMineApp (host)
//
// Responsibility:
// Measure what the owner feels and the test suite cannot see: the interval between frames. One `CADisplayLink`
// counts the frames that missed the display's own budget and keeps the worst one; every second it writes the
// second it measured to the app's own trace, and — with the diagnostic capture on — publishes the whole series
// where a journey test reads it. A scroll on the phone or in the simulator therefore produces the **hitch ratio**
// and the series behind it, instead of an opinion.
//
// It is also the run's clock on the device console: the same tick that states `frames=` states the journey line
// (`feedmine journey …`, PO's order of 2026-10-15, assembled by `FeedJourneyConsole`) — one timer, one cadence, so
// the console carries what a physical pass cannot otherwise see without a second clock being invented.
//
// Does not own: rendering, scrolling, or any decision. It reads the display's own clock and states a fact.
import Foundation
import QuartzCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The frame budget it judges against, and the buckets it counts.
///
/// The budget is the **display's** own target interval, `link.targetTimestamp - link.timestamp`: 16,67 ms on a
/// 60 Hz panel, 8,33 ms on a 120 Hz one. It is read per frame and stated by one function
/// (`budgetMilliseconds(target:)`), so the number a run records is the number its buckets judged — the 1000/60
/// this file used to write into the record stated 16,67 ms while judging 8,33 ms on any ProMotion display
/// (exercised in FeedMineAppTests; the display target measured on this machine's simulator and on the owner's
/// iPhone 14 Plus is 16,67 ms, so the two definitions agree *there* and the defect was latent everywhere else).
/// A dropped frame is felt from roughly one and a half budgets on, so the buckets are: on time, `late` (one frame
/// missed), `bad` (two), `severe` (three or more). The ratio that matters is `(late + bad + severe) / frames`, and
/// the worst interval says how bad the bad ones were.
@MainActor
final class FeedFrameMeter: NSObject {
    /// One measured second. This — and not an average — is the series: a second with a single 80 ms frame and a
    /// second with none are different facts about what the reader felt.
    struct Window: Equatable {
        var frames = 0
        var late = 0
        var bad = 0
        var severe = 0
        var worstMilliseconds: Double = 0
    }

    /// How many seconds the published series carries. A journey observes seconds, and the published label is an
    /// accessibility one: two minutes is more than any scroll journey looks at and still small.
    static let publishedWindowCeiling = 120

    /// One second's worth of frames, written where the rest of the run's evidence goes.
    private let record: (String, [String: String]) -> Void

    #if DEBUG
    /// One second's journey facts, asked for on the same tick (nil = do not ask). Debug-only, like everything on
    /// the device console: a shipping build compiles the property, the parameter's use and the call away, so the
    /// meter stays exactly what it was — one callback per frame doing arithmetic.
    private let journey: (@MainActor (Double) -> String?)?
    #endif

    private var link: CADisplayLink?
    /// When the run's own clock started, so the journey line can carry `t=` next to the frame series.
    private var startedAt: CFTimeInterval = 0
    private var windowStarted: CFTimeInterval = 0
    private var previous: CFTimeInterval = 0
    private var current = Window()
    #if DEBUG
    private var recent: [Window] = []
    private var measuredWindows = 0
    #endif
    /// The budget the frames of the window in progress were judged against — the same number the record states.
    private var budgetMilliseconds: Double = 1000.0 / 60.0

    init(record: @escaping (String, [String: String]) -> Void,
        journey: (@MainActor (Double) -> String?)? = nil) {
        self.record = record
        #if DEBUG
        self.journey = journey
        #endif
        super.init()
    }

    /// One definition of the budget, for the buckets and for the record alike.
    static func budgetMilliseconds(target: CFTimeInterval) -> Double {
        max(target, 1.0 / 120) * 1000
    }

    /// The record one measured second produces, with the budget that judged it: the number written is the number
    /// judged, because there is only one place that formats it and the caller hands it the budget the buckets used.
    static func recordFields(_ window: Window, budgetMilliseconds: Double) -> [String: String] {
        ["frames": String(window.frames), "late": String(window.late), "bad": String(window.bad),
            "severe": String(window.severe), "worst_ms": String(format: "%.1f", window.worstMilliseconds),
            "budget_ms": String(format: "%.2f", budgetMilliseconds)]
    }

    /// Which bucket one interval falls in, given the budget it is judged against.
    static func bucket(intervalMilliseconds: Double, budgetMilliseconds: Double) -> (late: Bool, bad: Bool, severe: Bool) {
        if intervalMilliseconds > budgetMilliseconds * 3 { return (false, false, true) }
        if intervalMilliseconds > budgetMilliseconds * 2 { return (false, true, false) }
        if intervalMilliseconds > budgetMilliseconds * 1.5 { return (true, false, false) }
        return (false, false, false)
    }

    /// Starts measuring once per process. Cheap enough to leave on: one callback per frame doing arithmetic.
    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        windowStarted = link.timestamp
        previous = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
        flush(at: previous)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        // `CADisplayLink.timestamp` is **0** until the link has fired once (measured on the device: the journey line
        // said `t=101933s`, the phone's uptime, because the clock had been read at zero). The run's own clock starts
        // with the first frame that was actually displayed.
        if startedAt == 0 { startedAt = now }
        defer { previous = now }
        guard previous > 0 else {
            windowStarted = now
            return
        }
        // The display's own target says what one budget is on this device (120 Hz panels report 8,33 ms).
        let budget = Self.budgetMilliseconds(target: link.targetTimestamp - link.timestamp)
        budgetMilliseconds = budget
        let interval = (now - previous) * 1000
        current.frames += 1
        let missed = Self.bucket(intervalMilliseconds: interval, budgetMilliseconds: budget)
        if missed.severe { current.severe += 1 } else if missed.bad { current.bad += 1 }
        else if missed.late { current.late += 1 }
        if interval > current.worstMilliseconds { current.worstMilliseconds = interval }
        if now - windowStarted >= 1 { flush(at: now) }
    }

    /// Writes one line per measured second — the series, not an average: a second with a single 80 ms frame and a
    /// second with none are different facts.
    private func flush(at now: CFTimeInterval) {
        guard current.frames > 0 else { windowStarted = now; return }
        let window = current
        record("frames", Self.recordFields(window, budgetMilliseconds: budgetMilliseconds))
        #if DEBUG
        NSLog("feedmine frames=%d late=%d bad=%d severe=%d worst_ms=%.1f budget_ms=%.2f", window.frames,
            window.late, window.bad, window.severe, window.worstMilliseconds, budgetMilliseconds)
        if let journey, let line = journey(now - startedAt) {
            NSLog("feedmine journey %@", line)
        }
        #endif
        #if DEBUG
        if FeedFrameEvidence.captureEnabled {
            measuredWindows += 1
            recent.append(window)
            if recent.count > Self.publishedWindowCeiling {
                recent.removeFirst(recent.count - Self.publishedWindowCeiling)
            }
        }
        #endif
        current = Window()
        windowStarted = now
        #if DEBUG
        if FeedFrameEvidence.captureEnabled { FeedFrameEvidence.publish(publishedSeries) }
        #endif
    }

    #if DEBUG
    /// The series as it is published, in the order it was measured: the budget once (the number every bucket in
    /// the series judged against), how many seconds this process has measured in total — so a reader of the series
    /// can say which second is which — and then one `frames/late/bad/severe/worst_ms` per second.
    var publishedSeries: String {
        let entries = recent.map { window in
            "\(window.frames)/\(window.late)/\(window.bad)/\(window.severe)/"
                + String(format: "%.1f", window.worstMilliseconds)
        }
        return "budget_ms=" + String(format: "%.2f", budgetMilliseconds)
            + ";seconds=" + String(measuredWindows)
            + ";series=" + entries.joined(separator: "|")
    }
    #endif
}

#if DEBUG && canImport(UIKit)
/// Where the meter publishes the series it measured, so a journey test asserts the app's **own** counters instead
/// of a paraphrase — and so the measurement and the assertion can never be two different numbers.
///
/// The reader is a SwiftUI `Text` over this tiny observable — the same channel the app already uses for the
/// viewport counters the suite reads, and it publishes **now**: reading the property *is* the read. The first
/// version pushed the string into a `UILabel` inside a `UIViewRepresentable` (`label.text = series`) and the
/// accessibility tree froze on the first window — measured 2026-10-16: 120 one-second windows written to the app's
/// own trace while the tree kept serving window 1, with a stored `XCUIElement` and with a freshly resolved one
/// alike. The instance the tree served was not the instance receiving the writes. What the journey reads has to be
/// what the app published *now*, so the value is rendered from the state instead of pushed into a view object.
///
/// Nothing the reader draws depends on this: the state is read by this overlay alone, so a publication re-evaluates
/// one 1×1 view per second and never the feed.
@MainActor
@Observable
final class FeedFrameEvidence {
    /// The diagnostic capture, off by default with the rest of the trace: a journey test turns it on, the normal
    /// operation pays nothing.
    static let captureEnabled = ProcessInfo.processInfo.environment["FEEDMINE_TRACE_CAPTURE"] == "1"
    static let shared = FeedFrameEvidence()

    /// The whole published series — the budget, how many seconds the process measured, and one
    /// `frames/late/bad/severe/worst_ms` per second, in the order they were measured.
    var series = ""

    static func publish(_ text: String) {
        shared.series = text
    }
}

/// The one point in the reader's window where the series is readable: invisible in pixels and in layout, present
/// in the accessibility tree a journey test reads.
struct FeedFrameEvidenceSurface: View {
    private let evidence = FeedFrameEvidence.shared

    var body: some View {
        Text(evidence.series)
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier("feed-frame-proof")
            .allowsHitTesting(false)
    }
}
#endif
