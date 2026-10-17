// File: FeedLaunchWitness.swift
// Module: FeedMineUI (diagnostics only)
//
// Responsibility:
//   Record, in the order they happened, the surfaces this process put on the reader's screen during its launch:
//   the ones that say "wait" and the first one that carried the reader's own ready cards.
//
// Owns:
//   Four facts and one clock. Nothing else.
//
// Does not own:
//   Any decision, any rendering, any admission, any publication. Nothing reads this to choose what to show — it is
//   evidence, not policy (the same rule as RunwayTrace). And nothing here *decides* a branch either: the host states
//   which branch its own body is drawing, and this only writes the fact down.
//
// Architectural invariants:
//   The witness exists because of the PO's headline criterion — "close and reopen the app: the feed must appear
//   immediately, from the ready content of the previous interaction … with no loading screen in between"
//   (1.0-checklist.md:3131-3132, restated :3220-3224). A UI test cannot sample that transition: `XCUIApplication
//   .launch()` returns only once the app is idle, so the loading surface that lived for the whole transition is
//   precisely the one it can never see. The app's own record can see it, and it is the only witness that can.
//
// Status:
//   DEBUG only: a shipped build records nothing and publishes nothing.

#if DEBUG
import Foundation

/// The reader's relaunch, as the app itself saw it.
///
/// The host calls `note(_:)` once per pass of its own body, stating the branch that pass is drawing; this writes
/// down the two facts the criterion compares, on the process's own clock (armed at the top of the app's
/// construction, so every number reads as "milliseconds since this launch began"):
///
/// - the **wait** surfaces: the app's own launch progress and the feed's absence surface, with the instant of the
///   first one, the instant of the last one and how many passes carried one;
/// - the **first pass that carried the reader's own ready cards**, with how many.
///
/// The instants are comparable on purpose: what the criterion asks is the **order**. A wait surface at 120 ms and
/// cards at 2 900 ms is the loading screen the criterion rules out; cards at 90 ms and a wait surface at 4 000 ms is
/// a later rebuild, not a reopen.
@MainActor
public enum FeedLaunchWitness {
    /// What the host's current body pass is about to draw. The host owns this branch — it holds the association and
    /// the screen's own inputs — so the record is taken from the same values the screen reads, never from a second
    /// opinion about them.
    public enum Branch: Sendable {
        /// The app is still building the local feed: its own progress surface.
        case launchProgress
        /// The feed's absence surface, stating this work state (`idle`, `preparing`, …).
        case feedAbsence(String)
        /// A surface that waits for nothing: a selection with no sources at all (V1's own empty state).
        case notAWaitSurface
        /// The reader's own ready cards, `count` of them.
        case cards(Int)
    }

    /// How many passes of the host's body carried a wait surface.
    public private(set) static var waitPasses = 0
    /// The first wait surface: what it was, and when. **One value**, written in one go, so a record can never state
    /// a wait surface without saying when it was on screen — they are the same fact.
    private static var firstWait: (kind: String, at: Double)?
    /// When the last one was on screen: with the first, the window the reader sat through.
    private static var lastWaitAt: Double?
    /// The first pass that carried the reader's own ready cards: how many, and when. One value, for the same reason.
    private static var firstCards: (count: Int, at: Double)?

    /// The card counts a cold start is judged on, and the first time each count was on screen. `firstCards` states
    /// the first pass that carried *any* card; these state when the window reached 1, 5 and 10 — the thresholds the
    /// cold-start measurement asks for — and they are read on the same clock as every other fact here.
    public static let cardMilestones = [1, 5, 10]
    private static var milestoneAt: [Int: Double] = [:]

    /// The origin every fact is stated from. The app arms it at the very top of its own construction
    /// (`FeedMineApp.init`), so the record's numbers read as "milliseconds since this launch began".
    ///
    /// Arming is what keeps the clock honest. A lazily-initialized origin is read *inside* the subtraction
    /// (`now - origin` evaluates `now` first and the origin second), so the first fact of a process could measure
    /// against an origin captured **after** itself and come out negative — measured twice, as `first_wait_ms=n/a`
    /// beside a real `kind=launch-progress`, and once as `cards=17 first_cards_ms=n/a`. An unarmed record still
    /// works: it takes its origin from its own first fact.
    public static func arm() {
        if origin == nil { origin = ProcessInfo.processInfo.systemUptime }
    }
    private static var origin: Double?

    /// One pass of the host's own body, stating what it is drawing. Called once per pass; a pass that draws the
    /// reader's feed is not a wait, and a pass that draws neither is not evidence about either.
    public static func note(_ branch: Branch) {
        switch branch {
        case .launchProgress: noteWaitSurface("launch-progress")
        case .feedAbsence(let kind): noteWaitSurface("absence:" + kind)
        case .notAWaitSurface: break
        case .cards(let count):
            for milestone in Self.cardMilestones where count >= milestone && milestoneAt[milestone] == nil {
                milestoneAt[milestone] = elapsedMilliseconds()
            }
            guard firstCards == nil else { return }
            firstCards = (count, elapsedMilliseconds())
        }
    }

    private static func noteWaitSurface(_ kind: String) {
        let now = elapsedMilliseconds()
        waitPasses += 1
        lastWaitAt = now
        if firstWait == nil { firstWait = (kind, now) }
    }

    /// The record as one line, for a run's output: fields a script can read.
    public static var record: String {
        let wait = firstWait
        let cards = firstCards
        return "wait_passes=\(waitPasses) kind=\(wait?.kind ?? "none")"
            + " first_wait_ms=\(wait.map { clock($0.at) } ?? "n/a")"
            + " last_wait_ms=\(lastWaitAt.map(clock) ?? "n/a")"
            + " cards=\(cards?.count ?? 0) first_cards_ms=\(cards.map { clock($0.at) } ?? "n/a")"
            + Self.cardMilestones.map { " cards\($0)_ms=\(milestoneAt[$0].map(clock) ?? "n/a")" }.joined()
    }

    /// Whether the reader's first reading surface was already their feed: no wait surface was rendered at all, or
    /// every wait surface came after the cards were on screen (a later rebuild, not a reopen).
    public static var firstSurfaceWasTheFeed: Bool {
        guard let cards = firstCards else { return false }
        guard let wait = firstWait else { return true }
        return wait.at > cards.at
    }

    private static func elapsedMilliseconds() -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        guard let origin else {
            origin = now
            return 0
        }
        return max(0, (now - origin) * 1000)
    }

    private static func clock(_ milliseconds: Double) -> String {
        milliseconds < 0 ? "n/a" : String(Int(milliseconds.rounded()))
    }
}
#endif
