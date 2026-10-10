//
// File: ReaderFilterExpiry.swift
// Module: FeedMineDomain
//
// Responsibility:
//   V1's auto-expiry of the overlay filter criteria: after four hours the reader's region/taxonomy/type/mood/
//   language selection is *pending* to be dropped, and it is dropped only when the reader makes an explicit
//   context transition — never by a clock changing the active presentation.
//
// Owns:
//   The expiry record (enabled flag plus when the selection was set) and the pure resolution of a filter.
//
// Does not own:
//   Storing the record (Persistence), deciding *when* a transition happens (Composition) or the presentation.
//
// Design: docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md §2 ("expiry record").
//

import Foundation

public struct ReaderFilterExpiry: Hashable, Codable, Sendable {
    /// V1's window: `filterAutoExpire` dropped the overlay selection four hours after it was set.
    public static let lifetime: TimeInterval = 4 * 60 * 60

    public let isEnabled: Bool
    /// When the overlay selection was last set or explicitly renewed. Nil with `isEnabled` means "nothing to
    /// expire yet", which is not the same as "expired".
    public let startsAt: Date?

    public static let disabled = ReaderFilterExpiry(isEnabled: false, startsAt: nil)

    public init(isEnabled: Bool, startsAt: Date?) {
        self.isEnabled = isEnabled
        self.startsAt = startsAt
    }

    public func expiresAt() -> Date? {
        guard isEnabled, let startsAt else { return nil }
        return startsAt.addingTimeInterval(Self.lifetime)
    }

    /// True when the selection has been set long enough to be dropped — a *pending* fact, not an action.
    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt = expiresAt() else { return false }
        return now >= expiresAt
    }

    /// The expiry record a new or renewed overlay selection starts. Exclusions never expire, so they are not
    /// part of what this record covers.
    public func renewed(at now: Date) -> ReaderFilterExpiry {
        ReaderFilterExpiry(isEnabled: isEnabled, startsAt: now)
    }

    /// The filter as an explicit transition should apply it at `now`: an expired overlay selection is dropped
    /// (region, taxonomy, language, content type and mood) while **content exclusions survive**, exactly as V1's
    /// four-hour rule left the content-filter screen alone.
    public func resolving(_ filter: ReaderFilter, at now: Date) -> ReaderFilter {
        guard isExpired(at: now) else { return filter }
        return ReaderFilter(exclusions: filter.exclusions)
    }
}
