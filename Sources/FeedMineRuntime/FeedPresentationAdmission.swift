// File: FeedPresentationAdmission.swift
// Module: FeedMineRuntime
// Owns: the only explicit reasons that may change the admitted reader list, and its bounds.
// Does not own: production, publication, acquisition, geometry or persistence.

import FeedMineDomain

/// Structural bounds of one admitted presentation. They are supplied when the presentation is
/// installed and frozen for the life of that presentation: no later path may rematerialize the
/// list with different bounds (plan constraint "congelar valores estruturais por sessão").
public struct FeedPresentationBounds: Hashable, Sendable {
    public let backwardCapacity: Int
    public let forwardCapacity: Int
    public let contextKey: ContextKey?

    public init(backwardCapacity: Int, forwardCapacity: Int, contextKey: ContextKey? = nil) {
        self.backwardCapacity = backwardCapacity
        self.forwardCapacity = forwardCapacity
        self.contextKey = contextKey
    }
}

/// Admission is the explicit boundary between *produced reserve* and the *admitted list*.
///
/// Production (acquisition, local slices, retry, foreground) extends the reserve and only ever
/// reads `FeedSession.currentPresentation()`. Nothing in that path may install a different list:
/// the reader's cards, order and geometry change only through one of the cases below.
public enum FeedPresentationAdmission: Hashable, Sendable {
    /// Installs the first presentation of an association, at most once per session.
    case initial(FeedPresentationBounds)
    /// Extends the admitted prefix after real forward movement of the reader.
    /// Stationary, backward and layout-driven observations do not extend the boundary.
    case forwardScroll(ViewportObservation)
    /// Recovers a presentation for an association that has none (relaunch after a state loss).
    case restore(FeedPresentationBounds)
}

public extension RunwayActivity {
    /// Real forward movement *and* the need to extend the content: the reader has reached the
    /// admitted tail. A forward scroll inside already-admitted history, a stationary settle, a
    /// backward gesture and a layout change never admit.
    var admitsForwardContent: Bool {
        self == .explicitTailApproach
    }
}
