//
// File: OPMLDocument.swift
// Module: FeedMineDomain
//
// Responsibility:
// Reading and writing OPML as values: what an import *would* do (a preview), and the document an export
// produces. V1's `OPMLParser` did the same, and this keeps its rules — an outline with `xmlUrl` is a feed, an
// outline without one is a category that may nest, duplicates are decided by the feed's identity while the
// fetchable address is kept verbatim.
//
// Does not own: writing anything (Composition commits a preview), where a file comes from (the app) or the
// reader's selection (Persistence).
import Foundation

/// One feed an OPML file names.
public struct ReaderImportEntry: Hashable, Sendable, Identifiable {
    /// The feed's identity (`FeedAddress.identity`): two entries with the same one are the same feed.
    public let id: String
    public let title: String
    /// The address to fetch, which may carry signed parameters the identity drops.
    public let requestURL: String
    /// The category path the file nested it under, outermost first. Empty at the top level.
    public let categoryPath: [String]
    /// True when the file names this feed more than once: the first occurrence wins, as V1 decided.
    public let isRepeatInFile: Bool

    public init(id: String, title: String, requestURL: String, categoryPath: [String],
        isRepeatInFile: Bool = false) {
        self.id = id; self.title = title; self.requestURL = requestURL
        self.categoryPath = categoryPath; self.isRepeatInFile = isRepeatInFile
    }
}

/// One outline the file offered and this build will not import, with the reason, so a preview can state it
/// instead of silently shrinking the file.
public struct ReaderImportRejection: Hashable, Sendable {
    public enum Reason: String, Hashable, Sendable {
        /// An outline with no `xmlUrl` and no children of its own: a category that leads nowhere.
        case emptyCategory
        /// An `xmlUrl` that is not an http(s) address this app could ever fetch.
        case unusableAddress
    }

    public let title: String?
    public let rawAddress: String?
    public let reason: Reason

    public init(title: String?, rawAddress: String?, reason: Reason) {
        self.title = title; self.rawAddress = rawAddress; self.reason = reason
    }
}

/// What an import would do, before anything is written. `entries` excludes repeats; `repeats` counts how many
/// outlines the file repeated, so a preview can say "3 already in this file" without listing them twice.
public struct ReaderImportPreview: Hashable, Sendable {
    /// The OPML document's own title, when it has one.
    public let name: String?
    public let entries: [ReaderImportEntry]
    public let repeats: Int
    public let rejections: [ReaderImportRejection]

    public init(name: String?, entries: [ReaderImportEntry], repeats: Int,
        rejections: [ReaderImportRejection]) {
        self.name = name; self.entries = entries; self.repeats = repeats; self.rejections = rejections
    }

    public var isEmpty: Bool { entries.isEmpty }
}

/// What an import actually did.
public struct ReaderImportResult: Hashable, Sendable {
    public let insertedSources: Int
    /// Entries the reader already had selected (nothing was written for them).
    public let alreadySelected: Int
    public let rejected: Int

    public init(insertedSources: Int, alreadySelected: Int, rejected: Int) {
        self.insertedSources = insertedSources; self.alreadySelected = alreadySelected; self.rejected = rejected
    }
}

public enum OPMLDocumentError: Error, Equatable, Sendable {
    case malformed(String)
}

public enum OPMLDocument {
    /// Parses a file into a preview. A file that is not XML at all is an error, not an empty preview: the two
    /// mean different things to a reader and to the reader's data.
    public static func preview(_ data: Data) throws -> ReaderImportPreview {
        let delegate = OutlineDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw OPMLDocumentError.malformed(parser.parserError?.localizedDescription ?? "not XML")
        }
        return delegate.preview()
    }

    /// The OPML an export writes. V1's own shape: a head with the document's title, one outline per feed with
    /// `text`, `title` and `xmlUrl`, nested under the categories the entries carry.
    public static func opml(title: String, entries: [ReaderImportEntry],
        dateCreated: Date = Date()) -> String {
        var lines: [String] = []
        let seconds = Int(dateCreated.timeIntervalSince1970)
        let stamp = ISO8601DateFormatter().string(from: dateCreated)
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<opml version=\"2.0\">")
        lines.append("  <head>")
        lines.append("    <title>\(escaped(title))</title>")
        lines.append("    <dateCreated>\(stamp)</dateCreated>")
        lines.append("    <dateModified>\(stamp)</dateModified>")
        lines.append("    <ownerName>Feedmine</ownerName>")
        lines.append("    <source>feedmine-\(seconds)</source>")
        lines.append("  </head>")
        lines.append("  <body>")
        lines.append(contentsOf: outlines(entries, depth: 2))
        lines.append("  </body>")
        lines.append("</opml>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Feeds grouped by their category path, rendered as nested outlines. Order is the entries' own, so an
    /// export is the list the reader is looking at.
    private static func outlines(_ entries: [ReaderImportEntry], depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []
        var grouped: [String: [ReaderImportEntry]] = [:]
        var topLevel: [ReaderImportEntry] = []
        var categoryOrder: [String] = []
        for entry in entries {
            guard let first = entry.categoryPath.first else { topLevel.append(entry); continue }
            if grouped[first] == nil { categoryOrder.append(first) }
            // The category it is drawn under is a heading; what it nests further stays on the entry itself.
            grouped[first, default: []].append(
                ReaderImportEntry(id: entry.id, title: entry.title, requestURL: entry.requestURL,
                    categoryPath: Array(entry.categoryPath.dropFirst()), isRepeatInFile: entry.isRepeatInFile))
        }
        for entry in topLevel {
            lines.append("\(indent)<outline type=\"rss\" text=\"\(escaped(entry.title))\" title=\"\(escaped(entry.title))\" xmlUrl=\"\(escaped(entry.requestURL))\"/>")
        }
        for category in categoryOrder {
            let children = grouped[category] ?? []
            lines.append("\(indent)<outline text=\"\(escaped(category))\" title=\"\(escaped(category))\">")
            lines.append(contentsOf: outlines(children, depth: depth + 1))
            lines.append("\(indent)</outline>")
        }
        return lines
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// One parser pass. V1's rules: an outline with `xmlUrl` is a feed, an outline without one is a category that
/// may nest, and identity decides a duplicate.
private final class OutlineDelegate: NSObject, XMLParserDelegate {
    private enum Outline {
        case category(String)
        case feed
    }

    private var name: String?
    private var entries: [ReaderImportEntry] = []
    private var rejections: [ReaderImportRejection] = []
    private var seen: Set<String> = []
    private var repeats = 0
    /// Every outline that is open, in order, so an end closes the outline that opened it.
    private var open: [Outline] = []
    /// Whether the outline at each depth has any child of its own: a category that leads nowhere is reported.
    private var hasChild: [Bool] = []
    private var categoryStack: [String] = []
    private var currentText = ""
    private var inHead = false

    func preview() -> ReaderImportPreview {
        ReaderImportPreview(name: name, entries: entries, repeats: repeats, rejections: rejections)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let element = elementName.lowercased()
        if element == "head" { inHead = true; return }
        if element == "title", inHead { currentText = ""; return }
        guard element == "outline" else { return }
        // This outline is a child of the one enclosing it.
        if !hasChild.isEmpty { hasChild[hasChild.count - 1] = true }
        let address = (attributeDict["xmlurl"] ?? attributeDict["xmlUrl"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (attributeDict["title"] ?? attributeDict["text"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty {
            open.append(.category(title))
            hasChild.append(false)
            categoryStack.append(title)
            return
        }
        open.append(.feed)
        hasChild.append(false)
        let identity = FeedAddress.identity(address)
        let request = FeedAddress.request(address)
        guard let scheme = URL(string: request)?.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            rejections.append(.init(title: title.isEmpty ? nil : title, rawAddress: address,
                reason: .unusableAddress))
            return
        }
        guard seen.insert(identity).inserted else {
            repeats += 1
            return
        }
        entries.append(ReaderImportEntry(id: identity, title: title, requestURL: request,
            categoryPath: categoryStack))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?) {
        let element = elementName.lowercased()
        if element == "head" { inHead = false; return }
        if element == "title", inHead {
            name = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        guard element == "outline", let outline = open.popLast() else { return }
        let hadChild = hasChild.isEmpty ? false : hasChild.removeLast()
        guard case .category(let title) = outline else { return }
        categoryStack.popLast()
        if !hadChild, !title.isEmpty {
            rejections.append(.init(title: title, rawAddress: nil, reason: .emptyCategory))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inHead { currentText += string }
    }
}
