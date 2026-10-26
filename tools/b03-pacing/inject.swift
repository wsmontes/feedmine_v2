import Cocoa
import ApplicationServices

// Native event injector for the Feedmine Simulator window.
// Posts real HID mouse events into Simulator.app (a mouse drag there IS a touch swipe on the device).
// Velocity is controlled by event timestamps: a drag that stops moving before the lift has zero release
// velocity, so the scroll does not coast and the number of cards consumed is set by the drag distance.

struct Config {
    var x: CGFloat = 1177
    var y0: CGFloat = 900
    var y1: CGFloat = 720
    var steps: Int = 12
    var dragMs: Int = 300
    // **Zero by default.** A dwell before the lift is a measured defect, not a knob: the pan recognizer
    // fails when the finger stops, the release becomes a tap on the card, and iOS hands the corpus URL to
    // Safari, which then swallows every later gesture (measured 2026-10-26: three profiles at exact
    // cadence, zero advances). Low release velocity has to come from a slow continuous drag instead.
    var holdMs: Int = 0
    var count: Int = 10
    var intervalMs: Int = 1000
    var label: String = "run"
    var log: String = "/tmp/b03-pilot/inject.jsonl"
}

func argValue(_ name: String, _ args: [String]) -> String? {
    if let i = args.firstIndex(of: name), i + 1 < args.count { return args[i + 1] }
    return nil
}

var cfg = Config()
let args = CommandLine.arguments
if let v = argValue("--x", args).flatMap(Double.init) { cfg.x = v }
if let v = argValue("--y0", args).flatMap(Double.init) { cfg.y0 = v }
if let v = argValue("--y1", args).flatMap(Double.init) { cfg.y1 = v }
if let v = argValue("--steps", args).flatMap(Int.init) { cfg.steps = v }
if let v = argValue("--drag-ms", args).flatMap(Int.init) { cfg.dragMs = v }
if let v = argValue("--hold-ms", args).flatMap(Int.init) { cfg.holdMs = v }
if let v = argValue("--count", args).flatMap(Int.init) { cfg.count = v }
if let v = argValue("--interval-ms", args).flatMap(Int.init) { cfg.intervalMs = v }
if let v = argValue("--label", args) { cfg.label = v }
if let v = argValue("--log", args) { cfg.log = v }

let src = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint) {
    guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
    e.post(tap: .cghidEventTap)
}

// Bring Simulator forward without disturbing anything else: the pilot drives a dedicated bench device.
if let sim = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").first {
    sim.activate(options: [])
}

// No focus click: a click on the device is a tap, and a tap on a card opens its URL in Safari, which
// then swallows every later gesture. The window is brought forward by activating Simulator only.
usleep(250_000)

func now() -> Double { return Date().timeIntervalSince1970 }
var logLines: [String] = []
let startedAt = now()

for g in 0..<cfg.count {
    let target = startedAt + Double(g) * Double(cfg.intervalMs) / 1000.0
    let wait = target - now()
    if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }

    let downAt = now()
    post(.leftMouseDown, CGPoint(x: cfg.x, y: cfg.y0))
    // Interpolated drag: `steps` move events spread over dragMs. Explicit pacing is the whole point.
    for s in 1...cfg.steps {
        let f = CGFloat(s) / CGFloat(cfg.steps)
        let p = CGPoint(x: cfg.x, y: cfg.y0 + (cfg.y1 - cfg.y0) * f)
        usleep(useconds_t(Double(cfg.dragMs) / Double(cfg.steps) * 1000.0))
        post(.leftMouseDragged, p)
    }
    // Dwell before the lift: the release velocity is what makes XCTest's swipe coast for several cards.
    if cfg.holdMs > 0 { usleep(useconds_t(cfg.holdMs * 1000)) }
    post(.leftMouseUp, CGPoint(x: cfg.x, y: cfg.y1))
    let upAt = now()

    let rec: [String: Any] = ["label": cfg.label, "gesture": g, "down_at": downAt, "up_at": upAt,
                              "intended_at": target, "interval_ms": cfg.intervalMs,
                              "distance_pt": Double(cfg.y0 - cfg.y1), "drag_ms": cfg.dragMs, "hold_ms": cfg.holdMs]
    if let d = try? JSONSerialization.data(withJSONObject: rec), let s = String(data: d, encoding: .utf8) {
        logLines.append(s)
    }
}

// The log is the instrument's own record of intent (what was scheduled), independent of the app.
let header = "{\"label\": \"\(cfg.label)\", \"started_at\": \(startedAt), \"gestures\": \(cfg.count), " +
    "\"interval_ms\": \(cfg.intervalMs), \"steps\": \(cfg.steps), \"drag_ms\": \(cfg.dragMs), " +
    "\"hold_ms\": \(cfg.holdMs), \"y0\": \(Double(cfg.y0)), \"y1\": \(Double(cfg.y1))}"
if FileManager.default.fileExists(atPath: cfg.log) {
    if let h = FileHandle(forWritingAtPath: cfg.log) {
        h.seekToEndOfFile()
        h.write((([header] + logLines).joined(separator: "\n") + "\n").data(using: .utf8)!)
        try? h.close()
    }
} else {
    try? (([header] + logLines).joined(separator: "\n") + "\n").write(toFile: cfg.log, atomically: true, encoding: .utf8)
}
print("\(cfg.label): \(cfg.count) gestures, interval \(cfg.intervalMs) ms, elapsed \(String(format: "%.2f", now() - startedAt)) s")
