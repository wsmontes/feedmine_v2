//
// File: ReaderExport.swift
// Module: FeedMineRuntime
//
// Responsibility:
// What a reader can export, as values: the scope (which list) and the format (which document). V1 offered six
// scopes and nine formats because its registry held every source it knew; V2's lists are the reader's selection,
// a collection and a saved box, and what is exported is one of those.
//
// Does not own: writing the file (Composition), where it goes (the app) or sharing it (a platform surface).
import Foundation

/// A scope carries a payload (a collection's or a box's identity), so it cannot be a `CaseIterable` list; the
/// surfaces build the ones the reader has.
public enum ReaderExportScope: Hashable, Sendable, Identifiable {
    /// The reader's own selection — the sources they are reading.
    case selection
    /// One source collection (T7/T8).
    case collection(String)
    /// One saved box: the sources the cards in it came from.
    case bookmarkBox(String)

    public var id: String {
        switch self {
        case .selection: return "selection"
        case .collection(let id): return "collection:\(id)"
        case .bookmarkBox(let id): return "box:\(id)"
        }
    }
}

public enum ReaderExportFormat: String, Hashable, Sendable, CaseIterable, Identifiable {
    case opml
    case json
    case csv
    case markdown
    case html
    case text
    /// V1's "Share Link": the first entry's link on its own, as a shareable artifact.
    case shareLink
    /// V1's "Social Card": the list as a short text a reader can paste.
    case socialCard

    public var id: String { rawValue }

    /// V1's own labels, in the app's language.
    public var title: String {
        switch self {
        case .opml: return String(localized: "OPML")
        case .json: return String(localized: "Backup JSON")
        case .csv: return String(localized: "CSV")
        case .markdown: return String(localized: "Markdown")
        case .html: return String(localized: "Blogroll HTML")
        case .text: return String(localized: "Texto simples")
        case .shareLink: return String(localized: "Link para compartilhar")
        case .socialCard: return String(localized: "Cartão social")
        }
    }

    /// V1's own symbols.
    public var systemImage: String {
        switch self {
        case .opml: return "doc.text"
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        case .markdown: return "text.alignleft"
        case .html: return "globe"
        case .text: return "doc.plaintext"
        case .shareLink: return "link"
        case .socialCard: return "rectangle.on.rectangle"
        }
    }
}

public struct ReaderExportRequest: Hashable, Sendable {
    public let scope: ReaderExportScope
    public let format: ReaderExportFormat

    public init(scope: ReaderExportScope, format: ReaderExportFormat) {
        self.scope = scope; self.format = format
    }
}
