// File: FeedItemView.swift
// Module: FeedMineUI
// Owns: how one occurrence is presented and which interaction it offers: card or row, tap, media tap
//       and the row's context menu. Copied from V1 `Views/FeedItemView.swift`.
// Does not own: what a tap means beyond stating it, or any execution.

import SwiftUI
import FeedMineRuntime

public struct FeedItemView: View, Equatable {
    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.card == rhs.card && lhs.appearance == rhs.appearance
            && lhs.isRead == rhs.isRead && lhs.isBookmarked == rhs.isBookmarked
            && lhs.isInBookmarkBox == rhs.isInBookmarkBox
            && lhs.availableActions == rhs.availableActions
    }

    public let card: PresentationCard
    public let appearance: ReaderAppearance
    public let isRead: Bool
    public let isBookmarked: Bool
    public let isInBookmarkBox: Bool
    /// Whether to render the band, the compact row, or let the size class decide (V1 behavior).
    public let layout: ReaderItemLayout
    public let availableActions: Set<ReaderCardAction>
    public let onAction: (ReaderCardActionEvent) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public enum ReaderItemLayout: String, Hashable, Sendable {
        case automatic, band, row
    }

    public init(card: PresentationCard, appearance: ReaderAppearance, isRead: Bool = false,
        isBookmarked: Bool = false, isInBookmarkBox: Bool = false, layout: ReaderItemLayout = .automatic,
        availableActions: Set<ReaderCardAction> = Set(ReaderCardAction.allCases),
        onAction: @escaping (ReaderCardActionEvent) -> Void) {
        self.card = card
        self.appearance = appearance
        self.isRead = isRead
        self.isBookmarked = isBookmarked
        self.isInBookmarkBox = isInBookmarkBox
        self.layout = layout
        self.availableActions = availableActions
        self.onAction = onAction
    }

    private var usesRow: Bool {
        switch layout {
        case .band: false
        case .row: true
        case .automatic: horizontalSizeClass == .regular
        }
    }

    public var body: some View {
        Group {
            if usesRow {
                // The compact line gets its own opening action, applied **here** and not inside the row: the row's
                // own header states it owns the layout and not the gestures, and this wrapper owns the surface's
                // interactions. A gesture is the right structure *here* and not on the card, because the objection
                // to gestures is that they wrap controls and steal their touches — and this row has no control of
                // its own (its menu rides on the `contextMenu` below, a different gesture from this tap). A button
                // was tried first and was the wrong tool: measured, it widened the card past the readable column
                // (730.25 pt against 704) in the iPad's landscape pass.
                FeedItemRowView(card: card, appearance: appearance, isRead: isRead)
                    .contentShape(Rectangle())
                    .onTapGesture { emit(.open) }
                    .contextMenu { rowContextMenu }
            } else {
                FeedItemCardView(card: card, appearance: appearance, isRead: isRead,
                    isBookmarked: isBookmarked, isInBookmarkBox: isInBookmarkBox,
                    availableActions: availableActions, onAction: onAction)
            }
        }
        // The identity used by the delivery's UI tests: the published occurrence. It is the card's own
        // element — without `.contain` the identifier would replace every identifier inside the card, and
        // the card itself would have no element with the card's frame.
        //
        // The wrapper deliberately recognises **no touches**. It used to carry `contentShape(Rectangle())` and a
        // tap gesture, and that layer sat above every control inside the card: it swallowed the tap meant for the
        // inline bookmark (measured: a 44×44 target reported not hittable) and the long press meant for the card's
        // own `contextMenu`, which never opened. Which surface answers a touch is now decided by the structure —
        // the content surface opens, the controls are its siblings — instead of by a contest between gestures.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(card.id.rawValue.uuidString)
    }

    /// The compact row has no menu of its own in V1; the wrapper supplies the same vocabulary.
    @ViewBuilder private var rowContextMenu: some View {
        if availableActions.contains(.save) {
            Button { emit(.save) } label: {
                Label(isBookmarked ? String(localized: "Remover dos salvos") : String(localized: "Salvar artigo"),
                    systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
            }
        }
        if availableActions.contains(.viewSource) {
            Button { emit(.viewSource) } label: {
                Label(String(localized: "Ver a fonte"), systemImage: "rectangle.stack")
            }
        }
        if availableActions.contains(.addSourceToCollection) {
            Button { emit(.addSourceToCollection) } label: {
                Label(String(localized: "Adicionar fonte a uma coleção"),
                    systemImage: "rectangle.stack.badge.plus")
            }
        }
        if availableActions.contains(.copyLink) {
            Button { emit(.copyLink) } label: {
                Label(String(localized: "Copiar link"), systemImage: "doc.on.doc")
            }
        }
        if availableActions.contains(.share), card.primaryActionKind == .externalURL {
            Button { emit(.share) } label: {
                Label(String(localized: "Compartilhar"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private func emit(_ action: ReaderCardAction) {
        onAction(ReaderCardActionEvent(action: action, cardID: card.id))
    }
}
