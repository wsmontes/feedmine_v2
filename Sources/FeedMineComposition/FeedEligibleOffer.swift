//
// File: FeedEligibleOffer.swift
// Module: FeedMineComposition
//
// Responsibility:
//   The full, settled evidence behind the end-of-eligible-content state. It carries no lifetime of its
//   own: the acquisition the driver's causal drain executed, read beside the runway's own facts at the
//   moment that drain ended.
//
// The rule lives with the facts it needs: the reader may be told the offer ended only when **every** fact
// holds. An empty local window, a finished acquisition round and an unavailable source are all the
// provisional state, never the end.
//
// Does not own: acquisition, local production, publication, admission or scheduling.
import FeedMineRuntime

/// What one settled causal drain proved about the reader's eligible offer.
public struct FeedEligibleOfferSettlement: Hashable, Sendable {
    /// The acquisition the drain executed. Only `.acceptedUnavailable(.noEligibleTargets)` — an attempt
    /// that found no eligible target to replenish from — can evidence the end.
    public let acquisition: RunwayAcquisitionCycleOutcome
    /// The runway's own supply fact: its local episode is exhausted with no head reconsideration pending.
    public let localSupplyExhausted: Bool
    /// Nothing is being produced locally.
    public let nothingInFlight: Bool
    /// No acquisition is still outstanding and able to replenish.
    public let noOutstandingAcquisition: Bool
    /// Nothing ready is still waiting to be published ahead of the reader. `readyAhead` is the runway's own
    /// reserve ahead of the reader's position: a count above zero (or an unknown amount) means stories the reader
    /// has not reached yet, so the end may not be stated. This is the second half of the ratified rule — "no
    /// eligible items awaiting preparation/publication" — and without it the block could be drawn after a card
    /// that is not the last one, with published stories still ahead (review, 2026-10-14).
    public let noStoryAhead: Bool

    /// Reads the runway's facts once, at the moment the acquisition settled.
    public init(acquisition: RunwayAcquisitionCycleOutcome, runway: RunwayControllerSnapshot) {
        let ready: Bool
        if let ahead = runway.readyAhead, case .exact(0) = ahead.amount { ready = true } else { ready = false }
        self.init(acquisition: acquisition, localSupplyExhausted: runway.localSupplyExhausted,
            nothingInFlight: !runway.localSliceInFlight,
            noOutstandingAcquisition: runway.outstandingAcquisition == nil, noStoryAhead: ready)
    }

    public init(acquisition: RunwayAcquisitionCycleOutcome, localSupplyExhausted: Bool,
        nothingInFlight: Bool, noOutstandingAcquisition: Bool, noStoryAhead: Bool) {
        self.acquisition = acquisition
        self.localSupplyExhausted = localSupplyExhausted
        self.nothingInFlight = nothingInFlight
        self.noOutstandingAcquisition = noOutstandingAcquisition
        self.noStoryAhead = noStoryAhead
    }

    /// True only with the full evidence: the attempt found no eligible target **and** nothing is awaiting
    /// preparation/publication **and** no acquisition can still replenish **and** the reader has genuinely
    /// reached the last published story.
    public var isEligibleOfferExhausted: Bool {
        guard acquisition == .acceptedUnavailable(.noEligibleTargets) else { return false }
        return localSupplyExhausted && nothingInFlight && noOutstandingAcquisition && noStoryAhead
    }
}
