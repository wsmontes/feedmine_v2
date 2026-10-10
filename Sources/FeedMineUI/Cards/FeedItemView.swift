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
                FeedItemRowView(card: card, appearance: appearance, isRead: isRead)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(card.id.rawValue.uuidString)
        .contentShape(Rectangle())
        .onTapGesture { emit(.open) }
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
