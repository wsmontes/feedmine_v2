import Foundation
import XCTest
import FeedMineComposition

/// The foreground cadence (owner's decision of 2026-10-17, item G): one drive opportunity per ≥ 10 s while the app
/// is active and visible, and none while it is not. Time is injected, so the five idle minutes below cost no wall
/// time and the count of opportunities is a fact of the test, not of the machine.
final class ForegroundDriveCadenceTests: XCTestCase {
    /// A clock the test advances: `sleep` parks until `advance()` resolves it, and a cancelled wait is resumed so
    /// the cadence can observe its own cancellation.
    private final class ManualClock: @unchecked Sendable {
        private struct Waiter {
            let deadline: TimeInterval
            let resume: () -> Void
        }

        private let lock = NSLock()
        private var now: TimeInterval = 0
        private var waiters: [Int: Waiter] = [:]
        private var nextID = 0

        var clock: ForegroundDriveCadence.Clock {
            { [self] interval in try await self.park(interval) }
        }

        /// Whether the cadence is between opportunities — parked, not driving.
        var isWaiting: Bool {
            lock.withLock { !waiters.isEmpty }
        }

        private func park(_ interval: TimeInterval) async throws {
            try Task.checkCancellation()
            let id = lock.withLock {
                nextID += 1
                return nextID
            }
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.withLock {
                        let deadline = now + interval
                        waiters[id] = Waiter(deadline: deadline) { continuation.resume() }
                    }
                }
            } onCancel: {
                let resume = lock.withLock { waiters.removeValue(forKey: id)?.resume }
                resume?()
            }
            try Task.checkCancellation()
        }

        /// Moves the clock forward and resolves every wait whose deadline has passed — in the cadence there is at
        /// most one, because a drive is offered only after the previous wait concluded.
        func advance(by interval: TimeInterval) {
            let due = lock.withLock { () -> [Waiter] in
                now += interval
                let due = waiters.filter { $0.value.deadline <= now + 1e-9 }
                for key in due.keys { waiters.removeValue(forKey: key) }
                return Array(due.values)
            }
            for waiter in due { waiter.resume() }
        }
    }

    private actor DriveCounter {
        private(set) var count = 0
        func record() { count += 1 }
    }

    /// Spins until `condition` holds, failing the test rather than hanging when it never does.
    private func waitUntil(timeout: TimeInterval = 5,
        _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            guard Date() < deadline else {
                XCTFail("the cadence never reached the expected state")
                return
            }
            await Task.yield()
        }
    }

    /// Five idle minutes in the foreground is more than one drive, and it is measured by the owner's floor.
    func testFiveIdleMinutesInTheForegroundOfferMoreThanOneDrive() async throws {
        XCTAssertEqual(ForegroundDriveCadence.interval, 10, "o piso do dono é 10 s, não um alvo")
        let clock = ManualClock()
        let drives = DriveCounter()
        let cadence = ForegroundDriveCadence(clock: clock.clock)
        await cadence.start { await drives.record() }
        await waitUntil { clock.isWaiting }
        // 5 min ÷ 10 s = 30 opportunities; the test consumes one advance per opportunity.
        let opportunities = Int((5 * 60) / ForegroundDriveCadence.interval)
        for _ in 0..<opportunities {
            clock.advance(by: ForegroundDriveCadence.interval)
            await waitUntil { clock.isWaiting }
        }
        await cadence.stop()
        let count = await drives.count
        XCTAssertGreaterThan(count, 1, "um app visível e parado recebe mais de uma oportunidade em cinco minutos")
        XCTAssertGreaterThanOrEqual(count, 25, "cinco minutos de foreground oferecem ~30 oportunidades, não uma")
    }

    /// Leaving the screen stops the cadence in the same call: five idle minutes backgrounded offer nothing, and a
    /// wake that races the stop is dropped rather than deferred.
    func testNoDriveIsOfferedWhileTheAppIsNotForeground() async throws {
        let clock = ManualClock()
        let drives = DriveCounter()
        let cadence = ForegroundDriveCadence(clock: clock.clock)
        await cadence.start { await drives.record() }
        await waitUntil { clock.isWaiting }
        clock.advance(by: ForegroundDriveCadence.interval)
        await waitUntil { await drives.count == 1 }
        await cadence.stop()
        for _ in 0..<30 { clock.advance(by: ForegroundDriveCadence.interval) }
        for _ in 0..<64 { await Task.yield() }
        let count = await drives.count
        XCTAssertEqual(count, 1, "fora do foreground nenhuma oportunidade é oferecida")
    }

    /// A foreground that repeats `start` (every `.active` does) never adds a second cadence: one loop, one interval.
    func testRepeatedStartDoesNotAddASecondCadence() async throws {
        let clock = ManualClock()
        let first = DriveCounter()
        let second = DriveCounter()
        let cadence = ForegroundDriveCadence(clock: clock.clock)
        await cadence.start { await first.record() }
        await waitUntil { clock.isWaiting }
        await cadence.start { await second.record() }
        for _ in 0..<5 {
            clock.advance(by: ForegroundDriveCadence.interval)
            await waitUntil { clock.isWaiting }
        }
        await cadence.stop()
        let firstCount = await first.count
        let secondCount = await second.count
        XCTAssertEqual(firstCount, 5, "as cinco oportunidades foram para a cadência original")
        XCTAssertEqual(secondCount, 0, "um segundo start enquanto roda não cria uma segunda pipeline")
    }
}
