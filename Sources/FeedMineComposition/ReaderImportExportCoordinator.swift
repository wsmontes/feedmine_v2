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

public enum ReaderImportExportError: Error, Equatable, Sendable {
    case nothingToWrite
    case unknownScope
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

    /// Writes a document for the request and returns its local URL. The file is the artifact; showing it or
    /// sharing it belongs to the app.
    public func export(_ request: ReaderExportRequest, at date: Date = Date()) throws -> URL {
        let entries = try entries(for: request.scope)
        guard !entries.isEmpty else { throw ReaderImportExportError.nothingToWrite }
        let (name, contents) = try document(request: request, entries: entries, at: date)
        let url = exportDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
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

    /// The file's name and its contents, V1's scopes and formats.
    private func document(request: ReaderExportRequest, entries: [ReaderImportEntry],
        at date: Date) throws -> (String, String) {
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

    private func name(_ extension: String, at date: Date) -> String {
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        return "feedmine-\(stamp).\(`extension`)"
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
