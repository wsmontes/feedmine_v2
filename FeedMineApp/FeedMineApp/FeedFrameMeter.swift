//
// File: FeedFrameMeter.swift
// Module: FeedMineApp (host)
//
// Responsibility:
// Measure what the owner feels and the test suite cannot see: the interval between frames. One `CADisplayLink`
// counts the frames that missed the budget and keeps the worst one; every second it writes what it saw to the
// app's own trace, so a scroll on the real device produces the **hitch ratio** instead of an opinion.
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

    private var link: CADisplayLink?
    private var windowStarted: CFTimeInterval = 0
    private var previous: CFTimeInterval = 0
    private var frames = 0
    private var late = 0
    private var bad = 0
    private var severe = 0
    private var worst: Double = 0
    private var worstAt: CFTimeInterval = 0

    init(record: @escaping (String, [String: String]) -> Void) {
        self.record = record
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
        #endif
        frames = 0; late = 0; bad = 0; severe = 0; worst = 0
        windowStarted = now
    }
}
