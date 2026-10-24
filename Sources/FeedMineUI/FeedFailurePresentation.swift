// File: FeedFailurePresentation.swift
// Module: FeedMineUI
//
// Responsibility:
// Decides how a failed feed attempt is stated to a reader. It exists because the app installed the *whole* feed as
// failed (`work = .failed`) for any failed refresh, including a single acquisition target among thousands, and the
// reader then saw a badge over a feed that kept working, with nothing to press.
//
// The rule: a failure while the reader already has cards is a statement about *this attempt* — said once, never a
// persistent state, and never a change to the cards. A feed with nothing to read is the only case that installs the
// failure state, because there the failure is the whole screen's truth.
//
// Does not own: which errors count as a connection failure (the composition decides from the transport domain) or
// how a state is drawn (the screen does).
import Foundation

public enum FeedFailurePresentation: Hashable, Sendable {
    /// The failure is stated as a notice and the state is left alone.
    case notice(String)
    /// The failure becomes the screen's own state (only for a feed with nothing to read).
    case state(FeedPresentationState.Work)

    public static func after(hasCards: Bool, connectionFailed: Bool) -> Self {
        let statement = connectionFailed
            ? String(localized: "Sem conexão")
            : String(localized: "Falha ao atualizar o feed")
        guard hasCards else {
            return .state(connectionFailed ? .unreachable : .failed(message: statement))
        }
        return .notice(statement)
    }
}
