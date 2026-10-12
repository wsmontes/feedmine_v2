//
// File: ReaderImportExportCoordinator.swift
// Module: FeedMineComposition
//
// Responsibility:
// T10's two tools. Import is **two steps** — a preview that writes nothing, then a commit that is atomic and
// idempotent — because a reader must be able to see what a file would add before it is added. Export writes one
// local document for a scope and a format and returns where it is; sharing it is the app's business.
//
// An imported feed is not in the shipped catalog, so its address is kept beside the reader's selection; the
// identity in that selection is the same key the catalog uses, computed by `FeedAddress`.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineRuntime
import FeedMineUI

public enum ReaderImportExportError: Error, Equatable, Sendable {
    case nothingToWrite
    case unknownScope
    /// The scope cannot be written in that format — V1 hid those combinations, and a surface that asks for one
    /// anyway is refused instead of handed a document about something else.
    case formatNotAvailable
}

public struct ReaderImportExportCoordinator: Sendable {
    private let database: RuntimeDatabase
    /// Where an export writes its file. The app states it (its own documents directory); no tool invents one.
    private let exportDirectory: URL

    public init(database: RuntimeDatabase, exportDirectory: URL) {
        self.database = database
        self.exportDirectory = exportDirectory
    }

    // MARK: - Import

    /// What importing this file would do. Nothing is written, so a reader can cancel at this point and their
    /// library is untouched (the plan's own requirement).
    public func previewImport(_ data: Data) async throws -> ReaderImportPreview {
        try OPMLDocument.preview(data)
    }

    /// Writes the preview's entries in one transaction. A feed the reader already has is counted, never
    /// duplicated: the identity is the primary key, so running the same import twice adds nothing.
    public func commitImport(_ preview: ReaderImportPreview, at date: Date = Date()) async throws -> ReaderImportResult {
        try ReaderLibraryStore(database: database).commitImport(preview.entries,
            rejected: preview.rejections.count, at: date)
    }

    /// Every feed this app imported from a file, so a session can build it: the catalog does not have it.
    public func importedSources() -> [ReaderImportEntry] {
        (try? ReaderLibraryStore(database: database).importedSources()) ?? []
    }

    // MARK: - Export

    /// The document a request would produce, as text: what the export sheet previews, and what a share or a
    /// save hands over. An empty scope is reported rather than previewed as nothing.
    public func preview(_ request: ReaderExportRequest, at date: Date = Date()) throws -> String {
        try documentText(request, at: date)
    }

    /// The document's file name, for a share or a save.
    public func fileName(for request: ReaderExportRequest, at date: Date = Date()) throws -> String {
        try document(for: request, at: date).name
    }

    /// Writes a document for the request and returns its local URL. The file is the artifact; showing it or
    /// sharing it belongs to the app.
    public func export(_ request: ReaderExportRequest, at date: Date = Date()) throws -> URL {
        let document = try document(for: request, at: date)
        let url = exportDirectory.appendingPathComponent(document.name)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try Data(document.contents.utf8).write(to: url, options: .atomic)
        return url
    }

    /// The scopes a reader can export right now: their selection, every collection and every box.
    public func exportChoices() -> [ReaderExportChoice] {
        var choices = [ReaderExportChoice(id: "selection", title: String(localized: "Minhas fontes"),
            systemImage: "list.bullet", scope: .selection)]
        let library = ReaderLibraryStore(database: database)
        for collection in (try? library.collections()) ?? [] {
            choices.append(ReaderExportChoice(id: "collection:\(collection.id)", title: collection.name,
                systemImage: "rectangle.stack.fill", scope: .collection(collection.id)))
        }
        for box in (try? library.bookmarkLists()) ?? [] {
            choices.append(ReaderExportChoice(id: "box:\(box.id)", title: box.name,
                systemImage: "folder", scope: .bookmarkBox(box.id)))
        }
        return choices
    }

    /// The entries a scope covers, from the same authorities the surfaces read: the reader's selection, a
    /// collection, or a saved box.
    func entries(for scope: ReaderExportScope) throws -> [ReaderImportEntry] {
        let imported = Dictionary(uniqueKeysWithValues: importedSources().map { ($0.id, $0) })
        switch scope {
        case .selection:
            let keys = (try? ReaderPreferencesStore(database: database).load()?.sourceKeys) ?? []
            return keys.sorted().map { key in
                imported[key] ?? ReaderImportEntry(id: key, title: Self.title(forKey: key),
                    requestURL: key, categoryPath: [])
            }
        case .collection(let id):
            let keys = try ReaderLibraryStore(database: database).sourceKeys(inCollection: id)
            return keys.sorted().map { key in
                imported[key] ?? ReaderImportEntry(id: key, title: Self.title(forKey: key),
                    requestURL: key, categoryPath: [])
            }
        case .bookmarkBox(let id):
            // A box holds card occurrences, not sources: the sources are the ones those cards came from.
            let store = PublicationStore(database: database)
            let cards = (try? ReaderLibraryStore(database: database).bookmarkedCardIDs(inList: id)) ?? []
            var seen = Set<String>()
            var entries: [ReaderImportEntry] = []
            for cardID in cards.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
                guard let card = try? store.card(id: cardID), let reference = card.primaryActionReference,
                    let url = URL(string: reference), let host = url.host, !host.isEmpty else { continue }
                let key = FeedAddress.identity("https://" + host)
                guard seen.insert(key).inserted else { continue }
                let named = (card.sourceDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = named.isEmpty ? Self.title(forKey: key) : named
                entries.append(imported[key] ?? ReaderImportEntry(id: key, title: title,
                    requestURL: key, categoryPath: []))
            }
            return entries
        }
    }

    /// The file's name and its contents, V1's scopes and formats. A saved box is written from its **articles**
    /// (V1's own rule) and only in the four formats an article list has; the other scopes are written from the
    /// feeds they name.
    private func document(for request: ReaderExportRequest, at date: Date) throws -> (name: String, contents: String) {
        if case .bookmarkBox(let id) = request.scope {
            let articles = try articles(inBox: id)
            guard !articles.isEmpty else { throw ReaderImportExportError.nothingToWrite }
            let title = Self.title(for: request.scope)
            switch request.format {
            case .csv: return (bookmarkName("csv", at: date), Self.articlesCSV(articles))
            case .text: return (bookmarkName("txt", at: date), Self.articlesText(articles, title: title))
            case .markdown: return (bookmarkName("md", at: date), Self.articlesMarkdown(articles, title: title))
            case .html: return (bookmarkName("html", at: date), Self.articlesHTML(articles, title: title))
            case .opml, .json, .shareLink, .socialCard:
                // V1 offered exactly the four above for a box and hid the rest: an OPML of a box would be a list
                // of feeds the reader never asked for, which is the document this build used to write.
                throw ReaderImportExportError.formatNotAvailable
            }
        }
        let entries = try entries(for: request.scope)
        guard !entries.isEmpty else { throw ReaderImportExportError.nothingToWrite }
        return try feedDocument(request: request, entries: entries, at: date)
    }

    private func documentText(_ request: ReaderExportRequest, at date: Date) throws -> String {
        try document(for: request, at: date).contents
    }

    /// The file's name and its contents, for a scope that names feeds.
    private func feedDocument(request: ReaderExportRequest, entries: [ReaderImportEntry],
        at date: Date) throws -> (name: String, contents: String) {
        let title = Self.title(for: request.scope)
        switch request.format {
        case .opml:
            return (name("opml", at: date), OPMLDocument.opml(title: title, entries: entries, dateCreated: date))
        case .json:
            return (name("json", at: date), Self.json(entries: entries, date: date))
        case .csv:
            return (name("csv", at: date), Self.csv(entries: entries))
        case .markdown:
            return (name("md", at: date), Self.markdown(title: title, entries: entries))
        case .html:
            return (name("html", at: date), Self.html(title: title, entries: entries))
        case .text:
            return (name("txt", at: date), entries.map(\.requestURL).joined(separator: "\n") + "\n")
        case .shareLink:
            guard let first = entries.first else { throw ReaderImportExportError.nothingToWrite }
            return (name("txt", at: date), first.requestURL + "\n")
        case .socialCard:
            return (name("md", at: date), Self.socialCard(title: title, entries: entries))
        }
    }

    /// One saved article, as V1's export carried it: what it says, where it is, whose it is and when it was
    /// published. V2 states no per-article category, so the article's own source is what a grouped document
    /// groups by.
    struct ExportArticle: Hashable, Sendable {
        let title: String
        let url: String
        let source: String
        let date: Date?
    }

    /// The reader's saved articles in one box, most recently written first (the order the box itself lists them
    /// in), which is what V1's `csvArticles`/`markdownArticles` sorted by publication.
    func articles(inBox boxID: String) throws -> [ExportArticle] {
        let library = ReaderLibraryStore(database: database)
        let publication = PublicationStore(database: database)
        var seen = Set<String>()
        var articles: [ExportArticle] = []
        for cardID in try library.bookmarkedCardIDs(inList: boxID).sorted(by: {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }) {
            guard let card = try? publication.card(id: cardID), let reference = card.primaryActionReference,
                let url = URL(string: reference), let host = url.host, !host.isEmpty else { continue }
            guard seen.insert(cardID.rawValue.uuidString).inserted else { continue }
            let named = (card.sourceDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            articles.append(ExportArticle(title: (card.title ?? "").isEmpty ? reference : card.title!,
                url: reference, source: named.isEmpty ? host : named, date: card.timestampValue))
        }
        return articles.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// V1's file name for a box's export (`<name>-bookmarks.csv` and friends).
    private func bookmarkName(_ `extension`: String, at date: Date) -> String {
        "feedmine-\(Self.stamp(date))-bookmarks.\(`extension`)"
    }

    private func name(_ `extension`: String, at date: Date) -> String {
        "feedmine-\(Self.stamp(date)).\(`extension`)"
    }

    private static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    /// V1's `csvArticles`: title, url, source, date, category — V2 groups by nothing, so the fourth column is the
    /// reader's own box and the category column is what the source is called here.
    static func articlesCSV(_ articles: [ExportArticle]) -> String {
        var lines = ["title,url,source,date,category"]
        let formatter = ISO8601DateFormatter()
        for article in articles {
            let stamp = article.date.map { formatter.string(from: $0) } ?? ""
            lines.append([article.title, article.url, article.source, stamp, article.source].map(csvField)
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// V1's `plainTextArticles`, in the app's own language.
    static func articlesText(_ articles: [ExportArticle], title: String) -> String {
        var lines = [title, String(repeating: "=", count: title.count), ""]
        lines.append(String(localized: "\(articles.count) artigos salvos"))
        lines.append("")
        for article in articles {
            lines.append("• \(article.title)")
            lines.append("  \(article.url)")
            lines.append("  \(article.source)\(article.date.map { " · " + Self.mediumDate($0) } ?? "")")
            lines.append("")
        }
        lines.append("---")
        lines.append(String(localized: "Exportado pelo Feedmine"))
        return lines.joined(separator: "\n") + "\n"
    }

    /// V1's `markdownArticles`: the count, then the articles grouped by where they came from, each with its own
    /// link and date.
    static func articlesMarkdown(_ articles: [ExportArticle], title: String) -> String {
        var lines = ["# \(title)", "", "> \(String(localized: "\(articles.count) artigos salvos"))", ""]
        let grouped = Dictionary(grouping: articles, by: \.source)
        for (source, group) in grouped.sorted(by: { $0.key < $1.key }) {
            lines.append("## \(source)")
            lines.append("")
            for article in group {
                let when = article.date.map { " · \(Self.mediumDate($0))" } ?? ""
                lines.append("- [\(article.title)](\(article.url)) — *\(source)*\(when)")
            }
            lines.append("")
        }
        lines.append("---")
        lines.append(String(localized: "*Exportado pelo Feedmine*"))
        return lines.joined(separator: "\n") + "\n"
    }

    /// V1's `htmlArticles`: a standalone reading list, in the app's own palette.
    static func articlesHTML(_ articles: [ExportArticle], title: String) -> String {
        var lines = ["<!DOCTYPE html>", "<html lang=\"\(Locale.current.language.languageCode?.identifier ?? "en")\">",
            "<head><meta charset=\"UTF-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
            "<title>\(escaped(title))</title>",
            "<style>body{font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;background:#FAF8F5;color:#2c2c2c;line-height:1.6;max-width:700px;margin:0 auto;padding:40px 20px}h1{font-size:1.8rem;margin-bottom:8px}.count{color:#666;margin-bottom:32px}.article{padding:16px 0;border-bottom:1px solid #f0ebe4}.article:last-child{border-bottom:none}.article-title{font-weight:600;font-size:1rem}.article-title a{color:#2c2c2c;text-decoration:none}.article-meta{font-size:0.8rem;color:#888;margin-top:4px}@media (prefers-color-scheme: dark){body{background:#1c1c1e;color:#f2f2f7}.article{border-bottom-color:#2c2c2e}.article-title a{color:#f2f2f7}.count,.article-meta{color:#98989d}}</style>",
            "</head>", "<body>", "<h1>\(escaped(title))</h1>",
            "<p class=\"count\">\(escaped(String(localized: "\(articles.count) artigos salvos")))</p>"]
        for article in articles {
            lines.append("<div class=\"article\">")
            lines.append("<div class=\"article-title\"><a href=\"\(escaped(article.url))\">\(escaped(article.title))</a></div>")
            let when = article.date.map { " · \(escaped(Self.mediumDate($0)))" } ?? ""
            lines.append("<div class=\"article-meta\">\(escaped(article.source))\(when)</div>")
            lines.append("</div>")
        }
        lines.append(contentsOf: ["</body>", "</html>"])
        return lines.joined(separator: "\n") + "\n"
    }

    /// V1's own article dates (`DateFormatter.dateStyle = .medium`).
    static func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func title(for scope: ReaderExportScope) -> String {
        switch scope {
        case .selection: return String(localized: "Minhas fontes")
        case .collection: return String(localized: "Coleção de fontes")
        case .bookmarkBox: return String(localized: "Caixa de salvos")
        }
    }

    /// A source's own title, when this build only has its key: the host is what the reader recognizes.
    static func title(forKey key: String) -> String {
        URL(string: key)?.host ?? key
    }

    /// A card's source name, when the box's export falls back to it.
    static func hostOf(_ reference: String) -> String? {
        URL(string: reference)?.host
    }

    static func json(entries: [ReaderImportEntry], date: Date) -> String {
        let payload: [String: Any] = [
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: date),
            "sources": entries.map { ["title": $0.title, "url": $0.requestURL, "identity": $0.id,
                "category": $0.categoryPath.joined(separator: "/")] },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text + "\n"
    }

    static func csv(entries: [ReaderImportEntry]) -> String {
        var lines = ["title,url,identity,category"]
        for entry in entries {
            lines.append([entry.title, entry.requestURL, entry.id, entry.categoryPath.joined(separator: "/")]
                .map(Self.csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        value.contains(",") || value.contains("\"") || value.contains("\n")
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : value
    }

    static func markdown(title: String, entries: [ReaderImportEntry]) -> String {
        var lines = ["# \(title)", ""]
        for entry in entries {
            lines.append("- [\(entry.title)](\(entry.requestURL))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func html(title: String, entries: [ReaderImportEntry]) -> String {
        var lines = ["<!doctype html>", "<html><head><meta charset=\"utf-8\"><title>\(escaped(title))</title></head>",
            "<body>", "<h1>\(escaped(title))</h1>", "<ul>"]
        for entry in entries {
            lines.append("<li><a href=\"\(escaped(entry.requestURL))\">\(escaped(entry.title))</a></li>")
        }
        lines.append(contentsOf: ["</ul>", "</body>", "</html>"])
        return lines.joined(separator: "\n") + "\n"
    }

    /// V1's social card: the same list, as a short text a reader can paste.
    static func socialCard(title: String, entries: [ReaderImportEntry]) -> String {
        var lines = ["**\(title)**", ""]
        for entry in entries.prefix(10) {
            lines.append("→ \(entry.title) — \(entry.requestURL)")
        }
        if entries.count > 10 { lines.append(String(localized: "… e mais \(entries.count - 10)")) }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
