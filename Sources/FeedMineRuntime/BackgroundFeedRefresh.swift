import Foundation

// A short optional iOS opportunity. Scheduling, acquisition, publication and persistence
// remain with the system and the existing composition, not a second background engine.
public enum BackgroundFeedRefresh {
    public static let identifier = "com.feedmine.background-refresh"

    /// A denied or expired grant must not invoke pipeline work. Admission and commits remain
    /// the responsibility of the normal pipeline; the iOS host completes the BG task once.
    public static func run(
        allowed: @Sendable () async -> Bool,
        opportunity: @Sendable () async -> Bool
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard await allowed(), !Task.isCancelled else { return false }
        let completed = await opportunity()
        return completed && !Task.isCancelled
    }
}
