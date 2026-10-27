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
    /// Prepared images for the **examined** window, decoded from the media pipeline's own assets. This is the only
    /// reason the preparation page can be image-bearing: every pixel here was prepared before it was stated, so the
    /// page never makes a decorative claim about an image that does not exist yet. Bounded by
    /// `previewImageCapacity`, merged by published key, and never removed while the same preparation is running.
    public let previewImages: [PresentationImage]
    /// How many revisions in the examined window have a prepared image, and how many are still undecided.
    /// `imagesPending > 0` is the fact that says "media work is actually scheduled": the surface may hold for it,
    /// and the absence vocabulary must not call it "no stories". Both are counts of this window, never of history.
    public let imagesPrepared: Int
    public let imagesPending: Int
    public let startedAt: Double
    public let lastUpdateAt: Double
    let headlineCapacity: Int
    let previewImageCapacity: Int

    public init(startedAt: Double, headlineCapacity: Int = 12, previewImageCapacity: Int = 6) {
        sources = []; headlines = []; preparedCards = 0; previewImages = []
        imagesPrepared = 0; imagesPending = 0
        self.startedAt = startedAt; lastUpdateAt = startedAt
        self.headlineCapacity = max(1, headlineCapacity)
        self.previewImageCapacity = max(0, previewImageCapacity)
    }

    private init(sources: [Source], headlines: [String], preparedCards: Int,
        previewImages: [PresentationImage], imagesPrepared: Int, imagesPending: Int,
        startedAt: Double, lastUpdateAt: Double, headlineCapacity: Int, previewImageCapacity: Int) {
        self.sources = sources; self.headlines = headlines; self.preparedCards = preparedCards
        self.previewImages = previewImages
        self.imagesPrepared = imagesPrepared; self.imagesPending = imagesPending
        self.startedAt = startedAt; self.lastUpdateAt = lastUpdateAt; self.headlineCapacity = headlineCapacity
        self.previewImageCapacity = previewImageCapacity
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
        /// The media pipeline's own numbers for the examined window, plus any newly prepared pixels. `prepared`
        /// is monotonic within one preparation (a decision is never un-made); `pending` is the current count of
        /// undecided revisions, which is why it may fall to zero and must not be maxed.
        case media(prepared: Int, pending: Int, previews: [PresentationImage])
    }

    public func applying(_ event: Event, at now: Double) -> PreparationProgress {
        var sources = self.sources, headlines = self.headlines, prepared = preparedCards
        var mergedPreview = previewImages
        var imagesPrepared = self.imagesPrepared, imagesPending = self.imagesPending
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
        case .media(let prepared, let pending, let fresh):
            imagesPrepared = max(imagesPrepared, prepared)
            imagesPending = max(0, pending)
            if !fresh.isEmpty {
                // Newest first, never a duplicate: the page draws exactly the pixels it was handed.
                var seen = Set(fresh.map(\.key))
                var merged = fresh
                for image in previewImages where !seen.contains(image.key) {
                    seen.insert(image.key)
                    merged.append(image)
                }
                if merged.count > previewImageCapacity { merged.removeLast(merged.count - previewImageCapacity) }
                mergedPreview = merged
            }
        }
        return PreparationProgress(sources: sources, headlines: headlines, preparedCards: prepared,
            previewImages: mergedPreview, imagesPrepared: imagesPrepared, imagesPending: imagesPending,
            startedAt: startedAt, lastUpdateAt: max(lastUpdateAt, now), headlineCapacity: headlineCapacity,
            previewImageCapacity: previewImageCapacity)
    }
}
