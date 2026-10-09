// File: PreparationProgress.swift
// Module: FeedMineRuntime
// Owns: the first-launch preparation evidence shown to the reader (PD-3, INV-06).
// Does not own: acquisition, timing policy or rendering.
//
// PD-3: "we are not installing software; we are going after the good content the user wants".
// Everything here is real pipeline evidence — sources being contacted, which contributed,
// headlines actually admitted, cards prepared. Nothing is invented (INV-06).
// The remaining-time estimate is derived from measured settle times, never a fixed number.

public struct PreparationProgress: Hashable, Sendable {
    public enum SourceState: Hashable, Sendable {
        case contacting
        case contributed
        case quiet
        case unreachable
    }
    public struct Source: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let state: SourceState
    }

    public let sources: [Source]
    /// Real admitted headlines, newest first, bounded by `headlineCapacity`.
    public let headlines: [String]
    public let preparedCards: Int
    public let startedAt: Double
    public let lastUpdateAt: Double
    let headlineCapacity: Int

    public init(startedAt: Double, headlineCapacity: Int = 12) {
        sources = []; headlines = []; preparedCards = 0
        self.startedAt = startedAt; lastUpdateAt = startedAt
        self.headlineCapacity = max(1, headlineCapacity)
    }

    private init(sources: [Source], headlines: [String], preparedCards: Int, startedAt: Double,
        lastUpdateAt: Double, headlineCapacity: Int) {
        self.sources = sources; self.headlines = headlines; self.preparedCards = preparedCards
        self.startedAt = startedAt; self.lastUpdateAt = lastUpdateAt; self.headlineCapacity = headlineCapacity
    }

    public var contributingSources: Int { sources.filter { $0.state == .contributed }.count }
    public var settledSources: Int { sources.filter { $0.state != .contacting }.count }

    /// Remaining seconds extrapolated from the measured average settle time; nil until one settled.
    public var estimatedRemainingSeconds: Double? {
        let settled = settledSources, pending = sources.count - settled
        guard settled > 0, contributingSources > 0, preparedCards > 0 else { return nil }
        guard pending > 0 else { return 0 }
        let perSource = (lastUpdateAt - startedAt) / Double(settled)
        return perSource * Double(pending)
    }

    /// Whether the remaining work is short relative to what has already been spent.
    public var isNearlyReady: Bool {
        guard let remaining = estimatedRemainingSeconds else { return false }
        return remaining <= lastUpdateAt - startedAt
    }

    public enum Event: Hashable, Sendable {
        case contacting(id: String, name: String)
        case settled(id: String, contributed: Bool, reachable: Bool)
        case admitted(headlines: [String])
        case prepared(cards: Int)
    }

    public func applying(_ event: Event, at now: Double) -> PreparationProgress {
        var sources = self.sources, headlines = self.headlines, prepared = preparedCards
        switch event {
        case .contacting(let id, let name):
            if let index = sources.firstIndex(where: { $0.id == id }) {
                sources[index] = Source(id: id, name: name, state: .contacting)
            } else {
                sources.append(Source(id: id, name: name, state: .contacting))
            }
        case .settled(let id, let contributed, let reachable):
            if let index = sources.firstIndex(where: { $0.id == id }) {
                sources[index] = Source(id: id, name: sources[index].name,
                    state: !reachable ? .unreachable : contributed ? .contributed : .quiet)
            }
        case .admitted(let fresh):
            for headline in fresh.reversed() where !headline.isEmpty && !headlines.contains(headline) {
                headlines.insert(headline, at: 0)
            }
            if headlines.count > headlineCapacity { headlines.removeLast(headlines.count - headlineCapacity) }
        case .prepared(let cards):
            prepared = max(prepared, cards)
        }
        return PreparationProgress(sources: sources, headlines: headlines, preparedCards: prepared,
            startedAt: startedAt, lastUpdateAt: max(lastUpdateAt, now), headlineCapacity: headlineCapacity)
    }
}
