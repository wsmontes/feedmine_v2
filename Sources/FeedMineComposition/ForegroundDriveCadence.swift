// File: ForegroundDriveCadence.swift
// Module: FeedMineComposition
// Owns: when a visible, active app is offered its next runway drive opportunity.
// Does not own: what a drive does, observation, policy, production or presentation.

import Foundation

/// One runway drive opportunity per `interval` of elapsed time, offered **only while the app is in the foreground**.
///
/// The owner's decision of 2026-10-17 (item G): a reader who is looking at the feed but not scrolling still gets
/// production answered behind them — one opportunity every ≥ 10 s. It is the *same* opportunity `foreground()`
/// already takes; the host hands that path in as `drive`, so this type adds no second pipeline, no observation and
/// no policy. It decides **when** a drive is offered, never what one does.
///
/// Leaving the foreground stops it: `.inactive` and `.background` both call `stop()`, and nothing here runs in the
/// background — the OS background grant remains the only background opportunity
/// (`docs/architecture/CONTINUOUS_FEED_RUNWAY_DESIGN.md`, amendment of 2026-10-17).
///
/// Time is injected. Production passes the live, cancellable sleep; a test passes its own clock and counts
/// opportunities without spending wall time.
public actor ForegroundDriveCadence {
    /// The owner's floor: no two opportunities closer than ten seconds. It is a **floor**, not a target — a slow
    /// drive simply finishes before the next wait begins.
    public static let interval: TimeInterval = 10

    /// One wait of `interval` seconds. Throws when the waiting task is cancelled.
    public typealias Clock = @Sendable (TimeInterval) async throws -> Void

    private let clock: Clock
    private var loop: Task<Void, Never>?
    private var generation = 0

    /// - Parameter clock: the wait between opportunities. The default is the live clock, which `Task.sleep` makes
    ///   cancellation-aware; a test injects its own.
    public init(clock: @escaping Clock = {
        try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    }) {
        self.clock = clock
    }

    /// Starts offering opportunities. A repeat while the cadence is already running is a **no-op**: the interval
    /// measures from the opportunity already pending, so a foreground that repeats this call never shortens it.
    public func start(drive: @escaping @Sendable () async -> Void) {
        guard loop == nil else { return }
        generation += 1
        let generation = generation
        loop = Task { [weak self] in
            await self?.run(generation: generation, drive: drive)
        }
    }

    /// Stops the cadence and cancels the pending wait. A drive already executing is not interrupted — it is the
    /// host's own foreground pass — but no further one is offered: the generation is checked before every drive, so
    /// a wake that races this call is **dropped**, not deferred to the next foreground.
    public func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
    }

    private func run(generation expected: Int, drive: @escaping @Sendable () async -> Void) async {
        while generation == expected, !Task.isCancelled {
            do { try await clock(Self.interval) } catch { break }
            // The app may have left the foreground while the interval elapsed. The opportunity belongs to the
            // foreground it was armed in, so it is dropped here rather than offered to whatever comes next.
            guard generation == expected, !Task.isCancelled else { break }
            await drive()
        }
        finished(generation: expected)
    }

    /// Only the loop that is still the current one clears the slot: a loop superseded by `stop()` or by a newer
    /// `start()` leaves the newer one alone.
    private func finished(generation expected: Int) {
        guard generation == expected else { return }
        loop = nil
    }
}
