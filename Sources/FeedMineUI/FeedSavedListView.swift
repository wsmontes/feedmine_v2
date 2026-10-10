// U2: saved-articles surface. Renders immutable summaries supplied by the composition; the list
// never reads storage, never resolves URLs and never initiates work.
import SwiftUI
import FeedMineDomain

/// One saved article as the app host may present it. A plain value: no storage handle, no URL.
public struct FeedSavedArticle: Identifiable, Hashable, Sendable {
    public let id: PublicationCardID
    public let title: String
    public let source: String?
    public let timestamp: Date?

    public init(id: PublicationCardID, title: String, source: String?, timestamp: Date?) {
        self.id = id
        self.title = title
        self.source = source
        self.timestamp = timestamp
    }
}

@MainActor
public struct FeedSavedListView: View {
    private let articles: [FeedSavedArticle]
    private let onOpen: (PublicationCardID) -> Void

    public init(articles: [FeedSavedArticle], onOpen: @escaping (PublicationCardID) -> Void) {
        self.articles = articles
        self.onOpen = onOpen
    }

    public var body: some View {
        Group {
            if articles.isEmpty {
                ContentUnavailableView {
                    Label("Nenhum artigo salvo", systemImage: "bookmark")
                } description: {
                    Text("Salve um artigo pelo menu do card para encontrá-lo aqui.")
                }
            } else {
                List(articles) { article in
                    Button { onOpen(article.id) } label: { row(article) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("saved-article-" + article.id.rawValue.uuidString)
                        .accessibilityAddTraits(.isLink)
                }
            }
        }
        .navigationTitle("Salvos")
    }

    @ViewBuilder private func row(_ article: FeedSavedArticle) -> some View {
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
}
