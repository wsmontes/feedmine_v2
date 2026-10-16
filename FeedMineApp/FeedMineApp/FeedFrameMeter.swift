//
// File: FeedFrameMeter.swift
// Module: FeedMineApp (host)
//
// Responsibility:
// Measure what the owner feels and the test suite cannot see: the interval between frames. One `CADisplayLink`
// counts the frames that missed the budget and keeps the worst one; every second it writes what it saw to the
// app's own trace, so a scroll on the real device produces the **hitch ratio** instead of an opinion.
//
// It is also the run's clock on the device console: the same tick that states `frames=` states the journey line
// (`feedmine journey …`, PO's order of 2026-10-15, assembled by `FeedJourneyConsole`) — one timer, one cadence, so
// the console carries what a physical pass cannot otherwise see without a second clock being invented.
//
// Does not own: rendering, scrolling, or any decision. It reads the display's own clock and states a fact.
import Foundation
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

/// The frame budget it judges against, and the buckets it counts.
///
/// A 60 Hz display gives 16,67 ms per frame. A dropped frame is felt from roughly one and a half budgets on, so
/// the buckets are: on time, `late` (one frame missed), `bad` (two), `severe` (three or more). The ratio that
/// matters is `(late + bad + severe) / frames`, and the worst interval says how bad the bad ones were.
@MainActor
final class FeedFrameMeter: NSObject {
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
    private var frames = 0
    private var late = 0
    private var bad = 0
    private var severe = 0
    private var worst: Double = 0
    private var worstAt: CFTimeInterval = 0

    init(record: @escaping (String, [String: String]) -> Void,
        journey: (@MainActor (Double) -> String?)? = nil) {
        self.record = record
        #if DEBUG
        self.journey = journey
        #endif
        super.init()
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
        guard previous > 0 else { return }
        let interval = (now - previous) * 1000
        frames += 1
        // The display's own target says what one budget is on this device (120 Hz panels report 8,33 ms).
        let budget = max(link.targetTimestamp - link.timestamp, 1.0 / 120) * 1000
        if interval > budget * 3 { severe += 1 } else if interval > budget * 2 { bad += 1 }
        else if interval > budget * 1.5 { late += 1 }
        if interval > worst { worst = interval; worstAt = now }
        if now - windowStarted >= 1 { flush(at: now) }
    }

    /// Writes one line per measured second — the series, not an average: a second with a single 80 ms frame and a
    /// second with none are different facts.
    private func flush(at now: CFTimeInterval) {
        guard frames > 0 else { windowStarted = now; return }
        let budget = 1000.0 / 60.0
        record("frames", ["frames": String(frames), "late": String(late), "bad": String(bad),
            "severe": String(severe), "worst_ms": String(format: "%.1f", worst),
            "budget_ms": String(format: "%.2f", budget),
            "worst_at": String(format: "%.3f", worstAt)])
        #if DEBUG
        NSLog("feedmine frames=%d late=%d bad=%d severe=%d worst_ms=%.1f", frames, late, bad, severe, worst)
        // The same tick, one line: what the journey itself is doing. Nothing is asked for — and nothing is
        // computed — unless the host handed a sampler in.
        if let journey, let line = journey(now - startedAt) {
            NSLog("feedmine journey %@", line)
        }
        #endif
        frames = 0; late = 0; bad = 0; severe = 0; worst = 0
        windowStarted = now
    }
}
