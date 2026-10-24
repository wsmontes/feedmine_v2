// U2: saved-articles surface. Renders immutable summaries supplied by the composition; the list
// never reads storage, never resolves URLs and never initiates work by itself — a retry is the reader's tap.
import SwiftUI
import FeedMineDomain

/// One saved article as the app host may present it. A plain value: no storage handle, no URL.
///
/// `availability` is the **persisted** state of the link's content (owner directive 2026-10-17 §2), not a
/// guess made while drawing: "salvo" is the link, and the row says whether the content is text-only, still
/// being prepared, durably local, or failed — including a full disk that could not hold it.
public struct FeedSavedArticle: Identifiable, Hashable, Sendable {
    public let id: PublicationCardID
    public let title: String
    public let source: String?
    public let timestamp: Date?
    public let availability: SavedMediaAvailability

    public init(id: PublicationCardID, title: String, source: String?, timestamp: Date?,
        availability: SavedMediaAvailability) {
        self.id = id
        self.title = title
        self.source = source
        self.timestamp = timestamp
        self.availability = availability
    }

    /// The row's availability: the persisted record when there is one, otherwise the published fact
    /// (`media_key IS NULL` is the only final text-only settlement). A preparation that returned `.failed`
    /// without a durable row is stated as failed **for this session**, because the write that would have
    /// recorded it was refused; it is recoverable and the retry path re-attempts it.
    public static func availability(recorded: SavedMediaAvailability?, hasPublishedMedia: Bool,
        failedInThisSession: Bool) -> SavedMediaAvailability {
        if failedInThisSession { return .failed }
        if let recorded { return recorded }
        return hasPublishedMedia ? .pending : .textOnly
    }
}

/// What the saved surface received from the composition. A read that failed is **not** an empty library: the
/// reader who saved articles must not be told they have none because the database could not be read.
public enum FeedSavedArticlesRead: Hashable, Sendable {
    case articles([FeedSavedArticle])
    case failed

    public var articles: [FeedSavedArticle] {
        if case .articles(let read) = self { return read }
        return []
    }

    public var failed: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
public struct FeedSavedListView: View {
    private let articles: [FeedSavedArticle]
    private let readFailure: Bool
    private let onOpen: (PublicationCardID) -> Void
    private let onRetry: (PublicationCardID) -> Void

    public init(articles: [FeedSavedArticle], onOpen: @escaping (PublicationCardID) -> Void,
        onRetry: @escaping (PublicationCardID) -> Void = { _ in }) {
        self.articles = articles
        readFailure = false
        self.onOpen = onOpen
        self.onRetry = onRetry
    }

    /// The surface states a failed read instead of drawing the empty library: "nothing saved" and "we could not
    /// read what you saved" are different facts and only one of them is the reader's.
    public init(read: FeedSavedArticlesRead, onOpen: @escaping (PublicationCardID) -> Void,
        onRetry: @escaping (PublicationCardID) -> Void = { _ in }) {
        articles = read.articles
        readFailure = read.failed
        self.onOpen = onOpen
        self.onRetry = onRetry
    }

    public var body: some View {
        Group {
            if readFailure {
                ContentUnavailableView {
                    Label(String(localized: "Não foi possível ler os artigos salvos"),
                        systemImage: "exclamationmark.triangle")
                } description: {
                    Text(String(localized: "Nada foi alterado. Abra os salvos novamente para tentar de novo."))
                }
            } else if articles.isEmpty {
                ContentUnavailableView {
                    Label("Nenhum artigo salvo", systemImage: "bookmark")
                } description: {
                    Text("Salve um artigo pelo menu do card para encontrá-lo aqui.")
                }
            } else {
                List(articles) { article in
                    VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
                        // U2: the summary area is the reader's target, not only the text it draws. The block is a
                        // link-styled button, and a tap between the title and the metadata line is a tap on it —
                        // measured: at the row's centre the button's action never ran, and the same tap reached
                        // it once the label declared its own shape (V1's own dead taps for a card without one).
                        Button { onOpen(article.id) } label: {
                            summary(article).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("saved-article-" + article.id.rawValue.uuidString)
                        .accessibilityAddTraits(.isLink)
                        // The availability line sits **outside** that button: a retry inside a button's label
                        // never receives the tap (the outer button consumes it), and the retry must be real.
                        availabilityLine(article)
                    }
                }
            }
        }
        .navigationTitle("Salvos")
        #if canImport(UIKit)
        // T5: the reader's root hides the navigation bar (V1 draws its own floating header); a pushed
        // destination brings it back so the reader keeps a way back.
        .toolbar(.visible, for: .navigationBar)
        #endif
    }

    @ViewBuilder private func summary(_ article: FeedSavedArticle) -> some View {
        VStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.tight) {
            Text(verbatim: article.title)
                .font(FeedDesignTokens.Typography.cardTitle)
                .lineLimit(3)
            HStack(spacing: FeedDesignTokens.Spacing.compact) {
                if let source = article.source {
                    Text(verbatim: source)
                }
                if let timestamp = article.timestamp {
                    Text(timestamp, format: .dateTime.day().month().year())
                }
            }
            .font(FeedDesignTokens.Typography.metadata)
            .foregroundStyle(FeedDesignTokens.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the link can open, stated. Only the settled, fully-local states are drawn as a plain fact; a
    /// recoverable state says what is missing and offers the retry instead of implying the unit is complete.
    @ViewBuilder private func availabilityLine(_ article: FeedSavedArticle) -> some View {
        HStack(spacing: FeedDesignTokens.Spacing.compact) {
            Label(Self.label(for: article.availability), systemImage: Self.symbol(for: article.availability))
            if article.availability.isRecoverable {
                Button("Tentar de novo") { onRetry(article.id) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("saved-media-retry-" + article.id.rawValue.uuidString)
            }
        }
        .font(FeedDesignTokens.Typography.metadata)
        .foregroundStyle(article.availability.isAvailableOffline
            ? FeedDesignTokens.Palette.secondaryText : FeedDesignTokens.Palette.statusCaution)
        .accessibilityIdentifier("saved-media-state-" + article.id.rawValue.uuidString)
    }

    private static func label(for availability: SavedMediaAvailability) -> String {
        switch availability {
        case .textOnly: return String(localized: "Somente texto")
        case .pending: return String(localized: "Mídia pendente")
        case .ready: return String(localized: "Disponível offline")
        case .failed: return String(localized: "Mídia indisponível")
        case .insufficientSpace: return String(localized: "Sem espaço para a mídia")
        }
    }

    private static func symbol(for availability: SavedMediaAvailability) -> String {
        switch availability {
        case .textOnly, .ready: return "checkmark.circle"
        case .pending: return "arrow.down.circle"
        case .failed: return "exclamationmark.triangle"
        case .insufficientSpace: return "externaldrive.badge.exclamationmark"
        }
    }
}
