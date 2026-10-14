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

    /// Reads the runway's facts once, at the moment the acquisition settled.
    public init(acquisition: RunwayAcquisitionCycleOutcome, runway: RunwayControllerSnapshot) {
        self.init(acquisition: acquisition, localSupplyExhausted: runway.localSupplyExhausted,
            nothingInFlight: !runway.localSliceInFlight,
            noOutstandingAcquisition: runway.outstandingAcquisition == nil)
    }

    public init(acquisition: RunwayAcquisitionCycleOutcome, localSupplyExhausted: Bool,
        nothingInFlight: Bool, noOutstandingAcquisition: Bool) {
        self.acquisition = acquisition
        self.localSupplyExhausted = localSupplyExhausted
        self.nothingInFlight = nothingInFlight
        self.noOutstandingAcquisition = noOutstandingAcquisition
    }

    /// True only with the full evidence: the attempt found no eligible target **and** nothing is awaiting
    /// preparation/publication **and** no acquisition can still replenish.
    public var isEligibleOfferExhausted: Bool {
        guard acquisition == .acceptedUnavailable(.noEligibleTargets) else { return false }
        return localSupplyExhausted && nothingInFlight && noOutstandingAcquisition
    }
}
